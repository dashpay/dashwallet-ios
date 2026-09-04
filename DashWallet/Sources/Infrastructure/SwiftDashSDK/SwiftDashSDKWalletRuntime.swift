//
//  SwiftDashSDKWalletRuntime.swift
//  DashWallet
//
//  Central owner of the SwiftDashSDK runtime lifecycle. Coordinates network
//  switching, host startup, wallet state clearing, and SPV coordinator
//  start/stop.
//
//  Lifecycle shape: every Obj-C / Swift entrypoint enqueues a single async
//  operation onto an internal task chain that serializes lifecycle work
//  end-to-end. Full runtime rebuilds use `refresh(trigger:)` /
//  `fullReset(lastError:forWipe:)`; Core-only controls use the same queue but
//  call only the SPV coordinator, preserving the host, wallet and BLAST —
//  no `DispatchGroup`, no `Thread.sleep`, no fire-and-forget Tasks
//  inside lifecycle work. Stop order is BLAST → SPV → wallet state →
//  host; start order is host (via SPV) → SPV → BLAST.
//

import Foundation
import OSLog
import SwiftDashSDK

/// Small, testable serial task chain used by the wallet runtime. Keeping the
/// queue independent from the singleton lets lifecycle ordering be regression
/// tested without constructing the SDK/FFI stack.
@MainActor
final class SerialAsyncLifecycleQueue {
    private var currentTask: Task<Void, Never>?

