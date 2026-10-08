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

// MARK: - ObjC bridge (called from AppDelegate.m at app launch)

@objc
class SwapTrackingServiceObjcWrapper: NSObject {
    @objc static func start() {
        SwapTrackingService.shared.start()
    }
}

// MARK: - SwapTrackingService

/// Background singleton that persists and polls all non-terminal swap orders.
///
/// Mirrors Android's `SwapTrackingService.kt`:
/// - `start()` at app launch resumes all non-terminal orders.
/// - Polls `/track` every 30 s for active orders (an unpaid Buy order less often — see
///   `isDueForPoll`).
/// - Tracks NEAR-routed sells by `depositAddress` and Maya-routed sells by tx hash.
/// - Material-change-only writes (unconditional writes turn the ticker into a tight loop).
/// - Ages out an order still unresolved after 24 h → `.expired`. A Buy order follows the
///   provider's deposit deadline instead — see `hasAgedOut(_:nowSeconds:finalStatus:)`.
final class SwapTrackingService {
    static let shared = SwapTrackingService()

    private enum Constants {
        static let pollIntervalNs: UInt64 = 30_000_000_000  // 30 s
        static let ageOutSeconds: Int64 = 86_400             // 24 h
        /// How often an unpaid Buy order is polled (provider status + deposit address) while
        /// a deposit is actually expected: when it is young, and for `settleSeconds` right
        /// after its deadline, when the answers decide whether it can be let go.
        static let unpaidPollIntervalSeconds: Int64 = 60
        /// How long an unpaid order counts as young.
        static let unpaidEagerSeconds: Int64 = 2 * 3_600
        /// The pace otherwise. An order nobody paid within two hours is most likely
        /// abandoned; it is still looked at until it is let go, just rarely.
        static let unpaidIdlePollIntervalSeconds: Int64 = 600
    }

    /// What one look at an order's deposit address established.
    private enum DepositLookup {
        /// The address holds the coin.
        case seen
        /// The lookup answered and the coin is not there.
        case absent
        /// No answer this time: not asked, or the request failed.
        case unknown
    }


    private enum TrackingRoute {
        case maya
        case near
        case swapKitHash
    }

    private let dao = SwapOrdersDAOImpl.shared
    private var trackingTask: Task<Void, Never>?

    /// Guards `visibleStatusOrderIDs`: written from the main thread
    /// (view lifecycle), read from `SwapNotificationProducer`'s
    /// background task.
    private let visibilityLock = NSLock()
    /// Counted PER ORDER, not a single tally: the producer processes every
    /// terminal order `observeAll` emits, so an app-wide count let an order
    /// the user is NOT watching be consumed silently while some other
    /// order's screen happened to be up — and dedup then kept it suppressed
    /// for good. Counts rather than a set for the original reason: during a
    /// stack transition the incoming and outgoing screens' lifecycle
    /// callbacks interleave, and removing on the outgoing screen's
    /// disappear would mark a still-visible replacement as gone.
    private var visibleStatusOrderIDs: [String: Int] = [:]

    /// When each unpaid Buy order was last polled (unix s); see `isDueForPoll`. In memory
    /// only — a relaunch simply polls again. An entry is dropped once its order has a
    /// deposit on record or has ended.
    private var lastUnpaidPoll: [String: Int64] = [:]
    private let unpaidPollLock = NSLock()

    /// When expired orders were last checked for a late payout (unix s). Read and written
    /// only by the poll loop itself, between cycles.
    private var lastLatePayoutCheck: Int64 = 0

    private init() {}

    // MARK: - Public

    /// Starts (or restarts) background polling for all non-terminal swap orders.
    /// Safe to call multiple times — cancels any previously running task.
    func start() {
        trackingTask?.cancel()
        trackingTask = Task { await pollLoop() }
        DWLogger.log("SwapTrackingService: started")
    }

    // MARK: - Public: live-status UI visibility

    /// True while a live status screen for THIS order
    /// (`SwapTransactionStatusHostingController`) is on screen.
    /// `SwapNotificationProducer` reads it to consume — instead of banner —
    /// a terminal order the user is already watching finish. Any other
    /// order still gets its banner.
    func isStatusUIVisible(forOrderID orderID: String) -> Bool {
        visibilityLock.lock()
        defer { visibilityLock.unlock() }
        return (visibleStatusOrderIDs[orderID] ?? 0) > 0
    }

