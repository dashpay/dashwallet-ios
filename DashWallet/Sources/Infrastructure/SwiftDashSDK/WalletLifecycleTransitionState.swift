//
//  WalletLifecycleTransitionState.swift
//  DashWallet
//

import Combine
import Foundation

/// Central published state of wallet preparation and interactive lifecycle
/// operations — network/wallet switches, removal and wipe. Two
/// explicit roles, and deliberately nothing more:
///
/// 1. **Presentation**: `phase` drives the app-wide blocking overlay
///    (`WalletLifecycleOverlayPresenter`), hosted in its own UIWindow so it
///    survives the root/tab rebuilds these operations trigger.
/// 2. **Admission gate for INTERACTIVE operations**: `tryBegin` is an atomic
///    MainActor check-and-set — every interactive entry point calls it
///    synchronously (no suspension between check and set), so at most one
///    interactive operation is admitted at a time.
///
/// What this type does NOT do: it does not serialize execution — the
/// runtime's `SerialAsyncLifecycleQueue` and the wiper's
/// `WalletWipeSerialExecutor` own that — and non-interactive network writers
/// (reinstall recovery, sole-network selection) bypass it entirely, matching
/// their pre-existing silent behavior.
@MainActor
final class WalletLifecycleTransitionState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case openingWallet
        case failedWalletOpen(WalletPreparationFailure)
        /// Launch hold while the DashSync → SwiftDashSDK key migrator imports
        /// an upgrading user's wallet. Owned by
        /// `LegacyWalletMigrationLaunchCoordinator`; the runtime may take the
        /// window over with `.openingWallet` once the wallet has landed.
        case migratingLegacyWallet
        /// The migrator settled without delivering a wallet while DashSync
        /// material is still in the keychain, or it did not settle in time.
        /// Blocking: the card offers Try Again, Export Logs and Help, never
        /// wallet creation — the user's wallet is still on the device.
        case failedLegacyMigration(WalletPreparationFailure)
        case switchingNetwork(from: WalletEnvironment.NetworkKind, to: WalletEnvironment.NetworkKind)
        /// The network switch failed after the old runtime was already torn
        /// down — the app may have no working manager, so the overlay stays
        /// up, blocking, offering Retry toward `target`.
        case failedNetworkSwitch(from: WalletEnvironment.NetworkKind, target: WalletEnvironment.NetworkKind, message: String?)
        /// Runtime wallet switch in flight (same network: stop → rebind →
        /// start). `targetName` is display-only.
        case switchingWallet(targetName: String?)
        /// Per-wallet removal in flight (`deleteLogicalWallet`).
        case removingWallet
        /// Add-wallet provisioning in flight (`SwiftDashSDKHost.addWallet` —
        /// blocking wallet creation on the current network plus the other
        /// network's mirror). `isImport` picks the card copy
        /// (Creating/Importing wallet…).
        case addingWallet(isImport: Bool)
        /// The wallet switch failed. The previous wallet is NOT guaranteed
        /// active afterwards (the registry is repointed before the rebuild
        /// and the host may have bound a fallback wallet), so the card
        /// blocks, offering Retry toward `targetId` and Switch Back toward
        /// `previousId`.
        case failedWalletSwitch(targetId: Data, targetName: String?, previousId: Data?, message: String?)
        /// A removal failed with the runtime alive — dismissable (OK → idle);
        /// the wiper leaves wallet state retryable by design.
        case failedWalletRemoval(message: String?)
        /// A full wallet wipe in flight — until the wiper's barrier reports
        /// data deleted AND runtime torn down. Owned by the Obj-C wipe flows
        /// (`DWAppRootViewController` Delete All, `DWRecoverViewController`
        /// phrase-authorized wipe) through `WalletLifecycleOverlayBridge`;
        /// `title` is the flow's progress copy ("Deleting All Wallets…" /
        /// "Deleting Wallet…"). Failure alerts stay UIKit (shown after
        /// `finish()`), so there is no failed-wipe phase.
        case wiping(title: String?)

        /// Compact form for gate/telemetry log lines (no wallet ids beyond
        /// what the operation logs themselves already include).
        var logLabel: String {
            switch self {
            case .idle: return "idle"
            case .openingWallet: return "openingWallet"
            case .failedWalletOpen: return "failedWalletOpen"
            case .migratingLegacyWallet: return "migratingLegacyWallet"
            case .failedLegacyMigration: return "failedLegacyMigration"
            case .switchingNetwork(_, let to): return "switchingNetwork(\(to))"
            case .failedNetworkSwitch(_, let target, _): return "failedNetworkSwitch(\(target))"
            case .switchingWallet: return "switchingWallet"
            case .removingWallet: return "removingWallet"
            case .addingWallet: return "addingWallet"
            case .failedWalletSwitch: return "failedWalletSwitch"
            case .failedWalletRemoval: return "failedWalletRemoval"
            case .wiping: return "wiping"
            }
        }
    }

    static let shared = WalletLifecycleTransitionState()

    @Published private(set) var phase: Phase = .idle
    /// Retained for an interactive switch's failure card; its owner keeps the
    /// phase and retry destination while the wallet-opening step runs.
    @Published private(set) var preparationFailure: WalletPreparationFailure?
    /// True from the launch hold's `begin` until it reports. `prepareWallet`
    /// hands a taken-over window back to the hold only while this is set:
    /// a hold that already reported has no watcher, timeout or Try Again
    /// left to own the window, so restoring its phase would strand a
    /// blocking card nothing can clear.
    private(set) var legacyLaunchHoldActive = false
    /// A verdict the hold reached while the runtime owned the window
    /// (`failLegacyMigration` during `.openingWallet`). The hand-back in
    /// `prepareWallet` presents it instead of the phase saved before the
    /// open, so the user gets the card with Try Again rather than a
    /// progress card nothing can clear. Cleared with the hold's lifetime and
    /// by every new migration attempt.
    private(set) var deferredLegacyFailure: WalletPreparationFailure?

    /// Only the launch hold flips this, around its own lifetime.
    func setLegacyLaunchHold(active: Bool) {
        legacyLaunchHoldActive = active
        if !active { deferredLegacyFailure = nil }
    }

    /// Internal (not private) so the admission-matrix table test can build
    /// fresh instances; production code uses only `shared`.
    init() {}

    /// Automatic kicks must leave the failure card and any unsent support
    /// draft intact. Explicit Retry / Sync Now use their existing entry points.
    var allowsAutomaticWalletPreparation: Bool {
        if case .failedWalletOpen = phase { return false }
        return true
    }

    /// Atomically admit `next` as the active operation. Admission rules: any
    /// operation may begin from `.idle`; a network switch may also begin from
    /// `.failedNetworkSwitch` (the failure card's Retry / Switch Back); a
    /// wallet switch may also begin from `.failedWalletSwitch` (Retry /
    /// Switch Back); the legacy-migration hold may be retried from its
    /// failure card, and the runtime's wallet open may take the window over
    /// from either legacy-migration phase once the imported wallet exists;
    /// an independently authorized wipe may begin from any failure phase.
    /// Admission does not imply a reset button on a failure card: a
    /// database-open failure offers Retry and Help, preserving data.
    /// Every other combination is rejected and the caller surfaces or logs it.
    func tryBegin(_ next: Phase) -> Bool {
        if next == .migratingLegacyWallet { deferredLegacyFailure = nil }
        switch (phase, next) {
        case (.idle, .openingWallet),
             (.failedWalletOpen, .openingWallet),
             (.failedWalletOpen, .wiping),
             (.idle, .migratingLegacyWallet),
             (.failedLegacyMigration, .migratingLegacyWallet),
             (.migratingLegacyWallet, .openingWallet),
             (.failedLegacyMigration, .openingWallet),
             (.failedLegacyMigration, .wiping),
             (.idle, .switchingNetwork),
             (.idle, .switchingWallet),
             (.idle, .removingWallet),
             (.idle, .addingWallet),
             (.idle, .wiping),
             (.failedNetworkSwitch, .switchingNetwork),
             (.failedWalletSwitch, .switchingWallet),
             // Composite add → switch: the add flow's own continuation into
             // its post-add switch, without dropping the window through idle.
             // Deliberately not owner-scoped — in practice only the add flow
             // can reach it, because the blocking overlay window covers every
             // other interactive entry point for `.addingWallet`'s lifetime.
             (.addingWallet, .switchingWallet),
             // Permit an independently authorized wipe after a failure.
             // The gate alone neither offers nor authorizes deletion.
             (.failedNetworkSwitch, .wiping),
             (.failedWalletSwitch, .wiping),
             (.failedWalletRemoval, .wiping):
            phase = next
            preparationFailure = nil
            return true
        default:
            DWLogger.log("🚦 LIFECYCLE tryBegin rejected: phase=\(phase.logLabel) next=\(next.logLabel)")
            return false
        }
    }

    /// Move a busy operation to its next in-flight phase (wallet switch →
    /// removal) WITHOUT passing through `.idle`, so the overlay window never
    /// flickers down mid-operation.
    func advance(to next: Phase) {
        guard phase != .idle else {
            // Never legal — but in Release a bare assert would present an
            // overlay phase with no owner left to clear it, so reject
            // instead. The caller's operation continues without the window.
            DWLogger.log("🚦 LIFECYCLE advance rejected from idle: next=\(next.logLabel)")
            assertionFailure("advance(to:) requires an operation in flight")
            return
        }
        phase = next
    }

    func finish() {
        // An operation that held the window while the launch hold reached
        // its verdict releases it to that verdict, not to idle: the card
        // and its Try Again would otherwise never appear.
        if legacyLaunchHoldActive, let deferred = deferredLegacyFailure {
            deferredLegacyFailure = nil
            phase = .failedLegacyMigration(deferred)
            preparationFailure = deferred
            return
        }
        phase = .idle
        preparationFailure = nil
    }

    func fail(_ failure: Phase) {
        phase = failure
    }

    /// The legacy-migration hold ended without a wallet. Keeps the window up
    /// and records the diagnostic the card's Export Logs / Help read. Only
    /// the hold's owner calls this, and only from its own phase.
    func failLegacyMigration(_ failure: WalletPreparationFailure) {
        guard legacyLaunchHoldActive else {
            DWLogger.log("🚦 LIFECYCLE failLegacyMigration rejected: no active hold, phase=\(phase.logLabel)")
            return
        }
        guard phase == .migratingLegacyWallet else {
            // Another operation owns the window (the runtime's open of the
            // imported wallet, or a switch): keep the verdict. It is
            // presented when that operation releases the window — by
            // `prepareWallet`'s hand-back or by `finish()`.
            deferredLegacyFailure = failure
            DWLogger.log("🚦 LIFECYCLE failLegacyMigration deferred behind \(phase.logLabel)")
            return
        }
        phase = .failedLegacyMigration(failure)
        preparationFailure = failure
    }

    /// Uses the existing switch overlay when an interactive operation owns
    /// it. Otherwise owns a startup overlay until local wallet data is ready.
    /// Opening failures never reset data, and never dismiss a switch's card.
    /// The launch hold's phases are taken over the same way: once the
    /// imported wallet exists the runtime's open owns the window, so the
    /// hold's release cannot dismiss it mid-open and a database failure
    /// lands on `.failedWalletOpen` as usual. An open that fails for an
    /// unrelated reason (no selectable wallet yet, for instance) hands the
    /// window back to the hold instead of dismissing it: the hold is still
    /// waiting for a wallet, and without its window the launch would sit on
    /// an empty root.
    func prepareWallet<T>(
        open: () async throws -> T,
        failure: (Error) -> WalletPreparationFailure?
    ) async throws -> T {
        let ownsOverlay: Bool
        let takenOverHold: Phase?
        switch phase {
        case .idle, .failedWalletOpen:
            takenOverHold = nil
            ownsOverlay = tryBegin(.openingWallet)
        case .migratingLegacyWallet, .failedLegacyMigration:
            takenOverHold = phase
            ownsOverlay = tryBegin(.openingWallet)
        default:
            takenOverHold = nil
            ownsOverlay = false
        }
        preparationFailure = nil
        do {
            let result = try await open()
            if ownsOverlay, phase == .openingWallet { finish() }
            return result
        } catch {
            let detail = failure(error)
            preparationFailure = detail
            if ownsOverlay, phase == .openingWallet {
                if let detail {
                    phase = .failedWalletOpen(detail)
                } else if let takenOverHold, legacyLaunchHoldActive {
                    // The hold is still waiting: give it its window back,
                    // showing any verdict it reached meanwhile. If it
                    // reported while the open ran, the wallet is present
                    // and the runtime's own recovery applies.
                    if let deferred = deferredLegacyFailure {
                        deferredLegacyFailure = nil
                        phase = .failedLegacyMigration(deferred)
                        preparationFailure = deferred
                    } else {
                        phase = takenOverHold
                        if case let .failedLegacyMigration(held) = takenOverHold { preparationFailure = held }
                    }
                } else {
                    // Unrelated startup errors keep their existing recovery flow.
                    finish()
                }
            }
            throw error
        }
    }
}

