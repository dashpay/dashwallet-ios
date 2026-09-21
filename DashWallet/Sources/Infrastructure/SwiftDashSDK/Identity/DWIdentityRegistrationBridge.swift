//
//  DWIdentityRegistrationBridge.swift
//  DashWallet
//
//  Obj-C facade over `DWIdentityRegistrationCoordinator`. The
//  coordinator is `@MainActor` Swift; this bridge exposes the same
//  surface to `DWDashPayModel.m` and `DWCheckExistenceUsernameValidationRule.m`
//  with Obj-C-friendly completion-based APIs and an `NSNotification`
//  posted on every phase / asset-lock-status transition.
//
//  Why a separate class instead of `@objc` on the coordinator:
//    - The coordinator's `startCreateUsername(_:) async throws -> Identifier`
//      surface uses Swift concurrency + value types that don't bridge
//      to Obj-C; the bridge wraps each surface in a Task + completion
//      pair.
//    - The coordinator stays Combine-only; the bridge owns the
//      NSNotification side-effects so there's a single owner per
//      effect.
//
//  Threading: the bridge mirrors the coordinator's MainActor-isolated
//  state into local `@objc` properties via a Combine subscription
//  that hops to main. Obj-C consumers read those cached values on
//  main thread (the only place they're observable today — every
//  Obj-C touchpoint is a UIKit / notification-observer call site).
//

import Combine
import Foundation
import OSLog
import SwiftDashSDK

extension Notification.Name {
    /// Posted after persisted SwiftDashSDK transaction-purpose metadata may
    /// have changed. Transaction-history projections observe this signal to
    /// invalidate snapshots that are not covered by a balance change (for
    /// example, an identity asset lock gaining its funding type/status).
    static let swiftDashSDKTransactionProjectionDidChange =
        Notification.Name("DWSwiftDashSDKTransactionProjectionDidChange")
}

/// Funding source for new-identity registration. Surfaced to Obj-C
/// as an NSInteger-backed enum so the SwiftUI form can route the
/// user's picker selection through the bridge without changing
/// `DWDashPayProtocol.createUsername:`.
///
/// - `core`: spend Core BIP44 UTXOs via `registerIdentityWithFunding`.
///   Default and only path before PR 5.
/// - `platformPayment`: spend credits already on DIP-17 Platform
///   Payment addresses via `registerIdentityFromAddresses`. Skips
///   the asset-lock IS/CL wait — there is no Core-chain asset-lock
///   in this path.
/// - `shielded`: spend a fixed exit denomination from the wallet's
///   shielded (Orchard) balance via `shieldedIdentityCreateFromPool`
///   (Type 20). The privacy-preserving default when the shielded
///   balance is funded, matured, and the pool clears the consensus
///   minimum — see `ShieldedIdentityFundingReadiness`. No asset-lock.
/// - `invitation`: fund the new identity from a DashPay invitation
///   voucher (DIP-13) via `claimInvitation`. The asset-lock was built
///   and broadcast by the INVITER, so there is no local asset-lock
///   row to track. Never user-pickable — entered only through
///   `DWIdentityRegistrationCoordinator.startClaimInvitation`.
@objc public enum DWIdentityFundingSource: Int {
    case core = 0
    case platformPayment = 1
    case shielded = 2
    case invitation = 3
}

extension DWIdentityFundingSource {
    /// Short tag for log lines.
    var logLabel: String {
        switch self {
        case .core: return "core"
        case .platformPayment: return "pp"
        case .shielded: return "shielded"
        case .invitation: return "invite"
        }
    }
}

// MARK: - RegistrationAttemptScope

