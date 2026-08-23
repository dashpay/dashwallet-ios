//
//  UnconfirmedTransactionRemover.swift
//  DashWallet
//
//  Removes never-accepted transactions from local wallet state. Two
//  entry points share the surgery:
//  - `remove(txidWire:)` — the tx-detail "Remove if Not on Network"
//    action for one stuck transaction (a parked asset lock, or any
//    network-dropped send such as a stalled CoinJoin sweep chunk);
//    explorer-checked per the rails below.
//  - `dropAllUnconfirmedAndRescan()` — the Core Sync screen's bulk
//    variant over every mempool-context row of the active wallet; it
//    skips the per-tx explorer check and relies on the filter rescan
//    to restore anything that was actually on-chain.
//
//  There is no removal API at any FFI layer (verified against the
//  pinned rust-dashcore/platform revs: key-wallet has no
//  reorg/rollback/remove path at all, and `untrack_asset_lock` is
//  `pub(crate)` + Built-only). What DOES exist is the restore path:
//  on wallet load the Rust side rehydrates its entire core state from
//  the SwiftData rows (`loadWalletList` → UTXO/tx-record restore
//  buffers), and `spent_outpoints` is documented as "rebuilt from
//  `transactions` during deserialization". So removal is performed on
//  the persistence layer — delete the transaction row, un-mark the
//  TXOs it spent, drop its asset-lock bookmark — followed by a full
//  runtime reload, after which the Rust wallet has never heard of the
//  transaction and its inputs are spendable again.
//  TODO(sdk-remove-tx): replace the persistence surgery with a
//  first-class SDK call once one exists upstream.
//
//  Ordered safety rails:
//    1. The row must exist locally and be unconfirmed (mempool
//       context, no block) — an IS/CL-locked or mined tx is never
//       touched.
//    2. A block explorer is consulted first; if it KNOWS the tx, the
//       removal is refused (the wallet just needs to catch up). If
//       the explorer can't be reached, the removal is refused too —
//       "if not on Blockchain" is a checked claim, never a guess.
//    3. After the reload, the wallet's compact-filter checkpoint is
//       rewound past the transaction's first-seen time
//       (`spvRescanFilters`), so if the explorer was wrong the
//       rescan re-discovers the transaction on-chain and restores it.
//
//  dashpay + dashwallet targets.
//

import Foundation
import OSLog
import SwiftDashSDK
import SwiftData

@MainActor
struct UnconfirmedTransactionRemover {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.unconfirmed-tx-remover")

    enum RemovalError: LocalizedError {
        case notReady
        case transactionNotFound
        case confirmedLocally
        case transactionOnChain
        case verificationUnavailable

        var errorDescription: String? {
            switch self {
            case .notReady:
                return NSLocalizedString("Wallet is not ready", comment: "DashPay")
            case .transactionNotFound:
                return NSLocalizedString("This transaction is not in the local wallet.", comment: "Remove never-accepted transaction: no local row")
            case .confirmedLocally:
                return NSLocalizedString("This transaction is confirmed and can't be removed.", comment: "Remove never-accepted transaction: local state says it's on-chain")
            case .transactionOnChain:
                return NSLocalizedString("Transaction is known to the network", comment: "Remove never-accepted transaction: refused because the explorer found it")
            case .verificationUnavailable:
                return NSLocalizedString("Couldn't reach a block explorer to verify the transaction isn't on the blockchain. Check your connection and try again.", comment: "Remove never-accepted transaction: explorer unreachable")
            }
        }
    }

    /// Minimum compact-filter rescan window, in blocks (~2.5 min each):
    /// at least ~30 hours even for a fresh transaction. There is no
    /// maximum — recovery depth is uncapped and reaches back past the
    /// oldest removed transaction's first appearance, bounded only by
    /// the SDK's wallet birth-height / stored-chain-data floors.
    private static let minRescanBlocks: UInt32 = 720
    /// Extra rewind margin below the transaction's first-seen height
    /// estimate (~1 day), covering clock skew and variable block times.
    private static let rescanMarginBlocks: UInt32 = 576