/// Launch-time owner of the `.migratingLegacyWallet` / `.failedLegacyMigration`
/// phases. The root controller cannot pick an initial screen while the
/// DashSync → SwiftDashSDK key migrator is still importing an upgrading
/// user's wallet: deciding "no wallet" then would offer Create/Recover to
/// someone whose wallet is milliseconds from landing — and if the import
/// fails, offering Create/Recover at all is wrong, because the wallet is
/// still in the keychain. This coordinator holds the launch, shows progress
/// after the overlay's usual delay, turns a failed or overdue import into a
/// blocking card with Try Again, and reports back exactly once: `true` when
/// a wallet is present (present it), `false` when there is nothing to
/// migrate (setup). It never reports while legacy material remains
/// unmigrated; the card's Try Again re-runs the migrator and the hold
/// continues. A late success is noticed even without Try Again.
///
/// Dependencies are injected so the state machine is testable without the
/// keychain or the SDK; production wiring lives beside the migrator.
@MainActor
final class LegacyWalletMigrationLaunchCoordinator: NSObject {
    /// What the keychain says about DashSync wallet material. Only
    /// `.absent` — a successful read that found nothing — releases the hold
    /// into setup; an unreadable keychain is a failure to show, not an
    /// absence to act on.
    enum LegacyMaterialState { case pending, absent, unreadable }