    /// Called from a status screen's `viewWillAppear`; each call must be
    /// balanced by `statusScreenWillDisappear(orderID:)` with the same id —
    /// screens go through `StatusVisibilityClaim`, which guarantees it. A screen with no
    /// order id yet (nothing submitted) registers nothing, so the producer
    /// banners rather than silently consuming.
    func statusScreenWillAppear(orderID: String?) {
        guard let orderID, !orderID.isEmpty else { return }
        visibilityLock.lock()
        defer { visibilityLock.unlock() }
        visibleStatusOrderIDs[orderID, default: 0] += 1
    }

    /// Called from a status screen's `viewWillDisappear`. Clamped at
    /// zero so an unbalanced disappear can only under-report visibility
    /// for its own screen, never pre-cancel a later screen's appear.
    func statusScreenWillDisappear(orderID: String?) {
        guard let orderID, !orderID.isEmpty else { return }
        visibilityLock.lock()
        defer { visibilityLock.unlock() }
        guard let count = visibleStatusOrderIDs[orderID] else { return }
        if count <= 1 {
            visibleStatusOrderIDs.removeValue(forKey: orderID)
        } else {
            visibleStatusOrderIDs[orderID] = count - 1
        }
    }

    /// One status screen's registration, released exactly once.
    ///
    /// A screen must unregister the id it registered, not whatever its view
    /// model holds when it leaves: `submittedTxId` is cleared by a retry or a
    /// reset and replaced by `setSubmittedSwap` while the screen is up, so
    /// re-reading it on disappear left the original order's count stuck above
    /// zero — and this service lives for the whole process, so that order's
    /// terminal banner was consumed from then on. A screen torn down without
    /// `viewWillDisappear` (its stack replaced while it is not on top) leaked
    /// the same way; `deinit` releases that case.
    final class StatusVisibilityClaim {
        private let service: SwapTrackingService
        private var orderID: String?

        init(service: SwapTrackingService = .shared) {
            self.service = service
        }

        /// Registers `orderID`, first releasing any id this claim still
        /// holds, so a repeated appear cannot count one screen twice.
        func begin(orderID: String?) {
            end()
            guard let orderID, !orderID.isEmpty else { return }
            self.orderID = orderID
            service.statusScreenWillAppear(orderID: orderID)
        }

        /// Releases the registered id, if any. Idempotent.
        func end() {
            guard let orderID else { return }
            self.orderID = nil
            service.statusScreenWillDisappear(orderID: orderID)
        }

        deinit {
            end()
        }
    }

    // MARK: - Private: Poll loop

    private func pollLoop() async {
        while !Task.isCancelled {
            let orders = await dao.all()
            let active = orders.filter { $0.status.isActive }
            DWLogger.log("SwapTrackingService: polling \(active.count) active order(s)")

            // Which wallet transaction pays out which Buy order, worked out once per cycle
            // over all orders: a payout belongs to one order, so it cannot be decided order
            // by order.
            let nowSeconds = Int64(Date().timeIntervalSince1970)
            let due = active.filter { isDueForPoll($0, nowSeconds: nowSeconds) }
            // One wallet read per cycle serves both the orders being polled and the
            // expired ones whose payout may still turn up. The latter are only looked for
            // at the idle pace: nothing about them changes fast, and each look reads the
            // wallet on the main actor.
            let lateDue = nowSeconds - lastLatePayoutCheck >= Constants.unpaidIdlePollIntervalSeconds
            let lateCandidates = !lateDue ? [] : orders.filter {
                $0.isBuy && !$0.isLegacyRecord && $0.status == .expired && $0.mayStillBePaidOut(now: Date())
            }
            if lateDue { lastLatePayoutCheck = nowSeconds }
            let payouts = await walletPayouts(for: due + lateCandidates, among: orders)
            await completeExpiredOrders(lateCandidates, paidOutBy: payouts)

            await withTaskGroup(of: Void.self) { group in
                for order in due {
                    let payoutTxHash = payouts[order.id]
                    group.addTask { await self.pollOrder(order, payoutTxHash: payoutTxHash) }
                }
            }

            try? await Task.sleep(nanoseconds: Constants.pollIntervalNs)
        }
    }

