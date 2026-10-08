//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// Shared buy-transaction matcher used by swap tracking and tx-history metadata.
///
/// We need to identify the buy's incoming DASH tx more precisely than "any tx to the same address":
/// the wallet's shared receive address can also catch unrelated receives, so we require
/// address + direction + time + approximate amount.
enum SwapBuyTransactionMatcher {
    private static let baseUnits = Decimal(100_000_000)
    private static let maximumRelativeAmountDifference = Decimal(string: "0.05", locale: Locale(identifier: "en_US_POSIX"))!

    /// How far a transaction may predate its order and still match.
    ///
    /// An unconfirmed tx reports the time the wallet first saw it, but once mined it reports the
    /// *block's* timestamp — which only has to beat the median of the last 11 blocks and so can sit
    /// minutes behind the wallet's clock. Comparing against the order time exactly meant a swap row
    /// lost its match the moment it confirmed and fell back to a plain "Received". The window is
    /// still far tighter than the address + amount checks, which do the real disambiguation.
    private static let timestampSlack: TimeInterval = 2 * 60 * 60

    /// The `firstSeen` fetch cutoff for matching `order`: order time minus
    /// `timestampSlack` (the matcher's own below-order-time allowance on the
    /// display date) minus a day for the firstSeen-vs-display-date skew
    /// (block timestamps trail the wall clock; restores re-stamp old rows).
    /// Callers hand this to `SwiftDashSDKWalletSource.fetchRecent(firstSeenSince:)`
    /// so the matcher's candidate pool is a ranged index scan, not the
    /// wallet's full history.
    static func fetchCutoff(for order: SwapOrder) -> Date {
        let orderTimestamp = TimeInterval(order.timestamp) / 1000.0
        return Date(timeIntervalSince1970: max(0, orderTimestamp - timestampSlack - 24 * 60 * 60))
    }

    /// Every transaction that could be `order`'s payout: received at its address, not before
    /// it (within `timestampSlack`), for about its expected amount.
    static func matchingTransactions(for order: SwapOrder, in transactions: [Transaction]) -> [Transaction] {
        guard order.isBuy else { return [] }
        let receiveAddress = order.toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !receiveAddress.isEmpty,
              let expectedDashAmount = expectedDashAmount(for: order), expectedDashAmount > 0
        else { return [] }
        let minimumTimestamp = TimeInterval(order.timestamp) / 1000.0
        return transactions.filter { tx in
            matches(
                tx,
                receiveAddress: receiveAddress,
                minimumTimestamp: minimumTimestamp,
                expectedDashAmount: expectedDashAmount
            )
        }
    }