/// The wallet and network a username registration belongs to.
///
/// `DWIdentityRegistrationCoordinator` and the bridge that mirrors it are
/// process-global, while the records a registration leaves behind
/// (`UsernamePrefs`) are per wallet and network. One label can legitimately
/// exist in two scopes at once — the same name failing on mainnet and
/// succeeding on testnet is routine for anyone testing — so a label alone
/// never identifies an attempt. This is what an attempt is qualified by.
struct RegistrationAttemptScope: Equatable {
    let networkRawValue: Int
    /// `nil` on an unsupported network, which then compares equal only to
    /// another reading taken in the same state — enough, because a
    /// registration cannot run there.
    let walletIdHex: String?

    static var current: RegistrationAttemptScope {
        RegistrationAttemptScope(
            networkRawValue: WalletEnvironment.networkKind.rawValue,
            walletIdHex: WalletEnvironment.activeWalletIdHex as String?)
    }
}

@objc(DWIdentityRegistrationBridge)
@MainActor
@objcMembers
public final class DWIdentityRegistrationBridge: NSObject {

    @objc public static let shared = DWIdentityRegistrationBridge()

    /// Internal notification posted by the bridge on every phase or
    /// asset-lock-status transition. Only `DWDashPayModel` is expected
    /// to observe this — the model then rebuilds its own
    /// `registrationStatus` from the bridge's cached @objc state and
    /// posts the canonical `DWDashPayRegistrationStatusUpdatedNotification`
    /// so existing UI consumers see a consistent model + notification
    /// pair (registration-order race avoidance).
    @objc public static let stateChangedNotification =
        NSNotification.Name("DWIdentityRegistrationBridgeStateChangedNotification")

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.identity-bridge")

    // MARK: - Cached @objc state

    /// Current registration state for the existing
    /// `DWDPRegistrationStatusViewController` UI. Refreshed from the
    /// coordinator on every phase / asset-lock-status transition.
    @objc public private(set) var currentState: DWDPRegistrationState = .processingPayment

    /// `YES` iff the active controller has terminated with `.failed`.
    @objc public private(set) var isFailed: Bool = false

    /// `YES` iff the active controller has terminated with `.completed`.
    @objc public private(set) var isCompleted: Bool = false

    /// Username currently being registered (nil outside of an active
    /// attempt).
    @objc public private(set) var currentUsername: String?

    /// Which wallet and network the attempt behind `currentUsername` was
    /// STARTED on, stamped when the bridge first sees that attempt and left
    /// alone for the rest of its life.
    ///
    /// The bridge mirrors every coordinator phase, so it carries attempts no
    /// screen handed anywhere — an invitation claim and a username purchase
    /// both reach the coordinator through `startCreateUsername`'s siblings and
    /// set `currentUsername` without a handoff. A reader that qualified bridge
    /// results by the last HANDOFF's scope therefore had no way to tell "the
    /// attempt this wallet handed off" from "some other attempt running under
    /// the same label", and a same-label registration finishing on another
    /// network read as this one's success.
    ///
    /// Not re-stamped on later phases: a network switch mid-registration must
    /// not move an attempt to the scope the user happens to be looking at.
    /// Swift-only — the Obj-C surface has no use for it.
    private(set) var currentAttemptScope: RegistrationAttemptScope?

    /// Last failure description, or nil if no failure recorded.
    @objc public private(set) var lastErrorMessage: String?

    /// Funding source the SwiftUI form picked for the next
    /// `startCreateUsername:` call. Defaults to `.core` so any caller
    /// that doesn't set it (legacy Obj-C call sites, future paths)
    /// gets the pre-PR-5 behavior. Reset back to `.core` on every
    /// terminal phase so a stale value can't leak into the next
    /// attempt.
    ///
    /// Written by `CreateUsernameView`'s Continue handler immediately
    /// before `DWDashPayModel.createUsername:` so the
    /// model→bridge call picks it up. Kept as a property (not a
    /// method parameter) to avoid widening `DWDashPayProtocol`'s
    /// surface for what is effectively SwiftDashSDK-path-only state.
    @objc public var preferredFundingSource: DWIdentityFundingSource = .core

