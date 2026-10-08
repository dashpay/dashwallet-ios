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
/// - Polls `/track` every 30 s for active orders.
/// - Tracks NEAR-routed sells by `depositAddress` and Maya-routed sells by tx hash.
/// - Material-change-only writes (unconditional writes turn the ticker into a tight loop).
/// - Ages out an order still unresolved after 24 h → `.expired`. A Buy order follows the
///   provider's deposit deadline instead — see `hasAgedOut(_:nowSeconds:finalStatus:)`.
final class SwapTrackingService {
    static let shared = SwapTrackingService()

    private enum Constants {
        static let pollIntervalNs: UInt64 = 30_000_000_000  // 30 s
        static let ageOutSeconds: Int64 = 86_400             // 24 h
        /// How long a Buy order with funds possibly in flight keeps being tracked past its
        /// deadline. The provider may still refund or complete it days later.
        static let fundedBuyGraceSeconds: Int64 = 7 * 86_400
        /// Gap between two source-chain looks at one unpaid order's deposit address while
        /// the order is young — the window in which a deposit is actually expected.
        static let depositCheckIntervalSeconds: Int64 = 60
        /// How long an order counts as young.
        static let depositCheckEagerSeconds: Int64 = 2 * 3_600
        /// The gap after that. An order nobody paid within two hours is most likely
        /// abandoned; it is still looked at until its deadline, just rarely.
        static let depositCheckIdleIntervalSeconds: Int64 = 600
    }

    /// What one look at an order's deposit address established.
    private enum DepositLookup {
        /// The address holds the coin.
        case seen
        /// The lookup answered and the coin is not there.
        case absent
        /// No answer this time: not due yet, or the request failed.
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

    /// When each unpaid Buy order's deposit address was last looked up on its source chain
    /// (unix s). In memory only — a relaunch simply looks again. Read and written from the
    /// poll loop's child tasks under `depositCheckLock`; an entry is dropped once its order
    /// no longer needs the lookup.
    private var lastDepositCheck: [String: Int64] = [:]
    private let depositCheckLock = NSLock()

    /// When each idle unpaid Buy order was last polled at all (unix s); see `isDueForPoll`.
    private var lastIdlePoll: [String: Int64] = [:]
    private let idlePollLock = NSLock()

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
            let payouts = await walletPayouts(for: due, among: orders)

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

