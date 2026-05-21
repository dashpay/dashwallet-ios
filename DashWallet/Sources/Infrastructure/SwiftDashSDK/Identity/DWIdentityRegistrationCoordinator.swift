//
//  DWIdentityRegistrationCoordinator.swift
//  DashWallet
//
//  App-scoped singleton orchestrator for SwiftDashSDK-backed DashPay
//  identity + DPNS username registration.
//
//  Sequence:
//    1. PIN / biometric gate via DWIdentityAuthorizer.
//    2. Pre-derive identity public keys + persist privates to Keychain
//       (`ManagedPlatformWallet.prePersistIdentityKeysForRegistration`).
//    3. Build asset-lock tx + broadcast + wait for IS/CL + submit
//       IdentityCreate state transition
//       (`registerIdentityWithFunding`).
//    4. Submit DPNS preorder + register state transitions
//       (`registerDpnsName`).
//    5. Mirror success into DWGlobalOptions for the legacy Obj-C
//       identity-read sites.
//
//  Progress is exposed two ways:
//    - `@Published phase` mirrored from `DWIdentityRegistrationController`
//      (idle / preparingKeys / inFlight / completed / failed).
//    - `@Published assetLockStatus` polled from SwiftData every 0.5s
//      while `phase == .inFlight`, sourced from the matching
//      `PersistentAssetLock` row.
//  The `DWRegistrationPhaseAdapter` collapses both onto the existing
//  3-state `DWDPRegistrationState` for the `DWDPRegistrationStatusViewController`
//  UI.
//
//  v1 scope:
//    - Single identity per wallet (`identityIndex` pinned at 0).
//    - Two funding paths (PR 5):
//      * Core-funded via `registerIdentityWithFunding` (default).
//      * Platform Payment via `registerIdentityFromAddresses` —
//        spends credits already on DIP-17 platform addresses.
//        Skips the Core-chain asset-lock IS/CL wait.
//    - No crash-resume (`resumeIdentityWithAssetLock` deferred to v2).
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@MainActor
final class DWIdentityRegistrationCoordinator: ObservableObject {

    static let shared = DWIdentityRegistrationCoordinator()

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.identity-coordinator")

    /// v1 pins identityIndex to 0; dashwallet only ever has one
    /// DashPay identity per wallet.
    private static let pinnedIdentityIndex: UInt32 = 0

    /// Number of identity keys to pre-derive. Matches the
    /// `SwiftExampleApp` reference (`Self.defaultKeyCount`).
    private static let defaultKeyCount: UInt32 = 4

    /// BIP44 account index used for asset-lock funding. dashwallet
    /// uses the default account only.
    private static let defaultAccountIndex: UInt32 = 0

    /// Asset-lock polling interval while `phase == .inFlight`. The
    /// FFI emits at most a handful of status transitions per
    /// registration (Built → Broadcast → IS/CL → Consumed), so a
    /// 0.5s cadence is plenty without burning CPU.
    private static let assetLockPollInterval: TimeInterval = 0.5

    /// Credits per DASH on Platform — 1e11 credits per DASH per
    /// `SwiftExampleApp/Views/CreateIdentityView.swift:54`. Used to
    /// convert the `DWDP_MIN_BALANCE_*` duff-denominated targets to
    /// the credit-denominated targets that `IdentityAddressInput`
    /// expects on the Platform Payment funding path.
    /// 1 duff = 1000 credits.
    private static let creditsPerDuff: UInt64 = 1_000

    // MARK: - Published surface

    /// Current phase, mirrored from the active controller.
    @Published private(set) var phase: DWIdentityRegistrationController.Phase = .idle

    /// Latest `PersistentAssetLock.statusRaw` for the active
    /// registration (0 = Built, 1 = Broadcast, 2 = InstantSendLocked,
    /// 3 = ChainLocked, 4 = Consumed). 0 outside of `.inFlight`.
    @Published private(set) var assetLockStatus: Int = 0

    /// When the most recent failure happened. Consulted by
    /// `DWRegistrationPhaseAdapter.map(...)` so the existing UI's
    /// 3-state error copies are accurate to where the chain broke.
    private(set) var failedAtPhase: DWDPRegistrationState?