    struct Dependencies {
        /// The migrator reached a terminal state for this launch.
        var isSettled: () -> Bool
        /// Whether an SDK wallet this build can select is persisted — one
        /// keychain read, one answer. Every verdict below derives from a
        /// single snapshot of it: `.present` presents the wallet, only a
        /// definite `.absent` may go on to ask about legacy material and
        /// reach setup, and `.unknown` — the inventory could not be read
        /// although the app is active and the device unlocked, a keychain
        /// failure that is not the lock — is a failure to show: the card,
        /// whose Try Again re-reads and whose late-success watcher completes
        /// the launch once a read works. Never setup over a wallet the read
        /// missed.
        var walletPresence: () -> WalletEnvironment.WalletPresence
        /// DashSync material still in the keychain and not marked migrated,
        /// confirmed absent, or unreadable.
        var legacyMaterial: () -> LegacyMaterialState
        /// Which terminal flag the migrator left, for the diagnostic code.
        var deferralReason: () -> WalletPreparationFailure.LegacyMigrationReason
        /// Re-run the migrator (the card's Try Again). Contract: by the time
        /// this returns, `isSettled` reports false until the NEW run ends —
        /// the run itself may start later on its own queue. A previous run's
        /// terminal state left in place would be read as the new run's
        /// verdict and re-show the card before the retry even began.
        var startMigration: () -> Void
        /// Subscribe the overlay window presenter before the first phase.
        var activateOverlay: () -> Void
        /// The hold delivered the wallet. Wired to an idempotent runtime
        /// start: a launch whose start saw an unreadable inventory left the
        /// runtime stopped, and neither Try Again (the migrator returns at
        /// its done sentinel without a material change) nor the late-success
        /// watcher would start it otherwise. Foreground-owned by
        /// construction — both run under the card, and the launch decision
        /// has been taken by then.
        var walletDelivered: () -> Void = {}
        /// Fires whenever persisted wallet material changed (the migrator
        /// reports its success through it); the failure card re-checks
        /// `hasWallet` on each element instead of polling the keychain.
        var walletMaterialChanges: () -> AsyncStream<Void> = {
            AsyncStream { continuation in
                let token = NotificationCenter.default.addObserver(
                    forName: .swiftDashSDKWalletMaterialDidChange, object: nil, queue: .main
                ) { _ in continuation.yield() }
                continuation.onTermination = { _ in NotificationCenter.default.removeObserver(token) }
            }
        }
        var pollInterval: TimeInterval = 0.1
        /// Progress is visible, so this only bounds a wedged migrator: past
        /// it the card offers Try Again instead of spinning forever.
        var settleTimeout: TimeInterval = 60
        /// Fallback re-check cadence while the card is up, should a material
        /// change go unannounced. Slow on purpose: each check is a keychain
        /// read on the main actor.
        var lateSuccessInterval: TimeInterval = 5
    }