    /// - Returns: whether the recovery filter rescan was armed. `false`
    ///   means the removal itself succeeded but the rescan didn't start
    ///   (SPV not running / arm threw) — the caller should tell the user
    ///   to run Rescan Filters manually so the safety net isn't silently
    ///   skipped.
    @discardableResult
    func remove(txidWire: Data) async throws -> Bool {
        guard let container = SwiftDashSDKHost.shared.modelContainer,
              let network = WalletEnvironment.network,
              let walletId = WalletEnvironment.activeWalletId(for: WalletEnvironment.networkKind) else {
            throw RemovalError.notReady
        }
        let displayTxid = Transaction.displayHex(txidWire)

        // 1. Local sanity — refuse anything the local store believes is
        //    past the mempool (context 0 = mempool; 1…3 = IS/inBlock/CL).
        let context = container.mainContext
        var descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == txidWire })
        descriptor.fetchLimit = 1
        guard let row = try context.fetch(descriptor).first else {
            throw RemovalError.transactionNotFound
        }
        guard row.context == 0, row.blockHeight == 0 else {
            throw RemovalError.confirmedLocally
        }

        // 2. The claim in the button title is checked, not assumed: a
        //    transaction the explorer knows (mempool or mined) is never
        //    removed, and an unreachable explorer refuses the removal.
        if try await Self.explorerKnowsTransaction(displayTxid: displayTxid, network: network) {
            Self.logger.notice("🗑️ TX-REMOVE :: refused — explorer reports \(displayTxid, privacy: .public) on the network")
            throw RemovalError.transactionOnChain
        }

        // 3. The explorer check suspended the main actor, so nothing from
        //    step 1 is trusted anymore: a filter match can have confirmed
        //    the transaction, or the active wallet can have switched.
        //    Re-resolve and re-validate everything before touching rows.
        guard WalletEnvironment.activeWalletId(for: WalletEnvironment.networkKind) == walletId else {
            throw RemovalError.notReady
        }
        guard let freshRow = try context.fetch(descriptor).first else {
            throw RemovalError.transactionNotFound
        }
        guard freshRow.context == 0, freshRow.blockHeight == 0 else {
            throw RemovalError.confirmedLocally
        }
        guard SwiftDashSDKWalletSource.isWalletMember(freshRow, walletId: walletId) else {
            throw RemovalError.transactionNotFound
        }
        let firstSeen: UInt64 = freshRow.firstSeen

        // 4. Persistence surgery, then the shared reload + rescan +
        //    cache-refresh tail.
        Self.excise(freshRow, in: context)
        try Self.deleteAssetLockBookmarks(forDisplayTxids: [displayTxid], walletId: walletId, in: context)
        try context.save()
        Self.logger.notice("🗑️ TX-REMOVE :: deleted \(displayTxid, privacy: .public)")

        return await Self.finishRemoval(
            txidsWire: [txidWire], walletId: walletId, oldestFirstSeen: firstSeen)
    }

    /// Bulk diagnostic for the Core Sync screen: drop EVERY unconfirmed
    /// (mempool-context, no block) transaction of the active wallet, free
    /// the TXOs they tried to spend, and rescan recent filters back past
    /// the oldest dropped transaction. Unlike `remove(txidWire:)` there is
    /// no per-transaction explorer check — the rescan is the safety rail:
    /// a dropped transaction that IS on the blockchain is re-matched and
    /// restored by it. Nothing is sent to the network.
    ///
    /// - Returns: how many transactions were dropped (0 = nothing to
    ///   drop; no reload or rescan runs, so `rescanArmed` is `false`),
    ///   and whether the recovery rescan was armed — `false` after a
    ///   non-zero drop means the caller must tell the user to run
    ///   Rescan Filters manually.
    func dropAllUnconfirmedAndRescan() async throws -> (dropped: Int, rescanArmed: Bool) {
        guard let container = SwiftDashSDKHost.shared.modelContainer,
              let walletId = WalletEnvironment.activeWalletId(for: WalletEnvironment.networkKind) else {
            throw RemovalError.notReady
        }
        let context = container.mainContext
        let rows = try Self.unconfirmedRows(in: context, walletId: walletId)
        guard !rows.isEmpty else { return (dropped: 0, rescanArmed: false) }

        var oldestFirstSeen = UInt64.max
        var displayTxids: [String] = []
        var txidsWire: [Data] = []
        for row in rows {
            oldestFirstSeen = min(oldestFirstSeen, row.firstSeen)
            displayTxids.append(Transaction.displayHex(row.txid))
            txidsWire.append(row.txid)
            Self.excise(row, in: context)
        }
        try Self.deleteAssetLockBookmarks(forDisplayTxids: displayTxids, walletId: walletId, in: context)
        try context.save()
        Self.logger.notice("🗑️ TX-REMOVE :: bulk-dropped \(rows.count, privacy: .public) unconfirmed tx(s): \(displayTxids.joined(separator: ","), privacy: .public)")

        let rescanArmed = await Self.finishRemoval(
            txidsWire: txidsWire, walletId: walletId, oldestFirstSeen: oldestFirstSeen)
        return (dropped: rows.count, rescanArmed: rescanArmed)
    }

    /// The active wallet's unconfirmed (mempool-context, no block) rows —
    /// exactly what `dropAllUnconfirmedAndRescan` would remove. Membership
    /// is relationship-based (`SwiftDashSDKWalletSource.isWalletMember`),
    /// so call on the main context's thread.
    static func unconfirmedRows(in context: ModelContext, walletId: Data) throws -> [PersistentTransaction] {
        try context.fetch(FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.context == 0 && $0.blockHeight == 0 }))
            .filter { SwiftDashSDKWalletSource.isWalletMember($0, walletId: walletId) }
    }

    /// Count variant of `unconfirmedRows` for UI display; 0 when no wallet
    /// is bound or the fetch fails.
    static func unconfirmedCount() -> Int {
        guard let container = SwiftDashSDKHost.shared.modelContainer,
              let walletId = WalletEnvironment.activeWalletId(for: WalletEnvironment.networkKind) else {
            return 0
        }
        return (try? unconfirmedRows(in: container.mainContext, walletId: walletId).count) ?? 0
    }

    /// Persistence surgery for one row. Inputs first: the `.nullify`
    /// inverse on `PersistentTransaction.inputs` only clears the
    /// relationship — the denormalized `isSpent` column must be flipped
    /// explicitly or the restore buffer would keep excluding these TXOs
    /// from the spendable set. Deleting the row then cascades its own
    /// outputs and unresolved pending-input placeholders. The caller
    /// saves the context.
    private static func excise(_ row: PersistentTransaction, in context: ModelContext) {
        for spent in row.inputs {
            spent.isSpent = false
            spent.spendingTransaction = nil
            spent.spendingInputIndex = nil
            spent.lastUpdated = Date()
        }
        context.delete(row)
    }

    /// Delete the asset-lock bookmarks (any vout of the given txids): the
    /// rows that make launch-time recovery re-track and re-broadcast a
    /// lock. Tiny table — fetch by wallet and filter in Swift, same as
    /// ShieldedTxLookup. The caller saves the context.
    private static func deleteAssetLockBookmarks(
        forDisplayTxids displayTxids: [String], walletId: Data, in context: ModelContext
    ) throws {
        let prefixes = displayTxids.map { $0.lowercased() + ":" }
        let locks = try context.fetch(FetchDescriptor<PersistentAssetLock>(
            predicate: PersistentAssetLock.predicate(walletId: walletId)))
        for lock in locks {
            let outPoint = lock.outPointHex.lowercased()
            if prefixes.contains(where: { outPoint.hasPrefix($0) }) {
                context.delete(lock)
            }
        }
    }

    /// Shared removal tail, after the rows are deleted and saved:
    /// app-side metadata cleanup, full runtime reload, filter rescan,
    /// and cache refresh. Returns whether the rescan was armed — the
    /// rescan is the recovery step that restores a wrongly-removed
    /// on-chain transaction, so callers surface `false` to the user
    /// instead of claiming a complete recovery.
    private static func finishRemoval(
        txidsWire: [Data], walletId: Data, oldestFirstSeen: UInt64
    ) async -> Bool {
        // App-side metadata (tax category override) keyed by the same
        // hash — a fresh install knows nothing about a removed tx, and
        // neither should this one.
        for txidWire in txidsWire {
            if let metadata = TransactionMetadataDAOImpl.shared.get(by: txidWire) {
                TransactionMetadataDAOImpl.shared.delete(dto: metadata)
            }
        }

        // Full runtime reload — the same serialized stop → load → start
        // lifecycle a network switch runs. The reloaded Rust wallet
        // rebuilds its tx set, UTXOs and spent_outpoints from the rows as
        // they now are, and dash-spv's mempool tracker (which kept
        // rebroadcasting) restarts without the removed transactions.
        await SwiftDashSDKWalletRuntime.shared.rearmPlatformSync()

        // Rescan compact filters, reaching back past the OLDEST removed
        // transaction's first appearance — uncapped in depth, because
        // this is the step that restores a removed tx that actually IS
        // mined (the bulk path never explorer-checked, and the single
        // path's explorer can be wrong). The SDK floors the rescan at
        // the wallet's birth height and the locally stored chain data;
        // a row with no usable first-seen time rescans from the floor.
        var rescanArmed = false
        let tip = SwiftDashSDKSPVCoordinator.shared.tipHeight
        if tip > 0, let manager = SwiftDashSDKHost.shared.manager {
            let ageSeconds = max(0, Date().timeIntervalSince1970 - TimeInterval(oldestFirstSeen))
            let ageBlocks = UInt32(clamping: Int(ageSeconds / 150)) + rescanMarginBlocks
            let blocksBack = max(minRescanBlocks, ageBlocks)
            let fromHeight = tip > blocksBack ? tip - blocksBack : 1
            do {
                try manager.spvRescanFilters(walletId: walletId, fromHeight: fromHeight)
                rescanArmed = true
                logger.notice("🗑️ TX-REMOVE :: filter rescan armed from height \(fromHeight, privacy: .public) (tip \(tip, privacy: .public))")
            } catch {
                logger.error("🗑️ TX-REMOVE :: filter rescan arm failed: \(String(describing: error), privacy: .public)")
            }
        } else {
            logger.error("🗑️ TX-REMOVE :: filter rescan skipped — SPV not running after reload")
        }

        // App caches that mirror the deleted rows.
        ShieldedTxLookup.shared.refresh()
        return rescanArmed
    }

    /// One GET against the network's Insight API. 200 = the explorer
    /// knows the tx (mempool or mined); 404 = it doesn't; anything else
    /// (including transport failure) refuses the removal rather than
    /// guessing.
    private static func explorerKnowsTransaction(displayTxid: String, network: Network) async throws -> Bool {
        let base = network == .mainnet
            ? "https://insight.dash.org/insight-api"
            : "https://insight.testnet.networks.dash.org/insight-api"
        guard let url = URL(string: "\(base)/tx/\(displayTxid)") else {
            throw RemovalError.verificationUnavailable
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let http: HTTPURLResponse
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RemovalError.verificationUnavailable
            }
            http = httpResponse
        } catch {
            throw RemovalError.verificationUnavailable
        }
        switch http.statusCode {
        case 200: return true
        case 404: return false
        default: throw RemovalError.verificationUnavailable
        }
    }
}