        do {
            if order.direction == "buy" {
                if let walletTxHash = payoutTxHash {
                    apiStatus = .completed
                    firstOutHash = walletTxHash
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
        let watchesDeposit = finalStatus == .notStarted && order.depositSeenAt == nil && order.canWatchDepositAddress
        if watchesDeposit {
            lookup = await lookUpDeposit(order, nowSeconds: nowSeconds)
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
            // - at its deadline, an order whose deposit address we watch also needs that
            //   lookup to have answered "nothing there";
            // - a day past the window the provider's answer alone is enough, so a lookup
            //   that never answers cannot keep the order alive;
            // - and silence has a limit too: `fundedBuyGraceSeconds` past the point where it
            //   would otherwise have gone, the order goes without an answer, so a provider
            //   that never answers again cannot keep it polled for the life of the install.
            let windowEnd = order.depositDeadline ?? (order.timestamp / 1000 + Constants.ageOutSeconds)
            let lookupSettled = !watchesDeposit || lookup == .absent || nowSeconds - windowEnd > Constants.ageOutSeconds
            let silenceLimit = max(windowEnd, order.depositSeenAt ?? 0) + 2 * Constants.fundedBuyGraceSeconds
            if order.isBuy, apiStatus == nil || !lookupSettled, nowSeconds <= silenceLimit {
                DWLogger.log("SwapTrackingService: order \(order.id) is past its window, waiting for an answer")
            } else {
                DWLogger.log("SwapTrackingService: order \(order.id) unresolved past its tracking window → expired")
                finalStatus = .expired
            }
        }

        // The provider reporting progress is deposit evidence too. Without recording it, an
        // order the provider acknowledged first (the usual case) would count as never paid
        // once it ended, and its row would vanish with the funds still at the provider.
        let providerReportedDeposit = order.isBuy && order.depositSeenAt == nil && finalStatus.impliesDeposit

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
        updated.status = finalStatus
        if depositSeenNow || providerReportedDeposit, updated.depositSeenAt == nil {
            updated.depositSeenAt = nowSeconds
        }
        if providerDeniedDeposit, updated.providerDeniedAt == nil { updated.providerDeniedAt = nowSeconds }
        if let firstOutHash { updated.outboundTxHash = firstOutHash }
        if let newActualAmount { updated.actualToAmount = newActualAmount }
        updated.lastChecked = nowSeconds
        if finalStatus.isTerminal { updated.finalisedAt = nowSeconds }
        if finalStatus != .notStarted || updated.depositSeenAt != nil { forgetPacing(for: order.id) }

        DWLogger.log("SwapTrackingService: order \(order.id) → \(finalStatus.rawValue)")
        await dao.update(dto: updated)
    }

    // MARK: - Private: Age-out

    /// Whether a still-active order has outlived its tracking window.
    ///
    /// Sell orders keep the flat 24 h. A Buy order is tied to the provider's deposit deadline:
    /// - no deposit anywhere → it expires at the deadline (24 h when none is known);
    /// - the deposit is on the source chain, or the provider has seen it → funds are in
    ///   flight, so it is tracked for `fundedBuyGraceSeconds` past the deadline. Dropping it
    ///   at 24 h is how an order could go dark two days before the provider's own cutoff.
    private func hasAgedOut(_ order: SwapOrder, nowSeconds: Int64, finalStatus: SwapOrderStatus) -> Bool {
        let createdSeconds = order.timestamp / 1000
        guard order.isBuy else {
            return nowSeconds - createdSeconds > Constants.ageOutSeconds
        }

        let fundsInFlight = order.depositSeenAt != nil || finalStatus != .notStarted
        if fundsInFlight {
            let anchor = max(order.depositDeadline ?? 0, order.depositSeenAt ?? 0, createdSeconds)
            return nowSeconds > anchor + Constants.fundedBuyGraceSeconds
        }
        if let deadline = order.depositDeadline {
            return nowSeconds > deadline
        }
        return nowSeconds - createdSeconds > Constants.ageOutSeconds
    }

    // MARK: - Private: Poll pacing

    /// Whether the order is asked about this cycle. Every active order is, each cycle —
    /// except a Buy order with no deposit on record that is past the eager window: most
    /// likely abandoned, it is asked about every `depositCheckIdleIntervalSeconds` until its
    /// deadline, when the eager pace returns to settle whether it can be let go.
    private func isDueForPoll(_ order: SwapOrder, nowSeconds: Int64) -> Bool {
        guard order.isBuy, !order.hasDepositOnRecord else { return true }
        let ageSeconds = nowSeconds - order.timestamp / 1000
        let pastDeadline = order.depositDeadline.map { nowSeconds > $0 } ?? false
        guard ageSeconds > Constants.depositCheckEagerSeconds, !pastDeadline else { return true }

        idlePollLock.lock()
        defer { idlePollLock.unlock() }
        guard nowSeconds - (lastIdlePoll[order.id] ?? 0) >= Constants.depositCheckIdleIntervalSeconds else { return false }
        lastIdlePoll[order.id] = nowSeconds
        return true
    }

    // MARK: - Private: Source-chain deposit check

    /// Looks at the order's deposit address for the coin the user was asked to send.
    ///
    /// Throttled per order: every `depositCheckIntervalSeconds` while the order is young,
    /// every `depositCheckIdleIntervalSeconds` afterwards — except past the deadline, where
    /// the answer decides whether the order is let go and is asked for at the eager pace.
    private func lookUpDeposit(_ order: SwapOrder, nowSeconds: Int64) async -> DepositLookup {
        guard let address = order.depositAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              let chain = order.fromAsset.split(separator: ".").first.map(String.init), !chain.isEmpty
        else { return .unknown }

        let ageSeconds = nowSeconds - order.timestamp / 1000
        let pastDeadline = order.depositDeadline.map { nowSeconds > $0 } ?? false
        let interval = ageSeconds <= Constants.depositCheckEagerSeconds || pastDeadline
            ? Constants.depositCheckIntervalSeconds
            : Constants.depositCheckIdleIntervalSeconds

        guard claimDepositLookup(for: order.id, nowSeconds: nowSeconds, interval: interval) else { return .unknown }

        do {
            let balances = try await SwapKitAPIService.shared.balance(chain: chain, address: address)
            return Self.holdsAsset(order.fromAsset, in: balances) ? .seen : .absent
        } catch {
            DWLogger.log("SwapTrackingService: deposit lookup failed for \(order.id): \(error)")
            // A failed look is retried at the eager pace, not after a full idle interval.
            setLastDepositLookup(for: order.id, to: nowSeconds - interval + Constants.depositCheckIntervalSeconds)
            return .unknown
        }
    }

    /// True when a lookup for the order is due, stamping it as started. Synchronous on
    /// purpose: `NSLock` must not be held across a suspension point.
    private func claimDepositLookup(for orderID: String, nowSeconds: Int64, interval: Int64) -> Bool {
        depositCheckLock.lock()
        defer { depositCheckLock.unlock() }
        guard nowSeconds - (lastDepositCheck[orderID] ?? 0) >= interval else { return false }
        lastDepositCheck[orderID] = nowSeconds
        return true
    }

    private func setLastDepositLookup(for orderID: String, to seconds: Int64) {
        depositCheckLock.lock()
        defer { depositCheckLock.unlock() }
        lastDepositCheck[orderID] = seconds
    }

    /// Drops the pacing entries of an order that has a deposit on record or has ended: it no
    /// longer needs its address looked up and is polled every cycle.
    private func forgetPacing(for orderID: String) {
        depositCheckLock.lock()
        lastDepositCheck.removeValue(forKey: orderID)
        depositCheckLock.unlock()
        idlePollLock.lock()
        lastIdlePoll.removeValue(forKey: orderID)
        idlePollLock.unlock()
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

    /// Order id → display hash of the wallet transaction that pays it out, for the Buy
    /// orders polled this cycle that have one. No wallet read when none is being polled.
    @MainActor
    private func walletPayouts(for due: [SwapOrder], among orders: [SwapOrder]) -> [String: String] {
        let activeBuys = due.filter(\.isBuy)
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