    private func pollOrder(_ order: SwapOrder, payoutTxHash: String?) async {
        let nowSeconds = Int64(Date().timeIntervalSince1970)

        // Always ask the API FIRST. The 24 h age-out must never pre-empt a real status:
        // an order can complete while the app is closed (polling only runs in-foreground), so an
        // order older than 24 h can already be `completed`/`refunded`. Aging out before checking
        // would mislabel a genuinely-completed swap as failed.
        let route = trackingRoute(for: order)

        var apiStatus: SwapOrderStatus?
        var firstOutHash: String?
        var newActualAmount: String?
        // Whether this cycle proved the Buy order's deposit exists other than by finding it
        // on chain: the payout is in the wallet, or the provider's own status says so.
        var depositProven = false

        do {
            if order.isBuy {
                if let walletTxHash = payoutTxHash {
                    apiStatus = .completed
                    firstOutHash = walletTxHash
                    depositProven = true
                } else {
                    // Buy orders use the deposit address as the tracking key until the Dash tx
                    // lands in the wallet; the source-chain address must never be treated as a hash.
                    let depositAddress = order.depositAddress ?? order.id
                    let result = try await SwapKitSwapProvider().fetchSwapStatus(
                        txid: order.id,
                        depositAddress: depositAddress
                    )

                    // Only treat the response as authoritative when the provider has observed the tx,
                    // or returned cleanly. When isObserved = true, a non-nil error is often a non-critical
                    // warning alongside valid status data (e.g. Maya returns both fields on completion).
                    if !result.requestFailed, result.isObserved || result.error == nil {
                        apiStatus = SwapOrderStatus.from(
                            trackStatus: result.observedStatus,
                            isObserved: result.isObserved
                        )
                        firstOutHash = result.outHashes?.first
                        newActualAmount = result.actualToAmount
                        depositProven = result.depositProven
                        // `observedStatus` folds "failed", "unknown" and anything new into
                        // refunded / pending. A Buy row states its status as fact, so read
                        // the provider's own word for those:
                        // - "failed" is a failure, not a refund — and it is the provider
                        //   speaking about a transaction it saw, so the deposit is on record;
                        // - "unknown" is what the tracker says before it has seen a deposit;
                        // - a word we do not know tells us nothing: keep the status we have.
                        switch result.providerStatus {
                        case "failed":
                            apiStatus = .failed
                            depositProven = true
                        case "unknown": apiStatus = .notStarted
                        case .some: apiStatus = nil
                        case nil: break
                        }
                    }
                }
            } else {
                let result: SwapStatusResult
                switch route {
                case .maya:
                    result = try await MayaSwapProvider().fetchSwapStatus(
                        txid: order.id,
                        depositAddress: nil
                    )
                case .near:
                    // NEAR-Intents tracking uses the deposit address, not the Dash tx hash.
                    result = try await SwapKitSwapProvider().fetchSwapStatus(
                        txid: order.id,
                        depositAddress: order.depositAddress
                    )
                case .swapKitHash:
                    result = try await SwapKitSwapProvider().fetchSwapStatus(
                        txid: order.id,
                        depositAddress: nil
                    )
                }

                // Only treat the response as authoritative when the provider has observed the tx,
                // or returned cleanly. When isObserved = true, a non-nil error is often a non-critical
                // warning alongside valid status data (e.g. Maya returns both fields on completion).
                if !result.requestFailed, result.isObserved || result.error == nil {
                    apiStatus = SwapOrderStatus.from(
                        trackStatus: result.observedStatus,
                        isObserved: result.isObserved
                    )
                    firstOutHash = result.outHashes?.first
                    newActualAmount = result.actualToAmount
                }
            }
        } catch {
            // Transient network error — no authoritative status this cycle; may still age out below.
            DWLogger.log("SwapTrackingService: poll error for \(order.id): \(error)")
        }

        // "Not started" after the provider has already reported progress is the tracker not
        // finding the swap this time, not the swap going backwards. Writing it would turn an
        // order in progress into one whose deposit the provider "does not see" — and, with
        // the deposit on chain, into a false "Stuck". Treat it as no information.
        if apiStatus == .notStarted, order.status.isProviderProgress {
            apiStatus = nil
        }

        var finalStatus = apiStatus ?? order.status

        // The provider does not report this Buy order's deposit. Before believing that
        // nothing was sent, look at the source chain: the deposit address belongs to this
        // order alone, so the coin sitting on it is the deposit. That is what turns an
        // invisible order into a history row — and, if the provider keeps not seeing it,
        // into "Stuck".
        var lookup = DepositLookup.unknown
        let watchesDeposit = finalStatus == .notStarted && order.depositSeenAt == nil
            && order.canWatchDepositAddress
        if watchesDeposit {
            lookup = await lookUpDeposit(order)
            if lookup == .seen {
                DWLogger.log("SwapTrackingService: order \(order.id) deposit seen on the source chain")
            }
        }
        let depositSeenNow = lookup == .seen

        // Decide the final status: prefer the API result; only fall back to the age-out when
        // the order is STILL non-terminal. Age-out lands on the neutral `.expired` (not
        // `.failed`) — funds may have arrived; we simply stopped tracking.
        var agingOrder = order
        if depositSeenNow { agingOrder.depositSeenAt = nowSeconds }
        if finalStatus.isActive, hasAgedOut(agingOrder, nowSeconds: nowSeconds, finalStatus: finalStatus) {
            // Expiry is terminal and, for an order with no deposit on record, removes it from
            // sight for good — so a Buy order is let go only on answers, never on silence:
            // - never in a cycle where the provider was not reached (`apiStatus == nil`);
            // - an unpaid order not before `settleSeconds` past its deadline — a transfer
            //   sent in the last minutes still has to show up, at the provider or on chain;
            // - an order whose deposit address we watch also needs that lookup to have
            //   answered "nothing there";
            // - a day past the window the provider's answer alone is enough, so a lookup
            //   that never answers cannot keep the order alive;
            // - and silence has a limit too: `SwapOrder.fundedGraceSeconds` after the order
            //   aged out, it goes without an answer, so a provider that never answers
            //   again cannot keep it polled for the life of the install.
            let agedOutAt = agedOutAt(agingOrder, finalStatus: finalStatus)
            let sinceAgedOut = nowSeconds - agedOutAt
            let fundsInFlight = agingOrder.depositSeenAt != nil || finalStatus != .notStarted
            let settled: Bool
            if fundsInFlight {
                settled = true                                   // already had its grace
            } else if sinceAgedOut <= order.settleSeconds {
                settled = false                                  // a late transfer may still land
            } else {
                settled = !watchesDeposit || lookup == .absent || sinceAgedOut > Constants.ageOutSeconds
            }
            if order.isBuy, apiStatus == nil || !settled, sinceAgedOut <= SwapOrder.fundedGraceSeconds {
                DWLogger.log("SwapTrackingService: order \(order.id) is past its window, waiting for an answer")
            } else {
                DWLogger.log("SwapTrackingService: order \(order.id) unresolved past its tracking window → expired")
                finalStatus = .expired
            }
        }

        // The provider's status proving the deposit (or the payout arriving) is deposit
        // evidence too. Without recording it, an order the provider acknowledged first (the
        // usual case) would count as never paid once it ended, and its row would vanish with
        // the funds still at the provider. Only a proving status counts (`depositProven`,
        // set above): "unknown" and unrecognised words say nothing about a deposit.
        let providerReportedDeposit = order.isBuy && order.depositSeenAt == nil && depositProven

        // The provider has just answered that it sees no deposit, more than the stuck
        // threshold after the deposit appeared on chain: that answer is what makes the order
        // "Stuck". Stamped once.
        let providerDeniedDeposit = apiStatus == .notStarted
            && finalStatus == .notStarted
            && order.providerDeniedAt == nil
            && order.depositSeenAt.map { nowSeconds > $0 + order.stuckAfterSeconds } == true

        // Material-change-only writes — avoids tight-loop DB churn.
        let changed = finalStatus != order.status
            || depositSeenNow
            || providerReportedDeposit
            || providerDeniedDeposit
            || (firstOutHash != nil && firstOutHash != order.outboundTxHash)
            || (newActualAmount != nil && newActualAmount != order.actualToAmount)

        guard changed else { return }

        // Write onto the row as it is NOW, not the snapshot this poll started from: the
        // network round-trips above are long, and a whole-row write of an old snapshot would
        // erase whatever landed in between. A row deleted meanwhile stays deleted.
        guard var updated = await dao.get(byId: order.id) else { return }
        // …and a row that is no longer the one this poll decided about is left alone: its
        // status was moved on by another write, or its id (the deposit address) now belongs
        // to a newer order. The next cycle decides afresh.
        guard updated.status == order.status, updated.timestamp == order.timestamp else { return }
        updated.status = finalStatus
        if depositSeenNow || providerReportedDeposit, updated.depositSeenAt == nil {
            updated.depositSeenAt = nowSeconds
        }
        if providerDeniedDeposit, updated.providerDeniedAt == nil { updated.providerDeniedAt = nowSeconds }
        if let firstOutHash { updated.outboundTxHash = firstOutHash }
        if let newActualAmount { updated.actualToAmount = newActualAmount }
        updated.lastChecked = nowSeconds
        if finalStatus.isTerminal { updated.finalisedAt = nowSeconds }
        if finalStatus != .notStarted || updated.depositSeenAt != nil { forgetUnpaidPacing(for: order.id) }

        DWLogger.log("SwapTrackingService: order \(order.id) → \(finalStatus.rawValue)")
        await dao.update(dto: updated)
    }

