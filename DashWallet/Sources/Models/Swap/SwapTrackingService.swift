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
/// - Polls `/track` every 30 s for active orders (a Buy order nobody paid, or one past its
///   window, less often — see `isDueForPoll`).
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
        /// abandoned; it is still looked at until it is let go, just rarely. Also the pace
        /// of any Buy order past its window: it stays until the answers that let it go
        /// arrive, and waiting for them must not cost a request every cycle.
        static let unpaidIdlePollIntervalSeconds: Int64 = 600
        /// The pace of an order still waiting for those answers `SwapOrder.fundedGraceSeconds`
        /// past its window — its wallet may be gone from the device, or its chain's lookup
        /// may never answer. It is not let go on silence, so it is asked rarely instead.
        static let dormantPollIntervalSeconds: Int64 = 6 * 3_600
    }

    /// What one look at an order's deposit address established.
    enum DepositLookup {
        /// The address holds the coin.
        case seen
        /// The lookup answered and the coin is not there.
        case absent
        /// No answer this time: not asked, or the request failed.
        case unknown
    }


    /// The wallet one poll cycle looked at. The cycle's wallet facts — synced or not, which
    /// transactions it holds — are this wallet's only, and orders of every wallet and network
    /// share the table.
    struct WalletView {
        var synced: Bool
        let walletId: String?
        let network: String?

        /// Whether a decision about `order` may rest on this wallet's transactions: it is
        /// synced, the order is not another wallet's, and it is still the active wallet
        /// (`activeWalletId` / `activeNetwork`, read when the decision is made — the
        /// requests in between are long enough for a switch).
        func vouches(for order: SwapOrder, activeWalletId: String?, activeNetwork: String?) -> Bool {
            synced && walletId == activeWalletId && network == activeNetwork
                && !order.isForeign(toWalletId: walletId, network: network)
        }
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

    /// When each paced Buy order was last polled (unix s), and whether the wallet was synced
    /// then; see `isDueForPoll`. In memory only — a relaunch simply polls again. An entry is
    /// dropped once its order has ended.
    private var lastPacedPoll: [String: (at: Int64, walletSynced: Bool)] = [:]
    private let pacedPollLock = NSLock()

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
            // The wallet has to be synced for its transactions to mean anything: before
            // that a payout may simply not be visible yet. And they only mean something for
            // its own orders.
            var wallet = await walletView()
            let due = active.filter { isDueForPoll($0, nowSeconds: nowSeconds, walletSynced: wallet.synced) }
            // One wallet read per cycle serves both the orders being polled and the
            // expired ones whose payout may still turn up. The latter are only looked for
            // at the idle pace — nothing about them changes fast — and at the dormant pace
            // once every one of them is past its late-payout window: a transaction dated
            // inside it can then only surface through a rescan or a settled ambiguity.
            let expiredFunded = !wallet.synced ? [] : orders.filter {
                $0.isBuy && !$0.isLegacyRecord && $0.status == .expired && $0.mayStillBePaidOut
                    && !$0.isForeign(toWalletId: wallet.walletId, network: wallet.network)
            }
            let anyInWindow = expiredFunded.contains {
                SwapBuyTransactionMatcher.latestPayoutDate(for: $0).map { TimeInterval(nowSeconds) <= $0 } ?? true
            }
            let lateInterval = anyInWindow
                ? Constants.unpaidIdlePollIntervalSeconds : Constants.dormantPollIntervalSeconds
            let lateCandidates = nowSeconds - lastLatePayoutCheck >= lateInterval ? expiredFunded : []
            if let payouts = walletPayouts(for: due + lateCandidates, among: orders, in: wallet) {
                if !lateCandidates.isEmpty { lastLatePayoutCheck = nowSeconds }
                await completeExpiredOrders(lateCandidates, paidOutBy: payouts)
                await pollOrders(due, payouts: payouts, wallet: wallet)
            } else {
                // The wallet could not be read: nothing about it is known this cycle.
                wallet.synced = false
                await pollOrders(due, payouts: [:], wallet: wallet)
            }

            try? await Task.sleep(nanoseconds: Constants.pollIntervalNs)
        }
    }

    private func pollOrders(_ due: [SwapOrder], payouts: [String: String], wallet: WalletView) async {
        await withTaskGroup(of: Void.self) { group in
            for order in due {
                let payoutTxHash = payouts[order.id]
                group.addTask {
                    await self.pollOrder(order, payoutTxHash: payoutTxHash, wallet: wallet)
                }
            }
        }
    }

    /// What one look at the provider (or the wallet) established about an order.
    private struct ProviderAnswer {
        var status: SwapOrderStatus?
        var firstOutHash: String?
        var actualAmount: String?
        /// Whether it proved the Buy order's deposit exists other than by finding it on
        /// chain: the payout is in the wallet, or the provider's own status says so.
        var depositProven = false
        /// Whether the order's state was established: the provider answered in words we
        /// understand, or the payout is in the wallet.
        var answered = false
    }

    private func pollOrder(_ order: SwapOrder, payoutTxHash: String?, wallet: WalletView) async {
        let nowSeconds = Int64(Date().timeIntervalSince1970)

        // Always ask the API FIRST. The 24 h age-out must never pre-empt a real status:
        // an order can complete while the app is closed (polling only runs in-foreground), so an
        // order older than 24 h can already be `completed`/`refunded`. Aging out before checking
        // would mislabel a genuinely-completed swap as failed.
        var answer = ProviderAnswer()
        do {
            answer = try await order.isBuy
                ? buyAnswer(for: order, payoutTxHash: payoutTxHash)
                : sellAnswer(for: order)
        } catch {
            // Transient network error — no authoritative status this cycle; may still age out below.
            DWLogger.log("SwapTrackingService: poll error for \(order.id): \(error)")
        }

        // "Not started" after the provider has already reported progress is the tracker not
        // finding the swap this time, not the swap going backwards. Writing it would turn an
        // order in progress into one whose deposit the provider "does not see" — and, with
        // the deposit on chain, into a false "Stuck". Treat it as no information about the
        // status (the provider did answer, which is what letting an old order go asks for).
        if answer.status == .notStarted, order.status.isProviderProgress {
            answer.status = nil
        }

        var finalStatus = answer.status ?? order.status

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

        // The wallet's word, for this order: taken now, after the requests above.
        let walletReady = wallet.vouches(
            for: order,
            activeWalletId: SwapOrder.currentOwnerWalletId,
            activeNetwork: SwapOrder.currentOwnerNetwork)

        // Decide the final status: prefer the API result; only fall back to the age-out when
        // the order is STILL non-terminal. Age-out lands on the neutral `.expired` (not
        // `.failed`) — funds may have arrived; we simply stopped tracking.
        // A deposit put on record in this very cycle — found on chain, or proven by the
        // provider — starts its grace now, so an order first heard about after a long gap
        // is not expired in the same breath.
        var agingOrder = order
        if order.depositSeenAt == nil, depositSeenNow || answer.depositProven { agingOrder.depositSeenAt = nowSeconds }
        if finalStatus.isActive, hasAgedOut(agingOrder, nowSeconds: nowSeconds, finalStatus: finalStatus) {
            let mayLetGo = !order.isBuy || Self.mayLetGo(
                fundsInFlight: Self.fundsInFlight(agingOrder, finalStatus: finalStatus),
                depositOnRecord: agingOrder.hasDepositOnRecord,
                sinceAgedOut: nowSeconds - agedOutAt(agingOrder, finalStatus: finalStatus),
                settleSeconds: order.settleSeconds,
                providerAnswered: answer.answered,
                walletReady: walletReady,
                watchesDeposit: watchesDeposit,
                lookup: lookup)
            if mayLetGo {
                DWLogger.log("SwapTrackingService: order \(order.id) unresolved past its tracking window → expired")
                finalStatus = .expired
            } else {
                DWLogger.log("SwapTrackingService: order \(order.id) is past its window, waiting for an answer")
            }
        }

        // The provider's status proving the deposit (or the payout arriving) is deposit
        // evidence too. Without recording it, an order the provider acknowledged first (the
        // usual case) would count as never paid once it ended, and its row would vanish with
        // the funds still at the provider. Only a proving status counts (`depositProven`):
        // "unknown" and unrecognised words say nothing about a deposit.
        let depositOnRecordNow = depositSeenNow
            || (order.isBuy && order.depositSeenAt == nil && answer.depositProven)

        // The provider has just answered that it sees no deposit, more than the stuck
        // threshold after the deposit appeared on chain: that answer is what makes the order
        // "Stuck". Stamped once — and only with the order's own wallet synced: before that
        // the payout of a swap that completed while the app was away may not be visible
        // yet, and the tracker having forgotten a finished swap would read as a denial.
        let providerDeniedDeposit = answer.status == .notStarted
            && walletReady
            && finalStatus == .notStarted
            && order.providerDeniedAt == nil
            && order.depositSeenAt.map { nowSeconds > $0 + order.stuckAfterSeconds } == true

        await record(
            finalStatus, for: order, answer: answer,
            depositOnRecordNow: depositOnRecordNow, providerDeniedDeposit: providerDeniedDeposit,
            nowSeconds: nowSeconds)
    }

    /// A Buy order's answer: the payout already in the wallet, otherwise the provider's status.
    private func buyAnswer(for order: SwapOrder, payoutTxHash: String?) async throws -> ProviderAnswer {
        if let payoutTxHash {
            return ProviderAnswer(
                status: .completed, firstOutHash: payoutTxHash, depositProven: true, answered: true)
        }
        // Buy orders use the deposit address as the tracking key until the Dash tx
        // lands in the wallet; the source-chain address must never be treated as a hash.
        let result = try await SwapKitSwapProvider().fetchSwapStatus(
            txid: order.id,
            depositAddress: order.depositAddress ?? order.id
        )
        var answer = Self.answer(from: result)
        guard answer.answered else { return answer }
        answer.depositProven = result.depositProven
        // `observedStatus` folds "failed", "unknown" and anything new into
        // refunded / pending. A Buy row states its status as fact, so read
        // the provider's own word for those:
        // - "failed" is a failure, not a refund — and it is the provider
        //   speaking about a transaction it saw, so the deposit is on record;
        // - "unknown" is what the tracker says before it has seen a deposit;
        // - a word we do not know tells us nothing: keep the status we have.
        switch result.providerStatus {
        case "failed":
            answer.status = .failed
            answer.depositProven = true
        case "unknown": answer.status = .notStarted
        case .some:
            answer.status = nil
            answer.answered = false
        case nil: break
        }
        return answer
    }

    private func sellAnswer(for order: SwapOrder) async throws -> ProviderAnswer {
        let result: SwapStatusResult
        switch trackingRoute(for: order) {
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
        return Self.answer(from: result)
    }

    /// Only treat the response as authoritative when the provider has observed the tx,
    /// or returned cleanly. When isObserved = true, a non-nil error is often a non-critical
    /// warning alongside valid status data (e.g. Maya returns both fields on completion).
    private static func answer(from result: SwapStatusResult) -> ProviderAnswer {
        guard !result.requestFailed, result.isObserved || result.error == nil else { return ProviderAnswer() }
        return ProviderAnswer(
            status: SwapOrderStatus.from(trackStatus: result.observedStatus, isObserved: result.isObserved),
            firstOutHash: result.outHashes?.first,
            actualAmount: result.actualToAmount,
            answered: true)
    }

    /// Writes what a poll established. Material-change-only — avoids tight-loop DB churn.
    private func record(
        _ finalStatus: SwapOrderStatus,
        for order: SwapOrder,
        answer: ProviderAnswer,
        depositOnRecordNow: Bool,
        providerDeniedDeposit: Bool,
        nowSeconds: Int64
    ) async {
        let newOutHash = answer.firstOutHash.flatMap { $0 != order.outboundTxHash ? $0 : nil }
        let newActualAmount = answer.actualAmount.flatMap { $0 != order.actualToAmount ? $0 : nil }
        let changed = finalStatus != order.status
            || depositOnRecordNow
            || providerDeniedDeposit
            || newOutHash != nil
            || newActualAmount != nil
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
        if depositOnRecordNow, updated.depositSeenAt == nil { updated.depositSeenAt = nowSeconds }
        if providerDeniedDeposit, updated.providerDeniedAt == nil { updated.providerDeniedAt = nowSeconds }
        if let newOutHash { updated.outboundTxHash = newOutHash }
        if let newActualAmount { updated.actualToAmount = newActualAmount }
        updated.lastChecked = nowSeconds
        if finalStatus.isTerminal {
            updated.finalisedAt = nowSeconds
            forgetPacing(for: order.id)
        }

        DWLogger.log("SwapTrackingService: order \(order.id) → \(finalStatus.rawValue)")
        await dao.update(dto: updated)
    }

    @MainActor
    private func walletView() -> WalletView {
        let walletId = SwapOrder.currentOwnerWalletId
        // The sync state carries no wallet identity, and during a switch it still describes
        // the wallet being left. It counts only while the wallet actually bound is the
        // selected one.
        // The same seed has the same wallet id on every network, so the running network is
        // compared as well.
        let host = SwiftDashSDKHost.shared
        let bound = host.wallet?.walletId.hexEncodedString()
        let isSelectedWallet = bound != nil && bound == walletId
            && host.runningNetwork != nil && host.runningNetwork == WalletEnvironment.network
        return WalletView(
            synced: SyncingActivityMonitor.shared.state == .syncDone && isSelectedWallet,
            walletId: walletId,
            network: SwapOrder.currentOwnerNetwork)
    }

    // MARK: - Private: Letting go

    /// Whether a Buy order past its window may be expired this cycle.
    ///
    /// Expiry is terminal and, for an order with no deposit on record, removes it from sight
    /// for good — so an order is let go only on answers, never on silence and never on
    /// elapsed time alone:
    /// - the provider has to have answered this cycle (`providerAnswered`);
    /// - the order's own wallet has to be synced (`walletReady`): until then its payout may
    ///   be in a wallet without being visible, and an expired unpaid order cannot claim it
    ///   afterwards;
    /// - an unpaid order not before `settleSeconds` past its deadline — a transfer sent in
    ///   the last minutes still has to show up, at the provider or on chain;
    /// - an order whose deposit address we watch also needs that lookup to have answered
    ///   "nothing there".
    /// An order with funds in flight has had its grace already, so the first two are all it
    /// needs.
    /// Until the answers come the order stays, polled at a slow pace (`isDueForPoll`). The
    /// one exception is an order whose deposit is on record: expiring it loses nothing — it
    /// keeps its row and is still matched to a late payout (`mayStillBePaidOut`) — so
    /// `SwapOrder.fundedGraceSeconds` past its window it goes without the answers, rather
    /// than read "Converting" for the life of the install.
    static func mayLetGo(
        fundsInFlight: Bool,
        depositOnRecord: Bool,
        sinceAgedOut: Int64,
        settleSeconds: Int64,
        providerAnswered: Bool,
        walletReady: Bool,
        watchesDeposit: Bool,
        lookup: DepositLookup
    ) -> Bool {
        if depositOnRecord, sinceAgedOut > SwapOrder.fundedGraceSeconds { return true }
        guard providerAnswered, walletReady else { return false }
        if fundsInFlight { return true }
        guard sinceAgedOut > settleSeconds else { return false }
        return !watchesDeposit || lookup == .absent
    }

    // MARK: - Private: Late payouts

    /// An expired Buy order with a deposit on record is no longer polled, but its payout can
    /// still arrive — the user handed the deposit to the provider, or the provider was just
    /// slow. When a transaction dated within `SwapOrder.latePayoutSeconds` of the expiry is
    /// in the wallet, the order is completed after all, so it does not stay "Not confirmed"
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
        guard Self.fundsInFlight(order, finalStatus: finalStatus) else { return windowEnd }
        return max(windowEnd, order.depositSeenAt ?? 0) + SwapOrder.fundedGraceSeconds
    }

    /// Whether the user's funds may be on their way: the deposit is on record, or the
    /// provider reports the order as anything but not started.
    private static func fundsInFlight(_ order: SwapOrder, finalStatus: SwapOrderStatus) -> Bool {
        order.depositSeenAt != nil || finalStatus != .notStarted
    }

    private func hasAgedOut(_ order: SwapOrder, nowSeconds: Int64, finalStatus: SwapOrderStatus) -> Bool {
        nowSeconds > agedOutAt(order, finalStatus: finalStatus)
    }

    // MARK: - Private: Poll pacing

    /// Whether the order is polled this cycle. Every active order is, each cycle — except
    /// two kinds of Buy order, which have the paces described at `Constants`:
    /// - one nobody has paid yet whose deposit address we watch: every
    ///   `unpaidPollIntervalSeconds` while young, every `unpaidIdlePollIntervalSeconds`
    ///   afterwards. The deposit-address lookup rides on the poll, so it has no pace of its
    ///   own;
    /// - one past its window, kept only until the answers that let it go arrive: every
    ///   `unpaidIdlePollIntervalSeconds`, and every `dormantPollIntervalSeconds` once it
    ///   has waited `SwapOrder.fundedGraceSeconds`.
    /// An unpaid order is back at `unpaidPollIntervalSeconds` for `settleSeconds` right
    /// after its deadline, when a last-minute transfer is still expected. An unpaid order
    /// we cannot watch has only the provider to learn from and keeps the full pace up to
    /// its deadline.
    ///
    /// An order past its window cannot be let go while the wallet is syncing, so a poll made
    /// then never waits longer than `unpaidIdlePollIntervalSeconds`, and does not use up the
    /// slot of the first poll with the wallet synced — the one that can decide.
    private func isDueForPoll(_ order: SwapOrder, nowSeconds: Int64, walletSynced: Bool) -> Bool {
        guard order.isBuy else { return true }
        let unpaid = order.status == .notStarted && order.depositSeenAt == nil
        let unpaidWatched = unpaid && order.canWatchDepositAddress
        let sinceAgedOut = nowSeconds - agedOutAt(order, finalStatus: order.status)
        let overdue = sinceAgedOut > 0
        guard unpaidWatched || overdue else { return true }

        let ageSeconds = nowSeconds - order.timestamp / 1000
        let settling = unpaid && overdue && sinceAgedOut <= order.settleSeconds
        let interval: Int64
        if settling || (unpaidWatched && ageSeconds <= Constants.unpaidEagerSeconds) {
            interval = Constants.unpaidPollIntervalSeconds
        } else if sinceAgedOut > SwapOrder.fundedGraceSeconds, walletSynced {
            interval = Constants.dormantPollIntervalSeconds
        } else {
            interval = Constants.unpaidIdlePollIntervalSeconds
        }

        pacedPollLock.lock()
        defer { pacedPollLock.unlock() }
        if let last = lastPacedPoll[order.id], nowSeconds - last.at < interval,
           !(overdue && walletSynced && !last.walletSynced) {
            return false
        }
        lastPacedPoll[order.id] = (nowSeconds, walletSynced)
        return true
    }

    /// Drops the pacing entry of an order that has ended.
    private func forgetPacing(for orderID: String) {
        pacedPollLock.lock()
        defer { pacedPollLock.unlock() }
        lastPacedPoll.removeValue(forKey: orderID)
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
            return Self.depositLookup(of: order.fromAsset, in: balances)
        } catch {
            DWLogger.log("SwapTrackingService: deposit lookup failed for \(order.id): \(error)")
            return .unknown
        }
    }

    /// What `balances` says about `asset` at the address: `.seen` for a positive amount,
    /// `.absent` for none, `.unknown` when the asset is listed with an amount that cannot be
    /// read — an answer we do not understand is not "nothing there". Identifiers are
    /// compared case-insensitively: ours are upper-cased, `/balance` keeps the contract's
    /// own case. Any positive amount counts, short of the order's or not: the question is
    /// whether the user's funds are at the address, and a partial deposit is funds at the
    /// address.
    ///
    /// A chain's own coin is not always named the same on both sides — `/balance` reports
    /// Toncoin as `TON.GRAM` where the coin list says `TON.TON`. So when `asset` is a native
    /// coin (no contract part) that is not listed under its own name, the chain's native
    /// balance counts for it, provided the answer has exactly one such entry to mean; with
    /// several, which one is ours is unknown.
    static func depositLookup(of asset: String, in balances: [SwapKitBalanceItem]) -> DepositLookup {
        func read(_ items: [SwapKitBalanceItem]) -> DepositLookup {
            let amounts = items.map { item in
                item.value.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
            }
            if amounts.contains(where: { ($0 ?? 0) > 0 }) { return .seen }
            return amounts.contains(where: { $0 == nil }) ? .unknown : .absent
        }
        let wanted = asset.uppercased()
        let exact = balances.filter { $0.identifier?.uppercased() == wanted }
        if !exact.isEmpty { return read(exact) }
        guard !wanted.contains("-"), let chain = SwapOrder.chain(ofAsset: wanted) else { return .absent }
        let natives = balances.filter { item in
            guard let identifier = item.identifier?.uppercased() else { return false }
            return !identifier.contains("-") && SwapOrder.chain(ofAsset: identifier) == chain
        }
        if natives.count > 1 { return .unknown }
        return read(natives)
    }

    /// True when `balances` carries a positive amount of `asset`; see `depositLookup`.
    static func holdsAsset(_ asset: String, in balances: [SwapKitBalanceItem]) -> Bool {
        depositLookup(of: asset, in: balances) == .seen
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
    /// them. Nil when `wallet`'s transactions could not be read.
    private func walletPayouts(for wanted: [SwapOrder], among orders: [SwapOrder], in wallet: WalletView) -> [String: String]? {
        let wantedBuys = wanted.filter(\.isBuy)
        guard !wantedBuys.isEmpty else { return [:] }
        guard let assignments = SwapBuyTransactionMatcher.walletAssignments(
            among: orders, walletId: wallet.walletId, network: wallet.network, strict: true) else { return nil }
        var result: [String: String] = [:]
        for order in wantedBuys {
            if let tx = assignments[order.id] { result[order.id] = tx.txHashHexString }
        }
        return result
    }
}