    /// Non-contested companion ("temporary") username to register in the
    /// same flow as a contested submission — see
    /// `DWIdentityRegistrationCoordinator.startCreateUsername`'s
    /// `temporaryUsername` parameter. Same lifecycle as
    /// `preferredFundingSource`: written by the SwiftUI form right before
    /// submit (nil for a plain submission), preserved across `.failed` so
    /// a retry keeps the user's choice, reset on `.completed`.
    @objc public var pendingTemporaryUsername: String?

    /// Proof-of-identity link the user chose to publish with a contested
    /// submission, in the same shape as `pendingTemporaryUsername`: written by
    /// the form right before submit, carried into the coordinator, cleared on
    /// `.completed`. Android carries it the same way — the link is captured on
    /// the request screen and published once the identity exists
    /// (`CreateIdentityService`), inside the flow that already holds the
    /// signer, so it costs no second PIN prompt.
    @objc public var pendingVerificationURL: URL?

    // MARK: - Subscriptions

    private var coordinatorSubscription: AnyCancellable?
    /// The phase behind the last `refreshFromCoordinator`, so a fresh attempt
    /// can be told from another tick of the one already running — see
    /// `currentAttemptScope`.
    private var lastObservedPhase: DWIdentityRegistrationController.Phase?

    private override init() {
        super.init()
        wireCoordinatorObservation()
    }

    // MARK: - Obj-C action surface

    /// Start the new-user create-username flow. The completion block
    /// fires on the main queue with either a hex-encoded 32-byte
    /// identity id or an NSError. Observers of
    /// `DWDashPayRegistrationStatusUpdatedNotification` see phase
    /// transitions in real time.
    @objc(startCreateUsername:completion:)
    public func startCreateUsername(
        _ username: String,
        completion: @escaping (String?, NSError?) -> Void
    ) {
        let source = preferredFundingSource
        let temporaryUsername = sanitizedTemporaryUsername(for: username)
        let verificationURL = sanitizedVerificationURL(for: username)
        Self.logger.info("🪪 IDENT-BRIDGE :: startCreateUsername username=\(username, privacy: .public) funding=\(source.logLabel, privacy: .public) temporary=\(temporaryUsername ?? "none", privacy: .public) verified=\(verificationURL != nil, privacy: .public)")
        Task { @MainActor in
            do {
                let identityId = try await DWIdentityRegistrationCoordinator.shared.startCreateUsername(
                    username,
                    fundingSource: source,
                    temporaryUsername: temporaryUsername,
                    verificationURL: verificationURL)
                let hex = identityId.map { String(format: "%02x", $0) }.joined()
                completion(hex, nil)
            } catch {
                completion(nil, Self.nsError(from: error))
            }
        }
    }

    /// Restart a failed attempt with the same username.
    @objc(retryWithUsername:completion:)
    public func retry(
        username: String,
        completion: @escaping (String?, NSError?) -> Void
    ) {
        let source = preferredFundingSource
        let temporaryUsername = sanitizedTemporaryUsername(for: username)
        Self.logger.info("🪪 IDENT-BRIDGE :: retry username=\(username, privacy: .public) funding=\(source.logLabel, privacy: .public)")
        Task { @MainActor in
            do {
                let identityId = try await DWIdentityRegistrationCoordinator.shared.retry(
                    username,
                    fundingSource: source,
                    temporaryUsername: temporaryUsername)
                let hex = identityId.map { String(format: "%02x", $0) }.joined()
                completion(hex, nil)
            } catch {
                completion(nil, Self.nsError(from: error))
            }
        }
    }

    /// Abort the current attempt and reset to idle.
    @objc public func cancel() {
        Self.logger.info("🪪 IDENT-BRIDGE :: cancel")
        DWIdentityRegistrationCoordinator.shared.cancel()
    }

