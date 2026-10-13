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

/// What the matcher reads of a wallet transaction.
protocol SwapPayoutCandidate {
    var txHashHexString: String { get }
    var date: Date { get }
    /// When the wallet's store first held the transaction, if it is known.
    var firstStored: Date? { get }
    var direction: TransactionDirection { get }
    var outputReceiveAddresses: [String] { get }
    var dashAmount: UInt64 { get }
}

extension Transaction: SwapPayoutCandidate {}

/// Which wallet transaction pays out which Buy order, as far as that can be told.
struct PayoutResolution<T> {
    /// Order id → the transaction that pays it out.
    var assigned: [String: T] = [:]
    /// Ids of the orders that fit a transaction another order fits as well, and were given
    /// none for that reason.
    var contested: Set<String> = []
    /// The completed ones of `contested` for which the wallet holds at least as many
    /// transactions they fit as there are completed orders fitting those: each can have
    /// its payout there. With fewer, somebody's has not arrived.
    var contestedWithEnough: Set<String> = []
    /// The ones of `assigned` whose transaction no other order fits: nothing that turns up
    /// later can make it somebody else's.
    var unshared: Set<String> = []
    /// The transactions that were looked at and given to no order: nobody's, or held back
    /// while it is not settled whose they are.
    var unassigned: [T] = []
    /// Order id → ids of the transactions the order fits that arrived within its bound
    /// as the wallet tells it right now (`SwapBuyTransactionMatcher.arrival`), earliest
    /// first and of those that arrived together the nearest in amount first, for the orders that have one and do not name their
    /// payout. Not the transactions another order has by name. The tracker keeps them
    /// with the order (`SwapOrder.payoutCandidates`).
    var datedInTime: [String: [String]] = [:]
    /// Ids of the orders that were given the transaction their recorded hash names
    /// without that hash being established as their payout yet
    /// (`SwapOrder.namesItsPayout`), and that are alone in recording it.
    var takenByName: Set<String> = []
}

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

    /// When `tx` reached the wallet, for matching it to `order`: its date — the time the
    /// wallet first saw it until it is mined, its block's time from then on — or the time
    /// the store first held it (`SwapPayoutCandidate.firstStored`, to the second), when
    /// that is earlier. A row is only written for a transaction the wallet has seen, so
    /// the store's time is never before the transaction existed; it is later than the
    /// block's for one the wallet met already mined.
    /// The store's time is the device's clock at one moment, as the order's own time is.
    /// One from before the order was made cannot be its payout's and is not used: the
    /// date decides then, as it does where the order's time is checked (`matches`).
    static func arrival<T: SwapPayoutCandidate>(of tx: T, for order: SwapOrder) -> Date {
        guard let stored = tx.firstStored?.timeIntervalSince1970,
              stored >= TimeInterval(order.timestamp) / 1000.0 else { return tx.date }
        return min(tx.date, Date(timeIntervalSince1970: stored.rounded(.down)))
    }

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

    /// The `firstSeen` cutoff of the pool `payoutResolution(among:in:)` needs for `orders`:
    /// far enough back for every order that can claim a transaction, not only the ones the
    /// caller is asking about — an order matched by date whose own payout is missing from
    /// the pool takes somebody else's. Nil when no order can claim anything.
    static func fetchCutoff(forAssignmentsAmong orders: [SwapOrder]) -> Date? {
        orders.filter { $0.isBuy && $0.mayStillBePaidOut }.map(fetchCutoff(for:)).min()
    }

    /// The latest time a transaction may have reached the wallet and still be `order`'s
    /// payout; nil when there is no such bound. A transaction's date is the time the wallet first saw the transaction until
    /// it is mined, and its block's time from then on, so a match made on it alone could
    /// lapse on confirmation. The bound is therefore put on the transaction's arrival
    /// (`arrival(of:for:)`): one written to the wallet in time stays in time when it is
    /// mined later, also when nobody read the wallet in between. The store's own time is
    /// lost when the row is written anew — the wallet restored, the transaction dropped
    /// and seen again — and two more things keep a match then:
    /// - the tracker writes a matched payout's hash into the order while the bound still
    ///   holds (`settleLatePayouts`), when no other order fits that transaction, and asks
    ///   the provider for it otherwise: an order that names its payout is not bounded by
    ///   date;
    /// - a transaction the order was seen to fit while within the bound is kept with
    ///   the order (`SwapOrder.payoutCandidates`) and stays within it, whatever date it
    ///   carries later. That says the order may still take it, not that it is the order's.
    ///
    /// The bound, by the order's status:
    /// - A completed order's payout exists by the time it is finalised (plus
    ///   `timestampSlack`), so a later one is somebody else's.
    /// - An expired order with a deposit on record is owed a payout that arrives within
    ///   `SwapOrder.latePayoutSeconds` of the expiry. The bound is on the transaction, so a
    ///   payout that arrived in time is still found however late the wallet is looked at.
    /// - An expired order nobody paid is owed nothing new. It can still take a transaction
    ///   from about the time it was let go (`timestampSlack`) — one it would have taken a
    ///   moment earlier, had the wallet shown it.
    static func latestPayoutDate(for order: SwapOrder) -> TimeInterval? {
        guard order.finalisedAt > 0 else { return nil }
        switch order.status {
        case .completed: return TimeInterval(order.finalisedAt) + timestampSlack
        case .expired where !order.isLegacyRecord:
            return order.hasDepositOnRecord
                ? TimeInterval(order.finalisedAt + SwapOrder.latePayoutSeconds)
                : TimeInterval(order.finalisedAt) + timestampSlack
        default: return nil
        }
    }

    /// Which transaction of the wallet `walletId` on `network` pays out which of `orders`:
    /// the one reading of the wallet the tracker and the row labeller share, so they match
    /// the same orders against the same pool. Orders of another wallet or network are left
    /// out. Nil when that wallet's transactions could not be read — no wallet is bound, or
    /// the one that is bound is another (mid-switch); "nothing found" must not be
    /// concluded from that. `strict` also makes a failed store read nil instead of an
    /// empty pool: for the tracker, which lets orders go on a payout being absent. The
    /// labeller is not strict: on a failed read it errs towards showing an order's own
    /// row, which costs a row too many for a moment.
    static func walletAssignments(
        among orders: [SwapOrder],
        walletId: String?,
        network: String?,
        strict: Bool
    ) -> PayoutResolution<Transaction>? {
        let claimants = orders.filter { !$0.isForeign(toWalletId: walletId, network: network) }
        guard let cutoff = fetchCutoff(forAssignmentsAmong: claimants) else { return PayoutResolution() }
        // Read the wallet's transactions from SwiftDashSDK; DashSync's allTransactions is frozen
        // (empty) post-migration, so a buy's incoming DASH would never match.
        // The matcher only considers rows around an order's own time, so range the fetch by
        // `firstSeen` instead of walking the wallet.
        // The same seed has the same wallet id on every network, so the network the bound
        // wallet runs on is compared as well.
        let runningNetwork = SwiftDashSDKWalletSource.onMain { SwiftDashSDKHost.shared.runningNetwork }
        guard network == SwapOrder.currentOwnerNetwork,
              runningNetwork != nil, runningNetwork == WalletEnvironment.network,
              let snapshot = strict
                  ? SwiftDashSDKWalletSource.fetchRecentOrFail(firstSeenSince: cutoff)
                  : SwiftDashSDKWalletSource.fetchRecent(firstSeenSince: cutoff),
              snapshot.walletId.hexEncodedString() == walletId else { return nil }
        return payoutResolution(among: claimants, in: snapshot.transactions)
    }

    /// Every transaction that could be `order`'s payout: received at its address, not before
    /// it (within `timestampSlack`), for about its expected amount.
    static func matchingTransactions<T: SwapPayoutCandidate>(for order: SwapOrder, in transactions: [T]) -> [T] {
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
    /// most one order, and an order only takes one that arrived within its own bound
    /// (`latestPayoutDate`). Settled in this priority:
    /// 1. the order that already names it as its payout (`outboundTxHash`) — and such an
    ///    order takes no other transaction (`SwapOrder.namesItsPayout`) — provided the
    ///    transaction also fits the order;
    /// 2. orders the provider reports as completed — it paid them out;
    /// 3. orders that are still owed a payout: the ones in flight (an active status) and the
    ///    expired ones with a deposit on record. Expiry is us no longer asking, not the
    ///    provider's word, so an expired order's late payout is not a newer order's to take;
    /// 4. ended orders with no deposit to go by: the ones saved before deposits were
    ///    recorded, and the expired ones nobody paid — these only take what
    ///    the others left, so an old attempt cannot stand between a live order and its payout.
    ///    Within each of tiers 2–4: an order that is alone on its transactions takes the
    ///    earliest — of those that arrived together, the nearest in amount. Orders that share any transaction get none of them, however many there
    ///    are: nothing ties the sequence of payouts to the sequence the orders were made
    ///    in — a later order can be paid first — and a wrong guess would finalise the other
    ///    attempt as paid, or show one order's payout under another. That holds for
    ///    completed orders too: completion says an order was paid, not with which of two
    ///    alike transactions. And across tiers 2 and 3: an order alone in its tier that fits
    ///    several transactions takes none while an order of tier 3 fits one of them — the
    ///    tier says who is served first, not which transaction is whose. With a single
    ///    transaction there is nothing to mix up, and the earlier tier has it. An order
    ///    that fits a transaction held back this way takes no other one either.
    ///    Among orders in flight a deposit on record does not rank one above another —
    ///    that record can lag behind a payout that is already in the wallet.
    /// Orders that can no longer be paid out (`mayStillBePaidOut`) claim nothing.
    ///
    /// Orders left without a transaction because one they fit was held back are reported
    /// as `contested`: a payout that may be theirs is in the wallet, which is not the same
    /// as none having arrived. They stay so until the others stop claiming (refunded,
    /// failed) or move to an earlier tier; orders that have all ended keep
    /// sharing for good, and their payouts stay unlabelled. An order whose only fitting
    /// transaction went to an earlier tier is not contested: the provider says that
    /// order was paid, and the transaction is the one payout there is.
    ///
    /// `transactions` has to reach back to `fetchCutoff(forAssignmentsAmong:)` of the same
    /// `orders`.
    static func payoutResolution<T: SwapPayoutCandidate>(
        among orders: [SwapOrder],
        in transactions: [T]
    ) -> PayoutResolution<T> {
        guard !transactions.isEmpty else { return PayoutResolution() }
        let claimants = orders
            .filter { $0.isBuy && $0.mayStillBePaidOut }
            .sorted { $0.timestamp < $1.timestamp }
        guard !claimants.isEmpty else { return PayoutResolution() }

        var free: [String: T] = [:]
        for tx in transactions { free[tx.txHashHexString.lowercased()] = tx }
        var assigned: [String: T] = [:]
        var contested = Set<String>()
        /// Transactions held back from every order because it is not settled whose they are.
        var withheld: [T] = []
        func withhold(_ txIds: some Sequence<String>) {
            for txId in txIds {
                if let tx = free.removeValue(forKey: txId) { withheld.append(tx) }
            }
        }
        func fits(_ order: SwapOrder, anyOf pool: [T]) -> Bool {
            matchingTransactions(for: order, in: pool).contains { isInTime($0, for: order) }
        }

        func take(_ txId: String, for order: SwapOrder) {
            guard let tx = free.removeValue(forKey: txId) else { return }
            assigned[order.id] = tx
        }
        let remembered = Dictionary(
            claimants.map { ($0.id, $0.inTimePayoutIds) }, uniquingKeysWith: { first, _ in first })
        func isDatedInTime(_ tx: T, for order: SwapOrder) -> Bool {
            latestPayoutDate(for: order).map { arrival(of: tx, for: order).timeIntervalSince1970 <= $0 } ?? true
        }
        func isInTime(_ tx: T, for order: SwapOrder) -> Bool {
            isDatedInTime(tx, for: order)
                || remembered[order.id]?.contains(tx.txHashHexString.lowercased()) == true
        }
        /// Ids of `pool` — transactions `order` fits, so both amounts are known — the one
        /// that reached the wallet first for `order` first; of those with one time of
        /// arrival, the one nearest the amount the order expects, then the lowest hash.
        func earliestFirst(_ pool: [T], for order: SwapOrder) -> [String] {
            guard let expected = expectedDashAmount(for: order) else { return [] }
            return pool.compactMap { tx -> (arrival: Date, off: Decimal, id: String)? in
                guard let received = receivedDashAmount(for: tx) else { return nil }
                return (arrival(of: tx, for: order), amountDistance(received, from: expected), tx.txHashHexString)
            }
            .sorted { ($0.arrival, $0.off, $0.id) < ($1.arrival, $1.off, $1.id) }
            .map { $0.id.lowercased() }
        }
        /// Ids of the free transactions `order` fits, in `earliestFirst` order.
        func fitting(_ order: SwapOrder) -> [String] {
            earliestFirst(
                matchingTransactions(for: order, in: Array(free.values)).filter { isInTime($0, for: order) },
                for: order)
        }

        // The orders whose hash is established as their payout come first: an older
        // record can carry the same hash without it being its own.
        for claimant in claimants.filter(\.namesItsPayout) + claimants.filter({ !$0.namesItsPayout }) {
            guard let recorded = claimant.outboundTxHash?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  let tx = free[recorded],
                  !matchingTransactions(for: claimant, in: [tx]).isEmpty else { continue }
            take(recorded, for: claimant)
        }

        let takenByName = assigned.mapValues { $0.txHashHexString.lowercased() }
        // An order that names its payout takes that transaction or none: while it is not
        // in the pool, a look-alike is not it.
        let unnamed = claimants.filter { assigned[$0.id] == nil && !$0.namesItsPayout }
        let completed = unnamed.filter { $0.status == .completed }
        let open = unnamed.filter { $0.status != .completed }
        // An expired order nobody paid ranks with the legacy ones: it only takes what the
        // others left.
        let isOwed: (SwapOrder) -> Bool = { $0.status.isActive || (!$0.isLegacyRecord && $0.hasDepositOnRecord) }
        for var tier in [completed, open.filter(isOwed), open.filter { !isOwed($0) }] {
            // An order that fits a held-back transaction is part of that open question: it
            // takes nothing, and what else it fits is held back with it.
            while let index = tier.firstIndex(where: { fits($0, anyOf: withheld) }) {
                let order = tier.remove(at: index)
                contested.insert(order.id)
                withhold(fitting(order))
            }
            // Fitting sets are taken before anything in the tier is assigned, and orders
            // that share a transaction are settled as one group — so the outcome does not
            // depend on the order in which the tier is walked.
            let fits = tier.map { (order: $0, txIds: fitting($0)) }.filter { !$0.txIds.isEmpty }
            var groups: [[(order: SwapOrder, txIds: [String])]] = []
            for entry in fits {
                let touching = groups.indices.filter { index in
                    groups[index].contains { !Set($0.txIds).isDisjoint(with: entry.txIds) }
                }
                var merged = [entry]
                for index in touching.reversed() { merged += groups.remove(at: index) }
                groups.append(merged)
            }
            let tierIds = Set(tier.map(\.id))
            for group in groups {
                let txIds = Set(group.flatMap(\.txIds))
                if group.count == 1, let txId = group[0].txIds.first {
                    // Tier 4 does not count: its orders only take what the others left.
                    let sharedWithALaterTier = txIds.count > 1 && open.contains { other in
                        isOwed(other) && assigned[other.id] == nil && !tierIds.contains(other.id)
                            && !txIds.isDisjoint(with: fitting(other))
                    }
                    if !sharedWithALaterTier {
                        take(txId, for: group[0].order)
                        continue
                    }
                }
                // Unsettled between these orders: the transaction is one of theirs, so it
                // is not left for the next tier to take.
                withhold(txIds)
                contested.formUnion(group.map(\.order.id))
            }
        }
        // For a completed order: are there as many held-back transactions it fits as
        // completed orders that fit them? Only those count — the provider says they were
        // paid; an order still open beside them may never be.
        let paid = claimants.filter { $0.status == .completed && contested.contains($0.id) }
        var enough = Set<String>()
        for order in paid {
            let reachable = withheld.filter { fits(order, anyOf: [$0]) }
            let sharing = paid.filter { fits($0, anyOf: reachable) }
            if !reachable.isEmpty, reachable.count >= sharing.count { enough.insert(order.id) }
        }
        let unshared = assigned.filter { id, tx in
            !claimants.contains { $0.id != id && !$0.namesItsPayout && fits($0, anyOf: [tx]) }
        }
        var datedInTime: [String: [String]] = [:]
        let namedTxIds = Set(takenByName.values)
        for order in claimants where !order.namesItsPayout && latestPayoutDate(for: order) != nil {
            let othersByName = takenByName[order.id].map { namedTxIds.subtracting([$0]) } ?? namedTxIds
            let txIds = earliestFirst(
                matchingTransactions(for: order, in: transactions).filter { isDatedInTime($0, for: order) },
                for: order)
                .filter { !othersByName.contains($0) }
            if !txIds.isEmpty { datedInTime[order.id] = txIds }
        }
        return PayoutResolution(
            assigned: assigned, contested: contested, contestedWithEnough: enough, unshared: Set(unshared.keys),
            unassigned: Array(free.values) + withheld, datedInTime: datedInTime,
            takenByName: Set(claimants.filter { order in
                guard !order.namesItsPayout, let txId = takenByName[order.id] else { return false }
                return !claimants.contains { $0.id != order.id && $0.dashShapedOutHash == txId }
            }.map(\.id)))
    }

    private static func matches<T: SwapPayoutCandidate>(
        _ tx: T,
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

    private static func receivedDashAmount<T: SwapPayoutCandidate>(for tx: T) -> Decimal? {
        guard tx.dashAmount != UInt64.max else { return nil }
        return Decimal(tx.dashAmount) / baseUnits
    }

    private static func isWithinTolerance(
        expectedDashAmount: Decimal,
        receivedDashAmount: Decimal
    ) -> Bool {
        let tolerance = expectedDashAmount * maximumRelativeAmountDifference
        return amountDistance(receivedDashAmount, from: expectedDashAmount) <= tolerance
    }

    private static func amountDistance(_ received: Decimal, from expected: Decimal) -> Decimal {
        abs(received - expected)
    }
}