    // MARK: - Private: Late payouts

    /// An expired Buy order with a deposit on record is no longer polled, but its payout can
    /// still arrive — the user handed the deposit to the provider, or the provider was just
    /// slow. When that transaction is in the wallet within `SwapOrder.latePayoutSeconds` of
    /// the expiry, the order is completed after all, so it does not stay "Not confirmed"
    /// beside its own payout.
    private func completeExpiredOrders(_ candidates: [SwapOrder], paidOutBy payouts: [String: String]) async {
        for order in candidates {
            guard let txHash = payouts[order.id],
                  var updated = await dao.get(byId: order.id), updated.status == .expired else { continue }
            let nowSeconds = Int64(Date().timeIntervalSince1970)
            updated.status = .completed
            updated.outboundTxHash = txHash
            updated.lastChecked = nowSeconds
            updated.finalisedAt = nowSeconds
            DWLogger.log("SwapTrackingService: order \(order.id) expired → completed, payout in the wallet")
            await dao.update(dto: updated)
        }
    }

    // MARK: - Private: Age-out

    /// When a still-active order outlives its tracking window (unix s).
    ///
    /// Sell orders keep the flat 24 h. A Buy order is tied to the provider's deposit deadline:
    /// - no deposit anywhere → the deadline (24 h after creation when none is known);
    /// - the deposit is on record, or the provider reports the order in progress → funds
    ///   are in flight, so `SwapOrder.fundedGraceSeconds` past the deadline (or past the moment the
    ///   deposit was put on record, if later). Dropping it at 24 h is how an order could go
    ///   dark two days before the provider's own cutoff.
    private func agedOutAt(_ order: SwapOrder, finalStatus: SwapOrderStatus) -> Int64 {
        let createdSeconds = order.timestamp / 1000
        guard order.isBuy else { return createdSeconds + Constants.ageOutSeconds }

        let windowEnd = order.depositDeadline ?? (createdSeconds + Constants.ageOutSeconds)
        let fundsInFlight = order.depositSeenAt != nil || finalStatus != .notStarted
        guard fundsInFlight else { return windowEnd }
        return max(windowEnd, order.depositSeenAt ?? 0) + SwapOrder.fundedGraceSeconds
    }

