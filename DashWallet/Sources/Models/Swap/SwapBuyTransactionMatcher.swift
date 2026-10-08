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

    static func matchedTransaction(
        for order: SwapOrder,
        in transactions: [Transaction]
    ) -> Transaction? {
        guard order.direction == "buy" else { return nil }

        let receiveAddress = order.toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !receiveAddress.isEmpty else { return nil }

        guard let expectedDashAmount = expectedDashAmount(for: order), expectedDashAmount > 0 else {
            return nil
        }

        let candidates = matchingTransactions(for: order, in: transactions)

        return candidates.min(by: { lhs, rhs in
            let lhsTimestamp = lhs.date.timeIntervalSince1970
            let rhsTimestamp = rhs.date.timeIntervalSince1970
            if lhsTimestamp != rhsTimestamp {
                return lhsTimestamp < rhsTimestamp
            }

            let lhsDifference = amountDifference(
                tx: lhs,
                expectedDashAmount: expectedDashAmount
            )
            let rhsDifference = amountDifference(
                tx: rhs,
                expectedDashAmount: expectedDashAmount
            )

            let lhsAbsoluteDifference = absolute(lhsDifference)
            let rhsAbsoluteDifference = absolute(rhsDifference)
            if lhsAbsoluteDifference != rhsAbsoluteDifference {
                return lhsAbsoluteDifference < rhsAbsoluteDifference
            }

            return lhs.txHashHexString < rhs.txHashHexString
        })
    }

    /// Every transaction that could be `order`'s payout: received at its address, not before
    /// it (within `timestampSlack`), for about its expected amount.
    static func matchingTransactions(for order: SwapOrder, in transactions: [Transaction]) -> [Transaction] {
        guard order.direction == "buy" else { return [] }
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
    /// `matchedTransaction(for:in:)` looks at one order alone, so two orders for the same
    /// amount to the same receive address both match the one payout that arrived. Here each
    /// transaction goes to at most one order, settled tier by tier:
    /// 1. the order that already names it as its payout (`outboundTxHash`);
    /// 2. orders the provider reports as completed, oldest first — it paid them out, and
    ///    payouts arrive in the order the swaps were made;
    /// 3. orders still in flight with a deposit on record;
    /// 4. orders with no deposit on record — they only take what is left, so an order
    ///    nobody paid cannot take a funded order's payout.
    /// In tiers 3 and 4, orders that fit the same transactions are settled together: with
    /// at least as many payouts as orders they pair up in time order; with fewer, none is
    /// assigned — which of two in-flight attempts a single payout answers is the provider's
    /// to say, and a wrong guess would finalise the other attempt as paid. Orders that ended
    /// without a payout claim nothing.
    static func payoutAssignments(
        among orders: [SwapOrder],
        in transactions: [Transaction]
    ) -> [String: Transaction] {
        guard !transactions.isEmpty else { return [:] }
        let claimants = orders.filter { $0.direction == "buy" && $0.mayStillBePaidOut }
        guard !claimants.isEmpty else { return [:] }

        var free: [(id: String, tx: Transaction)] = transactions.map { ($0.txHashHexString.lowercased(), $0) }
        var assigned: [String: Transaction] = [:]

        func take(_ txId: String, for order: SwapOrder) {
            guard let index = free.firstIndex(where: { $0.id == txId }) else { return }
            assigned[order.id] = free[index].tx
            free.remove(at: index)
        }

        for claimant in claimants {
            guard let recorded = claimant.outboundTxHash?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !recorded.isEmpty else { continue }
            take(recorded, for: claimant)
        }

        let completed = claimants
            .filter { $0.status == .completed && assigned[$0.id] == nil }
            .sorted { $0.timestamp < $1.timestamp }
        for claimant in completed {
            guard let match = matchedTransaction(for: claimant, in: free.map(\.tx)) else { continue }
            take(match.txHashHexString.lowercased(), for: claimant)
        }

        let inFlight = claimants.filter { $0.status != .completed && assigned[$0.id] == nil }
        for tier in [inFlight.filter(\.hasDepositOnRecord), inFlight.filter { !$0.hasDepositOnRecord }] {
            // Orders grouped by the exact set of free transactions they fit.
            var groups: [[String]: [SwapOrder]] = [:]
            let freeTxs = free.map(\.tx)
            for claimant in tier {
                let fitting = matchingTransactions(for: claimant, in: freeTxs)
                    .sorted { $0.date < $1.date }
                    .map { $0.txHashHexString.lowercased() }
                guard !fitting.isEmpty else { continue }
                groups[fitting, default: []].append(claimant)
            }
            for (txIds, group) in groups where txIds.count >= group.count {
                for (order, txId) in zip(group.sorted { $0.timestamp < $1.timestamp }, txIds) {
                    take(txId, for: order)
                }
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

    private static func amountDifference(
        tx: Transaction,
        expectedDashAmount: Decimal
    ) -> Decimal {
        (receivedDashAmount(for: tx) ?? 0) - expectedDashAmount
    }

    private static func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
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