    private let state: WalletLifecycleTransitionState
    private let dependencies: Dependencies
    private var completion: ((Bool) -> Void)?
    private var watcher: Task<Void, Never>?

    init(state: WalletLifecycleTransitionState, dependencies: Dependencies) {
        self.state = state
        self.dependencies = dependencies
    }

    /// Begin the hold. `completion` fires once, on the main actor. A second
    /// call while a hold is active is ignored. At launch the window is
    /// idle; should another operation hold it, the hold still runs and takes
    /// the window when its verdict arrives (`evaluate`), so the card is
    /// never lost to a busy window at begin.
    func begin(completion: @escaping (Bool) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        state.setLegacyLaunchHold(active: true)
        dependencies.activateOverlay()
        if !state.tryBegin(.migratingLegacyWallet) {
            DWLogger.log("🚦 LIFECYCLE legacy-migration hold could not take the window at begin: phase=\(state.phase.logLabel)")
        }
        waitForSettlement()
    }

    /// The failure card's Try Again: back to progress, re-run the migrator,
    /// wait again. Ignored unless the card is showing.
    func retry() {
        guard case .failedLegacyMigration = state.phase, state.tryBegin(.migratingLegacyWallet) else { return }
        dependencies.startMigration()
        waitForSettlement()
    }