    private func hasAgedOut(_ order: SwapOrder, nowSeconds: Int64, finalStatus: SwapOrderStatus) -> Bool {
        nowSeconds > agedOutAt(order, finalStatus: finalStatus)
    }

    // MARK: - Private: Poll pacing

    /// Whether the order is polled this cycle. Every active order is, each cycle — except a
    /// Buy order nobody has paid yet whose deposit address we watch, which has the one pace
    /// described at `Constants`: every `unpaidPollIntervalSeconds` while young and again
    /// right after its deadline, every `unpaidIdlePollIntervalSeconds` otherwise. The
    /// deposit-address lookup rides on the poll, so it has no pace of its own. An unpaid
    /// order we cannot watch has only the provider to learn from and keeps the full pace.
    private func isDueForPoll(_ order: SwapOrder, nowSeconds: Int64) -> Bool {
        guard order.isBuy, order.status == .notStarted, order.depositSeenAt == nil,
              order.canWatchDepositAddress else { return true }

        let ageSeconds = nowSeconds - order.timestamp / 1000
        let sinceDeadline = order.depositDeadline.map { nowSeconds - $0 }
        let settling = sinceDeadline.map { $0 > 0 && $0 <= order.settleSeconds } ?? false
        let interval = ageSeconds <= Constants.unpaidEagerSeconds || settling
            ? Constants.unpaidPollIntervalSeconds
            : Constants.unpaidIdlePollIntervalSeconds

        unpaidPollLock.lock()
        defer { unpaidPollLock.unlock() }
        guard nowSeconds - (lastUnpaidPoll[order.id] ?? 0) >= interval else { return false }
        lastUnpaidPoll[order.id] = nowSeconds
        return true
    }

