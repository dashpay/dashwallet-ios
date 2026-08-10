//
//  UnconfirmedTransactionRemover.swift
//  DashWallet
//
//  Removes a never-accepted transaction from local wallet state — the
//  tx-detail "Remove if not on Blockchain" action for a stuck asset
//  lock the network keeps rejecting (rebroadcasts end "outcome
//  uncertain", the tx is on no explorer, and the coins it tried to
//  spend stay locked forever).
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
                return NSLocalizedString("Transaction is on the blockchain", comment: "Remove never-accepted transaction: refused because the explorer found it")
            case .verificationUnavailable:
                return NSLocalizedString("Couldn't reach a block explorer to verify the transaction isn't on the blockchain. Check your connection and try again.", comment: "Remove never-accepted transaction: explorer unreachable")
            }
        }
    }

    /// Compact-filter rescan window bounds, in blocks (~2.5 min each):
    /// at least ~30 hours even for a fresh transaction, at most ~5 weeks
    /// for a long-stuck one.
    private static let minRescanBlocks: UInt32 = 720
    private static let maxRescanBlocks: UInt32 = 20_000
    /// Extra rewind margin below the transaction's first-seen height
    /// estimate (~1 day), covering clock skew and variable block times.
    private static let rescanMarginBlocks: UInt32 = 576

    func remove(txidWire: Data) async throws {
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
        let firstSeen: UInt64 = row.firstSeen

        // 2. The claim in the button title is checked, not assumed: a
        //    transaction the explorer knows (mempool or mined) is never
        //    removed, and an unreachable explorer refuses the removal.
        if try await Self.explorerKnowsTransaction(displayTxid: displayTxid, network: network) {
            Self.logger.notice("🗑️ TX-REMOVE :: refused — explorer reports \(displayTxid, privacy: .public) on the network")
            throw RemovalError.transactionOnChain
        }

        // 3. Persistence surgery. Inputs first: the `.nullify` inverse on
        //    `PersistentTransaction.inputs` only clears the relationship —
        //    the denormalized `isSpent` column must be flipped explicitly
        //    or the restore buffer would keep excluding these TXOs from
        //    the spendable set.
        let unspentInputCount = row.inputs.count
        for spent in row.inputs {
            spent.isSpent = false
            spent.spendingTransaction = nil
            spent.spendingInputIndex = nil
            spent.lastUpdated = Date()
        }
        // Deleting the row cascades its own outputs and unresolved
        // pending-input placeholders.
        context.delete(row)
        // The asset-lock bookmark (any vout of this txid): the row that
        // makes launch-time recovery re-track and re-broadcast the lock.
        // Tiny table — fetch by wallet and filter in Swift, same as
        // ShieldedTxLookup.
        let lockPrefix = displayTxid.lowercased() + ":"
        let locks = try context.fetch(FetchDescriptor<PersistentAssetLock>(
            predicate: PersistentAssetLock.predicate(walletId: walletId)))
        for lock in locks where lock.outPointHex.lowercased().hasPrefix(lockPrefix) {
            context.delete(lock)
        }
        try context.save()
        Self.logger.notice("🗑️ TX-REMOVE :: deleted \(displayTxid, privacy: .public) — \(unspentInputCount, privacy: .public) input(s) unspent")

        // App-side metadata (tax category override) keyed by the same
        // hash — a fresh install knows nothing about a removed tx, and
        // neither should this one.
        if let metadata = TransactionMetadataDAOImpl.shared.get(by: txidWire) {
            TransactionMetadataDAOImpl.shared.delete(dto: metadata)
        }

        // 4. Full runtime reload — the same serialized stop → load →
        //    start lifecycle a network switch runs. The reloaded Rust
        //    wallet rebuilds its tx set, UTXOs and spent_outpoints from
        //    the rows as they now are, and dash-spv's mempool tracker
        //    (which kept rebroadcasting) restarts without the tx.
        await SwiftDashSDKWalletRuntime.shared.rearmPlatformSync()

        // 5. Rescan recent compact filters, reaching back past the
        //    removed transaction's first appearance: if the explorer was
        //    wrong and the tx IS mined, the re-match finds it and the
        //    wallet state repairs itself. Best-effort — the removal
        //    already verified off-chain status; a failed arm is logged,
        //    not surfaced as a failed removal.
        let tip = SwiftDashSDKSPVCoordinator.shared.tipHeight
        if tip > 0, let manager = SwiftDashSDKHost.shared.manager {
            let ageSeconds = max(0, Date().timeIntervalSince1970 - TimeInterval(firstSeen))
            let ageBlocks = UInt32(clamping: Int(ageSeconds / 150)) + Self.rescanMarginBlocks
            let blocksBack = min(Self.maxRescanBlocks, max(Self.minRescanBlocks, ageBlocks))
            let fromHeight = tip > blocksBack ? tip - blocksBack : 1
            do {
                try manager.spvRescanFilters(walletId: walletId, fromHeight: fromHeight)
                Self.logger.notice("🗑️ TX-REMOVE :: filter rescan armed from height \(fromHeight, privacy: .public) (tip \(tip, privacy: .public))")
            } catch {
                Self.logger.error("🗑️ TX-REMOVE :: filter rescan arm failed: \(String(describing: error), privacy: .public)")
            }
        } else {
            Self.logger.error("🗑️ TX-REMOVE :: filter rescan skipped — SPV not running after reload")
        }

        // 6. App caches that mirror the deleted rows.
        ShieldedTxLookup.shared.refresh()
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