    /// Which transaction pays out which Buy order: order id → transaction.
    ///
    /// Looked at one order at a time, two orders for the same amount to the same receive
    /// address both match the one payout that arrived. Here each transaction goes to at
    /// most one order, settled in this priority:
    /// 1. the order that already names it as its payout (`outboundTxHash`), provided the
    ///    transaction also fits the order;
    /// 2. orders the provider reports as completed, oldest first — it paid them out, and
    ///    payouts arrive in the order the swaps were made. A completed order only takes a
    ///    transaction from before it was finalised (plus `timestampSlack`): its payout
    ///    exists by then, so a later one is somebody else's;
    /// 3. orders still in flight. One that is alone on its transactions takes the earliest.
    ///    Orders that share any transaction are settled together and only when it is
    ///    unambiguous: they fit exactly the same transactions and there are at least as
    ///    many as orders — then they pair up in time order. Otherwise none of them is
    ///    assigned: which of two attempts a payout answers is the provider's to say (it
    ///    moves the right one to tier 2), and a wrong guess would finalise the other
    ///    attempt as paid. Whether an order's deposit is on record does not rank it here —
    ///    that record can lag behind a payout that is already in the wallet.
    /// Orders that can no longer be paid out (`mayStillBePaidOut`) claim nothing.
    static func payoutAssignments(
        among orders: [SwapOrder],
        in transactions: [Transaction],
        now: Date = Date()
    ) -> [String: Transaction] {
        guard !transactions.isEmpty else { return [:] }
        let claimants = orders
            .filter { $0.isBuy && $0.mayStillBePaidOut(now: now) }
            .sorted { $0.timestamp < $1.timestamp }
        guard !claimants.isEmpty else { return [:] }

        var free: [String: Transaction] = [:]
        for tx in transactions { free[tx.txHashHexString.lowercased()] = tx }
        var assigned: [String: Transaction] = [:]

        func take(_ txId: String, for order: SwapOrder) {
            guard let tx = free.removeValue(forKey: txId) else { return }
            assigned[order.id] = tx
        }
        /// Ids of the free transactions `order` fits, earliest first.
        func fitting(_ order: SwapOrder, before limit: TimeInterval? = nil) -> [String] {
            matchingTransactions(for: order, in: Array(free.values))
                .filter { limit == nil || $0.date.timeIntervalSince1970 <= limit! }
                .sorted { ($0.date, $0.txHashHexString) < ($1.date, $1.txHashHexString) }
                .map { $0.txHashHexString.lowercased() }
        }

        for claimant in claimants {
            guard let recorded = claimant.outboundTxHash?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  let tx = free[recorded],
                  !matchingTransactions(for: claimant, in: [tx]).isEmpty else { continue }
            take(recorded, for: claimant)
        }

        for claimant in claimants where claimant.status == .completed && assigned[claimant.id] == nil {
            let limit = claimant.finalisedAt > 0 ? TimeInterval(claimant.finalisedAt) + timestampSlack : nil
            if let txId = fitting(claimant, before: limit).first { take(txId, for: claimant) }
        }

        // Fitting sets are taken before anything in the tier is assigned, and orders that
        // share a transaction are settled as one group — so the outcome does not depend on
        // the order in which the tier is walked.
        let inFlight = claimants.filter { $0.status != .completed && assigned[$0.id] == nil }
        let fits = inFlight.map { (order: $0, txIds: fitting($0)) }.filter { !$0.txIds.isEmpty }
        var groups: [[(order: SwapOrder, txIds: [String])]] = []
        for entry in fits {
            let touching = groups.indices.filter { index in
                groups[index].contains { !Set($0.txIds).isDisjoint(with: entry.txIds) }
            }
            var merged = [entry]
            for index in touching.reversed() { merged += groups.remove(at: index) }
            groups.append(merged)
        }
        for group in groups {
            let first = group[0].txIds
            guard group.allSatisfy({ $0.txIds == first }), first.count >= group.count else { continue }
            for (entry, txId) in zip(group.sorted { $0.order.timestamp < $1.order.timestamp }, first) {
                take(txId, for: entry.order)
            }
        }
        return assigned
    }

    private static func matches(
        _ tx: Transaction,
        receiveAddress: String,
        minimumTimestamp: TimeInterval,
        expectedDashAmount: Decimal
    ) -> Bool {
        guard tx.direction == .received else { return false }
        guard tx.date.timeIntervalSince1970 >= minimumTimestamp - timestampSlack else { return false }
        guard tx.outputReceiveAddresses.contains(receiveAddress) else { return false }

        guard let receivedDashAmount = receivedDashAmount(for: tx) else { return false }
        return isWithinTolerance(
            expectedDashAmount: expectedDashAmount,
            receivedDashAmount: receivedDashAmount
        )
    }

    static func expectedDashAmount(for order: SwapOrder) -> Decimal? {
        guard let raw = order.expectedToAmount?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func receivedDashAmount(for tx: Transaction) -> Decimal? {
        guard tx.dashAmount != UInt64.max else { return nil }
        return Decimal(tx.dashAmount) / baseUnits
    }

    private static func isWithinTolerance(
        expectedDashAmount: Decimal,
        receivedDashAmount: Decimal
    ) -> Bool {
        let delta = receivedDashAmount - expectedDashAmount
        let absoluteDelta = delta < 0 ? -delta : delta
        let tolerance = expectedDashAmount * maximumRelativeAmountDifference
        return absoluteDelta <= tolerance
    }
}