    /// Replacement for
    /// `DSIdentitiesManager.searchIdentityByDashpayUsername:withCompletion:`.
    /// The completion fires on the main queue with `available=YES`
    /// when the name is unregistered (i.e. the user can claim it),
    /// `available=NO` when it's taken, and a non-nil error on RPC
    /// failures.
    @objc(checkAvailability:completion:)
    public func checkAvailability(
        _ name: String,
        completion: @escaping (Bool, NSError?) -> Void
    ) {
        Task { @MainActor in
            do {
                let available = try await DWIdentityRegistrationCoordinator.shared.dpnsCheckAvailability(name)
                completion(available, nil)
            } catch {
                completion(false, Self.nsError(from: error))
            }
        }
    }

    // MARK: - Internal

    /// Resolve `pendingTemporaryUsername` for a submission of `username`.
    ///
    /// The property channel can go stale: a PIN-cancelled attempt never
    /// reaches a terminal phase (so the `.completed` cleanup doesn't
    /// run), and the legacy Obj-C entry point
    /// (`DWDashPayModel.createUsername:`) never writes the property at
    /// all. Rather than let a stale companion fail an unrelated
    /// submission at the coordinator's pre-flight pairing guard, drop —
    /// and clear — any value that doesn't validly pair with the label
    /// actually being submitted (contested main + non-contested
    /// companion). An intentional retry of the same contested attempt
    /// still pairs validly, so it keeps the user's choice.
    private func sanitizedTemporaryUsername(for username: String) -> String? {
        guard let temporary = pendingTemporaryUsername else { return nil }
        guard DWContestedNameStatusService.isContestedLabel(username),
              !DWContestedNameStatusService.isContestedLabel(temporary) else {
            Self.logger.warning("🪪 IDENT-BRIDGE :: dropping stale temporary username \(temporary, privacy: .public) for submission of \(username, privacy: .public)")
            pendingTemporaryUsername = nil
            return nil
        }
        return temporary
    }

    /// Same staleness rule as the companion: a link only belongs to a
    /// contested submission, so anything left over from an abandoned attempt
    /// is dropped rather than attached to an unrelated registration.
    private func sanitizedVerificationURL(for username: String) -> URL? {
        guard let url = pendingVerificationURL else { return nil }
        guard DWContestedNameStatusService.isContestedLabel(username) else {
            Self.logger.warning("🪪 IDENT-BRIDGE :: dropping stale verification link for submission of \(username, privacy: .public)")
            pendingVerificationURL = nil
            return nil
        }
        return url
    }

    /// Subscribe to the coordinator's published surface and mirror
    /// each transition into the cached @objc state + post the internal
    /// `stateChangedNotification`. `DWDashPayModel` is the sole
    /// observer of that notification — it mirrors the bridge's state
    /// into its own `registrationStatus` / `lastRegistrationError`
    /// and then posts the canonical
    /// `DWDashPayRegistrationStatusUpdatedNotification` for the wider
    /// UI. The bridge intentionally does NOT post the canonical name
    /// to avoid a registration-order race where existing UI observers
    /// would read stale model state.
    ///
    /// `@Published` emits in `willSet`, so a subscriber that re-reads
    /// the coordinator's properties from the sink can see stale state
    /// (the property hasn't been written yet). Pass the emitted
    /// values directly via `CombineLatest` to avoid that race and to
    /// guarantee consistency between phase and assetLockStatus.
    private func wireCoordinatorObservation() {
        let coord = DWIdentityRegistrationCoordinator.shared
        coordinatorSubscription = Publishers.CombineLatest(coord.$phase, coord.$assetLockStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, assetLockStatus in
                self?.refreshFromCoordinator(phase: phase, assetLockStatus: assetLockStatus)
            }
    }

