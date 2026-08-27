//
//  SwiftDashSDKReceiveAddressReader.swift
//  DashWallet
//
//  Receive-address adapter — SwiftDashSDK is the sole authoritative source.
//
//  Returns the next unused BIP44 external receive address for the wallet
//  bound to `SwiftDashSDKHost.shared`. The "next unused" decision is made
//  by Rust inside `core_wallet_next_receive_address`, which consults the
//  managed wallet's used-set. The used-set is populated by Core SPV block
//  processing and persisted across launches in
//  `Documents/SwiftDashSDK/Platform/<network>/`.
//
//  Cold-launch behavior:
//   - Warm launch with cached SPV state: returns the correct next-unused
//     address immediately (used-set hydrated from disk during host start).
//   - First launch post-migration / after wipe: SPV data dir is fresh, the
//     used-set starts empty, the FFI returns address index 0. As SPV
//     replays blocks, the used-set advances and the next read picks up the
//     new lowest-unused index.
//
//  Returns nil rather than throwing on failure — call sites already treat
//  nil as "no address yet" (DWReceiveModel clears the QR + cache, Swift
//  callers fall back to "" or fatalError as they did before).
//

import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@objc(DWSwiftDashSDKReceiveAddressReader)
final class SwiftDashSDKReceiveAddressReader: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.receive-address-reader")

    /// Main-thread trampoline: `SwiftDashSDKHost.shared` and `mainContext`
    /// are main-bound; Obj-C callers reach here from background queues.
    private static func onMain<T>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(body)
        }
    }

    /// Returns the next unused BIP44 external receive address on the primary
    /// account (index 0). Returns nil when the host hasn't bound a wallet
    /// yet or the FFI call fails. Never throws.
    ///
    /// Takes no network argument: the lookup goes through
    /// `SwiftDashSDKHost.shared`, which is already bound to the active
    /// network at the time `start(network:)` ran.
    @objc
    static func receiveAddress() -> String? {
        receiveDestination()?.address
    }

    /// The receive address and wallet id captured from the same host-bound
    /// wallet. Swift callers that retain work across wallet switches use this
    /// to keep the destination tied to its originating wallet.
    static func receiveDestination() -> (address: String, walletId: Data)? {
        onMain { readDestinationOnMain() }
    }

    // MARK: Request-amount receive detection (DWReceiveModel)

    /// Whether `address` has ever received an output. The SDK's TXO rows are
    /// exactly the wallet's own outputs, so a row existing for the address is
    /// DashSync's `addressIsUsed:`. Safe from any thread.
    @objc
    static func isAddressUsed(_ address: String) -> Bool {
        onMain {
            guard let container = SwiftDashSDKHost.shared.modelContainer,
                  let walletId = SwiftDashSDKHost.shared.wallet?.walletId else { return false }
            var descriptor = FetchDescriptor<PersistentTxo>(
                predicate: #Predicate { $0.address == address && $0.walletId == walletId })
            descriptor.fetchLimit = 1
            let rows = (try? container.mainContext.fetch(descriptor)) ?? []
            return !rows.isEmpty
        }
    }

    /// Received duffs summed for the request-amount check, ported 1:1 from
    /// the DashSync loop in `DWReceiveModel` (inherited unchanged from
    /// breadwallet): per transaction, sum the wallet's own outputs, skipping
    /// transactions that pay `address` and mempool-only rows (`context == 0`
    /// — neither InstantSend-locked, mined, nor chainlocked — standing in for
    /// the old `relayCount` propagation gate). Safe from any thread.
    @objc(receivedTotalExcludingAddress:)
    static func receivedTotal(excludingAddress address: String) -> UInt64 {
        onMain {
            guard let container = SwiftDashSDKHost.shared.modelContainer,
                  let walletId = SwiftDashSDKHost.shared.wallet?.walletId else { return 0 }
            // Scope to the active wallet via the TXO join: `PersistentTransaction`
            // carries no walletId, so gather the wallet's txids from its
            // walletId-scoped TXO rows (producing + spending sides) and sum
            // only those transactions' own outputs.
            let txoDescriptor = FetchDescriptor<PersistentTxo>(
                predicate: #Predicate { $0.walletId == walletId })
            guard let txos = try? container.mainContext.fetch(txoDescriptor) else { return 0 }
            var txids = Set<Data>()
            for txo in txos {
                if let producing = txo.transaction { txids.insert(producing.txid) }
                if let spending = txo.spendingTransaction { txids.insert(spending.txid) }
            }
            guard !txids.isEmpty else { return 0 }
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { txids.contains($0.txid) })
            guard let rows = try? container.mainContext.fetch(descriptor) else { return 0 }

            var total: UInt64 = 0
            for row in rows {
                let ownOutputs = row.outputs
                if ownOutputs.contains(where: { $0.address == address }) {
                    continue
                }
                if row.context == 0 {
                    continue
                }
                total += ownOutputs.reduce(0) { $0 + $1.amount }
            }
            return total
        }
    }

    @MainActor
    private static func readDestinationOnMain() -> (address: String, walletId: Data)? {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            Self.logger.warning("📬 RECVADDR :: host has no wallet yet")
            return nil
        }
        do {
            let address = try wallet.coreWallet().nextReceiveAddress(accountIndex: 0)
            return (address, wallet.walletId)
        } catch {
            Self.logger.warning(
                "📬 RECVADDR :: nextReceiveAddress failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