    private func waitForSettlement() {
        watcher?.cancel()
        let started = Date()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // A wallet that landed releases the hold before the migrator
                // settles: with several DashSync wallets the first import can
                // be open and running while a later one is still wedged.
                if self.dependencies.walletPresence() == .present {
                    self.deliver(hasWallet: true)
                    return
                }
                if self.dependencies.isSettled() {
                    self.evaluate(timedOut: false)
                    return
                }
                if Date().timeIntervalSince(started) >= self.dependencies.settleTimeout {
                    self.evaluate(timedOut: true)
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(self.dependencies.pollInterval * 1_000_000_000))
            }
        }
    }

    private func evaluate(timedOut: Bool) {
        // One snapshot for the whole verdict.
        let failure: WalletPreparationFailure
        switch dependencies.walletPresence() {
        case .present:
            deliver(hasWallet: true)
            return
        case .unknown:
            // Only a definite "no SDK wallet" may go on to ask about legacy
            // material; an unreadable inventory is a failure to show, never
            // setup over a wallet the read missed.
            failure = WalletPreparationFailure(unreadableWallet: ())
        case .absent:
            let reason: WalletPreparationFailure.LegacyMigrationReason
            switch dependencies.legacyMaterial() {
            case .absent:
                deliver(hasWallet: false)
                return
            case .unreadable:
                reason = .unreadableKeychain
            case .pending:
                reason = timedOut ? .timedOut : dependencies.deferralReason()
            }
            failure = WalletPreparationFailure(legacyMigration: reason)
        }
        if state.phase == .idle, !state.tryBegin(.migratingLegacyWallet) {
            DWLogger.log("🚦 LIFECYCLE legacy-migration hold could not take the window for its verdict")
        }
        state.failLegacyMigration(failure)
        DWLogger.log("🚦 LIFECYCLE launch hold did not deliver a wallet (\(failure.codes.joined(separator: ","))); holding on the failure card")
        watchForLateSuccess()
    }

    /// A migrator run that outlives the timeout, or a retry the user did not
    /// trigger from this card, can still land the wallet: keep watching so
    /// the launch completes instead of leaving the card (or a runtime-owned
    /// window) over an empty root.
    private func watchForLateSuccess() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            guard let self else { return }
            if self.deliverIfWalletPresent() { return }
            let changes = self.dependencies.walletMaterialChanges()
            let fallback = self.dependencies.lateSuccessInterval
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor [weak self] in
                    for await _ in changes {
                        guard let self, !Task.isCancelled else { return }
                        if self.deliverIfWalletPresent() { return }
                    }
                }
                group.addTask { @MainActor [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: UInt64(fallback * 1_000_000_000))
                        guard let self, !Task.isCancelled else { return }
                        if self.deliverIfWalletPresent() { return }
                    }
                }
                await group.next()
                group.cancelAll()
            }
        }
    }

    @discardableResult
    private func deliverIfWalletPresent() -> Bool {
        guard completion != nil, dependencies.walletPresence() == .present else { return false }
        deliver(hasWallet: true)
        return true
    }

    private func deliver(hasWallet: Bool) {
        watcher?.cancel()
        watcher = nil
        state.setLegacyLaunchHold(active: false)
        // Release only the phases this hold owns. The runtime may already
        // have taken the window over (`.openingWallet`) for the imported
        // wallet; that operation clears its own phase.
        switch state.phase {
        case .migratingLegacyWallet, .failedLegacyMigration:
            state.finish()
        default:
            break
        }
        let completion = self.completion
        self.completion = nil
        completion?(hasWallet)
        if hasWallet {
            // After the root has its controller and the window is released.
            dependencies.walletDelivered()
        }
    }
}

extension Notification.Name {
    /// Posted (main queue) by `SwiftDashSDKWalletRuntime.handleWalletMaterialChanged`
    /// whenever persisted wallet material changed — the migrator's success,
    /// a create/import, a removal. Typed, app-owned; not a re-emission of
    /// any other system's name.
    static let swiftDashSDKWalletMaterialDidChange =
        Notification.Name("org.dashfoundation.dash.swiftDashSDKWalletMaterialDidChange")
}