    @discardableResult
    func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = currentTask
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        currentTask = task
        return task
    }

    /// Value-returning variant: the operation is one link of the same serial
    /// chain (full barrier semantics — everything enqueued later waits for
    /// it), and its result or error is handed back to the caller through a
    /// continuation. The chain itself stays `Task<Void, Never>`.
    func enqueueAwaitable<T: Sendable>(
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            enqueue {
                do {
                    continuation.resume(returning: try await operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@objc(DWSwiftDashSDKWalletRuntime)
@MainActor
final class SwiftDashSDKWalletRuntime: NSObject {
    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-runtime")

    private static let seedMigratorDoneKey = "swiftSDKKeyMigration.v1.done"
    private static let seedMigratorDeferredKeys = [
        "swiftSDKKeyMigration.v1.deferredMultiWallet",
        "swiftSDKKeyMigration.v1.deferredUnknownChain",
        "swiftSDKKeyMigration.v1.deferredFailure",
    ]
    private static let seedMigratorWaitTimeout: TimeInterval = 30.0
    private static let seedMigratorPollInterval: TimeInterval = 0.1

    static let shared = SwiftDashSDKWalletRuntime()

    /// Serial gate at the Obj-C/Swift entrypoint boundary. Each entrypoint
    /// pushes its enqueue step through here so that two callers from
    /// different threads (e.g. a wipe and a wallet-material-changed
    /// notification arriving simultaneously) produce a strict FIFO order
    /// of Task creation, not just an order that happens to hold for
    /// MainActor-originated callers.
    private static let entryQueue = DispatchQueue(
        label: "org.dashfoundation.dash.swift-sdk-wallet-runtime.entry",
        qos: .userInitiated)

    private var observerToken: NSObjectProtocol?
    private let lifecycleQueue = SerialAsyncLifecycleQueue()
    private var currentNetwork: Network?

    private override init() {
        super.init()
    }

    // MARK: - Obj-C / Swift entrypoints
    //
    // All public entrypoints are fire-and-forget at the caller boundary —
    // they push one ordered step through `entryQueue` which then enqueues
    // a single op onto the serial lifecycle task chain.

    @objc(startIfReady)
    nonisolated static func startIfReady() {
        dispatchOnPipeline { shared.enqueueRefresh(trigger: .startIfReady) }
    }

    @objc(stop)
    nonisolated static func stop() {
        dispatchOnPipeline { shared.enqueueFullReset(lastError: nil, forWipe: false) }
    }

    /// Stop only Core SPV. The host, wallet, published balance and Platform
    /// sync services stay alive so a later Core restart does not rebuild the
    /// shared SDK runtime.
    @objc(stopCoreSPV)
    nonisolated static func stopCoreSPV() {
        dispatchOnPipeline { shared.enqueueStopCoreSPV() }
    }

    /// Redial Core SPV peers on the existing PlatformWalletManager. This is
    /// deliberately separate from `startIfReady`, whose job is a complete
    /// runtime refresh after network/wallet material changes.
    @objc(restartCoreSPV)
    nonisolated static func restartCoreSPV() {
        dispatchOnPipeline { shared.enqueueRestartCoreSPV() }
    }

    @objc(startObservingNetworkChanges)
    nonisolated static func startObservingNetworkChanges() {
        dispatchOnPipeline { shared.installNetworkObserver() }
    }

    @objc(handleWalletMaterialChanged)
    nonisolated static func handleWalletMaterialChanged() {
        dispatchOnPipeline { shared.enqueueRefresh(trigger: .walletMaterialChanged) }
    }

    /// Tear down the runtime after a completed wipe and report when that
    /// teardown has actually finished: `completion` fires (on the MainActor)
    /// only after the enqueued `fullReset(forWipe: true)` — BLAST stop, SPV
    /// stop, cleared wallet state, and the host's native shutdown — has
    /// returned. The wiper blocks its serial queue on this completion, so
    /// `waitForPendingWipe`'s barrier means "data wiped AND runtime torn
    /// down", not "teardown merely scheduled".
    nonisolated static func handleWalletWiped(completion: @escaping @Sendable () -> Void) {
        dispatchOnPipeline {
            shared.enqueue {
                await shared.fullReset(lastError: nil, forWipe: true)
                completion()
            }
        }
    }

    /// Rebuild the shared runtime through the same serialized lifecycle used
    /// at launch and after wallet recovery, then return only when Platform
    /// sync is bound again (or the start has failed). Sync Info uses this to
    /// turn "Sync Now" into a real in-session recovery action after Stop or a
    /// recover-time binding race.
    func rearmPlatformSync() async {
        let task = enqueueAwaitable { [weak self] in
            await self?.refresh(trigger: .platformSyncRearm)
        }
        await task.value
    }

    /// Restart Core SPV to dial a fresh peer set ("sync too slow? change
    /// peers"). Shares the exact Core-only restart operation with the
    /// diagnostics screen.
    /// Peer selection is seed-random — a redial of a previous peer is
    /// possible (no exclude-list in the SDK yet).
    @objc(rotatePeers)
    nonisolated static func rotatePeers() {
        restartCoreSPV()
    }

    // MARK: - Runtime network switching

    /// Interactive network switch: the single owner of the runtime rebuild.
    ///
    /// Strict sequence — `stop old runtime → await native teardown off-main →
    /// start new runtime → ready` — driven by exactly ONE `refresh` on the
    /// serial lifecycle chain. The `DWCurrentNetworkDidChange` post carries a
    /// `.managedSwitch` source so the runtime observer skips its own
    /// lifecycle reaction (UI listeners like DWRootModel behave as always);
    /// external key writers keep the observer-driven path.
    ///
    /// A no-op requires an actually-ready runtime (`isRuntimeReady`), not
    /// just a matching persisted key — a matching key over a dead runtime
    /// runs the full rebuild (self-heal).
    ///
    /// MUST NOT be called from within a lifecycle operation on
    /// `lifecycleQueue` (`refresh`/`fullReset` bodies): it awaits its own
    /// enqueued op, so a call from inside the chain would self-await and
    /// deadlock the queue. UI entry points and coordinators outside the
    /// chain are the intended callers.
    @MainActor
    func switchNetwork(to kind: WalletEnvironment.NetworkKind) async throws {
        guard kind != .devnet else { throw SwitchError.unsupportedNetwork }
        let targetNetwork: Network = kind == .mainnet ? .mainnet : .testnet
        // No-op check stays BEFORE the admission gate (read-only, never
        // consumes the gate); the gate itself rejects when ANY interactive
        // lifecycle operation — network switch, wallet switch, or removal —
        // is in flight, replacing the old network-only `.switching` guard.
        if WalletEnvironment.networkKind == kind, isRuntimeReady(for: targetNetwork) {
            Self.logger.info("🧭 RUNTIME :: switchNetwork — already on \(String(describing: kind), privacy: .public) with a ready runtime; no-op")
            return
        }

        // A Retry / Switch Back begins from the failure card, where the
        // persisted key already points at the FAILED target — carry the
        // network that was really active when the saga began, so the card
        // keeps offering a way back across repeated failed attempts.
        let from: WalletEnvironment.NetworkKind
        if case let .failedNetworkSwitch(savedFrom, _, _) = WalletLifecycleTransitionState.shared.phase {
            from = savedFrom
        } else {
            from = WalletEnvironment.networkKind
        }
        guard WalletLifecycleTransitionState.shared.tryBegin(.switchingNetwork(from: from, to: kind)) else {
            throw SwitchError.switchInProgress
        }
        let transitionID = String(UUID().uuidString.prefix(8))
        let started = CFAbsoluteTimeGetCurrent()
        // Thread stamp deliberately absent: this method is MainActor-bound
        // (always main); the off-main proof for the blocking teardown is the
        // shutdown metrics' `ranOffMainThread` in the HOST shutdown line.
        DWLogger.log("🔀 NETSWITCH [\(transitionID)] start \(from) → \(kind)")

        // Owned here for managed switches (the observer skips them): silence
        // and zero the published balance mirrors before anything else renders
        // the old network's funds as the new one's.
        SwiftDashSDKSPVCoordinator.shared.prepareForNetworkSwitch()
        PlatformAddressSyncCoordinator.shared.prepareForNetworkSwitch()

        // Skip the key write when it already matches (a dead runtime on the
        // right network heals via the refresh alone); `switchToNetwork`
        // would early-return without posting in that case anyway.
        if WalletEnvironment.networkKind != kind {
            WalletEnvironment.switchToNetwork(kind, source: .managedSwitch(transitionID: transitionID))
        }

        await enqueueAwaitable { [weak self] in
            await self?.refresh(trigger: .networkDidChange)
        }.value

        let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        if isRuntimeReady(for: targetNetwork) {
            WalletLifecycleTransitionState.shared.finish()
            DWLogger.log("🔀 NETSWITCH [\(transitionID)] ready in \(ms)ms")
        } else {
            let detail = SwiftDashSDKSPVCoordinator.shared.lastError
                ?? PlatformAddressSyncCoordinator.shared.lastError
            WalletLifecycleTransitionState.shared.fail(.failedNetworkSwitch(from: from, target: kind, message: detail))
            DWLogger.log("🔀 NETSWITCH [\(transitionID)] FAILED after \(ms)ms: \(detail ?? "runtime did not become ready")")
            throw SwitchError.startFailed(detail)
        }
    }

    // MARK: - Runtime wallet switching

    /// Switch the active wallet (same network) to `walletId` at runtime.
    ///
    /// Reuses the exact stop → clear → load → start sequence a network switch
    /// runs (`refresh`), the only difference being that the network is
    /// unchanged and the active-wallet registry is repointed first: after
    /// `WalletEnvironment.setActiveWalletId`, the host's Phase-0
    /// `resolveActiveWallet` binds `walletId` when it rebuilds. On success the
    /// new wallet is bound and its balance seeded, and
    /// `activeWalletDidChangeNotification` has been posted.
    ///
    /// Validation runs synchronously on the main actor before any teardown:
    /// the target must be a persisted wallet on the current network (its
    /// mnemonic present in `WalletStorage`), or the call throws without
    /// touching the running runtime. Switching to the already-active wallet is
    /// a success no-op.
    @MainActor
    func switchWallet(to walletId: Data) async throws {
        let network = try validateSwitchTarget(walletId)

        let kind = registryNetworkKind(for: network)
        if WalletEnvironment.activeWalletId(for: kind) == walletId,
           SwiftDashSDKHost.shared.wallet?.walletId == walletId {
            Self.logger.info("🧭 RUNTIME :: switchWallet — target already active; no-op")
            return
        }

        WalletEnvironment.setActiveWalletId(walletId, for: kind)

        // Same stop/clear/load/start sequence as a network switch, enqueued on
        // the serial lifecycle chain so it can't interleave with a concurrent
        // refresh/wipe. `.walletDidChange` never elides the refresh.
        await enqueueAwaitable { [weak self] in
            await self?.refresh(trigger: .walletDidChange)
        }.value

        guard SwiftDashSDKHost.shared.wallet?.walletId == walletId else {
            throw SwitchError.bindFailed
        }

        publishActiveWalletDidChange(reason: "wallet-switch")
    }

    /// Additive wallet provisioning (`SwiftDashSDKHost.addWallet`) as ONE
    /// link of the serial lifecycle chain, so a queued `refresh`/`fullReset`
    /// can never interleave with the multi-network create. Like
    /// `switchNetwork(to:)`, this MUST NOT be called from within a lifecycle
    /// operation already running on the chain — it awaits its own enqueued
    /// op and would self-await-deadlock the queue. The add flow's post-add
    /// `switchWallet` is deliberately a SECOND, sequential chain op (the
    /// caller awaits this method first), never nested inside it.
    @MainActor
    func performAddWallet(mnemonic: String, isImported: Bool) async throws
        -> SwiftDashSDKHost.AddWalletResult {
        try await lifecycleQueue.enqueueAwaitable {
            try await SwiftDashSDKHost.shared.addWallet(
                mnemonic: mnemonic,
                isImported: isImported)
        }
    }

    /// Validate that `walletId` is a switchable target on the current network:
    /// the network must be SDK-supported and a mnemonic for `walletId` must be
    /// persisted in `WalletStorage` — the same keychain surface the host loads
    /// and recovers wallets from. Returns the resolved `Network` for the
    /// caller's registry write. Throws (leaving the runtime untouched) on an
    /// unsupported network or an unknown/missing walletId.
    @MainActor
    private func validateSwitchTarget(_ walletId: Data) throws -> Network {
        let network: Network
        switch resolveCurrentNetwork() {
        case .failure:
            throw SwitchError.unsupportedNetwork
        case .success(let resolved):
            network = resolved
        }

        let persistedIds = SwiftDashSDKHost.persistedMnemonics().map { $0.walletId }
        guard persistedIds.contains(walletId) else {
            throw SwitchError.unknownWallet
        }
        return network
    }

    /// `WalletEnvironment.NetworkKind` for the SDK `Network`. Only
    /// `.mainnet`/`.testnet` reach a persisted wallet (the runtime fails fast
    /// on every other network before this is called), so the switch path never
    /// sees a network without a registry key; the `default` maps to `.testnet`
    /// defensively to keep the return non-optional.
    private func registryNetworkKind(for network: Network) -> WalletEnvironment.NetworkKind {
        switch network {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        default: return .testnet
        }
    }

    /// Push one ordered step from any thread into the MainActor lifecycle.
    /// `entryQueue` serializes Task creation; the MainActor then processes
    /// the enqueue calls in the order their Tasks were created. The block
    /// itself only touches the lifecycle queue (synchronous), so no
    /// `await` boundaries open up inside it for reordering.
    nonisolated private static func dispatchOnPipeline(
        _ block: @escaping @Sendable @MainActor () -> Void
    ) {
        entryQueue.async {
            Task { @MainActor in block() }
        }
    }

    // MARK: - Serial lifecycle pipeline

    /// Append a lifecycle operation to the serial task chain. Every new op
    /// awaits the previous task before running, so two callers in quick
    /// succession (for example two peer-rotation requests) are processed
    /// strictly in order.
    private func enqueue(_ op: @escaping @MainActor () async -> Void) {
        lifecycleQueue.enqueue(op)
    }

    /// Same serial-chain append as `enqueue`, but returns the appended task so
    /// an awaiting caller (`switchWallet`) can block until its own op — and
    /// every op enqueued before it — has completed. Preserves the FIFO
    /// ordering `enqueue` provides: the returned task awaits the previous
    /// lifecycle task before running.
    @discardableResult
    private func enqueueAwaitable(_ op: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        lifecycleQueue.enqueue(op)
    }

    private func enqueueRefresh(trigger: RefreshTrigger) {
        enqueue { [weak self] in
            await self?.refresh(trigger: trigger)
        }
    }

    private func enqueueFullReset(lastError: String?, forWipe: Bool) {
        enqueue { [weak self] in
            await self?.fullReset(lastError: lastError, forWipe: forWipe)
        }
    }

    private func enqueueStopCoreSPV() {
        enqueue {
            await SwiftDashSDKSPVCoordinator.shared.stopCoreAsync()
        }
    }

    private func enqueueRestartCoreSPV() {
        enqueue {
            do {
                try await SwiftDashSDKSPVCoordinator.shared.restartAsync()
            } catch {
                Self.logger.error("🧭 RUNTIME :: Core SPV restart failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Core lifecycle

    private func refresh(trigger: RefreshTrigger) async {
        Self.logger.info("🧭 RUNTIME :: refreshing runtime for \(trigger.rawValue, privacy: .public)")

        guard await waitForSeedMigratorIfNeeded() else {
            await fullReset(lastError: "Key migration not complete; SwiftDashSDK runtime cannot start.", forWipe: false)
            return
        }

        switch resolveCurrentNetwork() {
        case .failure(let error):
            await fullReset(lastError: error.localizedDescription, forWipe: false)
        case .success(let network):
            if shouldSkipRefresh(for: network, trigger: trigger) {
                Self.logger.info("🧭 RUNTIME :: refresh is already satisfied for \(network.rawValue, privacy: .public)")
                return
            }

            await fullReset(lastError: nil, forWipe: false)

            // A reinstall clears the selected-network UserDefaults key but
            // preserves SDK mnemonics. If every stored wallet belongs to the
            // other supported network, select that network instead of replaying
            // its seed through the current manager.
            if trigger == .walletMaterialChanged,
               selectSolePersistedNetworkIfNeeded(currentNetwork: network) {
                return
            }

            // Gate on SDK presence, not DashSync's hasAWallet (C6-A): the
            // runtime consumes the SDK wallet, and every SDK-wallet writer
            // re-triggers a refresh (the creator's and migrator's
            // handleWalletMaterialChanged) — and the migrator is awaited
            // above, so a legacy-upgrade launch has its mnemonic by this line.
            guard WalletEnvironment.hasSDKWallet else {
                Self.logger.info("🧭 RUNTIME :: no SDK wallet persisted; leaving runtime stopped for \(network.rawValue, privacy: .public)")
                return
            }

            do {
                try await SwiftDashSDKSPVCoordinator.shared.startAsync(for: network)
                try await PlatformAddressSyncCoordinator.shared.startAsync(for: network)
                currentNetwork = network
                if trigger == .walletMaterialChanged {
                    publishActiveWalletDidChange(reason: "wallet-started")
                } else if trigger == .networkDidChange {
                    // The same walletId can exist on both networks, but its
                    // SwiftData container and identity set are network-scoped.
                    // Publish only after the destination runtime is fully
                    // bound so identity/banner consumers re-read destination
                    // state instead of the cleared transition mirror.
                    publishActiveWalletDidChange(reason: "network-changed")
                }
            } catch {
                Self.logger.error("🧭 RUNTIME :: start failed: \(String(describing: error), privacy: .public)")
                await fullReset(lastError: error.localizedDescription, forWipe: false)
            }
        }
    }

    /// Deterministic teardown: BLAST → SPV → wallet state → host.
    /// Both BLAST and Core SPV consume `SwiftDashSDKHost.shared`; releasing
    /// the FFI handle while either tokio task is still running would be a
    /// use-after-free, so the host stop happens strictly after both
    /// coordinators have settled.
    private func fullReset(lastError: String?, forWipe: Bool) async {
        if forWipe {
            await PlatformAddressSyncCoordinator.stopForWipeAsync()
        } else {
            await PlatformAddressSyncCoordinator.shared.stopAsync()
        }
        await SwiftDashSDKSPVCoordinator.shared.stopAsync(lastError: lastError)
        SwiftDashSDKWalletState.shared.clearAllState()
        // Blocking native teardown runs off-main inside stopAsync; this only
        // suspends. The shutdown metrics are logged by the host (DWLogger)
        // so switch telemetry survives into diagnostic exports.
        await SwiftDashSDKHost.shared.stopAsync()
        currentNetwork = nil
#if DASHPAY
        // Readiness verdicts and completed recovery contexts belong to the
        // start that produced them.
        DWSameSeedIdentityRecoveryCoordinator.shared.resetForRuntimeTeardown()
#endif
        if forWipe {
            DWCurrentUserIdentityInfo.shared.resetForWalletRemoval()
            publishActiveWalletDidChange(reason: "wallet-removed")
        }
    }

    // MARK: - Helpers

    private func publishActiveWalletDidChange(reason: String) {
        let walletId = SwiftDashSDKHost.shared.wallet?.walletId.hexEncodedString() ?? "none"
        NotificationCenter.default.post(
            name: SwiftDashSDKWalletState.activeWalletDidChangeNotification,
            object: nil)
        Self.logger.info(
            "🧭 RUNTIME :: active-wallet change reason=\(reason, privacy: .public) wallet=\(walletId, privacy: .public)")
    }

    private func selectSolePersistedNetworkIfNeeded(currentNetwork: Network) -> Bool {
        guard let storedNetworks = try? SwiftDashSDKHost.persistedSDKWalletNetworks(),
              !storedNetworks.contains(currentNetwork),
              storedNetworks.count == 1,
              let storedNetwork = storedNetworks.first else {
            return false
        }

        let kind: WalletEnvironment.NetworkKind = storedNetwork == .mainnet ? .mainnet : .testnet
        Self.logger.info(
            "🧭 RUNTIME :: selecting sole persisted wallet network \(storedNetwork.networkName, privacy: .public)")
        return WalletEnvironment.switchToNetwork(kind)
    }

    private func shouldSkipRefresh(for network: Network, trigger: RefreshTrigger) -> Bool {
        switch trigger {
        case .walletMaterialChanged, .walletDidChange:
            // A runtime wallet switch always rebuilds — the active-wallet
            // registry was repointed to a different wallet on the SAME
            // network, so `currentNetwork == network` would otherwise wrongly
            // elide the rebind.
            return false
        case .startIfReady, .networkDidChange, .platformSyncRearm:
            return isRuntimeReady(for: network)
        }
    }

    /// Whether the runtime is fully bound and running for `network`: host has
    /// a bound wallet, SPV runs, and BLAST runs on that same network. The one
    /// readiness predicate shared by refresh elision (`shouldSkipRefresh`)
    /// and `switchNetwork(to:)`'s no-op / ready checks — a persisted network
    /// key alone never counts as "ready".
    ///
    /// Consulting live coordinator state matters beyond switches too:
    /// external callers (PlatformSyncStatusScreen, StorageExplorerUnavailableView,
    /// the Platform send path) can mutate BLAST without touching
    /// `currentNetwork`, and skipping a refresh after an out-of-band BLAST
    /// stop would leave the user without the sync they triggered.
    func isRuntimeReady(for network: Network) -> Bool {
        let blast = PlatformAddressSyncCoordinator.shared
        return currentNetwork == network
            && SwiftDashSDKHost.shared.wallet != nil
            && blast.isRunning
            && blast.runningNetwork == network
            && SwiftDashSDKSPVCoordinator.shared.isRunning
    }

    /// Internal (was private): reused by CrowdNode's TransactionObserver row
    /// scanner to render decoded addresses for the active network — reuse, not
    /// a copy, per the repo's no-copy-then-adapt guardrail.
    func resolveCurrentNetwork() -> Result<Network, RuntimeError> {
        guard let network = WalletEnvironment.network else {
            return .failure(.unsupportedCurrentNetwork("devnet"))
        }
        return .success(network)
    }

    private func waitForSeedMigratorIfNeeded() async -> Bool {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.seedMigratorDoneKey) != nil {
            return true
        }

        // A persisted SDK wallet is runnable material regardless of the
        // migrator's state. Gating on the sentinel here stranded users who
        // restored a wallet while the migrator kept failing without a
        // terminal flag: every refresh waited the full timeout, gave up,
        // and left the runtime stopped — main UI with an empty Wallets
        // screen and refused imports. A late successful migration still
        // lands through `handleWalletMaterialChanged`.
        if WalletEnvironment.hasSDKWallet {
            Self.logger.info("🧭 RUNTIME :: SDK wallet already persisted; not blocking on key migrator")
            return true
        }

        let deadline = Date().addingTimeInterval(Self.seedMigratorWaitTimeout)
        let sleepNanos = UInt64(Self.seedMigratorPollInterval * 1_000_000_000)
        while defaults.string(forKey: Self.seedMigratorDoneKey) == nil {
            if Self.seedMigratorDeferredKeys.contains(where: { defaults.object(forKey: $0) != nil }) {
                Self.logger.warning("🧭 RUNTIME :: key migrator deferred; continuing runtime refresh without migrated wallet material")
                return true
            }
            if Date() >= deadline {
                Self.logger.error("🧭 RUNTIME :: key migrator did not complete within \(Self.seedMigratorWaitTimeout, privacy: .public)s")
                return false
            }
            try? await Task.sleep(nanoseconds: sleepNanos)
        }

        return true
    }

    private func installNetworkObserver() {
        guard observerToken == nil else { return }

        observerToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.DWCurrentNetworkDidChange,
            object: nil,
            queue: nil
        ) { note in
            // A managed switch (`switchNetwork(to:)`) owns BOTH the mirror
            // zeroing and the single lifecycle refresh — reacting here would
            // double-drive the lifecycle and, after a failed switch, retry
            // the rebuild behind the transition state machine's back.
            // External writers (recovery, sole-network selection) still get
            // the full observer behavior below.
            guard !WalletEnvironment.isManagedSwitchNotification(note) else { return }
            Task { @MainActor in
                // The home screen's funds are three published mirrors: the core
                // balance plus BLAST's Platform and Shielded totals. `refresh`
                // clears all three, but only once the serial lifecycle queue
                // reaches `fullReset` — behind the seed-migrator wait and the
                // BLAST/SPV stops. Silence and zero them here so the previously
                // selected network's balances never render as the new one's.
                SwiftDashSDKSPVCoordinator.shared.prepareForNetworkSwitch()
                PlatformAddressSyncCoordinator.shared.prepareForNetworkSwitch()
                Self.shared.enqueueRefresh(trigger: .networkDidChange)
            }
        }

        Self.logger.info("🧭 RUNTIME :: registered DWCurrentNetworkDidChangeNotification observer")
    }

    private enum RefreshTrigger: String {
        case startIfReady
        case networkDidChange
        case walletMaterialChanged
        case walletDidChange
        case platformSyncRearm
    }

    enum RuntimeError: LocalizedError {
        case unsupportedCurrentNetwork(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedCurrentNetwork(let name):
                return "SwiftDashSDK runtime does not support \(name)"
            }
        }
    }

    /// Failure modes of `switchWallet(to:)` / `switchNetwork(to:)`. Surfaced
    /// to the caller rather than logged-and-swallowed so a UI switch flow can
    /// report why it failed.
    enum SwitchError: LocalizedError {
        /// The current network isn't SDK-supported (devnet/unsupported).
        case unsupportedNetwork
        /// No mnemonic is persisted in `WalletStorage` for the target walletId.
        case unknownWallet
        /// The stop/clear/load/start sequence ran but the host did not bind the
        /// requested wallet (e.g. its rows failed to load).
        case bindFailed
        /// Another interactive lifecycle operation (network switch, wallet
        /// switch, or removal) already holds the admission gate; the
        /// transition state machine admits one at a time.
        case switchInProgress
        /// The switch's teardown+rebuild ran but the destination runtime did
        /// not come up ready; carries the coordinators' last error when one
        /// was recorded.
        case startFailed(String?)

        var errorDescription: String? {
            switch self {
            case .unsupportedNetwork:
                return "Cannot switch wallet: the current network is not supported."
            case .unknownWallet:
                return "Cannot switch wallet: no wallet with that id is stored on this network."
            case .bindFailed:
                return "Switching wallet failed: the new wallet could not be loaded."
            case .switchInProgress:
                return "Another wallet operation is already in progress."
            case .startFailed(let detail):
                let base = "Switching networks failed: the runtime did not start."
                guard let detail, !detail.isEmpty else { return base }
                return base + " (\(detail))"
            }
        }
    }
}
