//
//  SwiftDashSDKWalletWiper.swift
//  DashWallet
//
//  Wipes SwiftDashSDK wallet state — full per-wallet deletion (SwiftData
//  rows incl. PersistentTransaction, Rust manager state, and Keychain
//  material) via PlatformWalletManager.deleteWallet. All app wipe entry points
//  call this app-owned boundary directly; no DashSync registry mirror or
//  notification trampoline remains.
//
//  The wipe-side concern lives separately from the create/import-side concerns in
//  SwiftDashSDKWalletCreator.swift, and from the upgrade-time concern
//  in SwiftDashSDKKeyMigrator.swift.
//

import Foundation
import OSLog
import SwiftDashSDK

/// Why a caller is allowed to request a global wallet wipe. Requiring an
/// explicit value keeps phrase-authorized recovery, an honest user-confirmed
/// delete-all action, and setup-time wallet replacement distinguishable at the
/// destructive boundary and in logs.
@objc(DWSwiftDashSDKWalletWipeAuthorization)
enum SwiftDashSDKWalletWipeAuthorization: Int {
    case recoveryFlow
    case confirmedDeleteAll
    case screenshotReplacement
    case debugReset

    fileprivate var removesPin: Bool {
        self != .screenshotReplacement
    }

    var removesMatchingLegacyMnemonicAccounts: Bool {
        self == .recoveryFlow
    }

    var removesAllLegacyMnemonicAccounts: Bool {
        self == .confirmedDeleteAll
    }

    fileprivate var logLabel: String {
        switch self {
        case .recoveryFlow: return "recovery-flow"
        case .confirmedDeleteAll: return "confirmed-delete-all"
        case .screenshotReplacement: return "screenshot-replacement"
        case .debugReset: return "debug-reset"
        }
    }
}

/// Serializes full-wallet wipes and provides a FIFO barrier for callers that
/// must not continue while a wipe is still mutating Keychain/runtime state.
///
final class WalletWipeSerialExecutor {
    private let queue: DispatchQueue
    private var lastWipeSucceeded = true

    init(label: String = "org.dashfoundation.dash.wallet-wiper") {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func enqueue(_ operation: @escaping () -> Bool) {
        queue.async {
            self.lastWipeSucceeded = operation()
        }
    }

    func notifyWhenIdle(
        on completionQueue: DispatchQueue = .main,
        completion: @escaping (Bool) -> Void
    ) {
        queue.async {
            let succeeded = self.lastWipeSucceeded
            completionQueue.async {
                completion(succeeded)
            }
        }
    }
}

enum SwiftDashSDKWalletDeletionError: LocalizedError {
    case invalidMnemonic
    case managerUnavailable
    case unrecognizedWalletNetwork
    case walletDeletionIncomplete

    var errorDescription: String? {
        switch self {
        case .invalidMnemonic:
            return NSLocalizedString(
                "The wallet recovery phrase is invalid. Please try again.",
                comment: "Wallets")
        case .managerUnavailable:
            return NSLocalizedString(
                "The wallet manager is not available. Please try again.",
                comment: "Wallets")
        case .unrecognizedWalletNetwork:
            return NSLocalizedString(
                "The wallet network could not be determined. Please try again.",
                comment: "Wallets")
        case .walletDeletionIncomplete:
            return NSLocalizedString(
                "The wallet could not be fully removed. Please try again.",
                comment: "Wallets")
        }
    }
}

/// Resolves a Keychain wallet id against the deterministic ids derived from
/// its mnemonic. Wallet ids are network-scoped even when a seed is shared;
/// the mainnet-derived id is also a stable logical identifier for grouping
/// mirrored mainnet/testnet entries without retaining the mnemonic.
enum SwiftDashSDKStoredWalletNetworkResolver {
    struct Resolution {
        let network: Network
        let canonicalMainnetWalletId: Data
    }

    /// The networks a stored wallet id can be scoped to. key-wallet folds a
    /// per-network discriminant into the id digest, so all three ids of one
    /// seed are distinct.
    static let storableNetworks: [Network] = [.mainnet, .testnet, .devnet]

    static func walletIds(for mnemonic: String) throws -> [Network: Data] {
        let mnemonic = Mnemonic.normalizePhrase(mnemonic)
        guard Mnemonic.validate(mnemonic) else {
            throw SwiftDashSDKWalletDeletionError.invalidMnemonic
        }
        var ids: [Network: Data] = [:]
        for network in storableNetworks {
            ids[network] = try SwiftDashSDK.Wallet(
                mnemonic: mnemonic,
                network: network
            ).id
        }
        return ids
    }