    /// Last error description, for surfacing to the registration UI
    /// when phase is `.failed`.
    private(set) var lastErrorMessage: String?

    /// Username being registered. Stashed at submit time so the
    /// `.completed` mirror can write DWGlobalOptions.dashpayUsername.
    private(set) var currentUsername: String?

    /// Funding source for the in-flight attempt (the value the
    /// coordinator's caller passed into `startCreateUsername(_:fundingSource:)`).
    /// Read by `DWIdentityRegistrationBridge.refreshFromCoordinator`
    /// when mapping phase → UI state so the Platform Payment path
    /// can skip the asset-lock progression rule in
    /// `DWRegistrationPhaseAdapter`. Defaults to `.core` outside of
    /// an active attempt.
    private(set) var currentFundingSource: DWIdentityFundingSource = .core

    // MARK: - Internal state

    private var controller: DWIdentityRegistrationController?
    private var phaseSubscription: AnyCancellable?
    private var assetLockPollingTask: Task<Void, Never>?

    private let authorizer = DWIdentityAuthorizer()

    private init() {}

    // MARK: - Errors

    enum CoordinatorError: LocalizedError {
        case noWallet
        case noNetwork
        case noModelContainer
        case noSDK
        case authCancelled
        case authFailed
        case keyDerivation(Error)
        case identityRegistration(Error)
        case dpnsRegistration(Error)
        case availabilityCheck(Error)
        case insufficientPlatformCredits(required: UInt64, available: UInt64)
        case alreadyInFlight

        var errorDescription: String? {
            switch self {
            case .noWallet:
                return NSLocalizedString("Wallet is not ready for identity registration", comment: "DashPay")
            case .noNetwork:
                return NSLocalizedString("Network is not configured", comment: "DashPay")
            case .noModelContainer:
                return NSLocalizedString("Storage is not configured", comment: "DashPay")
            case .noSDK:
                return NSLocalizedString("SDK is not initialized", comment: "DashPay")
            case .authCancelled:
                return NSLocalizedString("Authentication cancelled", comment: "DashPay")
            case .authFailed:
                return NSLocalizedString("Authentication failed", comment: "DashPay")
            case .keyDerivation(let underlying):
                return underlying.localizedDescription
            case .identityRegistration(let underlying):
                return underlying.localizedDescription
            case .dpnsRegistration(let underlying):
                return underlying.localizedDescription
            case .availabilityCheck(let underlying):
                return underlying.localizedDescription
            case .insufficientPlatformCredits:
                return NSLocalizedString("Not enough Platform credits to register an identity", comment: "DashPay")
            case .alreadyInFlight:
                return NSLocalizedString("Identity registration already in progress", comment: "DashPay")
            }
        }
    }

    // MARK: - Public API

