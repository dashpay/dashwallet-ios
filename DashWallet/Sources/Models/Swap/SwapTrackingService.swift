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
        /// How many completed orders are asked for their payout's hash in one cycle
        /// (`recoverPayoutIdentities`).
        static let payoutIdentityAsksPerCycle = 2
        /// `UserDefaults` key: the completed Buy orders asked for their payout's hash
        /// without getting it — `payoutIdentityKey` → [times asked, not to be asked again
        /// before (unix s)] (`payoutIdentityAsk`).
        static let payoutIdentityAsksKey = "swapTracking.v3.payoutIdentityAsks"
        /// The wait after the first such try; doubled with each further one, up to
        /// `payoutIdentityLongestRetrySeconds`.
        static let payoutIdentityFirstRetrySeconds: Int64 = unpaidIdlePollIntervalSeconds
        static let payoutIdentityLongestRetrySeconds: Int64 = 30 * 24 * 3_600
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
        /// Ids of the orders a transaction in this wallet may be the payout of, without
        /// that being settled (`PayoutResolution.contested`).
        var contested: Set<String> = []
        /// Whether the store holds this wallet's transactions up to the height its sync
        /// reached (`historyIsPersisted`). Nil when the cycle did not ask.
        var historyPersisted: Bool?

        /// Whether a decision about `order` may rest on this wallet's transactions: it is
        /// synced and they are known to be in the store, not only scanned
        /// (`historyPersisted`), the order is not another wallet's, and it is still the
        /// active wallet (`activeWalletId` / `activeNetwork`, read when the decision is
        /// made — the requests in between are long enough for a switch). And the wallet has to be
        /// clear about the order: with a transaction in it that may be the order's payout,
        /// "no payout arrived" is not something it says.
        func vouches(for order: SwapOrder, activeWalletId: String?, activeNetwork: String?) -> Bool {
            synced && historyPersisted == true && walletId == activeWalletId && network == activeNetwork
                && !order.isForeign(toWalletId: walletId, network: network)
                && !contested.contains(order.id)
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
    /// then, or could not be relied on after all (`readFailed`: its read failed, or its
    /// store was behind the sync); see `isDueForPoll`. In memory only — a relaunch simply
    /// polls again. An entry is dropped once its order has ended.
    private var lastPacedPoll: [String: (at: Int64, walletSynced: Bool, readFailed: Bool)] = [:]
    private let pacedPollLock = NSLock()

    /// Since when (unix s) each watched order's deposit address has been found empty by
    /// every poll in a row. Guarded by `pacedPollLock`, in memory only.
    private var depositAddressEmptySince: [String: Int64] = [:]

    /// When ended orders were last checked for a late payout (unix s). Read and written
    /// only by the poll loop itself, between cycles.
    private var lastLatePayoutCheck: Int64 = 0

    /// Completed Buy orders found to name a transaction of the wallet as their payout:
    /// nothing is left to settle for them (`settleLatePayouts`). In memory only, and
    /// touched only by the poll loop. Keyed by `payoutIdentityKey`.
    private var ordersNamingTheirPayout: Set<String> = []

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
            let (view, scannedTip) = await walletView()
            var wallet = view
            let due = active.filter { isDueForPoll($0, nowSeconds: nowSeconds, walletSynced: wallet.synced) }
            // "Synced" is the network's word, and the transactions are read from the store.
            // A decision resting on their absence needs them written there as well — asked
            // only in a cycle with an order such a decision can come up for, after the tip
            // was read and before the transactions are.
            let awaitingTheWalletsWord = due.filter {
                $0.isBuy && !$0.isForeign(toWalletId: wallet.walletId, network: wallet.network)
                    && needsTheWalletsWord($0, nowSeconds: nowSeconds)
            }
            if wallet.synced, !awaitingTheWalletsWord.isEmpty {
                let watermark = SwiftDashSDKWalletSource.persistedSyncedHeightSnapshot()
                let persisted = Self.historyIsPersisted(
                    upTo: scannedTip, watermark: watermark, walletId: wallet.walletId)
                wallet.historyPersisted = persisted
                if !persisted {
                    // Retried at the idle pace, not after a dormant interval.
                    markWalletReadFailed(awaitingTheWalletsWord)
                    let written = watermark?.height.map(String.init) ?? "unavailable"
                    let ofThisWallet = watermark?.walletId.hexEncodedString() == wallet.walletId
                    DWLogger.log(
                        "SwapTrackingService: wallet store written to \(written) (this wallet's: \(ofThisWallet)),"
                            + " synced to \(scannedTip) — the wallet does not vouch for a missing payout this cycle")
                }
            }
            // One wallet read per cycle serves both the orders being polled and the ended
            // ones whose payout may still turn up: the expired ones that still claim, and
            // the completed ones still inside their window (`settleLatePayouts`). They are
            // only looked for at the idle pace — nothing about them changes fast — and at
            // the dormant pace once every one of them is past its window: a transaction
            // dated inside it can then only surface through a rescan or a settled
            // ambiguity. The window counts one dormant interval longer, so an order let go
            // a moment before its payout became readable is not left for hours.
            let inWindow: (SwapOrder) -> Bool = {
                SwapBuyTransactionMatcher.latestPayoutDate(for: $0).map {
                    TimeInterval(nowSeconds - Constants.dormantPollIntervalSeconds) <= $0
                } ?? true
            }
            let lateClaimants = !wallet.synced ? [] : orders.filter {
                guard $0.isBuy, !$0.isForeign(toWalletId: wallet.walletId, network: wallet.network)
                else { return false }
                switch $0.status {
                case .expired: return !$0.isLegacyRecord && $0.mayStillBePaidOut
                case .completed:
                    return $0.finalisedAt > 0 && inWindow($0)
                        && !ordersNamingTheirPayout.contains(Self.payoutIdentityKey(for: $0))
                default: return false
                }
            }
            let lateInterval = lateClaimants.contains(where: inWindow)
                ? Constants.unpaidIdlePollIntervalSeconds : Constants.dormantPollIntervalSeconds
            let lateCandidates = nowSeconds - lastLatePayoutCheck >= lateInterval ? lateClaimants : []
            if let resolution = walletPayouts(for: due + lateCandidates, among: orders, in: wallet) {
                let payouts = resolution.assigned
                wallet.contested = resolution.contested
                if !lateCandidates.isEmpty { lastLatePayoutCheck = nowSeconds }
                await settleLatePayouts(lateCandidates, paidOutBy: payouts, unshared: resolution.unshared)
                await recordWalletEvidence(
                    datedInTime: resolution.datedInTime, takenByName: resolution.takenByName, among: orders)
                await pollOrders(due, payouts: payouts, wallet: wallet)
            } else {
                // The wallet could not be read: nothing about it is known this cycle.
                wallet.synced = false
                markWalletReadFailed(due)
                await pollOrders(due, payouts: [:], wallet: wallet)
            }
            // Read again: this cycle may have named some of them.
            await recoverPayoutIdentities(among: await dao.all())

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
        let emptySince = watchesDeposit ? noteDepositAddress(of: order, empty: lookup == .absent, at: nowSeconds) : nil

        // The wallet's word, for this order. Its transactions are the cycle's read, from
        // before the requests above; that it is still the active wallet is checked now.
        var walletReady = wallet.vouches(
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
            let sinceAgedOut = nowSeconds - agedOutAt(agingOrder, finalStatus: finalStatus)
            var mayLetGo = !order.isBuy || Self.mayLetGo(
                fundsInFlight: Self.fundsInFlight(agingOrder, finalStatus: finalStatus),
                depositOnRecord: agingOrder.hasDepositOnRecord,
                sinceAgedOut: sinceAgedOut,
                settleSeconds: order.settleSeconds,
                providerAnswered: answer.answered,
                walletReady: walletReady,
                watchesDeposit: watchesDeposit,
                lookup: lookup)
            // The wallet's transactions were read before the requests above, and a payout
            // can have been written while they ran. An order let go on that read is asked
            // about again, now; one that goes on its deposit and grace alone keeps its
            // claim to a late payout and needs no such look. A wallet that no longer says
            // "no payout" does not say it for the "Stuck" stamp below either.
            let goesOnGraceAlone = agingOrder.hasDepositOnRecord && sinceAgedOut > SwapOrder.fundedGraceSeconds
            if order.isBuy, mayLetGo, !goesOnGraceAlone {
                // An order that goes on its deposit address being empty needs that from two
                // polls apart: one "nothing there" may be an indexer behind its chain.
                if watchesDeposit, emptySince.map({ nowSeconds - $0 >= Constants.unpaidPollIntervalSeconds }) != true {
                    mayLetGo = false
                    markWalletReadFailed([order])
                    DWLogger.log(
                        "SwapTrackingService: order \(order.id) — deposit address seen empty once,"
                            + " asked again before it is let go")
                }
                if mayLetGo {
                    walletReady = await walletStillHoldsNoPayout(for: order, asReadBy: wallet)
                    mayLetGo = walletReady
                }
            }
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
            && Self.isPastStuckThreshold(order, nowSeconds: nowSeconds)

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
        // A Buy order's out hash is its Dash payout or nothing: the other hashes of the
        // answer are the deposit's, on another chain.
        var answer = Self.answer(from: result, outHash: result.dashPayoutHash)
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
        return Self.answer(from: result, outHash: result.outHashes?.first)
    }

    /// Only treat the response as authoritative when the provider has observed the tx,
    /// or returned cleanly. When isObserved = true, a non-nil error is often a non-critical
    /// warning alongside valid status data (e.g. Maya returns both fields on completion).
    private static func answer(from result: SwapStatusResult, outHash: String?) -> ProviderAnswer {
        guard !result.requestFailed, result.isObserved || result.error == nil else { return ProviderAnswer() }
        return ProviderAnswer(
            status: SwapOrderStatus.from(trackStatus: result.observedStatus, isObserved: result.isObserved),
            firstOutHash: outHash,
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
        if let newOutHash {
            updated.outboundTxHash = newOutHash
        }
        // For a Buy order the answer's hash is the Dash payout: the provider's Dash leg, or
        // the wallet's transaction — also when an older record held that hash already.
        if updated.isBuy, updated.payoutNamedAt == nil,
           let named = SwapOrder.dashTxId(from: answer.firstOutHash), named == updated.dashShapedOutHash {
            updated.payoutNamedAt = nowSeconds
        }
        if let newActualAmount { updated.actualToAmount = newActualAmount }
        updated.lastChecked = nowSeconds
        if finalStatus.isTerminal {
            updated.finalisedAt = nowSeconds
            forgetPacing(for: order.id)
        }

        DWLogger.log("SwapTrackingService: order \(order.id) → \(finalStatus.rawValue)")
        await dao.update(dto: updated)
    }

    /// A second look at the wallet for an order about to be let go, with everything the
    /// cycle's first look needed read afresh: the same wallet still synced and bound, its
    /// store written up to the tip, and the payouts worked out again over all orders.
    /// An order it keeps is polled again at the idle pace.
    private func walletStillHoldsNoPayout(for order: SwapOrder, asReadBy first: WalletView) async -> Bool {
        let (wallet, scannedTip) = await walletView()
        var refusal: String?
        if !wallet.synced || wallet.walletId != first.walletId || wallet.network != first.network {
            refusal = "the wallet is no longer the synced one the cycle read"
        } else if !Self.historyIsPersisted(
            upTo: scannedTip,
            watermark: SwiftDashSDKWalletSource.persistedSyncedHeightSnapshot(),
            walletId: wallet.walletId) {
            refusal = "the wallet store is behind the sync"
        } else {
            let resolution = walletPayouts(for: [order], among: await dao.all(), in: wallet)
            if resolution == nil {
                refusal = "the wallet could not be read"
            } else if !Self.holdsNoPayout(for: order, in: resolution) {
                refusal = "a transaction that may be its payout is in the wallet now"
            }
        }
        guard let refusal else { return true }
        markWalletReadFailed([order])
        DWLogger.log("SwapTrackingService: order \(order.id) not let go on a second look — \(refusal)")
        return false
    }

    /// Whether a wallet read says it holds no payout for `order`: the read succeeded, gave
    /// the order no transaction, and left none that may be its payout unsettled.
    static func holdsNoPayout(for order: SwapOrder, in resolution: PayoutResolution<String>?) -> Bool {
        guard let resolution else { return false }
        return resolution.assigned[order.id] == nil && !resolution.contested.contains(order.id)
    }

    /// Whether the store holds the wallet's transactions up to the height the sync reached.
    ///
    /// The sync state turns "done" on the network phases alone, while the transactions of
    /// the blocks it scanned may still be on their way into the store — after a long gap
    /// or a rescan the two can be far apart. The persisted sync height is the SDK's durable
    /// claim that everything up to it has been written: it is stored in the same round as
    /// the round's transactions, and held back for a wallet whose write failed. Until it
    /// reaches the scanned tip, "no payout in the wallet" may only mean "not written yet".
    /// A watermark that cannot be read, or belongs to another wallet, proves nothing.
    ///
    /// Only the decisions that rest on a missing payout need this (`WalletView.vouches`):
    /// letting an unpaid order go, and calling one "Stuck". A wallet whose watermark stays
    /// behind — the SDK stops advancing it for the session after a failed write — keeps
    /// such orders as they are; payouts that are in the store are matched all the same.
    static func historyIsPersisted(
        upTo scannedTip: UInt32,
        watermark: (walletId: Data, height: UInt32?)?,
        walletId: String?
    ) -> Bool {
        guard scannedTip > 0, let watermark, let height = watermark.height else { return false }
        return watermark.walletId.hexEncodedString() == walletId && height >= scannedTip
    }

    /// The cycle's wallet, and the height its sync has scanned to.
    @MainActor
    private func walletView() -> (view: WalletView, scannedTip: UInt32) {
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
        let monitor = SyncingActivityMonitor.shared
        let view = WalletView(
            synced: monitor.state == .syncDone && isSelectedWallet,
            walletId: walletId,
            network: SwapOrder.currentOwnerNetwork)
        return (view, monitor.snapshot.lastTerminalBlockHeight)
    }

    // MARK: - Private: Letting go

    /// Whether a Buy order past its window may be expired this cycle.
    ///
    /// Expiry is terminal and, for an order with no deposit on record, removes it from sight
    /// for good — so an order is let go only on answers, never on silence and never on
    /// elapsed time alone:
    /// - the provider has to have answered this cycle (`providerAnswered`);
    /// - the order's own wallet has to be synced and its transactions written to the store
    ///   (`walletReady`): until then its payout may be in a wallet without being visible,
    ///   and an expired unpaid order can only claim it afterwards if it existed by then;
    /// - an unpaid order not before `settleSeconds` past its deadline — a transfer sent in
    ///   the last minutes still has to show up, at the provider or on chain;
    /// - an order whose deposit address we watch also needs that lookup to have answered
    ///   "nothing there".
    /// An order with funds in flight has had its grace already, so the first two are all it
    /// needs.
    /// The wallet's word here is the cycle's read; the caller asks the wallet once more
    /// before acting on a yes (`walletStillHoldsNoPayout`).
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

    /// An ended Buy order is no longer polled, but its payout can still turn up in the wallet.
    /// - An expired order with a deposit on record: the user handed the deposit to the
    ///   provider, or the provider was just slow. With a transaction that arrived within
    ///   `SwapOrder.latePayoutSeconds` of the expiry in the wallet, the order is completed
    ///   after all, so it does not stay "Not confirmed" beside its own payout.
    /// - An expired order nobody paid, let go a moment before its payout became readable:
    ///   completed the same way, and the payout is the proof of its deposit.
    /// - A completed order that names no payout (the provider's answer carried no Dash leg):
    ///   the hash of the transaction it is matched to is written into it, so the match no
    ///   longer depends on the transaction's date, which changes when it is mined. Only for
    ///   a transaction no other order fits (`unshared`) — a match that another order's
    ///   payout turning up could still change is not made permanent. A hash that names
    ///   the order's payout (`SwapOrder.namesItsPayout`) is left alone: it may be the
    ///   provider's, for a transaction still to arrive. Any other — of another shape, or
    ///   an older record's, which may be from the deposit's chain — is replaced.
    private func settleLatePayouts(
        _ candidates: [SwapOrder],
        paidOutBy payouts: [String: String],
        unshared: Set<String>
    ) async {
        for order in candidates {
            // The row as it is now, and only while it is still the order the wallet was
            // read for: its id, the deposit address, can pass to a newer order.
            guard let txHash = payouts[order.id], var updated = await dao.get(byId: order.id),
                  updated.timestamp == order.timestamp else { continue }
            let nowSeconds = Int64(Date().timeIntervalSince1970)
            let outcome: String
            switch updated.status {
            case .expired:
                updated.status = .completed
                updated.outboundTxHash = txHash
                updated.payoutNamedAt = nowSeconds
                if updated.depositSeenAt == nil { updated.depositSeenAt = nowSeconds }
                updated.lastChecked = nowSeconds
                updated.finalisedAt = nowSeconds
                outcome = "expired → completed, payout in the wallet"
            case .completed where updated.namesItsPayout && updated.dashShapedOutHash == txHash.lowercased():
                ordersNamingTheirPayout.insert(Self.payoutIdentityKey(for: order))
                continue
            case .completed where unshared.contains(order.id) && !updated.namesItsPayout:
                updated.outboundTxHash = txHash
                updated.payoutNamedAt = nowSeconds
                outcome = "completed, payout found in the wallet"
            default:
                continue
            }
            // Not `update`, which swallows a failed write: the order counts as settled
            // only once that is stored, and is looked at again otherwise.
            do {
                try await dao.save(dto: updated)
                ordersNamingTheirPayout.insert(Self.payoutIdentityKey(for: order))
                DWLogger.log("SwapTrackingService: order \(order.id) \(outcome)")
            } catch {
                DWLogger.log("SwapTrackingService: order \(order.id) late payout not saved: \(error)")
            }
        }
    }

    /// Keeps with the orders what a reading of the wallet showed about their payouts:
    /// - the transactions an order fits while they are within its bound
    ///   (`SwapOrder.payoutCandidates`): the date moves when a transaction is mined, and
    ///   what was the order's to take before stays so after;
    /// - that an older record's hash is the wallet transaction it was given by name: the
    ///   Dash payout after all, not a hash from the deposit's chain (`payoutNamedAt`).
    /// Called by the poll loop and by the row labeller, which reads the wallet whenever
    /// its transactions change — a transaction can be mined between two polls. Each row is
    /// changed as it is at that moment (`SwapOrdersDAOImpl.amend`), and only while it is
    /// still the order the wallet was read for: its id, the deposit address, can pass to
    /// a newer order.
    func recordWalletEvidence(
        datedInTime: [String: [String]],
        takenByName: Set<String>,
        among orders: [SwapOrder]
    ) async {
        let nowSeconds = Int64(Date().timeIntervalSince1970)
        for order in orders where order.isBuy && !order.namesItsPayout {
            let txIds = datedInTime[order.id] ?? []
            let namedHash = takenByName.contains(order.id) ? order.dashShapedOutHash : nil
            // Nothing to add for most orders at most readings: told from the snapshot,
            // before the row is read again.
            guard namedHash != nil || order.payoutCandidates(adding: txIds) != nil else { continue }
            let timestamp = order.timestamp
            let status = order.status
            do {
                try await dao.amend(id: order.id) { row in
                    guard row.timestamp == timestamp, row.status == status, row.isBuy, !row.namesItsPayout
                    else { return false }
                    if let namedHash, row.dashShapedOutHash == namedHash {
                        row.payoutNamedAt = nowSeconds
                        return true
                    }
                    guard let candidates = row.payoutCandidates(adding: txIds) else { return false }
                    row.payoutCandidates = candidates
                    return true
                }
            } catch {
                DWLogger.log("SwapTrackingService: order \(order.id) wallet evidence not saved: \(error)")
            }
        }
    }

    // MARK: - Private: Payout identity

    /// What identifies an order in the persisted record of the ones already asked: a Buy
    /// order's id is its deposit address, which a later order can have again.
    static func payoutIdentityKey(for order: SwapOrder) -> String { "\(order.id)|\(order.timestamp)" }

    /// The completed Buy orders to ask now which Dash transaction paid them out: those
    /// that do not name it for sure (`SwapOrder.namesItsPayout`) — saved before the
    /// provider's Dash leg was read, or completed by an answer without one. Not within
    /// `unpaidIdlePollIntervalSeconds` of completing: the answer that completed the order
    /// had no such leg, and the provider may add it shortly after. And not before the
    /// time set for an order by its last try (`notBefore`, by `payoutIdentityKey`). The
    /// ones that have waited longest come first, those never asked ahead of all.
    static func ordersToAskForPayoutIdentity(
        among orders: [SwapOrder],
        notBefore: [String: Int64],
        nowSeconds: Int64
    ) -> [SwapOrder] {
        orders.filter {
            $0.isBuy && $0.status == .completed && !$0.namesItsPayout
                && nowSeconds - $0.finalisedAt >= Constants.unpaidIdlePollIntervalSeconds
                && nowSeconds >= notBefore[payoutIdentityKey(for: $0), default: 0]
        }.sorted {
            notBefore[payoutIdentityKey(for: $0), default: 0] < notBefore[payoutIdentityKey(for: $1), default: 0]
        }
    }

    /// How long an order is left alone after it was asked for the `timesAsked`-th time
    /// without its payout's hash coming of it. No such try is the last — the provider can
    /// name the payout later, however old the order — so the order is asked again, ever
    /// more rarely: ten minutes, twenty, forty… up to thirty days.
    static func payoutIdentityRetryDelay(timesAsked: Int) -> Int64 {
        let doublings = min(max(timesAsked, 1) - 1, 16)
        return min(Constants.payoutIdentityLongestRetrySeconds, Constants.payoutIdentityFirstRetrySeconds << doublings)
    }

    /// The record of one more try that brought no hash: [times asked, not to be asked
    /// again before (unix s)], given the record so far. A request the provider did not
    /// answer (`answered` false) is no word of its: it is tried again after the first
    /// wait, and does not make the waits longer.
    static func payoutIdentityAsk(after previous: [Int]?, answered: Bool, nowSeconds: Int64) -> [Int] {
        let timesBefore = previous.flatMap { payoutIdentityTimesAsked(in: $0) } ?? 0
        let timesAsked = answered ? timesBefore + 1 : timesBefore
        return [timesAsked, Int(nowSeconds + payoutIdentityRetryDelay(timesAsked: timesAsked))]
    }

    /// How many times `ask` says the order was asked; nil when it is no such record.
    private static func payoutIdentityTimesAsked(in ask: [Int]) -> Int? {
        guard ask.count == 2, (0...1_000_000).contains(ask[0]) else { return nil }
        return ask[0]
    }

    /// When the order with the record `ask` may be asked again (unix s): at once when
    /// the record is none, or its time is further off than the longest wait — written
    /// while the device's clock ran ahead, it must not silence the order for good.
    static func payoutIdentityNotBefore(of ask: [Int], nowSeconds: Int64) -> Int64 {
        guard payoutIdentityTimesAsked(in: ask) != nil,
              Int64(ask[1]) <= nowSeconds + Constants.payoutIdentityLongestRetrySeconds else { return 0 }
        return Int64(ask[1])
    }

    /// A completed order that does not name its payout is matched to a wallet transaction
    /// by address, amount and date — and the date moves when the transaction is mined.
    /// The provider knows the payout: each such order is asked, a few per cycle, and the
    /// Dash hash it answers with is written into the order, which then has that
    /// transaction by name. A try that does not end with the hash stored — an answer
    /// without one, a failed request, a failed write — is recorded, and the order is
    /// asked again later (`payoutIdentityAsk`).
    private func recoverPayoutIdentities(among orders: [SwapOrder]) async {
        // No orders may be a failed read of them: the record is not pruned on that.
        guard !orders.isEmpty else { return }
        let defaults = UserDefaults.standard
        let stored = defaults.dictionary(forKey: Constants.payoutIdentityAsksKey) ?? [:]
        // Entries of orders that are gone, or named since, are dropped with the next write.
        let unnamed = Set(orders.filter { !$0.namesItsPayout }.map(Self.payoutIdentityKey(for:)))
        var asks = stored.compactMapValues { $0 as? [Int] }.filter { unnamed.contains($0.key) }
        let startSeconds = Int64(Date().timeIntervalSince1970)
        let toAsk = Self.ordersToAskForPayoutIdentity(
            among: orders,
            notBefore: asks.mapValues { Self.payoutIdentityNotBefore(of: $0, nowSeconds: startSeconds) },
            nowSeconds: startSeconds)
            .prefix(Constants.payoutIdentityAsksPerCycle)
        for order in toAsk {
            let key = Self.payoutIdentityKey(for: order)
            let answer = try? await buyAnswer(for: order, payoutTxHash: nil)
            let nowSeconds = Int64(Date().timeIntervalSince1970)
            // Recorded first: whatever comes of this try short of the hash being stored,
            // the order waits before the next one.
            asks[key] = Self.payoutIdentityAsk(
                after: asks[key], answered: answer?.answered == true, nowSeconds: nowSeconds)
            guard let answer, answer.answered, answer.status == .completed,
                  let hash = SwapOrder.dashTxId(from: answer.firstOutHash) else { continue }
            let timestamp = order.timestamp
            do {
                // The row as it is now: it may have been named, or replaced, since the
                // cycle began. Throws when the write fails: the order is done with only
                // once the hash is stored.
                let named = try await dao.amend(id: order.id) { row in
                    guard row.timestamp == timestamp, row.status == .completed, !row.namesItsPayout
                    else { return false }
                    row.outboundTxHash = hash
                    row.payoutNamedAt = nowSeconds
                    return true
                }
                if named {
                    DWLogger.log("SwapTrackingService: order \(order.id) completed, payout named by the provider")
                    asks[key] = nil
                }
            } catch {
                DWLogger.log("SwapTrackingService: order \(order.id) payout hash not saved: \(error)")
            }
        }
        if !NSDictionary(dictionary: asks).isEqual(to: stored) {
            defaults.set(asks, forKey: Constants.payoutIdentityAsksKey)
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

    /// Whether the provider has had the order's deposit for longer than it takes to notice it.
    private static func isPastStuckThreshold(_ order: SwapOrder, nowSeconds: Int64) -> Bool {
        order.depositSeenAt.map { nowSeconds > $0 + order.stuckAfterSeconds } == true
    }

    /// Whether this poll of a Buy order can come to a decision that rests on the wallet
    /// holding no payout for it: letting it go past its window, or the "Stuck" stamp.
    private func needsTheWalletsWord(_ order: SwapOrder, nowSeconds: Int64) -> Bool {
        if hasAgedOut(order, nowSeconds: nowSeconds, finalStatus: order.status) { return true }
        return order.status == .notStarted && order.providerDeniedAt == nil
            && Self.isPastStuckThreshold(order, nowSeconds: nowSeconds)
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
    /// slot of the first poll with the wallet synced — the one that can decide. A poll
    /// whose wallet read failed, or whose store was still behind the sync
    /// (`markWalletReadFailed`), is followed at the idle pace: not at the dormant one, and
    /// not every cycle while that lasts.
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
        if let last = lastPacedPoll[order.id] {
            let wait: Int64
            if last.readFailed {
                wait = min(interval, Constants.unpaidIdlePollIntervalSeconds)
            } else if overdue && walletSynced && !last.walletSynced {
                wait = 0
            } else {
                wait = interval
            }
            if nowSeconds - last.at < wait { return false }
        }
        lastPacedPoll[order.id] = (nowSeconds, walletSynced, false)
        return true
    }

    /// Restamps this cycle's paced polls as made without the wallet: the cycle started
    /// with it synced and then failed to read it, or found its store behind the sync, and
    /// such a poll must not hold a dormant slot against the one that can decide.
    private func markWalletReadFailed(_ orders: [SwapOrder]) {
        pacedPollLock.lock()
        defer { pacedPollLock.unlock() }
        for order in orders {
            if let last = lastPacedPoll[order.id] { lastPacedPoll[order.id] = (last.at, false, true) }
        }
    }

    /// Drops the pacing entry of an order that has ended.
    private func forgetPacing(for orderID: String) {
        pacedPollLock.lock()
        defer { pacedPollLock.unlock() }
        lastPacedPoll.removeValue(forKey: orderID)
        depositAddressEmptySince.removeValue(forKey: orderID)
    }

    /// Records what a poll found at the order's deposit address and returns since when
    /// (unix s) every poll has found it empty; nil when this one did not.
    private func noteDepositAddress(of order: SwapOrder, empty: Bool, at nowSeconds: Int64) -> Int64? {
        pacedPollLock.lock()
        defer { pacedPollLock.unlock() }
        guard empty else {
            depositAddressEmptySince.removeValue(forKey: order.id)
            return nil
        }
        let since = depositAddressEmptySince[order.id] ?? nowSeconds
        depositAddressEmptySince[order.id] = since
        return since
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

    /// A `/balance` amount, read whole: ASCII digits with at most one decimal point. Nil for
    /// anything else — `Decimal(string:)` alone stops at the first character it does not
    /// know and would read "0junk" or "0,5" as zero, and a negative amount is no balance.
    static func balanceAmount(_ raw: String?) -> Decimal? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.range(of: #"\A(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)\z"#, options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// What `balances` says about `asset` at the address: `.seen` for a positive amount,
    /// `.absent` for none, `.unknown` when the asset is listed with an amount that cannot be
    /// read, or when an entry does not say which asset it is — an answer we do not
    /// understand is not "nothing there". Identifiers are
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
            let amounts = items.map { balanceAmount($0.value) }
            if amounts.contains(where: { ($0 ?? 0) > 0 }) { return .seen }
            return amounts.contains(where: { $0 == nil }) ? .unknown : .absent
        }
        func named(_ items: [SwapKitBalanceItem]) -> DepositLookup {
            let wanted = asset.uppercased()
            let exact = items.filter { $0.identifier?.uppercased() == wanted }
            if !exact.isEmpty { return read(exact) }
            guard !wanted.contains("-"), let chain = SwapOrder.chain(ofAsset: wanted) else { return .absent }
            let natives = items.filter { item in
                guard let identifier = item.identifier?.uppercased() else { return false }
                return !identifier.contains("-") && SwapOrder.chain(ofAsset: identifier) == chain
            }
            if natives.count > 1 { return .unknown }
            return read(natives)
        }
        // An entry with no asset name that holds something (or an amount that cannot be
        // read) may be the one asked about, so with one in the answer the asset is not
        // known to be absent.
        let unnamed = balances.filter {
            ($0.identifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let lookup = named(balances)
        return lookup == .absent && read(unnamed) != .absent ? .unknown : lookup
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
    /// `wanted` Buy orders that have one, and which orders have an unsettled one. No wallet
    /// read when there is no Buy order among them. Nil when `wallet`'s transactions could
    /// not be read.
    private func walletPayouts(
        for wanted: [SwapOrder],
        among orders: [SwapOrder],
        in wallet: WalletView
    ) -> PayoutResolution<String>? {
        let wantedBuys = wanted.filter(\.isBuy)
        guard !wantedBuys.isEmpty else { return PayoutResolution() }
        guard let resolution = SwapBuyTransactionMatcher.walletAssignments(
            among: orders, walletId: wallet.walletId, network: wallet.network, strict: true) else { return nil }
        var result = PayoutResolution<String>(
            contested: resolution.contested, unshared: resolution.unshared,
            datedInTime: resolution.datedInTime, takenByName: resolution.takenByName)
        for order in wantedBuys {
            if let tx = resolution.assigned[order.id] { result.assigned[order.id] = tx.txHashHexString }
        }
        return result
    }
}