    static func resolve(walletId: Data, mnemonic: String) throws -> Resolution {
        let walletIds = try walletIds(for: mnemonic)
        guard let mainnetWalletId = walletIds[.mainnet] else {
            throw SwiftDashSDKWalletDeletionError.unrecognizedWalletNetwork
        }
        for network in storableNetworks {
            if walletIds[network] == walletId {
                return Resolution(network: network, canonicalMainnetWalletId: mainnetWalletId)
            }
        }

        throw SwiftDashSDKWalletDeletionError.unrecognizedWalletNetwork
    }
}

private final class WalletWipeResultAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var failureCount = 0

    func recordFailure() {
        lock.lock()
        failureCount += 1
        lock.unlock()
    }

    var succeeded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failureCount == 0
    }
}

@objc(DWSwiftDashSDKWalletWiper)
final class SwiftDashSDKWalletWiper: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-wiper")

    private static let wipeExecutor = WalletWipeSerialExecutor()

    // MARK: - Public entry point

    /// Starts a full app/SDK-owned wipe for an explicitly identified
    /// authorization path. Whether the PIN is removed is part of that path,
    /// rather than an independently selectable flag: a failed SDK deletion
    /// leaves both wallet material and its authentication state available for
    /// retry. Callers observe completion through `waitForPendingWipe`.
    @objc(wipeWalletWithAuthorization:)
    static func wipeWallet(authorization: SwiftDashSDKWalletWipeAuthorization) {
        logger.notice("global wipe requested; authorization=\(authorization.logLabel, privacy: .public)")
        wipeExecutor.enqueue {
            performWipe(
                removingPin: authorization.removesPin,
                authorization: authorization)
        }
    }

    /// Invoke `completion` on the main queue with the last queued wipe's result
    /// after every wipe enqueued before this call has finished. UI flows use
    /// this barrier before navigating away from a deleting-wallet state.
    @objc(waitForPendingWipeWithCompletion:)
    static func waitForPendingWipe(completion: @escaping (Bool) -> Void) {
        wipeExecutor.notifyWhenIdle(completion: completion)
    }

    // MARK: - Background wipe body

    /// The actual wipe body. Runs on a background `DispatchQueue` —
    /// uses keychain-backed storage only, so it has no `@MainActor`
    /// requirements. Total cost ~10–50 ms (much faster than the
    /// migrator's create path because there's no PBKDF2 or FFI work).
    ///
    /// Idempotent. Reports failure when enumeration or any per-wallet SDK
    /// deletion fails, leaving runtime/registry state available for retry.
    private static func performWipe(
        removingPin: Bool,
        authorization: SwiftDashSDKWalletWipeAuthorization
    ) -> Bool {
        let startedAt = ContinuousClock.now
        // Whatever this wipe leaves behind, the app-level gate's cached view of
        // which networks hold material is about to be wrong.
        defer { WalletEnvironment.invalidateWalletMaterialCache() }
        let storage = WalletStorage()
        let walletIdsByNetwork: [Network: Set<Data>]

        if authorization.removesMatchingLegacyMnemonicAccounts {
            do {
                let beforeCleanup = try classifyStoredWallets(storage: storage)
                guard let authorizedMnemonic = soleNormalizedMnemonic(
                    in: beforeCleanup.mnemonics) else {
                    logger.error(
                        "recovery wipe requires exactly one distinct SDK mnemonic; refusing legacy and SDK deletion")
                    return false
                }

                try SwiftDashSDKKeyMigrator.removeLegacyMnemonicAccountsBeforeWipe(
                    matching: authorizedMnemonic)

                // Migration and cleanup share a queue. Re-read SDK state after
                // that barrier so a different seed imported while cleanup was
                // waiting can never be swept by this phrase-authorized flow.
                let afterCleanup = try classifyStoredWallets(storage: storage)
                guard soleNormalizedMnemonic(in: afterCleanup.mnemonics) == authorizedMnemonic else {
                    logger.error(
                        "SDK mnemonic inventory changed during recovery wipe; refusing SDK deletion")
                    return false
                }
                walletIdsByNetwork = afterCleanup.walletIdsByNetwork
            } catch {
                logger.error(
                    "matching legacy mnemonic cleanup failed; refusing SDK wipe: \(String(describing: error), privacy: .public)")
                return false
            }
        } else {
            if authorization.removesAllLegacyMnemonicAccounts {
                do {
                    try SwiftDashSDKKeyMigrator.removeAllLegacyMnemonicAccounts()
                } catch {
                    logger.error(
                        "legacy mnemonic cleanup failed; refusing SDK wipe: \(String(describing: error), privacy: .public)")
                    return false
                }
            }

            // Classify the global Keychain inventory by its network-derived
            // wallet id. Debug and screenshot flows reach this branch without
            // touching legacy DashSync data.
            do {
                walletIdsByNetwork = try classifyStoredWallets(
                    storage: storage).walletIdsByNetwork
            } catch {
                logger.error(
                    "failed to classify wallet inventory: \(String(describing: error), privacy: .public)")
                return false
            }
        }

        // Delete each network through a manager configured with that network's
        // ModelContainer. This clears SwiftData, Rust state, identities, and
        // SDK-owned Keychain material together. The current network is handled
        // last so a failure preparing the inactive network leaves the live
        // wallet untouched.
        guard deleteWalletsFromSDK(walletIdsByNetwork) else {
            let elapsed = startedAt.duration(to: .now)
            logger.error(
                "wallet wipe failed after \(String(describing: elapsed), privacy: .public); preserving runtime and registry for retry")
            return false
        }

        // The SDK wallet deletion is now known to have succeeded for every
        // network. Clear every global app-owned store only at this commit
        // point, so a failed wipe preserves a coherent wallet,
        // authentication, metadata, and preferences state for retry.
        DispatchQueue.main.sync {
            if removingPin {
                AuthenticationService.shared.removePin()
            }
            App.shared.cleanUp()
            DWGlobalOptions.sharedInstance().restoreToDefaults()
            DWAppGroupOptions.sharedInstance().restoreToDefaults()
            CrowdNode.shared.resetForWipe()
        }

        // These stores use UserDefaults + locks and are safe on this queue.
        CoinJoinRecovery.shared.resetForWipe()
        CoinJoinWithdrawalStore.shared.resetForWipe()
        ShieldedWithdrawalStore.shared.resetForWipe()
        AssetLockProbeStore.shared.resetForWipe()
        SPVChainResyncMarker.resetForWipe()
        // Without this a contested submission outlived the wallet that made it:
        // reset mid-vote, create a new wallet, and the new wallet reported the
        // old one's name as still in voting.
        DWContestedNameStatusService.resetForWipe()
        DWCurrentUserIdentityInfo.resetPendingMainNamesForWipe()

        // Clear every network-scoped active-wallet registry entry only after
        // the network stores and the global SDK Keychain inventory are empty.
        // Devnet included: its ids are network-scoped, so a surviving
        // DW_ACTIVE_WALLET_ID_2 would point at deleted material.
        WalletEnvironment.setActiveWalletId(nil, for: .mainnet)
        WalletEnvironment.setActiveWalletId(nil, for: .testnet)
        WalletEnvironment.setActiveWalletId(nil, for: .devnet)
        // The wallet devnet was last entered from is gone too.
        WalletEnvironment.devnetProvisioningSourceWalletId = nil

        let elapsed = startedAt.duration(to: .now)
        logger.info(
            "wiped SwiftDashSDK wallets across mainnet/testnet in \(String(describing: elapsed), privacy: .public); authorization=\(authorization.logLabel, privacy: .public)")

        // Reset-all also drops the user's TRACKED (wallet-independent)
        // masternodes and their vaulted keys — they survive single-wallet
        // deletion, not a full reset (owner decision 2026-08-24). Runs
        // SYNCHRONOUSLY before the runtime teardown below: the cleanup
        // needs the host's manager and model container, which
        // `handleWalletWiped(completion:)` tears down. This body runs on the wipe
        // executor's background queue, so the main hop cannot deadlock.
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                TrackedMasternodeKeyVault.wipeAllTrackedState()
            }
        }

        // Tear down the app-owned runtime now that all wallet material is
        // gone (stops BLAST/SPV, drops the host-owned manager/wallet, clears
        // published wallet state; public chain data is kept so the next
        // wallet on this device skips an expensive resync) — and WAIT for
        // that teardown. Blocking here keeps the wipe executor's queue
        // occupied until the runtime is really down, so `waitForPendingWipe`
        // means "data wiped AND runtime torn down": the wipe HUDs stay up
        // through the teardown, and a wallet created right after their
        // completion can no longer interleave with a still-queued fullReset.
        let teardownFinished = DispatchSemaphore(value: 0)
        SwiftDashSDKWalletRuntime.handleWalletWiped {
            teardownFinished.signal()
        }
        // Defensive off-main check mirroring `deleteWalletsFromSDK` (which
        // already refused main much earlier): waiting here on main would
        // deadlock — and NOT waiting must not report success, because the
        // contract is "data wiped AND runtime torn down", so fail as
        // conservatively as the timeout path below.
        guard !Thread.isMainThread else {
            logger.error("performWipe unexpectedly on the main thread; cannot await runtime teardown — reporting failure")
            return false
        }
        let teardownStarted = CFAbsoluteTimeGetCurrent()
        // Bounded wait: the worst legitimate case is a wedged native
        // teardown (~45 s of Rust join budgets) queued behind a stalled
        // start (~45 s of SDK/DAPI budgets); anything past this deadline
        // is a hang, not a slow path. On expiry give up on WAITING — the
        // teardown itself stays queued and still runs — and report
        // failure rather than success, so no caller treats the wipe as
        // complete while `fullReset` is unfinished (the wipe body is
        // idempotent; a Retry re-enters this barrier behind it).
        if teardownFinished.wait(timeout: .now() + .seconds(180)) == .timedOut {
            logger.error("runtime teardown did not finish within 180s; reporting wipe failure while it completes in the background")
            return false
        }
        let teardownMs = Int((CFAbsoluteTimeGetCurrent() - teardownStarted) * 1000)
        DWLogger.log("🧹 WIPE runtime teardown awaited \(teardownMs)ms")
        return true
    }

    /// Match each SDK-owned Keychain wallet id to the network discriminant
    /// included in its deterministic id. An unknown id is a hard failure:
    /// guessing a manager could recreate the false-success/data-resurrection
    /// bug this classification exists to prevent.
    private static func classifyStoredWallets(
        storage: WalletStorage
    ) throws -> (
        walletIdsByNetwork: [Network: Set<Data>],
        mnemonics: [String]
    ) {
        var walletIdsByNetwork: [Network: Set<Data>] = [.mainnet: [], .testnet: [], .devnet: []]
        var mnemonics: [String] = []

        for walletId in try storage.listWalletIdsWithMnemonic() {
            let mnemonic = try storage.retrieveMnemonic(for: walletId)
            let resolution = try SwiftDashSDKStoredWalletNetworkResolver.resolve(
                walletId: walletId,
                mnemonic: mnemonic)
            walletIdsByNetwork[resolution.network, default: []].insert(walletId)
            mnemonics.append(mnemonic)
        }

        return (walletIdsByNetwork, mnemonics)
    }

    /// Phrase-authorized recovery may wipe mirrored mainnet/testnet IDs, but
    /// never two different logical seeds. Empty or ambiguous input fails closed.
    static func soleNormalizedMnemonic(in mnemonics: [String]) -> String? {
        let distinct = Set(mnemonics.map(Mnemonic.normalizePhrase))
        guard distinct.count == 1 else { return nil }
        return distinct.first
    }

    // MARK: - Deletion backend

    /// How one network's persisted wallet material is removed.
    ///
    /// The manager case is the normal path and the only one that also drops
    /// the wallet from the native registry. The offline case exists because
    /// building a devnet manager requires an SDK, and a devnet SDK requires
    /// the quorum service: without this, an offline device or a retired
    /// devnet would make locally stored recovery material undeletable. It
    /// deletes exactly what `PlatformWalletManager.deleteWallet` deletes —
    /// identity keychain items, SwiftData rows, then the Keychain
    /// mnemonic/metadata once no row for the id survives — minus the native
    /// removal, which has no meaning when no native manager holds the wallet.
    private enum DeletionBackend {
        case manager(PlatformWalletManager, isTemporary: Bool)
        case offline(PlatformWalletPersistenceHandler)

        /// Wallet ids the backend itself knows about.
        ///
        /// The offline path reads them from the store it is bound to —
        /// `restorableWalletIds()`, the same network-scoped fetch the SDK's
        /// own loader uses — rather than reporting none. A devnet scope's rows
        /// have to be discoverable WITHOUT the shared mnemonic: the phrase is
        /// what the wipe is removing, so a retry after a partial wipe, or a
        /// scope whose ids were never in the Keychain inventory, would
        /// otherwise present as "nothing to delete" and let the wipe report
        /// success over records that are still there.
        @MainActor
        var loadedWalletIds: Set<Data> {
            switch self {
            case .manager(let manager, _): return Set(manager.wallets.keys)
            case .offline(let handler): return Set(handler.restorableWalletIds())
            }
        }

        /// Explicit deletion cannot succeed while a completed migration copy
        /// still contains wallet data, even if the live store is already empty.
        @MainActor
        func deleteCompletedMigrationSnapshots() throws {
            switch self {
            case .manager(let manager, _):
                guard let handler = manager.persistence else {
                    throw SwiftDashSDKWalletDeletionError.managerUnavailable
                }
                try handler.deleteCompletedMigrationSnapshots()
            case .offline(let handler):
                try handler.deleteCompletedMigrationSnapshots()
            }
        }

        /// Remove one wallet's material through this backend.
        ///
        /// `preservingSharedSecrets` keeps the Keychain mnemonic and metadata
        /// even when this store has no row left for the id. The devnet-scoped
        /// mnemonic is shared by every devnet, while
        /// `walletRowCountAcrossNetworks` counts rows in ONE ModelContainer —
        /// so a sweep of devnet A cannot see devnet B's rows and would drop
        /// the very phrase that names them. Scopes swept ahead of the
        /// authoritative leg pass true; that leg then removes the shared
        /// material once no other scope still holds rows. Only the offline
        /// path honours it, which is sufficient: a manager backend is only
        /// ever the authoritative leg, never a swept scope.
        @MainActor
        func delete(_ walletId: Data, preservingSharedSecrets: Bool = false) throws {
            try deleteCompletedMigrationSnapshots()
            switch self {
            case .manager(let manager, _):
                try manager.deleteWallet(walletId: walletId)
            case .offline(let handler):
                let identityIds = try handler.identityIdsForWallet(walletId: walletId)
                // Keychain before SwiftData, for the same retry-safety reason
                // the SDK's own deletion gives: once the identity rows are
                // gone, the keys they name can no longer be found.
                for identityId in identityIds {
                    try KeychainManager.shared.deleteAllKeychainItems(forIdentityId: identityId)
                }
                try KeychainManager.shared.deleteAllIdentityPrivateKeys(forWalletId: walletId)
                try handler.deleteWalletData(walletId: walletId)
                guard !preservingSharedSecrets else { return }
                if try handler.walletRowCountAcrossNetworks(walletId: walletId) == 0 {
                    let storage = WalletStorage()
                    // Metadata first so the mnemonic stays available for a retry.
                    try storage.deleteMetadata(for: walletId)
                    try storage.deleteMnemonic(for: walletId)
                }
            }
        }

        /// Tears down a manager this backend owns. No-op for a borrowed live
        /// manager (the runtime's) and for the offline path, which holds only
        /// the process-cached container.
        func shutDownIfOwned() async {
            if case .manager(let manager, let isTemporary) = self, isTemporary {
                await manager.shutdown()
            }
        }
    }

    /// The backend for `network`, preferring a manager and falling back to
    /// the store-only path.
    ///
    /// The fallback is devnet-only on purpose: mainnet and testnet build
    /// their SDK from local parameters, so a failure there is a real fault
    /// and must not be papered over by a weaker deletion path.
    @MainActor
    private static func deletionBackend(for network: Network, forFullWipe: Bool = false) async throws -> DeletionBackend {
        let host = SwiftDashSDKHost.shared
        let backend: DeletionBackend
        do {
            let (manager, isTemporary) = try await host.managerForWipe(network: network)
            backend = .manager(manager, isTemporary: isTemporary)
        } catch {
            guard network == .devnet else { throw error }
            logger.error(
                """
                devnet manager unavailable for deletion                 (\(String(describing: error), privacy: .public));                 deleting devnet material from the store directly
                """)
            backend = .offline(try await host.storeOnlyPersistenceHandler(for: network))
        }
        if forFullWipe {
            do {
                // Delete All must also remove copies from empty stores. A
                // single-wallet removal waits until membership is established
                // and DeletionBackend.delete runs, before touching snapshots.
                try backend.deleteCompletedMigrationSnapshots()
            } catch {
                await backend.shutDownIfOwned()
                throw error
            }
        }
        return backend
    }

    /// Run synchronous full deletion through the manager belonging to each
    /// network. Manager-persisted ids are unioned with the Keychain inventory
    /// so a previous partial wipe's seedless SwiftData wallet is removed too.
    private static func deleteWalletsFromSDK(
        _ storedWalletIdsByNetwork: [Network: Set<Data>]
    ) -> Bool {
        // `finished.wait()` below blocks this thread until the `@MainActor`
        // task signals it. On the main thread that task could never be
        // scheduled, so the wait would deadlock rather than fail.
        guard !Thread.isMainThread else {
            logger.error("Refusing synchronous wallet deletion on the main thread")
            return false
        }

        let finished = DispatchSemaphore(value: 0)
        let result = WalletWipeResultAccumulator()
        Task { @MainActor in
            let host = SwiftDashSDKHost.shared
            var networks: [Network] = [.mainnet, .testnet]
            // Devnet joins the wipe when this device holds devnet material:
            // either a devnet-scoped Keychain entry, or a persisted devnet
            // store. The store half is what makes a retry safe — a previous
            // attempt may already have removed the shared mnemonic, and an
            // inclusion test reading only the Keychain inventory would then
            // skip devnet entirely and let the wipe report success over rows
            // that are still there. Preparing a devnet deletion reaches for
            // the quorum service first, so it stays gated on there being
            // something to delete; when that service is unreachable the
            // deletion still happens, through the store-only backend.
            let devnetScopes = DevnetConfiguration.persistedDevnetScopes()
            if !(storedWalletIdsByNetwork[.devnet] ?? []).isEmpty || !devnetScopes.isEmpty {
                networks.append(.devnet)
            }
            if let current = host.runningNetwork,
               let currentIndex = networks.firstIndex(of: current) {
                networks.remove(at: currentIndex)
                networks.append(current)
            }

            // Other devnet scopes are swept BEFORE the loop that deletes the
            // configured one, because that loop's devnet leg is what removes
            // the shared devnet mnemonic — and once the phrase is gone,
            // nothing can enumerate the wallets whose rows still sit in
            // another devnet's store. Sweeping first means the mnemonic
            // outlives every scope that still needs it to be found.
            if networks.contains(.devnet) {
                await sweepOtherDevnetScopes(
                    scopes: devnetScopes,
                    walletIds: storedWalletIdsByNetwork[.devnet] ?? [],
                    result: result)
            }

            for network in networks {
                do {
                    let backend = try await deletionBackend(for: network, forFullWipe: true)
                    var walletIds = backend.loadedWalletIds
                    walletIds.formUnion(storedWalletIdsByNetwork[network] ?? [])

                    for walletId in walletIds.sorted(by: {
                        $0.lexicographicallyPrecedes($1)
                    }) {
                        do {
                            try deleteWalletFromSDK(
                                walletId,
                                deleteWallet: { id in
                                    try backend.delete(id)
                                })
                        } catch {
                            result.recordFailure()
                            logDeletionFailure(error, walletId: walletId, network: network)
                        }
                    }
                    // A detached per-network manager is owned by this loop:
                    // shut it down deterministically before the next network
                    // (or the post-wipe rebuild) can touch the same
                    // process-cached ModelContainer. The live published
                    // manager (isTemporary == false) is the runtime's to
                    // tear down.
                    await backend.shutDownIfOwned()
                } catch {
                    result.recordFailure()
                    logger.error(
                        "failed to prepare \(network.networkName, privacy: .public) manager for wipe: \(String(describing: error), privacy: .public)")
                }
            }

            do {
                let remaining = try WalletStorage().listWalletIdsWithMnemonic()
                if !remaining.isEmpty {
                    result.recordFailure()
                    logger.error(
                        "wallet wipe left \(remaining.count, privacy: .public) SDK mnemonic item(s); reporting failure")
                }
            } catch {
                result.recordFailure()
                logger.error(
                    "failed to verify empty SDK wallet inventory: \(String(describing: error), privacy: .public)")
            }

            finished.signal()
        }
        finished.wait()
        return result.succeeded
    }

    /// Delete the same wallet ids from every devnet store this device holds
    /// that is NOT the configured one.
    ///
    /// The loop above walks `Network.devnet`, which resolves to the CURRENT
    /// devnet's scope. A device pointed at devnet A and later at devnet B has a
    /// store per devnet, and the mnemonic that names those wallets is shared
    /// across them — so deleting on B removed the mnemonic while A's wallet and
    /// identity rows stayed, unreachable afterwards by anything that enumerates
    /// from the Keychain. The wipe would then pass its final inventory check
    /// and report success over records that are still there.
    ///
    /// Store-only by construction: another devnet's DAPI is not reachable (and
    /// not worth reaching) just to delete local rows.
    @MainActor
    private static func sweepOtherDevnetScopes(
        scopes: [String],
        walletIds: Set<Data>,
        result: WalletWipeResultAccumulator
    ) async {
        let current = Network.devnet.persistenceScope
        for scope in scopes where scope != current {
            do {
                let handler = try await SwiftDashSDKHost.shared.storeOnlyPersistenceHandler(
                    for: .devnet,
                    scope: scope)
                let backend = DeletionBackend.offline(handler)
                try backend.deleteCompletedMigrationSnapshots()
                // The Keychain inventory can be empty here — a retry after the
                // shared mnemonic was already removed — so the ids this scope's
                // own store reports are unioned in. A scope's rows are always
                // deletable from the scope itself.
                var scopedWalletIds = backend.loadedWalletIds
                scopedWalletIds.formUnion(walletIds)
                guard !scopedWalletIds.isEmpty else { continue }
                for walletId in scopedWalletIds.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                    do {
                        // The shared devnet mnemonic is left alone: it still
                        // names rows in the scopes not yet swept, and the
                        // configured scope's own deletion removes it last.
                        try deleteWalletFromSDK(walletId, deleteWallet: {
                            try backend.delete($0, preservingSharedSecrets: true)
                        })
                    } catch {
                        result.recordFailure()
                        logDeletionFailure(error, walletId: walletId, network: .devnet)
                    }
                }
                logger.info("swept devnet scope \(scope, privacy: .public) for \(scopedWalletIds.count, privacy: .public) wallet(s)")
            } catch {
                result.recordFailure()
                logger.error(
                    "failed to open devnet scope \(scope, privacy: .public) for wipe: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func logDeletionFailure(
        _ error: Error,
        walletId: Data,
        network: Network
    ) {
        let walletLabel = walletId.prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
        logger.error(
            "deleteWallet failed for \(network.networkName, privacy: .public)/\(walletLabel, privacy: .public)…: \(String(describing: error), privacy: .public)")
    }

    /// Delete every SDK representation (mainnet/testnet, plus devnet when
    /// one is stored) of one recovery phrase.
    /// Legacy cleanup runs first on the migrator's serial queue, so an import
    /// that was already in flight is visible to the managers prepared below.
    /// The live network is deleted last, preserving its mnemonic for Retry if
    /// inactive-network deletion fails.
    @MainActor
    static func deleteLogicalWallet(mnemonic phrase: String) async throws {
        let mnemonic = Mnemonic.normalizePhrase(phrase)
        guard Mnemonic.validate(mnemonic) else {
            throw SwiftDashSDKWalletDeletionError.invalidMnemonic
        }
        // Same reason the full wipe invalidates: removing one wallet changes
        // which networks still hold material, and the app-level gate caches
        // that answer for the process. Without this, removing the only
        // selectable wallet on an install that also carries devnet material
        // leaves `hasWallet` reporting true until the next launch — the
        // `walletNotFound` dead end the gate exists to prevent. On `defer`
        // because a partial deletion changes the answer too.
        defer { WalletEnvironment.invalidateWalletMaterialCache() }

        let walletIds = try SwiftDashSDKStoredWalletNetworkResolver.walletIds(
            for: mnemonic)
        guard walletIds.count == SwiftDashSDKStoredWalletNetworkResolver.storableNetworks.count else {
            throw SwiftDashSDKWalletDeletionError.unrecognizedWalletNetwork
        }

        try await SwiftDashSDKKeyMigrator.removeLegacyMnemonicAccounts(
            matching: mnemonic)

        let storage = WalletStorage()
        let storedWalletIds = Set(try storage.listWalletIdsWithMnemonic())
        let host = SwiftDashSDKHost.shared
        var networks: [Network] = [.mainnet, .testnet]
        // Same conditional devnet leg as the full wipe: only when this
        // phrase's devnet-scoped id is actually stored is a devnet manager
        // worth (and safe to require) building.
        if let devnetId = walletIds[.devnet], storedWalletIds.contains(devnetId) {
            networks.append(.devnet)
        }
        if let current = host.runningNetwork ?? WalletEnvironment.network,
           let currentIndex = networks.firstIndex(of: current) {
            networks.remove(at: currentIndex)
            networks.append(current)
        }

        struct PendingDeletion {
            let network: Network
            let walletId: Data
            let backend: DeletionBackend
            /// True for the extra devnet scopes swept ahead of the configured
            /// one: they must not remove the shared devnet mnemonic, which
            /// still names the rows the authoritative leg is about to delete.
            var preservesSharedSecrets: Bool = false
        }

        var deletions: [PendingDeletion] = []

        // Detached managers are owned by this function; shut them down
        // deterministically on both the success and every failure path (a
        // manager-preparation or deletion throw would otherwise leave
        // teardown to the fire-and-forget deinit fallback, racing any
        // follow-up rebuild over the same process-cached ModelContainer).
        func shutDownTemporaryManagers() async {
            for deletion in deletions {
                await deletion.backend.shutDownIfOwned()
            }
            deletions.removeAll()
        }

        do {
            for network in networks {
                guard let walletId = walletIds[network] else { continue }
                // Every OTHER devnet this device holds a store for, for the
                // same reason the full wipe sweeps them: the devnet-scoped
                // mnemonic is shared across devnets, so removing it while
                // another devnet's rows survive leaves records nothing can
                // enumerate afterwards. Store-only — another devnet's DAPI is
                // neither reachable nor needed to delete local rows.
                if network == .devnet {
                    let current = Network.devnet.persistenceScope
                    for scope in DevnetConfiguration.persistedDevnetScopes() where scope != current {
                        let handler = try await SwiftDashSDKHost.shared.storeOnlyPersistenceHandler(
                            for: .devnet,
                            scope: scope)
                        deletions.append(PendingDeletion(
                            network: .devnet,
                            walletId: walletId,
                            backend: .offline(handler),
                            preservesSharedSecrets: true))
                    }
                }
                let backend = try await deletionBackend(for: network)
                if storedWalletIds.contains(walletId) || backend.loadedWalletIds.contains(walletId) {
                    deletions.append(PendingDeletion(
                        network: network,
                        walletId: walletId,
                        backend: backend))
                } else {
                    // Built a detached manager only to find nothing to delete on
                    // this network — shut it down now rather than leaving it to
                    // the deinit fallback.
                    await backend.shutDownIfOwned()
                }
            }

            for deletion in deletions {
                try deleteWalletFromSDK(
                    deletion.walletId,
                    deleteWallet: { walletId in
                        try deletion.backend.delete(
                            walletId,
                            preservingSharedSecrets: deletion.preservesSharedSecrets)
                    })

                let kind = WalletEnvironment.networkKind(for: deletion.network)
                if WalletEnvironment.activeWalletId(for: kind) == deletion.walletId {
                    WalletEnvironment.setActiveWalletId(nil, for: kind)
                }
            }
        } catch {
            await shutDownTemporaryManagers()
            throw error
        }
        await shutDownTemporaryManagers()

        let remaining = Set(try storage.listWalletIdsWithMnemonic())
        guard walletIds.values.allSatisfy({ !remaining.contains($0) }) else {
            throw SwiftDashSDKWalletDeletionError.walletDeletionIncomplete
        }
    }

    /// Full per-wallet SwiftDashSDK deletion of a single wallet: the Rust
    /// manager state + this wallet's SwiftData rows and Keychain mnemonic via
    /// `PlatformWalletManager.deleteWallet(walletId:)`. The app-side cleanup
    /// runs only after that complete SDK operation succeeds. On failure the
    /// error is propagated and no additional destructive cleanup runs.
    ///
    /// The single per-wallet deletion primitive shared by the full wipe
    /// (`deleteWalletsFromSDK`) and the Wallets screen's per-wallet Remove
    /// flow (`WalletsViewModel`) — one body, not a copy on each side
    /// (guardrail #1). Callers own their own registry/runtime bookkeeping
    /// (the wipe tears the runtime down; the remove flow rebinds via
    /// `switchWallet` before deleting the active wallet).
    @MainActor
    static func deleteWalletFromSDK(
        _ walletId: Data,
        deleteWallet: (@MainActor (Data) throws -> Void)? = nil,
        clearAppState: (@MainActor (Data) -> Void)? = nil
    ) throws {
        let deleteWallet = deleteWallet ?? { walletId in
            guard let manager = SwiftDashSDKHost.shared.manager else {
                throw SwiftDashSDKWalletDeletionError.managerUnavailable
            }
            try manager.deleteWallet(walletId: walletId)
        }

        do {
            try deleteWallet(walletId)
        } catch {
            logger.error("deleteWallet failed: \(String(describing: error), privacy: .public)")
            throw error
        }

        // Clear this wallet's per-wallet app-side state that lives outside the
        // SDK/SwiftData/Keychain teardown above: CrowdNode account state and the
        // CoinJoin withdrawal tag set are UserDefaults, keyed by walletId hex.
        // Done here (not in the UI) so BOTH the per-wallet Remove flow and the
        // full wipe's per-wallet loop clear them — one shared deletion primitive
        // (guardrail #1). Hex must match `WalletEnvironment.activeWalletIdHex`
        // (lowercase, %02x). Idempotent; UserDefaults-only, so thread-agnostic.
        if let clearAppState {
            clearAppState(walletId)
        } else {
            let walletIdHex = walletId.map { String(format: "%02x", $0) }.joined()
            CrowdNodeDefaults.shared.clearPerWalletKeys(forWalletIdHex: walletIdHex)
            CoinJoinWithdrawalStore.shared.clearForWallet(walletIdHex: walletIdHex)
            ShieldedWithdrawalStore.shared.clearForWallet(walletIdHex: walletIdHex)
            AssetLockProbeStore.shared.clearForWallet(walletIdHex: walletIdHex)
        }

        // Per-wallet identity bookkeeping, not app-state cleanup: it runs on
        // every deletion regardless of the injected `clearAppState` seam.
        // walletIds are deterministic per mnemonic+network, so the same
        // phrase re-imported later must inherit neither the generated-wallet
        // marker (a short probe budget on an imported seed) nor this
        // wallet's settled identity-recovery context (a backstop that never
        // runs).
        GeneratedWalletIdentityMarker.clear(walletId: walletId)
#if DASHPAY
        DWSameSeedIdentityRecoveryCoordinator.shared.forgetWallet(walletId: walletId)
#endif
    }
}