    /// Run the full new-user create-username flow:
    /// PIN gate → pre-derive keys → IdentityCreate → DPNS register.
    /// On success, mirrors the username into `DWGlobalOptions` and
    /// returns the 32-byte identifier. On failure, sets
    /// `failedAtPhase` + `lastErrorMessage` and rethrows.
    ///
    /// `fundingSource` selects between Core BIP44 UTXOs
    /// (`registerIdentityWithFunding` → asset-lock + IS/CL + ST) and
    /// DIP-17 Platform Payment addresses
    /// (`registerIdentityFromAddresses` → direct address-funded ST).
    /// Defaults to `.core` for callers that don't care (legacy
    /// Obj-C entry points, retries after a terminal phase).
    @discardableResult
    func startCreateUsername(
        _ username: String,
        fundingSource: DWIdentityFundingSource = .core
    ) async throws -> Identifier {
        Self.logger.info("🪪 IDENT-COORD :: startCreateUsername username=\(username, privacy: .public) funding=\(fundingSource == .core ? "core" : "pp", privacy: .public)")

        // Preconditions — resolved once up-front so failures are
        // surfaced before the PIN prompt.
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            Self.logger.error("🪪 IDENT-COORD :: no managed wallet")
            throw CoordinatorError.noWallet
        }
        guard let network = SwiftDashSDKHost.shared.runningNetwork else {
            Self.logger.error("🪪 IDENT-COORD :: no running network")
            throw CoordinatorError.noNetwork
        }
        guard let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            Self.logger.error("🪪 IDENT-COORD :: no model container")
            throw CoordinatorError.noModelContainer
        }

        // Single-flight guard. The FFI calls we're about to make
        // (`registerIdentityWithFunding` / `registerIdentityFromAddresses`
        // / `registerDpnsName`) can't be cancelled — `resetState()`
        // would drop our observers but the underlying network work
        // keeps racing to its terminal. Letting a second submit in
        // would race two asset-lock broadcasts against the same
        // identity index and tear up the DWGlobalOptions mirror on
        // whichever completion fires last. Reject overlapping starts
        // and let the existing attempt finish or fail terminally.
        let currentPhase = phase
        switch currentPhase {
        case .preparingKeys, .inFlight:
            Self.logger.warning("🪪 IDENT-COORD :: rejecting concurrent start; phase=\(String(describing: currentPhase), privacy: .public)")
            throw CoordinatorError.alreadyInFlight
        case .idle, .completed, .failed:
            break
        }

        // Tear down any prior terminal controller / subscription
        // before creating a fresh attempt. Safe even if no prior
        // attempt ran — `resetState()` is idempotent.
        resetState()

        currentUsername = username
        currentFundingSource = fundingSource
        failedAtPhase = nil
        lastErrorMessage = nil

        let newController = DWIdentityRegistrationController()
        controller = newController
        wireController(newController)
        // Asset-lock polling only applies to the Core-funded path —
        // the Platform Payment path never writes a `PersistentAssetLock`
        // row, and polling would just keep `assetLockStatus` pegged at
        // 0 throughout the FFI call (which would force the adapter
        // backwards to `.processingPayment` on every emit if the
        // funding-source branch in the adapter wasn't honored).
        if fundingSource == .core {
            startAssetLockPolling(walletId: wallet.walletId, modelContainer: modelContainer)
        }

        // PIN / biometric gate. Throws on cancel / failure; the
        // controller stays at `.idle` so the UI doesn't show
        // "Processing payment" for a cancellation.
        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            resetState()
            throw CoordinatorError.authCancelled
        } catch {
            lastErrorMessage = CoordinatorError.authFailed.localizedDescription
            newController.enterFailed(lastErrorMessage ?? "")
            throw CoordinatorError.authFailed
        }

        // Step 1: pre-derive identity public keys + persist privates
        // to Keychain. Synchronous on the FFI side; the resolver
        // callback reads the mnemonic via WalletStorage.
        newController.enterPreparingKeys()
        let pubkeys: [ManagedPlatformWallet.IdentityPubkey]
        do {
            pubkeys = try wallet.prePersistIdentityKeysForRegistration(
                identityIndex: Self.pinnedIdentityIndex,
                keyCount: Self.defaultKeyCount,
                network: network)
            Self.logger.info("🪪 IDENT-COORD :: pre-derived \(pubkeys.count, privacy: .public) keys")
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: key derivation failed: \(String(describing: error), privacy: .public)")
            failedAtPhase = .processingPayment
            lastErrorMessage = error.localizedDescription
            newController.enterFailed(error.localizedDescription)
            throw CoordinatorError.keyDerivation(error)
        }

        // Build the signer used by both IdentityCreate and DPNS
        // register. The signer's lifetime is the whole chain — the
        // FFI captures an unretained pointer to it, so we hold the
        // strong reference here for the duration of the awaits.
        let signer = KeychainSigner(modelContainer: modelContainer)

        // Step 2: IdentityCreate. Two paths depending on funding
        // source, OR skipped entirely if a prior attempt at this
        // identity index already landed an identity on Platform —
        // re-running IdentityCreate would fail with a unique-key
        // collision because the DIP-9 derived authentication keys
        // at `pinnedIdentityIndex` are deterministic per wallet and
        // already bound to the prior identity in Platform's unique-
        // key index. The resume path picks up the persisted
        // identityId from SwiftData and falls through to DPNS
        // register so a transient failure between IdentityCreate
        // success and DPNS register can be retried without leaving
        // the user stuck.
        newController.enterInFlight()
        let identityId: Identifier
        if let resumedId = lookupExistingIdentityId(
            walletId: wallet.walletId,
            modelContainer: modelContainer)
        {
            Self.logger.info("🪪 IDENT-COORD :: resume — identity already exists at index \(Self.pinnedIdentityIndex, privacy: .public), skipping IdentityCreate")
            identityId = resumedId
        } else {
        do {
            switch fundingSource {
            case .core:
                let result = try await wallet.registerIdentityWithFunding(
                    amountDuffs: DWDP_MIN_BALANCE_TO_CREATE_USERNAME,
                    accountIndex: Self.defaultAccountIndex,
                    identityIndex: Self.pinnedIdentityIndex,
                    identityPubkeys: pubkeys,
                    signer: signer)
                identityId = result.0

            case .platformPayment:
                let targetCredits = UInt64(DWDP_MIN_BALANCE_TO_CREATE_USERNAME) * Self.creditsPerDuff
                let inputs = try buildPlatformPaymentInputs(
                    walletId: wallet.walletId,
                    modelContainer: modelContainer,
                    targetCredits: targetCredits)
                Self.logger.info("🪪 IDENT-COORD :: PP inputs=\(inputs.count, privacy: .public) targetCredits=\(targetCredits, privacy: .public)")
                let created = try await wallet.registerIdentityFromAddresses(
                    inputs: inputs,
                    output: nil,
                    identityIndex: Self.pinnedIdentityIndex,
                    identityPubkeys: pubkeys,
                    identitySigner: signer,
                    addressSigner: signer)
                identityId = created.identityId
            }
            Self.logger.info("🪪 IDENT-COORD :: identity created, id=\(identityId.map { String(format: "%02x", $0) }.joined().prefix(8), privacy: .public)…")
        } catch let coordError as CoordinatorError {
            // `buildPlatformPaymentInputs` throws our own typed error
            // before any FFI call — surface as a registration failure
            // anchored at `.processingPayment` since nothing has hit
            // the network yet.
            Self.logger.error("🪪 IDENT-COORD :: identity creation precondition failed: \(String(describing: coordError), privacy: .public)")
            failedAtPhase = .processingPayment
            lastErrorMessage = coordError.localizedDescription
            newController.enterFailed(coordError.localizedDescription)
            throw coordError
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: identity creation failed: \(String(describing: error), privacy: .public)")
            // Decide whether failure happened during payment processing
            // (asset-lock not yet IS/CL'd) or during identity create
            // (asset-lock confirmed but ST failed). The polled
            // assetLockStatus reflects the latest known state — only
            // meaningful for the Core path; Platform Payment has no
            // asset-lock and always anchors at `.creatingID` since the
            // FFI submit was the only on-chain step.
            switch fundingSource {
            case .core:
                failedAtPhase = assetLockStatus < 2 ? .processingPayment : .creatingID
            case .platformPayment:
                failedAtPhase = .creatingID
            }
            lastErrorMessage = error.localizedDescription
            newController.enterFailed(error.localizedDescription)
            throw CoordinatorError.identityRegistration(error)
        }
        } // end if-let resumedId

        // Step 3: DPNS preorder + register.
        do {
            _ = try await wallet.registerDpnsName(
                identityId: identityId,
                name: username,
                signer: signer)
            Self.logger.info("🪪 IDENT-COORD :: DPNS name registered: \(username, privacy: .public)")
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: DPNS registration failed: \(String(describing: error), privacy: .public)")
            failedAtPhase = .registrationUsername
            lastErrorMessage = error.localizedDescription
            newController.enterFailed(error.localizedDescription)
            throw CoordinatorError.dpnsRegistration(error)
        }

        // Step 4: mark complete + mirror to DWGlobalOptions. The
        // controller transition triggers the phaseSubscription
        // sink which posts the notification + writes
        // DWGlobalOptions.
        newController.enterCompleted(identityId: identityId)
        Self.logger.info("🪪 IDENT-COORD :: registration complete")
        return identityId
    }

    /// Restart the flow after a `.failed` terminal phase. Identical
    /// to `startCreateUsername(_:fundingSource:)` — the prior
    /// controller is discarded and a fresh attempt runs end-to-end.
    /// The Keychain-persisted identity keys from the prior attempt
    /// are overwritten during pre-derive.
    @discardableResult
    func retry(
        _ username: String,
        fundingSource: DWIdentityFundingSource = .core
    ) async throws -> Identifier {
        Self.logger.info("🪪 IDENT-COORD :: retry username=\(username, privacy: .public) funding=\(fundingSource == .core ? "core" : "pp", privacy: .public)")
        return try await startCreateUsername(username, fundingSource: fundingSource)
    }

    /// Abort the current attempt and reset to `.idle`. Safe to call
    /// from any phase. NOTE: cannot truly cancel an in-flight FFI
    /// call — `registerIdentityWithFunding` will still race to its
    /// terminal — but stops the coordinator from observing the
    /// outcome, which is the user-visible behavior we want.
    func cancel() {
        Self.logger.info("🪪 IDENT-COORD :: cancel")
        resetState()
    }

    /// Forward DPNS availability checks to the SDK. Used by
    /// `DWCheckExistenceUsernameValidationRule` to replace
    /// `DSIdentitiesManager.searchIdentityByDashpayUsername:`.
    func dpnsCheckAvailability(_ name: String) async throws -> Bool {
        guard let sdk = SwiftDashSDKHost.shared.sdk else {
            throw CoordinatorError.noSDK
        }
        do {
            return try await sdk.dpnsCheckAvailability(name: name)
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: dpns availability check failed: \(String(describing: error), privacy: .public)")
            throw CoordinatorError.availabilityCheck(error)
        }
    }

    // MARK: - Internal helpers

    private func wireController(_ controller: DWIdentityRegistrationController) {
        phaseSubscription = controller.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] newPhase in
                self?.handlePhaseChange(newPhase)
            }
    }

    private func handlePhaseChange(_ newPhase: DWIdentityRegistrationController.Phase) {
        phase = newPhase

        // Mirror to DWGlobalOptions on terminal success so existing
        // Obj-C consumers (87 sites referencing
        // DSBlockchainIdentity.currentDashpayUsername) keep working
        // until row #17 migrates them individually.
        if case .completed = newPhase, let username = currentUsername {
            DWGlobalOptions.sharedInstance().dashpayUsername = username
            DWGlobalOptions.sharedInstance().dashpayRegistrationCompleted = true
        }

        // Stop asset-lock polling on terminal phases — no further
        // statusRaw transitions will arrive.
        switch newPhase {
        case .completed, .failed:
            assetLockPollingTask?.cancel()
            assetLockPollingTask = nil
        default:
            break
        }

        // The bridge observes this @Published surface and posts the
        // Obj-C notification; the coordinator stays Combine-only so
        // there's a single owner of NotificationCenter side-effects.
    }

    private func startAssetLockPolling(walletId: Data, modelContainer: ModelContainer) {
        assetLockPollingTask?.cancel()
        assetLockPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.assetLockPollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.pollAssetLockStatus(walletId: walletId, modelContainer: modelContainer)
            }
        }
    }

    private func pollAssetLockStatus(walletId: Data, modelContainer: ModelContainer) async {
        // Only poll while the registration is in-flight; outside of
        // that, the published value should sit at 0 / last terminal.
        guard case .inFlight = phase else { return }

        let context = modelContainer.mainContext
        let pinnedIndex = Int32(Self.pinnedIdentityIndex)
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId && row.identityIndexRaw == pinnedIndex
            }
        )
        descriptor.fetchLimit = 1
        do {
            let rows = try context.fetch(descriptor)
            guard let row = rows.first else { return }
            if assetLockStatus != row.statusRaw {
                assetLockStatus = row.statusRaw
                Self.logger.debug("🪪 IDENT-COORD :: assetLockStatus → \(row.statusRaw, privacy: .public)")
            }
        } catch {
            Self.logger.warning("🪪 IDENT-COORD :: asset-lock poll failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func resetState() {
        phaseSubscription?.cancel()
        phaseSubscription = nil
        assetLockPollingTask?.cancel()
        assetLockPollingTask = nil
        controller?.resetToIdle()
        controller = nil
        phase = .idle
        assetLockStatus = 0
        failedAtPhase = nil
        lastErrorMessage = nil
        currentUsername = nil
        currentFundingSource = .core
    }

    /// Look up the persisted identity at `pinnedIdentityIndex` for
    /// the given wallet. Returns the 32-byte identifier if found, or
    /// `nil` if no prior attempt completed IdentityCreate.
    ///
    /// Used by `startCreateUsername` to skip the IdentityCreate step
    /// when a previous attempt landed the identity but failed before
    /// DPNS register completed. Re-running IdentityCreate in that
    /// state would always fail with a unique-key collision (the
    /// DIP-9 derived authentication keys are deterministic per
    /// identity index), so detection + resume is the only way to
    /// recover without bumping the index.
    private func lookupExistingIdentityId(
        walletId: Data,
        modelContainer: ModelContainer
    ) -> Identifier? {
        let context = modelContainer.mainContext
        let pinnedIndex = Self.pinnedIdentityIndex
        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { identity in
                identity.wallet?.walletId == walletId
                    && identity.identityIndex == pinnedIndex
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.identityId
    }

    /// Greedy-select DIP-17 Platform Payment addresses to cover
    /// `targetCredits`, returning the flat `IdentityAddressInput` list
    /// `registerIdentityFromAddresses` expects.
    ///
    /// Ported from `SwiftExampleApp/Views/CreateIdentityView.swift:1086-1113`.
    /// Sorts candidates by balance descending so the smallest number
    /// of inputs covers the target — keeps the resulting state
    /// transition compact.
    ///
    /// `PersistentPlatformAddress.balance` is in credits (1e11 per
    /// DASH), matching `IdentityAddressInput.credits`, so no
    /// conversion is needed inside this function. Each `spend` is
    /// clamped to `addr.balance` so a single fat address doesn't
    /// over-spend; remaining target rolls onto the next address.
    ///
    /// Throws `CoordinatorError.insufficientPlatformCredits` if the
    /// candidate set can't cover the target — surfacing the precise
    /// shortfall is more useful than a generic FFI error from the
    /// SDK on a too-short inputs list.
    private func buildPlatformPaymentInputs(
        walletId: Data,
        modelContainer: ModelContainer,
        targetCredits: UInt64
    ) throws -> [ManagedPlatformWallet.IdentityAddressInput] {
        let context = modelContainer.mainContext
        // PlatformPayment accounts (`accountType == 14`) hold the only
        // `platformAddresses`. Read every account for this wallet —
        // dashwallet only has one PP account today but the example
        // app's pattern doesn't assume that, and the cost is the same.
        let accountDescriptor = FetchDescriptor<PersistentAccount>(
            predicate: #Predicate { account in
                account.accountType == 14
                    && account.wallet.walletId == walletId
            }
        )
        let accounts: [PersistentAccount]
        do {
            accounts = try context.fetch(accountDescriptor)
        } catch {
            Self.logger.error("🪪 IDENT-COORD :: PP account fetch failed: \(String(describing: error), privacy: .public)")
            throw CoordinatorError.identityRegistration(error)
        }
        let candidates = accounts
            .flatMap { $0.platformAddresses }
            .filter { $0.balance > 0 }
            .sorted { $0.balance > $1.balance }
        let totalAvailable = candidates.reduce(UInt64(0)) { $0 + $1.balance }
        guard totalAvailable >= targetCredits else {
            throw CoordinatorError.insufficientPlatformCredits(
                required: targetCredits,
                available: totalAvailable)
        }
        var remaining = targetCredits
        var inputs: [ManagedPlatformWallet.IdentityAddressInput] = []
        for addr in candidates {
            guard remaining > 0 else { break }
            let spend = min(addr.balance, remaining)
            inputs.append(
                ManagedPlatformWallet.IdentityAddressInput(
                    addressType: addr.addressType,
                    hash: addr.addressHash,
                    credits: spend))
            remaining -= spend
        }
        return inputs
    }
}