    /// Drops the pacing entry of an order that has a deposit on record or has ended: from
    /// then on it is polled every cycle, or not at all.
    private func forgetUnpaidPacing(for orderID: String) {
        unpaidPollLock.lock()
        defer { unpaidPollLock.unlock() }
        lastUnpaidPoll.removeValue(forKey: orderID)
    }

    // MARK: - Private: Source-chain deposit check

    /// Looks at the order's deposit address for the coin the user was asked to send. Runs
    /// whenever an unpaid, address-watched order is polled; `isDueForPoll` sets the pace.
    private func lookUpDeposit(_ order: SwapOrder) async -> DepositLookup {
        guard let address = order.depositAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              let chain = order.fromChain, !chain.isEmpty
        else { return .unknown }

        do {
            let balances = try await SwapKitAPIService.shared.balance(chain: chain, address: address)
            return Self.holdsAsset(order.fromAsset, in: balances) ? .seen : .absent
        } catch {
            DWLogger.log("SwapTrackingService: deposit lookup failed for \(order.id): \(error)")
            return .unknown
        }
    }

    /// True when `balances` carries a positive amount of `asset`. Identifiers are compared
    /// case-insensitively: ours are upper-cased, `/balance` keeps the contract's own case.
    /// Any positive amount counts, short of the order's or not: the question is whether the
    /// user's funds are at the address, and a partial deposit is funds at the address.
    static func holdsAsset(_ asset: String, in balances: [SwapKitBalanceItem]) -> Bool {
        let wanted = asset.uppercased()
        return balances.contains { item in
            guard item.identifier?.uppercased() == wanted,
                  let value = item.value.flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) })
            else { return false }
            return value > 0
        }
    }

    // MARK: - Private: Route resolution

    private func trackingRoute(for order: SwapOrder) -> TrackingRoute {
        let provider = order.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if provider.contains("maya") {
            return .maya
        }

        if provider.contains("near") {
            return .near
        }

        if order.service == "maya" {
            return .maya
        }

        return .swapKitHash
    }

    /// Order id → display hash of the wallet transaction that pays it out, for those of the
    /// `wanted` Buy orders that have one. No wallet read when there is no Buy order among
    /// them.
    @MainActor
    private func walletPayouts(for wanted: [SwapOrder], among orders: [SwapOrder]) -> [String: String] {
        let activeBuys = wanted.filter(\.isBuy)
        guard let cutoff = activeBuys.map(SwapBuyTransactionMatcher.fetchCutoff(for:)).min() else { return [:] }
        // Read the wallet's transactions from SwiftDashSDK; DashSync's allTransactions is frozen
        // (empty) post-migration, so a buy's incoming DASH would never match.
        // The matcher only considers rows around an order's own time, so range the fetch by
        // `firstSeen` (from the oldest active Buy order) instead of walking the wallet.
        let transactions = SwiftDashSDKWalletSource.fetchRecent(firstSeenSince: cutoff)?.transactions ?? []
        let assignments = SwapBuyTransactionMatcher.payoutAssignments(among: orders, in: transactions)
        var result: [String: String] = [:]
        for order in activeBuys {
            if let tx = assignments[order.id] { result[order.id] = tx.txHashHexString }
        }
        return result
    }
}