    private func refreshFromCoordinator(
        phase: DWIdentityRegistrationController.Phase,
        assetLockStatus: Int
    ) {
        let coord = DWIdentityRegistrationCoordinator.shared
        // `failedAtPhase`, `currentUsername`, `lastErrorMessage` are
        // written by the coordinator BEFORE it flips `phase` to a
        // terminal state, so reading them here is safe — by the time
        // we observe a `.failed` / `.completed` emission, the
        // failedAtPhase / error fields already reflect the new state.
        currentState = DWRegistrationPhaseAdapter.map(
            phase: phase,
            assetLockStatus: assetLockStatus,
            fundingSource: coord.currentFundingSource,
            failedAtPhase: coord.failedAtPhase)
        switch phase {
        case .failed:
            isFailed = true
            isCompleted = false
        case .completed:
            isFailed = false
            isCompleted = true
        default:
            isFailed = false
            isCompleted = false
        }
        let previousUsername = currentUsername
        let wasActive = lastObservedPhase?.isActive ?? false
        lastObservedPhase = phase
        currentUsername = coord.currentUsername
        if let running = coord.currentUsername, !running.isEmpty {
            // An attempt begins where an inactive phase turns active — which
            // covers a retry of the SAME label after a failure, possibly on a
            // different wallet or network. A changed label is the other start,
            // and a nil scope catches a bridge built mid-registration.
            if (phase.isActive && !wasActive) || running != previousUsername || currentAttemptScope == nil {
                currentAttemptScope = RegistrationAttemptScope.current
            }
        } else {
            currentAttemptScope = nil
        }
        lastErrorMessage = coord.lastErrorMessage

        // Reset preferredFundingSource to the safe default on
        // `.completed` only. On `.failed`, preserve the source so a
        // retry (which goes through `DWDashPayModel.retry` →
        // `createUsername:` → bridge without re-running the
        // SwiftUI picker) uses the same funding the user originally
        // picked — flipping a PP-funded failure back to `.core` would
        // strand a PP-only wallet on a path that has no Core balance.
        if case .completed = phase {
            preferredFundingSource = .core
            pendingTemporaryUsername = nil
            pendingVerificationURL = nil
        }

        // Internal notification — DWDashPayModel observes this,
        // rebuilds its own state, and then posts the canonical
        // DWDashPayRegistrationStatusUpdatedNotification for the
        // wider UI. We avoid posting the canonical name here so
        // existing observers can't see stale `DWDashPayModel`
        // state during the registration-order window.
        NotificationCenter.default.post(
            name: DWIdentityRegistrationBridge.stateChangedNotification,
            object: nil)

        // `assetLockStatus` is populated by polling the persisted
        // `PersistentAssetLock`, so a non-zero value proves that the SDK's
        // funding purpose/status is now available to the transaction
        // projection. A terminal phase is the fallback for a fast FFI call
        // that completes between poll ticks. Notify on failures too: the
        // asset lock may have been persisted before a later Platform step
        // failed, and the pending history row still needs its real purpose
        // and amount in the current session.
        let transactionProjectionMayHaveChanged: Bool
        switch phase {
        case .completed, .failed:
            transactionProjectionMayHaveChanged = true
        default:
            transactionProjectionMayHaveChanged = assetLockStatus > 0
        }
        if transactionProjectionMayHaveChanged {
            NotificationCenter.default.post(
                name: .swiftDashSDKTransactionProjectionDidChange,
                object: nil)
        }
    }

    private static func nsError(from error: Error) -> NSError {
        // PIN / biometric cancellation is a user action, not a failure.
        // Surface it as the canonical Cocoa user-cancel (domain, code)
        // so the awaiting SwiftUI form can suppress the error popup
        // without depending on the Swift enum → NSError bridging
        // ordinal (which shifts if `CoordinatorError`'s cases reorder).
        if let coordError = error as? DWIdentityRegistrationCoordinator.CoordinatorError,
           case .authCancelled = coordError {
            return NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        }
        if let nsError = error as NSError? {
            return nsError
        }
        return NSError(
            domain: "DWIdentityRegistrationBridge",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
    }
}
