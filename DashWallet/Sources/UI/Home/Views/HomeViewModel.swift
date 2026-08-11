//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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
import Combine
import CoreData
import SwiftData
import SwiftDashSDK

private let kBaseBalanceHeaderHeight: CGFloat = 100
private let kTimeskewTolerance: TimeInterval = 3600 // 1 hour
private let maxShortcutsCount = 4

/// One selectable category in the home screen's transaction filter. The
/// filter is multi-select (checkboxes): a transaction shows when it belongs
/// to ANY selected category, and a selection covering every offered category
/// means "All" — which also shows transactions that fit no category (internal
/// transfers, CoinJoin mixing groups).
enum TransactionFilterCategory: CaseIterable {
    case sent
    case received
    case rewards
    case masternode
    case giftCard
    case shieldedSent
    case shieldedReceived
}

class HomeViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "HomeViewModel", qos: .userInitiated)
    /// Whether a reconcile pass is queued or running. `queue` is serial, so
    /// without this every trigger enqueues another full pass and they drain
    /// back-to-back — each one re-reading the window and republishing the whole
    /// list to the main thread for a result the pass behind it is about to
    /// replace. Main-actor state, mutated only from `reloadTxDataSource` and
    /// `finishReloadPass`.
    private var reloadPassInFlight = false
    /// A trigger that arrived while a pass was in flight. Collapsed to a
    /// single follow-up pass, so a burst of N notifications costs two passes
    /// (the one running plus one more that sees all of it), not N.
    private var reloadPassRequestedAgain = false
    /// Triggers folded into the current pass — logged so the next session's
    /// numbers say how much this actually absorbs.
    private var reloadPassCoalesced = 0
    private var timeSkewDialogShown: Bool = false
    /// Session guard so the proactive CoinJoin-sweep popup shows at most once
    /// per launch (re-evaluated each launch while a leftover balance exists).
    private var coinJoinSweepDialogShown: Bool = false

    static let shared: HomeViewModel = {
        return HomeViewModel(transactionSource: SwiftDashSDKWalletSource())
    }()

    private let transactionSource: TransactionSource
    private var txByHash: [String: TransactionListDataItem] = [:]
    private var crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
    private var coinJoinTxSets: [String: CoinJoinMixingTxSet] = [:] // Grouped by date
    private var coinJoinWithdrawalSet = CoinJoinWithdrawalTxSet() // Single combined "CoinJoin Withdrawals" group (app's sweep tx)
    private var metadataProviders: [MetadataProvider] = []
    #if DEBUG
    var isPreviewMode: Bool = false
    #endif

    /// Tracks whether initial data load has completed (Fix #2)
    private var hasCompletedInitialLoad: Bool = false

    // MARK: Timeline window (all accessed on `queue`)

    /// Number of rows the first page and each scroll-driven page target.
    /// Pages are day-completed, so the real count can exceed this by the
    /// boundary day's remainder.
    private static let timelinePageSize = 100

    /// Window row count beyond which `trimWindowIfNeeded()` re-tightens an
    /// untouched full-history window back to about one page (recovery-sync
    /// growth cap; see that method).
    private static let timelineTrimThreshold = 400

    /// The wrapped rows of the loaded timeline window, keyed by wire-order
    /// txid. The visible list is rebuilt from this cache in memory; SwiftData
    /// is only consulted for the scoped page/delta fetches that maintain it.
    private var windowTxs: [Data: Transaction] = [:]

    /// Start of the oldest fully-loaded calendar day (Unix seconds); 0 when
    /// the window covers the whole history.
    private var windowOldestDayStart: UInt64 = 0

    /// True when wallet rows exist below `windowOldestDayStart`.
    private var hasOlderHistory: Bool = false

    /// Floor for the next `timelineDelta` fetch — the max `lastUpdated`
    /// observed across window-covering fetches. Never advanced by older-page
    /// fetches: a paged-in row's stamp can postdate window updates the next
    /// delta still has to pick up.
    private var lastReconcileStamp: Date? = nil

    /// Number of scroll-driven pages the user has loaded this session.
    /// Non-zero disables the recovery-sync trim so explicitly loaded rows
    /// are never yanked back out from under the user.
    private var userRequestedPages = 0

    /// Set (via `queue`) when a save deleted feed rows or the fiat currency
    /// changed: the next reconcile re-reads and re-wraps the whole window
    /// instead of merging a delta (deletions are invisible to the
    /// `lastUpdated` delta; cached wrappers hold currency-specific strings).
    private var pendingWindowRefetch = false

    /// Worker-side mirrors of the published filter-gate flags, so the pass
    /// never has to hop to the main thread to read its previous answer when
    /// `filterCategoryGates()` returns nil.
    private var knownHasRewards = false
    private var knownHasMasternodes = false

    /// Debounce timer for sync state changes to prevent excessive reloads (Fix #4)
    private var syncStateDebounceWorkItem: DispatchWorkItem?
    private let syncStateDebounceInterval: TimeInterval = 0.5

    /// Funnel for every "wallet content changed, reload the tx list" trigger.
    /// Throttled in `observeWallet()` so the save/balance notification storm
    /// during sync coalesces into at most one full reload per interval.
    private let txReloadRequests = PassthroughSubject<Void, Never>()

    /// Converts the SDK's current-value balance publisher into actual balance
    /// changes. The initial snapshot is already covered by the eager Home load,
    /// while `removeDuplicates()` prevents the coordinator's repeated 1 Hz
    /// snapshots from requesting redundant transaction-list reloads.
    static func distinctBalanceChanges<P: Publisher>(
        from publisher: P
    ) -> AnyPublisher<Void, Never> where P.Output == WalletBalance?, P.Failure == Never {
        publisher
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    @Published private(set) var txItems: [TransactionGroup] = []

    /// Whether the first full transaction load has finished, published on the
    /// main thread for the home feed.
    ///
    /// Distinct from the worker-queue `hasCompletedInitialLoad`, which guards
    /// reload/incremental-update sequencing off the main thread. This one
    /// exists so the view can tell "still loading" from "genuinely empty" —
    /// `txItems` is empty in both cases, and rendering the empty-state copy
    /// during the initial load tells the user they have no transactions
    /// before that is known.
    @Published private(set) var hasLoadedInitialTxItems: Bool = false

    /// True when older history exists below the loaded timeline window —
    /// drives the feed's tail loading row.
    @Published private(set) var canLoadMoreHistory: Bool = false
    /// True while a scroll-driven page fetch is in flight.
    @Published private(set) var isLoadingMoreHistory: Bool = false
    /// Increments when a page lands. The tail loading row keys its identity
    /// on this so its `onAppear` re-fires and paging continues while the row
    /// stays visible (e.g. a filter that matches nothing in the new page).
    @Published private(set) var historyPageStamp: Int = 0

    @Published var shortcutItems: [ShortcutAction] = []
    @Published var showTimeSkewAlertDialog: Bool = false
    @Published var showCoinJoinSweepDialog: Bool = false
    /// Post-sync destination-choice sheet (`CoinJoinMoveFundsSheet`) —
    /// presented instead of `showCoinJoinSweepDialog` when the CoinJoin
    /// balance is large enough to offer the Shielded destination.
    @Published var showCoinJoinMoveFundsSheet: Bool = false
    @Published private(set) var timeSkew: TimeInterval = 0
    @Published private(set) var showJoinDashpay: Bool = false
    /// Selected filter categories (multi-select checkboxes). Defaults to every
    /// category — i.e. "All". Never empty: the dialog blocks unchecking the
    /// last box.
    @Published var selectedFilters: Set<TransactionFilterCategory> = Set(TransactionFilterCategory.allCases) {
        didSet {
            reloadTxDataSource()
        }
    }

    /// True when the wallet has ever received a masternode/mining reward
    /// (any coinbase tx in history). Gates the "Rewards" filter row; computed
    /// on each full reload.
    @Published private(set) var hasRewardsHistory: Bool = false

    /// True when the wallet has ever had a masternode special transaction
    /// (proRegTx / update / revocation). Gates the "Masternode" filter row;
    /// computed on each full reload.
    @Published private(set) var hasMasternodeHistory: Bool = false

    @Published private(set) var headerHeight: CGFloat = kBaseBalanceHeaderHeight // TDOO: move back to HomeView when fully transitioned to SwiftUI
    @Published private(set) var showReclassifyTransaction: Transaction? = nil
    @Published var shouldShowShortcutBanner: Bool = false
    @Published var giftCardTxId: Data? = nil
    
#if DASHPAY
    var joinDashPayState: JoinDashPayState = .callToAction
#endif
    
    private lazy var syncModel = SyncModelImpl()
    
    private var reclassifyTransactionsActivatedAt: Date {
        get { DWGlobalOptions.sharedInstance().dateReclassifyYourTransactionsFlowActivated ?? Date() }
    }
    
    private var shouldDisplayReclassifyTransaction: Bool {
        get { DWGlobalOptions.sharedInstance().shouldDisplayReclassifyYourTransactionsFlow }
        set(value) {
            DWGlobalOptions.sharedInstance().shouldDisplayReclassifyYourTransactionsFlow = value
            
            if (!value) {
                showReclassifyTransaction = nil
            }
        }
    }
    
    init(transactionSource: TransactionSource) {
        self.transactionSource = transactionSource
        syncModel.networkStatusDidChange = { status in
            self.recalculateHeight()
        }

        self.setupMetadataProviders()
        self.onSyncStateChanged()
        self.recalculateHeight()

        // First load right away — `onSyncStateChanged()` above only schedules
        // one behind its 0.5s debounce, which reads as a visibly empty list
        // at startup before the rows pop in. There's no notification storm to
        // coalesce yet, and the fetch runs on `queue`, so this is safe to
        // start immediately.
        self.reloadTxsAndShortcuts()

        self.observeCoinJoinSweep()
        self.observeWallet()
        self.observeNetworkChange()
        #if DASHPAY
        self.observeDashPay()
        #endif
    }

    #if DEBUG
    /// Lightweight init used only by SwiftUI previews.
    /// Skips wallet/sync/coinjoin wiring that depends on the Dash core runtime.
    private init(previewShortcuts: [ShortcutAction]) {
        self.transactionSource = HomeViewModelPreviewTransactionSource()
        self.isPreviewMode = true
        self.shortcutItems = previewShortcuts
    }

    static func makeForPreview(shortcuts: [ShortcutAction]) -> HomeViewModel {
        HomeViewModel(previewShortcuts: shortcuts)
    }
    #endif

    /// Observes network changes (testnet <-> mainnet) to clear cached transaction data
    private func observeNetworkChange() {
        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearCachedData()
#if DASHPAY
                // The selected network changes before its SDK runtime is
                // ready. Keep the banner hidden during that transition; the
                // post-ready wallet-context notification re-evaluates it.
                self?.showJoinDashpay = false
#endif
            }
            .store(in: &cancellableBag)

        // A runtime wallet switch rebinds the host to a different wallet on the
        // SAME network. The cached tx items belong to the old wallet, so treat
        // it exactly like a network switch: drop the caches and reload the new
        // wallet's tx list (SwiftDashSDKWalletSource reads the host's now-active
        // wallet). The balance-driven reloads don't cover this — the balance
        // notifications the switch posts can carry the same total, and their
        // observers don't clear the stale per-hash cache.
        NotificationCenter.default.publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearCachedData()
#if DASHPAY
                // The runtime posts this only after the destination
                // network's wallet + SwiftData container are bound. Defer
                // one main-queue turn so DWCurrentUserIdentityInfo's
                // notification observer invalidates its old-network snapshot
                // before the banner asks for the destination username.
                DispatchQueue.main.async { [weak self] in
                    self?.checkJoinDashPay()
                }
#endif
            }
            .store(in: &cancellableBag)
    }

    /// Clears all cached transaction data when switching networks
    private func clearCachedData() {
        DWLogger.log("HomeViewModel: Network changed, clearing cached transaction data")

        // Dispatch to self.queue to ensure thread-safe access to txByHash, crowdNodeTxSet, coinJoinTxSets
        // These properties are also accessed/modified in reloadTxDataSource() on self.queue
        self.queue.async { [weak self] in
            guard let self = self else { return }

            // Clear cached data structures on the same queue they're accessed
            self.txByHash.removeAll()
            self.crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
            self.coinJoinTxSets.removeAll()
            self.windowTxs.removeAll()
            self.windowOldestDayStart = 0
            self.hasOlderHistory = false
            self.lastReconcileStamp = nil
            self.userRequestedPages = 0
            self.pendingWindowRefetch = false
            self.knownHasRewards = false
            self.knownHasMasternodes = false

            // Reset load tracking so the new network's data loads correctly
            self.hasCompletedInitialLoad = false

            // Update UI-bound properties on main thread. The new network's
            // history is loading from scratch, so the feed goes back to its
            // loading state rather than claiming the wallet is empty.
            DispatchQueue.main.async {
                self.txItems = []
                self.hasLoadedInitialTxItems = false
                self.canLoadMoreHistory = false
                self.isLoadingMoreHistory = false
            }

            // Reload fresh data from the new network's wallet
            // reloadTxsAndShortcuts() will dispatch back to queue internally
            DispatchQueue.main.async {
                self.reloadTxsAndShortcuts()
            }
        }
    }
    
    @MainActor
    func checkTimeSkew(force: Bool = false) {
        Task {
            let (isTimeSkewed, timeSkew) = await getDeviceTimeSkew(force: force)
            self.timeSkew = timeSkew
            
            if isTimeSkewed && (!timeSkewDialogShown || force) {
                timeSkewDialogShown = true
                showTimeSkewAlertDialog = true
            }
        }
    }
    
    private func observeWallet() {
        // All reload triggers below funnel into this one throttled pipeline.
        // During sync the persister saves a SwiftData batch several times per
        // second (with a balance notification usually alongside), and each
        // full reload is expensive — unthrottled, the storm kept the reload
        // queue permanently busy and the list janky. `throttle` (not
        // `debounce`) so a continuous save storm still repaints once per
        // interval instead of starving until it ends; `latest: true`
        // guarantees a trailing reload that picks up the final batch. A lone
        // event (e.g. a received tx while idle) passes through immediately.
        txReloadRequests
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.reloadTxsAndShortcuts()
            }
            .store(in: &cancellableBag)

        // Each trigger hops to the main queue before `send()` — the
        // notifications post from arbitrary threads (persister save thread,
        // balance updates) and PassthroughSubject requires serialized sends.
        // (DispatchQueue.main, not RunLoop.main: the latter is default-mode
        // only and stalls delivery during scroll tracking.)
        NotificationCenter.default.publisher(for: Notification.Name.fiatCurrencyDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Cached wrappers hold currency-specific display strings —
                // re-read and re-wrap the window rather than merge a delta.
                self.queue.async { self.pendingWindowRefetch = true }
                self.txReloadRequests.send()
            }
            .store(in: &cancellableBag)

        // Reload when SwiftData saves — Rust's persister callback writes
        // PersistentTransaction rows on every Core SPV / BLAST batch, and
        // SwiftData posts NSManagedObjectContextDidSave under the hood. The
        // legacy SwiftDashSDKWalletState.$transactions bridge is dead (its
        // input callback was removed in the SDK refactor), so we read
        // directly from SwiftData via SwiftDashSDKWalletSource and use this
        // notification as the reload trigger.
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { Self.saveTouchesFeedRows($0) }
            // Inspected before the main-queue hop, like the filter above —
            // the userInfo object sets belong to the posting thread.
            .map { Self.saveDeletesFeedRows($0) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deletedFeedRows in
                guard let self else { return }
                if deletedFeedRows {
                    // A deleted row is invisible to the lastUpdated delta —
                    // flag the next reconcile to re-read the loaded window.
                    self.queue.async { self.pendingWindowRefetch = true }
                }
                self.txReloadRequests.send()
            }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: .swiftDashSDKTransactionProjectionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    ShieldedTxLookup.shared.refresh()
                    self?.txReloadRequests.send()
                }
            }
            .store(in: &cancellableBag)

        // The platform-address recorder inserts into the app's SQLite —
        // invisible to the SwiftData save trigger above — so it posts its
        // own signal when a received row lands.
        NotificationCenter.default.publisher(for: .platformAddressActivityRecorded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.txReloadRequests.send()
            }
            .store(in: &cancellableBag)

        // Balance changes can precede or arrive without a SwiftData save (for
        // example seed/clear transitions), so retain an independent trigger.
        // Equal snapshots are filtered and the initial current-value emission
        // is skipped because init already starts an eager full reload.
        Self.distinctBalanceChanges(from: SwiftDashSDKWalletState.shared.$balance)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.txReloadRequests.send()
            }
            .store(in: &cancellableBag)
        
        syncModel.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                if state == .syncing {
                    // Reload once per transition into .syncing — replaces the
                    // legacy sync-will-start notification observer. Goes
                    // through the throttled funnel rather than calling
                    // `reloadTxsAndShortcuts()` directly: this sink also
                    // schedules the debounced sync-state reload, so a direct
                    // call raced it into two full passes per transition. The
                    // funnel's sink reloads shortcuts too, so nothing is lost.
                    DWLogger.log("HomeViewModel: Sync started, reloading transactions")
                    self.txReloadRequests.send()
                }
                self.onSyncStateChanged()
                self.maybeShowCoinJoinSweepDialog()
            }
            .store(in: &cancellableBag)
    }
    
    /// Entities whose rows the home feed actually renders.
    private static let feedRowEntityNames: Set<String> = [
        "PersistentTransaction",
        "PersistentTxo",
    ]

    /// Whether a SwiftData save touched anything the feed renders.
    ///
    /// The model container is shared with bookkeeping that saves on its own
    /// cadence — sync state, masternode lists, platform-address sync — and an
    /// unfiltered save trigger turned every one of those into a full re-read
    /// of the whole history plus a wholesale `txItems` republish. On a
    /// 1756-transaction wallet that fired roughly every 15s indefinitely, and
    /// the republish re-diffs the list under the user's finger mid-scroll.
    ///
    /// Fails OPEN: a save whose payload we can't inspect is treated as
    /// relevant, so an unexpected notification shape costs a redundant reload
    /// rather than a feed that stops updating.
    private static func saveTouchesFeedRows(_ notification: Notification) -> Bool {
        guard let userInfo = notification.userInfo else { return true }
        var sawInspectableChange = false
        for key in [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey] {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            guard !objects.isEmpty else { continue }
            sawInspectableChange = true
            if objects.contains(where: { feedRowEntityNames.contains($0.entity.name ?? "") }) {
                return true
            }
        }
        return !sawInspectableChange
    }

    /// Whether a SwiftData save DELETED feed rows (e.g.
    /// `UnconfirmedTransactionRemover`). Deletions are invisible to the
    /// `lastUpdated` delta reconcile, so they force a window re-read. Unlike
    /// `saveTouchesFeedRows` this fails CLOSED on an uninspectable payload:
    /// that payload already triggers a reload via the fail-open filter, and
    /// answering true here would turn every such save into a window refetch.
    private static func saveDeletesFeedRows(_ notification: Notification) -> Bool {
        guard let objects = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> else {
            return false
        }
        return objects.contains(where: { feedRowEntityNames.contains($0.entity.name ?? "") })
    }

    // Entry point of the throttled reconcile pass. The pass is scoped to the
    // loaded timeline window (page/delta fetches, in-memory rebuild) — but it
    // still republishes the whole list, so it stays behind the funnel's
    // throttle rather than running per notification.
    private func reloadTxDataSource() {
        // Read main-actor state BEFORE handing off, never from inside the
        // worker pass. A `DispatchQueue.main.sync` from the queue is a barrier
        // whose cost is main-thread *availability*, not work: at launch the
        // main thread is busy with tab-bar layout, avatar state and CrowdNode
        // restore, so a reload that hops mid-pass inherits all of it. Hopping
        // once up front, asynchronously, keeps the pass free-running.
        let dispatch = { @MainActor [weak self] in
            guard let self else { return }
            // A pass already owns the queue: record that the world changed
            // again and let it re-run once when it lands. Enqueueing here
            // instead is what produced bursts of identical rebuilds — the
            // reported duration of each includes the wait behind the ones
            // before it, so a backlog reads as a slow pass and every entry in
            // it republishes the full list.
            guard !self.reloadPassInFlight else {
                self.reloadPassRequestedAgain = true
                self.reloadPassCoalesced += 1
                return
            }
            self.reloadPassInFlight = true
            // Pair each request with the filter selection that was live when
            // it was made. Reading it inside the pass instead would let a pass
            // triggered by one change render a selection the user made after
            // it started.
            let selectedFilters = self.selectedFilters
            let startedAt = Date()
            self.queue.async { [weak self] in
                self?.performReload(selectedFilters: selectedFilters, startedAt: startedAt)
                self?.finishReloadPass()
            }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated { dispatch() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { dispatch() } }
        }
    }

    /// Release the pass and, if the world moved while it ran, run exactly one
    /// more. Called outside `performReload` so every early return in it — an
    /// unbound host, a nil delta — still releases.
    private func finishReloadPass() {
        DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in
            guard let self else { return }
            let coalesced = self.reloadPassCoalesced
            self.reloadPassCoalesced = 0
            self.reloadPassInFlight = false
            if coalesced > 0 {
                DWLogger.log("HomeViewModel: coalesced \(coalesced) reconcile trigger(s) into that pass")
            }
            guard self.reloadPassRequestedAgain else { return }
            self.reloadPassRequestedAgain = false
            self.reloadTxDataSource()
        } }
    }

    private func performReload(selectedFilters: Set<TransactionFilterCategory>, startedAt: Date) {
        // `startedAt` is stamped when the pass was REQUESTED, on the main
        // actor. `workStartedAt` is when it actually got the queue. Reporting
        // only their sum reads a backlog as a slow pass — which is exactly how
        // a burst of triggers used to look like one 21-second rebuild.
        let workStartedAt = Date()
        DWLogger.log("HomeViewModel: Starting timeline reconcile")

        // --- Stage 1: bring the wrapped-row window up to date. Every
        // SwiftData read here is scoped to the loaded day range — no path
        // is O(wallet history).
        if !hasCompletedInitialLoad {
            guard let window = transactionSource.timelineWindow(targetRowCount: Self.timelinePageSize) else {
                // Host not bound yet (launch race): publish the same
                // "loaded, empty" state this pass always produced here, and
                // leave `hasCompletedInitialLoad` unset so the next trigger
                // retries the first page.
                DispatchQueue.main.async {
                    self.txItems = []
                    self.hasLoadedInitialTxItems = true
                }
                return
            }
            applyTimelineWindow(window)
            hasCompletedInitialLoad = true
            DWLogger.log("HomeViewModel: Timeline first page loaded — \(windowTxs.count) rows, older history: \(hasOlderHistory)")
        } else if pendingWindowRefetch {
            // Deletions / currency changes invalidate the cached wrappers —
            // re-read and re-wrap the whole loaded window (window-sized, not
            // wallet-sized). The flag clears only once the re-read actually
            // happened: a nil delta (host momentarily unbound) keeps the
            // request pending for the next pass instead of dropping it.
            if let delta = transactionSource.timelineDelta(
                updatedAfter: .distantPast, notBefore: windowOldestDayStart) {
                pendingWindowRefetch = false
                replaceWindow(with: delta)
            }
        } else if let delta = transactionSource.timelineDelta(
            updatedAfter: lastReconcileStamp ?? .distantPast,
            notBefore: windowOldestDayStart) {
            if delta.isCompleteWindow {
                replaceWindow(with: delta)
            } else {
                for tx in delta.transactions {
                    windowTxs[tx.txHashData] = tx
                }
                advanceReconcileStamp(delta.maxLastUpdated)
            }
        }
        trimWindowIfNeeded()

        // --- Stage 2: whole-history filter gates, answered by the store
        // without materializing rows; nil keeps the previous answer.
        if let gates = transactionSource.filterCategoryGates() {
            knownHasRewards = gates.hasRewards
            knownHasMasternodes = gates.hasMasternodes
        }

        // --- Stage 3: rebuild the visible list from the in-memory window.
        rebuildTimelineItems(
            selectedFilters: selectedFilters,
            startedAt: startedAt,
            workStartedAt: workStartedAt,
            pageCompleted: false)
    }

    /// Replace the window cache with a freshly fetched first page.
    private func applyTimelineWindow(_ window: WalletTimelineWindow) {
        windowTxs = Dictionary(
            window.transactions.map { ($0.txHashData, $0) },
            uniquingKeysWith: { first, _ in first })
        windowOldestDayStart = window.oldestLoadedDayStart
        hasOlderHistory = window.hasOlderHistory
        advanceReconcileStamp(window.maxLastUpdated)
    }

    /// Replace the window cache from a complete-window delta (a refetch
    /// after deletions/currency change, or the source's predicate-translation
    /// fallback).
    private func replaceWindow(with delta: WalletTimelineDelta) {
        windowTxs = Dictionary(
            delta.transactions.map { ($0.txHashData, $0) },
            uniquingKeysWith: { first, _ in first })
        advanceReconcileStamp(delta.maxLastUpdated)
    }

    private func advanceReconcileStamp(_ stamp: Date?) {
        guard let stamp else { return }
        if lastReconcileStamp.map({ stamp > $0 }) ?? true {
            lastReconcileStamp = stamp
        }
    }

    /// Recovery-sync growth cap. While the window still covers the whole
    /// (small) history, every restored batch enters through the delta path
    /// and the window grows with the wallet. Past the threshold, re-tighten
    /// by refetching the first page — unless the user has explicitly paged
    /// deeper, in which case the rows they loaded stay put.
    ///
    /// A store refetch rather than an in-memory trim: the store computes the
    /// boundary in `firstSeen` space — the same key paging and deltas filter
    /// by — while the cached wrappers only expose the display date, which
    /// can differ for legacy rows (`firstSeen` predating block-timestamp
    /// adoption) and would let a date-keyed trim drop rows that paging then
    /// never re-fetches.
    private func trimWindowIfNeeded() {
        guard userRequestedPages == 0,
              !hasOlderHistory,
              windowTxs.count > Self.timelineTrimThreshold else { return }
        guard let window = transactionSource.timelineWindow(targetRowCount: Self.timelinePageSize),
              window.hasOlderHistory else { return }
        applyTimelineWindow(window)
        DWLogger.log("HomeViewModel: Timeline window re-tightened to \(windowTxs.count) rows (recovery growth cap)")
    }

    /// Whether an interleaved (shielded / platform / cross-day group) item's
    /// day is covered by the loaded timeline window. Items below the paged
    /// window stay hidden until their day is paged in, so a day never
    /// renders partially. Undated restored entries (the trailing
    /// "Date unknown" band) are covered only once the whole history is
    /// loaded — the band renders after the last real day.
    private func windowCovers(date: Date, hasKnownDate: Bool = true) -> Bool {
        guard hasOlderHistory else { return true }
        guard hasKnownDate else { return false }
        return UInt64(max(0, date.timeIntervalSince1970)) >= windowOldestDayStart
    }

    /// Extend the timeline window one day-completed page down. Called from
    /// the feed's tail loading row on the main thread.
    func loadMoreHistory() {
        guard canLoadMoreHistory, !isLoadingMoreHistory else { return }
        isLoadingMoreHistory = true
        let selectedFilters = self.selectedFilters
        let startedAt = Date()
        queue.async { [weak self] in
            guard let self else { return }
            let workStartedAt = Date()
            guard self.hasOlderHistory, self.windowOldestDayStart > 0,
                  let page = self.transactionSource.olderTimelinePage(
                      endingBefore: self.windowOldestDayStart,
                      targetRowCount: Self.timelinePageSize) else {
                DispatchQueue.main.async { self.isLoadingMoreHistory = false }
                return
            }
            for tx in page.transactions {
                self.windowTxs[tx.txHashData] = tx
            }
            self.windowOldestDayStart = page.oldestLoadedDayStart
            self.hasOlderHistory = page.hasOlderHistory
            self.userRequestedPages += 1
            // The paged-in rows now sit inside the delta scope (`notBefore`
            // = the new boundary), so later updates to them reconcile
            // normally. The page itself must NOT advance the delta stamp:
            // its rows' `lastUpdated` can postdate window updates the next
            // delta still has to pick up.
            DWLogger.log("HomeViewModel: Timeline paged to \(self.windowTxs.count) rows, older history: \(self.hasOlderHistory)")
            self.rebuildTimelineItems(
                selectedFilters: selectedFilters,
                startedAt: startedAt,
                workStartedAt: workStartedAt,
                pageCompleted: true)
        }
    }

    /// The rebuild's input rows: the window cache plus point-lookup backfill
    /// of tagged CoinJoin sweeps (the combined "CoinJoin Withdrawals" group
    /// totals every sweep even when its row sits below the loaded window —
    /// cost scales with the number of recorded sweeps), in deterministic
    /// timeline order: date desc with the txid hex as tie-breaker, so
    /// equal-timestamp rows (same-block mixing bursts) keep a stable order
    /// across rebuilds instead of reshuffling.
    private func timelineInputTransactions() -> [Transaction] {
        var inputByTxid = windowTxs
        let missingSweepTxids = CoinJoinWithdrawalStore.shared.allTxids()
            .filter { inputByTxid[$0] == nil }
        if !missingSweepTxids.isEmpty {
            for tx in transactionSource.wrappedTransactions(txids: missingSweepTxids) {
                inputByTxid[tx.txHashData] = tx
            }
        }
        return inputByTxid.values.sorted { lhs, rhs in
            guard lhs.date == rhs.date else { return lhs.date > rhs.date }
            return lhs.txHashHexString > rhs.txHashHexString
        }
    }

    /// Rebuild `txItems` from the loaded window. Pure in-memory over the
    /// cached wrappers except for three intentionally small reads: the
    /// shielded/platform activity fetches and the sweep-txid point lookups.
    /// Runs on `queue`.
    private func rebuildTimelineItems(
        selectedFilters: Set<TransactionFilterCategory>,
        startedAt: Date,
        workStartedAt: Date,
        pageCompleted: Bool
    ) {
        let transactions = timelineInputTransactions()

        // Reconcile restored Shielded → Core destinations before Core rows
        // are filtered/classified. The activity projection can recover a
        // destination tag that was absent from the local withdrawal store.
        // Receipt matching sees the loaded window, not the whole history.
        // Rendered shielded items sit inside the window (the `windowCovers`
        // gate in `appendInterleavedActivity`), and the match tolerance is
        // -1h…+24h around the item,
        // so the only candidate a rendered item can miss is a receipt up to
        // an hour before it across the window's bottom midnight — a pending
        // row that resolves once that day is paged in.
        let shieldedItems = SwiftDashSDKWalletSource.fetchShieldedActivity(
            coreTransactions: transactions)
        self.crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
        self.coinJoinTxSets = [:]
        self.coinJoinWithdrawalSet = CoinJoinWithdrawalTxSet()

        // Gate the "Rewards" / "Masternode" filter rows — the store-probed
        // whole-history answers (stage 2), so they don't flap with the
        // current selection or the loaded window.
        let hasRewards = knownHasRewards
        let hasMasternodes = knownHasMasternodes

        // Snapshot each provider's metadata once per reload —
        // `availableMetadata` copies the whole dictionary through the
        // provider's serial queue, so reading it per-transaction costs
        // O(n) queue hops + dictionary copies per reload.
        let metadataSnapshots = self.metadataProviders.map { $0.availableMetadata }
        let giftCardTxIds = Set(GiftCardMetadataProvider.shared.availableMetadata.keys)

        var items: [TransactionListDataItem] = transactions.compactMap { wrappedTx -> TransactionListDataItem? in
            Tx.shared.updateRateIfNeeded(for: wrappedTx)

            if !self.passesFilter(transaction: wrappedTx, selected: selectedFilters, hasRewards: hasRewards, hasMasternodes: hasMasternodes, giftCardTxIds: giftCardTxIds) {
                return nil
            }

            // TODO(crowdnode-home-grouping): the "CrowdNode · Account" group
            // needs decode-based ObservedTransaction matching (the SDK
            // snapshot here doesn't carry transactionData); ports separately.
            // Until then CrowdNode txs render as individual rows — the
            // current behavior (the old DS-backed grouping branch was dead
            // long before the .ds source case was deleted).
            if wrappedTx.isCoinJoinMixing {
                // CoinJoin mixing tx — group it into the per-day
                // "Mixing Transactions" set.
                let date = DWDateFormatter.sharedInstance.dateOnly(from: wrappedTx.date)
                let coinJoinTxSet = self.coinJoinTxSets[date] ?? CoinJoinMixingTxSet()
                self.coinJoinTxSets[date] = coinJoinTxSet

                if coinJoinTxSet.tryInclude(wrappedTx) {
                    return nil
                }
            } else if wrappedTx.isCoinJoinWithdrawal {
                // App-tagged CoinJoin offload (sweep) tx → the single
                // combined "CoinJoin Withdrawals" group.
                if self.coinJoinWithdrawalSet.tryInclude(wrappedTx) {
                    return nil
                }
            }

            return .tx(wrappedTx, self.resolveMetadata(for: wrappedTx.txHashData, in: metadataSnapshots))
        }

        appendInterleavedActivity(
            to: &items,
            shieldedItems: shieldedItems,
            selectedFilters: selectedFilters,
            hasRewards: hasRewards,
            hasMasternodes: hasMasternodes)

        self.txByHash.removeAll()
        items.forEach { item in
            self.txByHash[item.id] = item
        }

        if !crowdNodeTxSet.transactionMap.isEmpty {
            let item: TransactionListDataItem = .crowdnode(crowdNodeTxSet)
            items.append(item)
            self.txByHash[FullCrowdNodeSignUpTxSet.id] = item
        }

        for (_, coinJoinTxSet) in self.coinJoinTxSets {
            if !coinJoinTxSet.transactionMap.isEmpty {
                let item: TransactionListDataItem = .coinjoin(coinJoinTxSet)
                items.append(item)
                self.txByHash[coinJoinTxSet.id] = item
            }
        }

        // The cross-day sweep group renders only once its (latest-tx) day is
        // paged in — same day-atomicity as every other row; its totals are
        // already complete from the point lookups above whenever it shows.
        if !self.coinJoinWithdrawalSet.transactionMap.isEmpty,
           windowCovers(date: self.coinJoinWithdrawalSet.groupDay) {
            let item: TransactionListDataItem = .coinjoinWithdrawal(self.coinJoinWithdrawalSet)
            items.append(item)
            self.txByHash[self.coinJoinWithdrawalSet.id] = item
        }

        // Restored shielded entries with no recoverable date (`hasKnownDate
        // == false`, date == .distantPast) collect under one dedicated
        // trailing group instead of a spurious epoch-day header; the
        // distantPast sentinel makes both sorts place them last.
        let unknownDateKey = NSLocalizedString(
            "Date unknown",
            comment: "History group header for restored shielded operations whose original date is not recoverable")
        let groupedItems = Dictionary(
            grouping: items.sorted(by: { lhs, rhs in
                guard lhs.date == rhs.date else { return lhs.date > rhs.date }
                // Equal dates: the shared `.distantPast` sentinel of the
                // "Date unknown" band orders by exact on-chain sequence,
                // newest (highest note position) first; same-timestamp
                // dated rows (same-block bursts) fall through to the id so
                // their order is stable across rebuilds.
                let lhsKey = lhs.chainOrderKey ?? 0
                let rhsKey = rhs.chainOrderKey ?? 0
                guard lhsKey == rhsKey else { return lhsKey > rhsKey }
                return lhs.id > rhs.id
            }),
            by: {
                $0.hasKnownDate
                    ? DWDateFormatter.sharedInstance.dateOnly(from: $0.date)
                    : unknownDateKey
            }
        )

        let array = groupedItems.compactMap { key, items -> TransactionGroup? in
            guard let first = items.first else { return nil }
            return TransactionGroup(id: key, date: first.date, items: items)
        }.sorted { $0.date > $1.date }

        let now = Date()
        let elapsedMs = Int(now.timeIntervalSince(startedAt) * 1000)
        let workMs = Int(now.timeIntervalSince(workStartedAt) * 1000)
        DWLogger.log("HomeViewModel: Timeline rebuild complete in \(elapsedMs)ms (queued \(max(0, elapsedMs - workMs))ms, work \(workMs)ms), \(array.count) groups, \(self.txByHash.count) items cached, window \(windowTxs.count) rows")

        publishTimeline(
            array,
            hasRewards: hasRewards,
            hasMasternodes: hasMasternodes,
            pageCompleted: pageCompleted)
    }

    /// Interleave the shielded operations (private receives/sends,
    /// Platform↔Shielded moves, shielded identity fundings) and the observed
    /// incoming Platform-address payments (app-recorded — the SDK persists
    /// no per-payment platform history; see PlatformAddressActivityStore) —
    /// the Core rows only cover operations with an L1 leg; the day-grouping
    /// sort merges the timelines. Platform items are received-only by
    /// construction, so they ride the `.received` filter category. Both are
    /// clamped to the loaded day range via `windowCovers`.
    private func appendInterleavedActivity(
        to items: inout [TransactionListDataItem],
        shieldedItems: [ShieldedActivityItem],
        selectedFilters: Set<TransactionFilterCategory>,
        hasRewards: Bool,
        hasMasternodes: Bool
    ) {
        for shielded in shieldedItems {
            guard windowCovers(date: shielded.date, hasKnownDate: shielded.hasKnownDate) else { continue }
            guard self.passesShieldedFilter(
                item: shielded,
                selected: selectedFilters,
                hasRewards: hasRewards,
                hasMasternodes: hasMasternodes)
            else { continue }
            items.append(.shieldedActivity(shielded))
        }

        let platformItems = SwiftDashSDKWalletSource.fetchPlatformActivity()
        for platform in platformItems {
            guard windowCovers(date: platform.date) else { continue }
            guard self.passesCategoryFilter(
                categories: [.received],
                selected: selectedFilters,
                hasRewards: hasRewards,
                hasMasternodes: hasMasternodes)
            else { continue }
            items.append(.platformActivity(platform))
        }
    }

    /// Publish a rebuilt group array and the paging/gate state to the main
    /// thread in one hop.
    private func publishTimeline(
        _ array: [TransactionGroup],
        hasRewards: Bool,
        hasMasternodes: Bool,
        pageCompleted: Bool
    ) {
        let canLoadMore = hasOlderHistory
        let groupCount = array.count
        DispatchQueue.main.async {
            // The one part of a reconcile that is unavoidably main-thread:
            // assigning `txItems` republishes the whole list and SwiftUI diffs
            // it. Timed so the cost of republishing is a number rather than an
            // inference.
            let publishStartedAt = Date()
            self.txItems = array
            self.hasLoadedInitialTxItems = true
            if self.canLoadMoreHistory != canLoadMore {
                self.canLoadMoreHistory = canLoadMore
            }
            if pageCompleted {
                self.isLoadingMoreHistory = false
                self.historyPageStamp += 1
            }
            if self.hasRewardsHistory != hasRewards {
                self.hasRewardsHistory = hasRewards
            }
            if self.hasMasternodeHistory != hasMasternodes {
                self.hasMasternodeHistory = hasMasternodes
            }
            let publishMs = Int(Date().timeIntervalSince(publishStartedAt) * 1000)
            if publishMs >= 50 {
                DWLogger.log("HomeViewModel: publish held the main thread \(publishMs)ms for \(groupCount) groups")
            }
        }
    }
    
    private func onTransactionStatusChanged(tx: Transaction) {
        self.queue.async { [weak self] in
            guard let self = self else { return }

            // Fix #2: If initial load hasn't completed yet, the cache is empty and
            // incremental updates won't work correctly. Trigger a full reload instead.
            if !self.hasCompletedInitialLoad {
                DWLogger.log("HomeViewModel: Initial load not complete, triggering full reload for tx: \(tx.txHashHexString)")
                DispatchQueue.main.async {
                    self.reloadTxsAndShortcuts()
                }
                return
            }

            // Below the paged window: the row isn't on screen and its
            // day-group isn't loaded — it renders correctly when its day is
            // paged in. Rows at/above the boundary join the window cache so
            // the next in-memory rebuild keeps them.
            if self.hasOlderHistory,
               UInt64(max(0, tx.date.timeIntervalSince1970)) < self.windowOldestDayStart {
                return
            }
            self.windowTxs[tx.txHashData] = tx

            let selectedFilters = DispatchQueue.main.sync { self.selectedFilters }
            let historyFlags = DispatchQueue.main.sync { (self.hasRewardsHistory, self.hasMasternodeHistory) }

            // A coinbase / masternode tx arriving incrementally unlocks its
            // filter row without waiting for the next full reload.
            if tx.isCoinbaseTransaction && !historyFlags.0 {
                self.knownHasRewards = true
                DispatchQueue.main.async {
                    self.hasRewardsHistory = true
                }
            }
            if tx.isMasternodeTransaction && !historyFlags.1 {
                self.knownHasMasternodes = true
                DispatchQueue.main.async {
                    self.hasMasternodeHistory = true
                }
            }

            if !self.passesFilter(transaction: tx, selected: selectedFilters, hasRewards: historyFlags.0, hasMasternodes: historyFlags.1) {
                return
            }

            Tx.shared.updateRateIfNeeded(for: tx)
            let txHashHex = tx.txHashHexString
            let itemId = txHashHex
            let txItem: TransactionListDataItem = .tx(tx, resolveMetadata(for: tx.txHashData))
            let newDateKey = DWDateFormatter.sharedInstance.dateOnly(from: tx.date)

            // TODO(crowdnode-home-grouping): the CrowdNode absorb-into-group
            // branch that lived here was dead (it was fed by DashSync's
            // DSTransactionManagerTransactionStatusDidChange, which no longer
            // fires post-M6) and was removed with the CrowdNode tracking port.
            // Today this path is fed by the metadata-provider refresh below
            // (gift-card / custom-icon updates re-rendering an existing row).

            if let existingItem = self.txByHash[itemId] {
                // Updating existing item
                self.txByHash[itemId] = txItem

                // Fix: Find the OLD date group where this transaction currently lives
                // Transaction dates can change when going from unconfirmed to confirmed
                var oldGroupIndex: Int? = nil
                var oldItemIndex: Int? = nil
                var oldDateKey: String? = nil

                let currentGroups = DispatchQueue.main.sync { self.txItems }
                for (gIdx, group) in currentGroups.enumerated() {
                    if let iIdx = group.items.firstIndex(where: { $0.id == itemId }) {
                        oldGroupIndex = gIdx
                        oldItemIndex = iIdx
                        oldDateKey = group.id
                        break
                    }
                }

                var isChanged = true
                if case let .tx(existingTx, oldMetadata) = existingItem, case let .tx(newTx, metadata) = txItem {
                    isChanged = newTx.state != existingTx.state || oldMetadata != metadata
                }

                // Fix: Handle transaction moving between date groups (e.g., unconfirmed -> confirmed)
                if let oldDateKey = oldDateKey, oldDateKey != newDateKey {
                    DWLogger.log("HomeViewModel: Transaction \(itemId) date changed from \(oldDateKey) to \(newDateKey)")

                    // Remove from old group
                    if let oldGIdx = oldGroupIndex, let oldIIdx = oldItemIndex {
                        DispatchQueue.main.async {
                            // Validate both group index and item index bounds before removal
                            // txItems may have changed between when indices were captured and now
                            guard oldGIdx >= 0,
                                  oldGIdx < self.txItems.count,
                                  oldIIdx >= 0,
                                  oldIIdx < self.txItems[oldGIdx].items.count else {
                                DWLogger.log("HomeViewModel: Skipping removal - indices out of bounds (groupIdx: \(oldGIdx), itemIdx: \(oldIIdx))")
                                return
                            }

                            self.txItems[oldGIdx].items.remove(at: oldIIdx)

                            // Remove empty groups (re-check bounds after item removal)
                            if oldGIdx < self.txItems.count && self.txItems[oldGIdx].items.isEmpty {
                                self.txItems.remove(at: oldGIdx)
                            }

                            // Add to new group (similar to new item logic)
                            if let newGroupIndex = self.txItems.firstIndex(where: { $0.id == newDateKey }) {
                                self.txItems[newGroupIndex].items.append(txItem)
                                self.txItems[newGroupIndex].items.sort { $0.date > $1.date }
                            } else {
                                let newGroup = TransactionGroup(id: newDateKey, date: txItem.date, items: [txItem])
                                let insertIndex = self.txItems.firstIndex(where: { $0.date < txItem.date })
                                if let index = insertIndex {
                                    self.txItems.insert(newGroup, at: index)
                                } else {
                                    self.txItems.append(newGroup)
                                }
                            }
                        }
                    }
                } else if isChanged {
                    // Same date group, just update in place
                    if let groupIndex = oldGroupIndex, let itemIndex = oldItemIndex {
                        DispatchQueue.main.async {
                            guard groupIndex < self.txItems.count,
                                  itemIndex < self.txItems[groupIndex].items.count else { return }
                            var updatedGroup = self.txItems[groupIndex]
                            var updatedItems = updatedGroup.items
                            updatedItems[itemIndex] = txItem
                            updatedGroup.items = updatedItems
                            self.txItems[groupIndex] = updatedGroup
                        }
                    }
                }
            } else {
                // New item
                self.txByHash[itemId] = txItem
                let shouldShowReclassify = self.shouldDisplayReclassifyTransaction && tx.date > reclassifyTransactionsActivatedAt

                // Re-check the current data source inside the main-queue hop;
                // a full reload may replace all groups between these queues.
                DispatchQueue.main.async {
                    if let currentGroupIndex = self.txItems.firstIndex(where: { $0.id == newDateKey }) {
                        self.txItems[currentGroupIndex].items.append(txItem)
                        self.txItems[currentGroupIndex].items.sort { $0.date > $1.date }
                    } else {
                        let newGroup = TransactionGroup(id: newDateKey, date: txItem.date, items: [txItem])
                        let insertIndex = self.txItems.firstIndex(where: { $0.date < txItem.date })
                        if let index = insertIndex {
                            self.txItems.insert(newGroup, at: index)
                        } else {
                            self.txItems.append(newGroup)
                        }
                    }
                    self.showReclassifyTransaction = shouldShowReclassify ? tx : nil
                }
            }
        }
    }
    
    func reclassifyTransactionShown(isShown: Bool) {
        if isShown {
            shouldDisplayReclassifyTransaction = false
        }
    }
    
    
    private func recalculateHeight() {
        var height = kBaseBalanceHeaderHeight
        let hasNetwork = syncModel.networkStatus == .online

        if !hasNetwork {
            height += 85
        }

        if shouldShowShortcutBanner {
            // Banner height + the gap between the bar and the banner (added via setCustomSpacing
            // in HomeHeaderView). Without the gap term the fixed header height is too short and
            // the .fill stack shrinks the bar, shifting its card upward.
            height += 70 + HomeHeaderView.shortcutBarBannerSpacing
        }

        self.headerHeight = height
    }
    
    private func getDeviceTimeSkew(force: Bool) async -> (Bool, TimeInterval) {
        do {
            let timeSkew = try await TimeUtils.getTimeSkew(force: force)
            let maxAllowedTimeSkew = kTimeskewTolerance
            return (abs(timeSkew) > maxAllowedTimeSkew, timeSkew)
        } catch {
            // Ignore errors
            return (false, 0)
        }
    }
}

extension HomeViewModel {
    private func onSyncStateChanged() {
        // Fix #4: Debounce sync state changes to prevent excessive reloads.
        // During active sync, state can change rapidly which would cause
        // multiple expensive full reloads in quick succession.
        syncStateDebounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            DWLogger.log("HomeViewModel: Sync state changed (debounced), requesting reload")
            // Through the shared funnel, not straight to the reload: this
            // debounce only coalesces sync-state changes among themselves, so
            // calling directly raced the throttled save/balance triggers and
            // each fired its own full pass.
            self.txReloadRequests.send()
            #if DASHPAY
            self.checkJoinDashPay()
            #endif
        }

        syncStateDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + syncStateDebounceInterval, execute: workItem)
    }
    
    func reloadTxsAndShortcuts() {
        self.reloadTxDataSource()
        self.reloadShortcuts()
    }
}

// MARK: - CoinJoin Recovery Sweep (post-migration)

extension HomeViewModel {
    /// Live CoinJoin-account leftover balance (duffs) — SDK source of truth,
    /// the same value the Settings "Move CoinJoin Funds" row binds to.
    var coinJoinSweepAmountDuffs: UInt64 {
        SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
    }

    /// Formatted leftover amount for the popup message.
    var coinJoinSweepAmountFormatted: String {
        String(format: "%.6f DASH", Double(coinJoinSweepAmountDuffs) / Double(kOneDash))
    }

    private func observeCoinJoinSweep() {
        // The leftover balance lands after the (wide) recovery scan completes,
        // sometimes just after `.syncDone`; observe it so the popup still
        // surfaces if the balance arrives a beat later than the state change.
        SwiftDashSDKWalletState.shared.$coinJoinBalanceDuffs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.maybeShowCoinJoinSweepDialog()
            }
            .store(in: &cancellableBag)
    }

    /// Whether the post-sync popup can offer the Shielded-balance destination:
    /// the wallet's shielded sub-wallet is bound (an Orchard address resolves)
    /// AND the CoinJoin balance is comfortably above the drain's fee overhead
    /// — the Type 18 pool fee (carved from the locked value) plus an L1-fee
    /// allowance for the many-input drain transaction — so at least half the
    /// moved amount survives the fees. Fails closed (BIP44-only popup) when
    /// the fee estimate or the shielded binding is unavailable.
    var coinJoinShieldDestinationAvailable: Bool {
        let balanceDuffs = coinJoinSweepAmountDuffs
        // Host + manager are `@MainActor`-isolated — reuse the wallet source's
        // main-thread trampoline (same file).
        return SwiftDashSDKWalletSource.onMain {
            guard let manager = SwiftDashSDKHost.shared.manager,
                  let wallet = SwiftDashSDKHost.shared.wallet,
                  ((try? manager.shieldedDefaultAddress(walletId: wallet.walletId)) ?? nil) != nil,
                  let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits
            else { return false }
            // The shared Type 18 pool-fee estimate (credits → duffs is ÷ 1000);
            // `sendFeeReserveDuffs` (0.001 DASH) allows for the L1 fee of a
            // drain spending hundreds of mixed-coin inputs.
            let overheadDuffs = poolFeeCredits / 1000 + WalletBalance.sendFeeReserveDuffs
            return balanceDuffs >= overheadDuffs * 2
        }
    }

    /// Proactively surface the "move your mixed coins" popup once per session
    /// after sync completes, while a recoverable CoinJoin balance exists.
    /// Bound to the live balance (not a persistent flag): it re-prompts each
    /// launch until the user sweeps, then self-stops (balance → 0). The durable
    /// Settings row covers the same action for users who dismiss it.
    ///
    /// When the balance is large enough to shield, the destination-choice
    /// sheet (`CoinJoinMoveFundsSheet`) is shown instead of the BIP44-only
    /// dialog.
    func maybeShowCoinJoinSweepDialog() {
        let balance = coinJoinSweepAmountDuffs
        // Economic floor: below the L1-fee allowance a drain of many tiny
        // mixed inputs cannot pay its own fee — prompting would offer a sweep
        // that can never succeed. Dust leftovers stay visible (and manually
        // sweepable) via the Tools / Settings "Move CoinJoin Funds" rows,
        // which keep the lower `recoveryDustThresholdDuffs` floor.
        let viableFloor = max(WalletBalance.sendFeeReserveDuffs, CoinJoinRecovery.recoveryDustThresholdDuffs)
        let suppressed = WalletEnvironment.network.map {
            CoinJoinRecovery.shared.isSweepPromptSuppressed(currentBalanceDuffs: balance, for: $0)
        } ?? false
        DWLogger.log("HomeViewModel: sweep dialog check — \(balance) duffs (\(String(format: "%.6f", Double(balance) / Double(kOneDash))) DASH), viableFloor \(viableFloor), above=\(balance > viableFloor), suppressed=\(suppressed), syncDone=\(syncModel.state == .syncDone), alreadyShown=\(coinJoinSweepDialogShown)")
        guard !coinJoinSweepDialogShown,
              syncModel.state == .syncDone,
              balance > viableFloor,
              !suppressed else { return }
        coinJoinSweepDialogShown = true
        if coinJoinShieldDestinationAvailable {
            showCoinJoinMoveFundsSheet = true
        } else {
            showCoinJoinSweepDialog = true
        }
    }

    /// "Later" on either sweep surface: persist the dismissal (keyed to the
    /// current balance, so newly mixed coins re-arm the prompt) and close the
    /// surface. The Tools / Settings rows remain the durable entry points.
    func deferCoinJoinSweep() {
        if let network = WalletEnvironment.network {
            CoinJoinRecovery.shared.recordSweepPromptDismissal(
                balanceDuffs: coinJoinSweepAmountDuffs, for: network)
        }
        showCoinJoinSweepDialog = false
        showCoinJoinMoveFundsSheet = false
    }

    /// Sweep the leftover CoinJoin balance into the user's spendable balance
    /// via the shared `WalletSendService` flow (PIN → own BIP44 dest → sweep →
    /// balance refresh + recovery-flag clear). Auth-cancel is an expected no-op;
    /// the Settings row remains for retry on other failures.
    func performCoinJoinSweep() async -> String? {
        do {
            _ = try await WalletSendService.shared.sweepCoinJoin()
            return nil
        } catch {
            DWLogger.log("HomeViewModel: sweep (home popup) failed: \(error)")
            // nil when the user cancelled auth; a message on real failures.
            return WalletSendService.coinJoinSweepUserMessage(for: error)
        }
    }
}

// MARK: - Metadata

extension HomeViewModel {
    private func setupMetadataProviders() {
        let giftCardMetadata = GiftCardMetadataProvider.shared
        let customIconMetadata = CustomIconMetadataProvider.shared
        let coinbaseMetadata = CoinbaseMetadataProvider.shared
        let swapOrderMetadata = SwapOrderMetadataProvider.shared
        self.metadataProviders = [giftCardMetadata, coinbaseMetadata, customIconMetadata, swapOrderMetadata]
        
        for provider in self.metadataProviders {
            provider.metadataUpdated
                .receive(on: self.queue)
                .sink { [weak self] txHash in
                    guard let self = self else { return }

                    // Providers emit the wire-order txid (`Transaction.txHashData`),
                    // which is the SDK row key. A miss (persister race) is a no-op —
                    // the NSManagedObjectContextDidSave full reload covers it.
                    if let transaction = SwiftDashSDKWalletSource.fetch(txid: txHash) {
                        self.onTransactionStatusChanged(tx: transaction)
                    }
                }
                .store(in: &cancellableBag)
        }
    }
    
    private func resolveMetadata(for txId: Data) -> TxRowMetadata? {
        resolveMetadata(for: txId, in: metadataProviders.map { $0.availableMetadata })
    }

    /// `snapshots` holds one pre-copied `availableMetadata` per provider, in
    /// provider (priority) order — full-reload loops snapshot once and reuse
    /// across all transactions instead of re-copying per row.
    private func resolveMetadata(for txId: Data, in snapshots: [[Data: TxRowMetadata]]) -> TxRowMetadata? {
        var finalMetadata: TxRowMetadata? = nil

        // Metadata will not be replaced if already found, so in case
        // of conflicts metadataProviders should be sorted by priority
        for providerMetadata in snapshots {
            guard let metadata = providerMetadata[txId] else { continue }
            
            if finalMetadata == nil {
                finalMetadata = metadata
            } else {
                if finalMetadata?.title == nil {
                    finalMetadata?.title = metadata.title
                }

                if finalMetadata?.details == nil {
                    finalMetadata?.details = metadata.details
                }
                
                if finalMetadata?.icon == nil {
                    finalMetadata?.icon = metadata.icon
                }
                
                if finalMetadata?.iconId == nil {
                    finalMetadata?.iconId = metadata.iconId
                }
                
                if finalMetadata?.secondaryIcon == nil {
                    finalMetadata?.secondaryIcon = metadata.secondaryIcon
                }
            }
        }

        return finalMetadata
    }
    
    /// Union semantics: show the tx when it belongs to any selected category.
    /// A selection covering every OFFERED category (rewards / masternode are
    /// offered only when their history flags are set) is "All" and also admits
    /// txs that fit no category (internal transfers, CoinJoin mixing groups).
    ///
    /// `giftCardTxIds` is an optional pre-snapshotted key set for the
    /// `.giftCard` category — full-reload loops pass it to avoid copying the
    /// provider's dictionary per transaction; single-tx callers omit it.
    private func passesFilter(transaction: Transaction, selected: Set<TransactionFilterCategory>, hasRewards: Bool, hasMasternodes: Bool, giftCardTxIds: Set<Data>? = nil) -> Bool {
        var offered = Set(TransactionFilterCategory.allCases)
        if !hasRewards {
            offered.remove(.rewards)
        }
        if !hasMasternodes {
            offered.remove(.masternode)
        }
        if selected.isSuperset(of: offered) {
            return true
        }
        return !selected.isDisjoint(with: categories(of: transaction, giftCardTxIds: giftCardTxIds))
    }

    /// Filter check for a pure-shielded history item — the counterpart of
    /// `passesFilter(transaction:...)` with the same "everything offered
    /// selected → show all" fast path. Direction maps to the dedicated
    /// shielded categories only (never plain sent/received: those mean
    /// on-chain transparent movements).
    private func passesShieldedFilter(
        item: ShieldedActivityItem,
        selected: Set<TransactionFilterCategory>,
        hasRewards: Bool,
        hasMasternodes: Bool
    ) -> Bool {
        var categories: Set<TransactionFilterCategory> = []
        switch item.direction {
        case .incoming:
            categories.insert(.shieldedReceived)
        case .outgoing:
            categories.insert(.shieldedSent)
        case .selfTransfer:
            categories.formUnion([.shieldedSent, .shieldedReceived])
        }
        return passesCategoryFilter(
            categories: categories,
            selected: selected,
            hasRewards: hasRewards,
            hasMasternodes: hasMasternodes)
    }

    /// Shared filter check for non-Core history items with precomputed
    /// categories — same "everything offered selected → show all" fast
    /// path as `passesFilter(transaction:...)`.
    private func passesCategoryFilter(
        categories: Set<TransactionFilterCategory>,
        selected: Set<TransactionFilterCategory>,
        hasRewards: Bool,
        hasMasternodes: Bool
    ) -> Bool {
        var offered = Set(TransactionFilterCategory.allCases)
        if !hasRewards {
            offered.remove(.rewards)
        }
        if !hasMasternodes {
            offered.remove(.masternode)
        }
        if selected.isSuperset(of: offered) {
            return true
        }
        return !selected.isDisjoint(with: categories)
    }

    /// Categories a transaction belongs to. Overlaps are allowed (a gift-card
    /// purchase is also a sent tx); rewards and shielded receipts are carved
    /// out of received, mirroring how the old single-select filter separated
    /// rewards from receives.
    private func categories(of transaction: Transaction, giftCardTxIds: Set<Data>? = nil) -> Set<TransactionFilterCategory> {
        if transaction.isCoinbaseTransaction {
            return [.rewards]
        }
        if transaction.isMasternodeTransaction {
            return [.masternode]
        }
        var categories: Set<TransactionFilterCategory> = []
        if transaction.isShieldedTransfer {
            categories.insert(.shieldedSent)
        }
        let isShieldedReceipt = transaction.isShieldedWithdrawalReceipt
        if isShieldedReceipt {
            categories.insert(.shieldedReceived)
        }
        let ids = giftCardTxIds ?? Set(GiftCardMetadataProvider.shared.availableMetadata.keys)
        if ids.contains(transaction.txHashData) {
            categories.insert(.giftCard)
        }
        switch transaction.direction {
        case .sent:
            categories.insert(.sent)
        case .received:
            if !isShieldedReceipt {
                categories.insert(.received)
            }
        case .moved, .notAccountFunds:
            break
        }
        return categories
    }
}

// MARK: - Shortcuts

extension HomeViewModel {
    @MainActor
    func checkShortcutBanner() {
        let options = DWGlobalOptions.sharedInstance()
        let newValue = (options.shortcutBannerState == 2 && options.shortcuts == nil)
        if newValue != shouldShowShortcutBanner {
            shouldShowShortcutBanner = newValue
            recalculateHeight()
        }
    }

    @MainActor
    func dismissShortcutBanner() {
        DWGlobalOptions.sharedInstance().shortcutBannerState = 3
        shouldShowShortcutBanner = false
        recalculateHeight()
    }

    func reloadShortcuts() {
        #if DEBUG
        guard !isPreviewMode else { return }
        #endif
        let options = DWGlobalOptions.sharedInstance()
        let isTestnet = WalletEnvironment.isTestnet

        // Check for custom configuration first. Mapped on main: the Switch
        // Wallet availability gate reads main-actor wallet state, and this
        // reload can run off-main (the published write lands on main anyway).
        if let customShortcuts = options.shortcuts,
           customShortcuts.count == maxShortcutsCount {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let canSwitchWallet = MainActor.assumeIsolated { WalletsViewModel.switchableWalletCount > 1 }
                let items = customShortcuts.compactMap { number -> ShortcutAction? in
                    guard var type = ShortcutActionType(rawValue: number.intValue) else { return nil }
                    // A faucet shortcut saved on testnet degrades to Spend
                    // after a switch to mainnet (no mainnet faucet exists);
                    // the saved config is untouched, so it comes back when
                    // the user returns to testnet.
                    if type == .getTestDash && !isTestnet {
                        type = .spend
                    }
                    // A Switch Wallet shortcut degrades to Receive while the
                    // device is back to a single wallet; the saved config is
                    // untouched, so it returns when another wallet is added.
                    if type == .switchWallet && !canSwitchWallet {
                        type = .receive
                    }
                    // Dash DEX is offered only on mainnet with SwapKit configured (mirrors
                    // ShortcutActionType.customizableActions and ServiceDataProvider.shouldShow);
                    // a saved DEX shortcut degrades to Spend whenever that gate isn't met. The
                    // saved config is untouched, so it returns once the gate passes again.
                    let dashDEXAvailable = !isTestnet && SwapKitConstants.isConfigured
                    if type == .dashDEX && !dashDEXAvailable {
                        type = .spend
                    }
                    return ShortcutAction(type: type)
                }
                .filter { action in
                    // A saved CrowdNode shortcut stays hidden until the user
                    // has actually signed up.
                    if action.type == .crowdNode {
                        let state = CrowdNode.shared.signUpState
                        return state == .finished || state == .linkedOnline
                    }
                    return true
                }
                if items.count == maxShortcutsCount {
                    self.shortcutItems = items
                } else {
                    self.applyDefaultShortcuts(options: options, isTestnet: isTestnet)
                }
            }
            return
        }

        applyDefaultShortcuts(options: options, isTestnet: isTestnet)
    }

    /// The default state-based bar (no custom configuration, or the saved one
    /// no longer maps to a full set of actions).
    private func applyDefaultShortcuts(options: DWGlobalOptions, isTestnet: Bool) {
        let walletNeedsBackup = options.walletNeedsBackup
        let userHasBalance = options.userHasBalance
        // On testnet the last default slot offers the faucet instead of
        // Spend — test Dash is what a testnet wallet actually needs.
        let lastSlot: ShortcutActionType = isTestnet ? .getTestDash : .spend

        var mutableItems = [ShortcutAction]()
        mutableItems.reserveCapacity(maxShortcutsCount)

        // State 1: Zero balance and not verified passphrase
        if !userHasBalance && walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .secureWallet))
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .buySellDash))
            mutableItems.append(ShortcutAction(type: lastSlot))
        }
        // State 2: Zero balance and verified passphrase
        else if !userHasBalance && !walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .send))
            mutableItems.append(ShortcutAction(type: .buySellDash))
            mutableItems.append(ShortcutAction(type: lastSlot))
        }
        // State 3: Has balance and verified passphrase
        else if userHasBalance && !walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .send))
            mutableItems.append(ShortcutAction(type: .scanToPay))
            mutableItems.append(ShortcutAction(type: lastSlot))
        }
        // State 4: Has balance and not verified passphrase
        else if userHasBalance && walletNeedsBackup {
            mutableItems.append(ShortcutAction(type: .secureWallet))
            mutableItems.append(ShortcutAction(type: .receive))
            mutableItems.append(ShortcutAction(type: .send))
            mutableItems.append(ShortcutAction(type: lastSlot))
        }

        DispatchQueue.main.async {
            self.shortcutItems = mutableItems
        }
    }

    /// Re-check banner visibility after shortcuts change (e.g., user customized via long press)
    @MainActor
    func recheckBannerAfterCustomization() {
        if shouldShowShortcutBanner {
            checkShortcutBanner()
        }
    }
}

/// A wrapped, newest-first slice of the wallet timeline covering complete
/// calendar days: the page fetch always finishes its boundary day, so a
/// loaded day is never partially represented and per-day aggregations built
/// from the window (the CoinJoin mixing groups) stay exact without reading
/// the whole history.
struct WalletTimelineWindow {
    let walletId: Data
    /// Wrapped rows, `firstSeen` desc.
    let transactions: [Transaction]
    /// Start of the oldest fully-loaded calendar day (Unix seconds, local
    /// calendar); 0 when the window reaches the beginning of history.
    let oldestLoadedDayStart: UInt64
    /// True when rows exist below `oldestLoadedDayStart`.
    let hasOlderHistory: Bool
    /// Max `lastUpdated` across the fetched rows — the caller's floor for
    /// the next delta fetch. Nil when the fetch produced no rows or the
    /// source doesn't track update stamps.
    let maxLastUpdated: Date?
}

/// Rows changed since a reconcile stamp, scoped to the loaded window.
struct WalletTimelineDelta {
    let transactions: [Transaction]
    let maxLastUpdated: Date?
    /// True when `transactions` is the ENTIRE loaded window (a from-scratch
    /// re-read) rather than just the changed rows — the caller replaces its
    /// cache instead of merging, which is how row deletions get observed.
    let isCompleteWindow: Bool
}

protocol TransactionSource {
    var allTransactions: Array<Transaction> { get }

    /// The newest rows as a day-completed window of about `targetRowCount`.
    /// Nil when the source has no active wallet yet.
    func timelineWindow(targetRowCount: Int) -> WalletTimelineWindow?
    /// The next day-completed page strictly below `dayStartCutoff`
    /// (a previous window's `oldestLoadedDayStart`).
    func olderTimelinePage(endingBefore dayStartCutoff: UInt64, targetRowCount: Int) -> WalletTimelineWindow?
    /// Rows with `lastUpdated` after `stamp` whose `firstSeen` is at/after
    /// `dayStart`. Nil when the source can't answer.
    func timelineDelta(updatedAfter stamp: Date, notBefore dayStart: UInt64) -> WalletTimelineDelta?
    /// Whole-history "has any coinbase / masternode special tx" answers for
    /// the Rewards / Masternode filter rows, computed without materializing
    /// the history. Nil when unanswerable (caller keeps its previous answer).
    func filterCategoryGates() -> (hasRewards: Bool, hasMasternodes: Bool)?
    /// Wrapped rows for specific txids (point lookups).
    func wrappedTransactions(txids: Set<Data>) -> [Transaction]
}

/// Fixture-source defaults (onboarding demo, previews): the whole
/// `allTransactions` set is one complete, already-loaded window; there is
/// nothing older to page in and no store to answer deltas or gates from.
extension TransactionSource {
    func timelineWindow(targetRowCount: Int) -> WalletTimelineWindow? {
        WalletTimelineWindow(
            walletId: Data(),
            transactions: allTransactions.sorted { $0.date > $1.date },
            oldestLoadedDayStart: 0,
            hasOlderHistory: false,
            maxLastUpdated: nil)
    }

    func olderTimelinePage(endingBefore dayStartCutoff: UInt64, targetRowCount: Int) -> WalletTimelineWindow? { nil }

    func timelineDelta(updatedAfter stamp: Date, notBefore dayStart: UInt64) -> WalletTimelineDelta? { nil }

    func filterCategoryGates() -> (hasRewards: Bool, hasMasternodes: Bool)? { nil }

    func wrappedTransactions(txids: Set<Data>) -> [Transaction] { [] }
}

struct CoreWithdrawalReceiptCandidate: Equatable {
    let amountDuffs: UInt64
    let date: Date
}

struct CoreWithdrawalReceiptMatchPolicy {
    /// A withdrawal destination is the wallet's next unused Core receive
    /// address, so one transaction paying it is authoritative even when the
    /// restored shielded activity timestamp or reconstructed amount differs.
    /// Address reuse is handled conservatively: require one unambiguous
    /// amount/time candidate rather than consuming an unrelated receipt.
    static func selectedIndex(
        expectedAmountDuffs: UInt64,
        activityDate: Date,
        candidates: [CoreWithdrawalReceiptCandidate]
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return 0 }

        let inWindow = candidates.indices.filter {
            isWithinMatchWindow(candidates[$0].date, around: activityDate)
        }
        if expectedAmountDuffs > 0 {
            let exactInWindow = inWindow.filter {
                candidates[$0].amountDuffs == expectedAmountDuffs
            }
            if exactInWindow.count == 1 { return exactInWindow[0] }

            let exact = candidates.indices.filter {
                candidates[$0].amountDuffs == expectedAmountDuffs
            }
            if exact.count == 1 { return exact[0] }
        }
        return inWindow.count == 1 ? inWindow[0] : nil
    }

    private static func isWithinMatchWindow(_ date: Date, around anchor: Date) -> Bool {
        let delta = date.timeIntervalSince(anchor)
        return delta >= -3600 && delta <= 86_400
    }
}

/// Pure SwiftDashSDK source for the home screen tx list. Queries the
/// `PersistentTransaction` rows persisted by Rust's SwiftData callbacks
/// (Core SPV block apply + BLAST events) directly from
/// `SwiftDashSDKHost.shared.modelContainer`. DashSync is not in the loop.
///
/// Mirrors the SwiftExampleApp's `TransactionListView` pattern, adapted
/// for the existing UIKit + Combine home view: instead of `@Query`, we do
/// a synchronous fetch and feed the existing `Transaction` wrapper.
///
/// Threading: only the `@MainActor` host's handles (`modelContainer` +
/// active `walletId`) are read through a brief main-thread hop. The fetch
/// and the per-tx wrapping run on the CALLER's thread against a private
/// `ModelContext`, so a full home-list reload never blocks the main
/// thread mid-scroll. A private context reads the last SAVED state —
/// which is exactly what the `NSManagedObjectContextDidSave` reload
/// trigger guarantees is current.
struct SwiftDashSDKWalletTransactionSnapshot {
    let walletId: Data
    let transactions: [Transaction]
}

/// Objective-C-facing, value-only projection used by the phone-side Watch
/// bridge. The archived `BRAppleWatchTransactionData` wire model stays
/// unchanged; only its source moves from frozen DashSync transactions to the
/// active SwiftDashSDK wallet snapshot.
@objcMembers
final class DWAppleWatchTransactionSnapshot: NSObject {
    let amountText: String
    let amountTextInLocalCurrency: String
    let dateText: String
    let typeRawValue: Int

    init(amountText: String,
         amountTextInLocalCurrency: String,
         dateText: String,
         typeRawValue: Int) {
        self.amountText = amountText
        self.amountTextInLocalCurrency = amountTextInLocalCurrency
        self.dateText = dateText
        self.typeRawValue = typeRawValue
    }
}

@objc
final class DWAppleWatchSnapshotProvider: NSObject {
    private enum WatchTransactionType: Int {
        case sent
        case received
        case moved
        case invalid
    }

    @objc
    static func hasWallet() -> Bool {
        SwiftDashSDKWalletSource.hasActiveWallet
    }

    /// The legacy bridge sent at most the account's 100 newest Core
    /// transactions. Keep that limit and ordering so existing watches receive
    /// the same archive shape and list semantics.
    ///
    /// The page is picked by `firstSeen` (the store's indexed timeline) and
    /// then displayed in `date` order like before; the two only diverge by
    /// the mempool→block timestamp skew, and never inside a 100-row window
    /// that matters to a watch face. Scoping the fetch is what keeps a
    /// context send from materializing a many-thousand-tx wallet.
    @objc
    static func recentTransactions() -> [DWAppleWatchTransactionSnapshot] {
        guard let snapshot = SwiftDashSDKWalletSource.fetchRecent(limit: 100) else {
            return []
        }

        return snapshot.transactions
            .sorted { $0.date > $1.date }
            .map(makeSnapshot)
    }

    private static func makeSnapshot(_ transaction: Transaction) -> DWAppleWatchTransactionSnapshot {
        let type: WatchTransactionType
        switch transaction.state {
        case .invalid:
            type = .invalid
        default:
            switch transaction.direction {
            case .sent:
                type = .sent
            case .received, .notAccountFunds:
                type = .received
            case .moved:
                type = .moved
            }
        }

        let signedAmount = transaction.appleWatchSignedAmount
        let localAmount = CurrencyExchanger.shared.fiatAmountString(for: signedAmount.dashAmount)

        return DWAppleWatchTransactionSnapshot(
            amountText: signedAmount.formattedDashAmount,
            amountTextInLocalCurrency: "(\(localAmount))",
            dateText: watchDateText(transaction.date),
            typeRawValue: type.rawValue)
    }

    private static func watchDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "Mdja",
                                                        options: 0,
                                                        locale: Locale.current)
        return formatter.string(from: date)
            .replacingOccurrences(of: "am", with: "a")
            .replacingOccurrences(of: "pm", with: "p")
            .replacingOccurrences(of: "AM", with: "a")
            .replacingOccurrences(of: "PM", with: "p")
            .replacingOccurrences(of: "a.m.", with: "a")
            .replacingOccurrences(of: "p.m.", with: "p")
            .replacingOccurrences(of: "A.M.", with: "a")
            .replacingOccurrences(of: "P.M.", with: "p")
    }
}

class SwiftDashSDKWalletSource: TransactionSource {
    var allTransactions: Array<Transaction> {
        Self.fetchAll().sorted { $0.date > $1.date }
    }

    // TransactionSource timeline conformance — the store-backed overrides of
    // the fixture defaults, delegating to the scoped static fetches below.

    func timelineWindow(targetRowCount: Int) -> WalletTimelineWindow? {
        Self.fetchTimelineWindow(targetRowCount: targetRowCount)
    }

    func olderTimelinePage(endingBefore dayStartCutoff: UInt64, targetRowCount: Int) -> WalletTimelineWindow? {
        Self.fetchOlderTimelinePage(endingBefore: dayStartCutoff, targetRowCount: targetRowCount)
    }

    func timelineDelta(updatedAfter stamp: Date, notBefore dayStart: UInt64) -> WalletTimelineDelta? {
        Self.fetchTimelineDelta(updatedAfter: stamp, notBefore: dayStart)
    }

    func filterCategoryGates() -> (hasRewards: Bool, hasMasternodes: Bool)? {
        Self.fetchFilterCategoryGates()
    }

    func wrappedTransactions(txids: Set<Data>) -> [Transaction] {
        Self.fetch(txids: txids)?.transactions ?? []
    }

    /// All persisted SDK transactions wrapped for the app (`firstSeen` desc).
    /// Safe from any thread. Shared read for every tx-history consumer that
    /// used to enumerate DashSync's `DSWallet.allTransactions`.
    static func fetchAll() -> [Transaction] {
        fetchCurrentWalletSnapshot()?.transactions ?? []
    }

    /// Active wallet id and its persisted transactions, captured from one
    /// host-handle read. Callers that retain work across wallet switches use
    /// the id to prevent a pending operation from matching another wallet's
    /// transaction set.
    static func fetchCurrentWalletSnapshot() -> SwiftDashSDKWalletTransactionSnapshot? {
        guard let (container, walletId) = hostHandles() else { return nil }
        let transactions = fetchAndWrap(in: ModelContext(container), walletId: walletId)
        return SwiftDashSDKWalletTransactionSnapshot(walletId: walletId, transactions: transactions)
    }

    /// Single transaction by txid (wire order — the same `Data` as
    /// `DSTransaction.txHashData`). Safe from any thread.
    static func fetch(txid: Data) -> Transaction? {
        guard let (container, walletId) = hostHandles() else { return nil }
        return fetchOne(txid: txid, in: ModelContext(container), walletId: walletId)
    }

    /// The newest `limit` wallet transactions (`firstSeen` desc — the same
    /// timeline the full snapshot is sorted by). Safe from any thread.
    ///
    /// Wallet-scoped in SQL against the `firstSeen` index (see
    /// `scopedNewestFirst`), so callers that need a page of recent rows no
    /// longer materialize the entire wallet the way
    /// `fetchCurrentWalletSnapshot()` does.
    static func fetchRecent(limit: Int) -> SwiftDashSDKWalletTransactionSnapshot? {
        guard let (container, walletId) = hostHandles() else { return nil }
        let transactions = scopedNewestFirst(
            in: ModelContext(container), walletId: walletId,
            minFirstSeen: 0, limit: limit)
        return SwiftDashSDKWalletTransactionSnapshot(walletId: walletId, transactions: transactions)
    }

    /// Wallet transactions first seen at/after `cutoff` (`firstSeen` desc).
    /// Safe from any thread.
    ///
    /// `firstSeen` is the SDK's observation stamp (wall clock when the tx
    /// enters the mempool; the block timestamp once mined/restored), while
    /// `Transaction.date` prefers the block timestamp — so callers matching
    /// on the display date must pad `cutoff` with generous slack for that
    /// skew rather than pass an exact bound (e.g.
    /// `SwapBuyTransactionMatcher.fetchCutoff(for:)`).
    static func fetchRecent(firstSeenSince cutoff: Date) -> SwiftDashSDKWalletTransactionSnapshot? {
        guard let (container, walletId) = hostHandles() else { return nil }
        let transactions = scopedNewestFirst(
            in: ModelContext(container), walletId: walletId,
            minFirstSeen: UInt64(max(0, cutoff.timeIntervalSince1970)), limit: nil)
        return SwiftDashSDKWalletTransactionSnapshot(walletId: walletId, transactions: transactions)
    }

    /// The subset of wallet transactions whose txid (wire order) is in
    /// `txids`, `firstSeen` desc. Safe from any thread. Point lookups on the
    /// unique txid index — cost scales with `txids.count`, not with the
    /// wallet's history size.
    static func fetch(txids: Set<Data>) -> SwiftDashSDKWalletTransactionSnapshot? {
        guard let (container, walletId) = hostHandles() else { return nil }
        guard !txids.isEmpty else {
            return SwiftDashSDKWalletTransactionSnapshot(walletId: walletId, transactions: [])
        }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { txids.contains($0.txid) },
            sortBy: [SortDescriptor(\.firstSeen, order: .reverse)])
        descriptor.relationshipKeyPathsForPrefetching = [\.outputs, \.inputs]
        let rows = (try? context.fetch(descriptor)) ?? []
        let transactions = rows
            .filter { isWalletMember($0, walletId: walletId) }
            .map { wrap($0, walletId: walletId) }
        return SwiftDashSDKWalletTransactionSnapshot(walletId: walletId, transactions: transactions)
    }

    /// The active wallet's shielded operations as history items, for
    /// interleaving with the Core rows. Safe from any thread.
    ///
    /// Three reductions happen here rather than in the view model:
    /// - ShieldFromAssetLock entries are dropped: their Core asset-lock
    ///   spend always renders as a history row already
    ///   (`Transaction.isShieldedTransfer`).
    /// - An internal Withdrawal is projected as Pending until its matching
    ///   Core receipt appears, then dropped so the receipt becomes the single
    ///   authoritative history row. A withdrawal to an EXTERNAL Core address
    ///   produces no wallet-side Core transaction, so it always stays and
    ///   renders as a Sent row.
    /// - Rows are deduped by `entryId`: an intra-wallet transfer writes
    ///   a Sent row on the sending account and a Received row on the
    ///   receiving account for the same operation; the outgoing
    ///   (initiating) side wins.
    static func fetchShieldedActivity(
        coreTransactions: [Transaction] = []
    ) -> [ShieldedActivityItem] {
        guard let (container, walletId) = hostHandles() else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentShieldedActivity>(
            predicate: #Predicate { $0.walletId == walletId })
        guard let rows = try? context.fetch(descriptor) else { return [] }

        var byEntry: [Data: PersistentShieldedActivity] = [:]
        // Entry ids that also produced a Received projection: an
        // intra-wallet transfer writes Sent + Received rows for the same
        // operation (see the dedupe doc above), so a surviving Sent row
        // whose entry id is in here paid one of the wallet's own accounts.
        var receivedEntryIds: Set<Data> = []
        for row in rows where row.kindTag != ShieldedActivityItem.Kind.shieldFromAssetLock.rawValue {
            if row.kindTag == ShieldedActivityItem.Kind.received.rawValue {
                receivedEntryIds.insert(row.entryId)
            }
            if let existing = byEntry[row.entryId] {
                if shouldPreferShieldedProjection(row, over: existing) {
                    byEntry[row.entryId] = row
                }
            } else {
                byEntry[row.entryId] = row
            }
        }

        let noteValueByCmx = shieldedNoteValueByCmx(in: context, walletId: walletId)
        let outgoingNoteValueByCmx = outgoingShieldedNoteValueByCmx(in: context, walletId: walletId)

        // The wallet's own default Orchard address (raw 43 bytes), for the
        // Sent-destination ownership check. Keyed by the SAME walletId the
        // rows were fetched with (not a re-read of the host's active wallet,
        // which could have switched between the two main hops). Nil until
        // the shielded sub-wallet is bound — then the Received-row evidence
        // still covers live intra-wallet transfers.
        let ownShieldedRaw43: Data? = onMain {
            guard let manager = SwiftDashSDKHost.shared.manager else { return nil }
            return ((try? manager.shieldedDefaultAddress(walletId: walletId)) ?? nil)
        }

        var items: [ShieldedActivityItem] = []
        for row in byEntry.values {
            let reconstructedAmountCredits = projectedShieldedAmountCredits(
                for: row,
                noteValueByCmx: noteValueByCmx,
                outgoingNoteValueByCmx: outgoingNoteValueByCmx)
            let reconstructedAmountDuffs = reconstructedAmountCredits / 1000

            switch row.kindTag {
            case ShieldedActivityItem.Kind.withdrawal.rawValue:
                let address = withdrawalDestinationAddress(counterparty: row.counterparty)
                if let address, isActiveWalletCoreAddress(address, walletId: walletId, in: context) {
                    // Live withdrawals record this before the payout arrives,
                    // but restored activity can rebuild the same durable tag.
                    ShieldedWithdrawalStore.shared.record(address: address)
                    let pendingItem = ShieldedActivityItem(
                        row: row,
                        amountCreditsOverride: reconstructedAmountCredits,
                        destinationAddress: address,
                        isAwaitingTransparentReceipt: true)
                    // Keep a local Pending row during the gap between the
                    // shielded spend and the asynchronously persisted L1
                    // receipt. Once a matching receipt exists, suppress the
                    // placeholder so the operation never renders twice.
                    if hasMatchingCoreReceipt(
                        for: pendingItem,
                        address: address,
                        in: coreTransactions) {
                        continue
                    }
                    items.append(pendingItem)
                    continue
                }
                // External (or undecodable-script) withdrawal: nothing
                // else in the history covers it — hiding it would make
                // funds silently vanish from the timeline.
                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits,
                    destinationAddress: address,
                    isExternalDestination: true))
            case ShieldedActivityItem.Kind.unshield.rawValue:
                // Unshield destination = 21-byte serialized PlatformAddress.
                // Unlike withdrawals, both flavors stay in the list (there
                // is never a Core row for either); the ownership check only
                // decides internal-move vs Sent presentation. An
                // undecodable counterparty defaults to the internal
                // presentation — the honest reading of "destination
                // unknown" for an own-initiated operation.
                let address = unshieldDestinationAddress(counterparty: row.counterparty)
                let isExternal = address.map {
                    !isActiveWalletPlatformAddress($0, walletId: walletId, in: context)
                } ?? false
                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits,
                    destinationAddress: address,
                    isExternalDestination: isExternal))
            case ShieldedActivityItem.Kind.received.rawValue:
                if matchingCoreInternalTransfer(
                    for: row,
                    amountDuffs: reconstructedAmountDuffs,
                    route: .coreToShielded,
                    in: coreTransactions) != nil {
                    // Restored Core → Shielded transfers are already covered by
                    // the authoritative L1 asset-lock row in the main list.
                    continue
                }
                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits))
            case ShieldedActivityItem.Kind.shieldedSpend.rawValue:
                if let address = unshieldDestinationAddress(counterparty: row.counterparty) {
                    let isExternal = !isActiveWalletPlatformAddress(address, walletId: walletId, in: context)
                    items.append(ShieldedActivityItem(
                        row: row,
                        kindOverride: .unshield,
                        amountCreditsOverride: reconstructedAmountCredits,
                        destinationAddress: address,
                        isExternalDestination: isExternal))
                    continue
                }

                if let address = withdrawalDestinationAddress(counterparty: row.counterparty) {
                    let isOwnAddress = isActiveWalletCoreAddress(
                        address,
                        walletId: walletId,
                        in: context)
                    if isOwnAddress {
                        ShieldedWithdrawalStore.shared.record(address: address)
                    }
                    let receipt = matchingCoreReceipt(
                        amountDuffs: reconstructedAmountDuffs,
                        address: address,
                        around: Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000.0),
                        in: coreTransactions)
                    let receiptAmountCredits = receipt.map { $0.dashAmount * 1000 }
                    let effectiveAmount = receiptAmountCredits ?? reconstructedAmountCredits

                    if isOwnAddress {
                        // Same-seed restore: once the transparent receipt is in
                        // the wallet's L1 history, that row is authoritative.
                        if receipt != nil {
                            continue
                        }
                        items.append(ShieldedActivityItem(
                            row: row,
                            kindOverride: .withdrawal,
                            amountCreditsOverride: effectiveAmount,
                            destinationAddress: address,
                            isAwaitingTransparentReceipt: true))
                    } else {
                        items.append(ShieldedActivityItem(
                            row: row,
                            kindOverride: .withdrawal,
                            amountCreditsOverride: effectiveAmount,
                            destinationAddress: address,
                            isExternalDestination: true))
                    }
                    continue
                }

                if row.identityId.count == 32 {
                    items.append(ShieldedActivityItem(
                        row: row,
                        kindOverride: .identityCreate,
                        amountCreditsOverride: reconstructedAmountCredits))
                    continue
                }

                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits))
            case ShieldedActivityItem.Kind.sent.rawValue:
                // A shielded → shielded send's counterparty is the recipient's
                // 43-byte raw Orchard address (live-recorded, or OVK-recovered
                // by the restore scan). Surface it so the row and detail sheet
                // name where the money went instead of a bare "Sent /
                // Shielded". External only when the destination is provably
                // not the wallet's own: an intra-wallet transfer leaves a
                // Received row under the same entry id, and a send to the
                // wallet's default Orchard address is its own funds either way.
                let address = shieldedDestinationAddress(counterparty: row.counterparty)
                let isOwnDestination = receivedEntryIds.contains(row.entryId)
                    || (ownShieldedRaw43 != nil && row.counterparty == ownShieldedRaw43)
                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits,
                    destinationAddress: address,
                    isExternalDestination: address != nil && !isOwnDestination))
            default:
                items.append(ShieldedActivityItem(
                    row: row,
                    amountCreditsOverride: reconstructedAmountCredits))
            }
        }
        return items
    }

    private static func shouldPreferShieldedProjection(
        _ lhs: PersistentShieldedActivity,
        over rhs: PersistentShieldedActivity
    ) -> Bool {
        let lhsScore = shieldedProjectionPreferenceScore(lhs)
        let rhsScore = shieldedProjectionPreferenceScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        return lhs.createdAtMs > rhs.createdAtMs
    }

    private static func shieldedProjectionPreferenceScore(_ row: PersistentShieldedActivity) -> Int {
        var score = 0
        if row.kindTag != ShieldedActivityItem.Kind.shieldedSpend.rawValue { score += 100 }
        if row.kindTag != ShieldedActivityItem.Kind.received.rawValue { score += 40 }
        if row.amount > 0 { score += 30 }
        if !row.identityId.isEmpty { score += 20 }
        if !row.counterparty.isEmpty { score += 10 }
        if row.direction == ShieldedActivityItem.Direction.outgoing.rawValue { score += 5 }
        if row.hasBlockHeight { score += 3 }
        score += row.status
        return score
    }

    private static func projectedShieldedAmountCredits(
        for row: PersistentShieldedActivity,
        noteValueByCmx: [Data: UInt64],
        outgoingNoteValueByCmx: [Data: UInt64]
    ) -> UInt64 {
        if row.amount > 0 { return row.amount }

        let incomingCredits = sumChunked32Values(from: row.noteCmxs, using: noteValueByCmx)
        if incomingCredits > 0 { return incomingCredits }

        let outgoingCredits = sumChunked32Values(from: row.noteCmxs, using: outgoingNoteValueByCmx)
        if outgoingCredits > 0 { return outgoingCredits }

        return 0
    }

    private static func matchingCoreInternalTransfer(
        for row: PersistentShieldedActivity,
        amountDuffs: UInt64,
        route: Transaction.InternalTransferRoute,
        in transactions: [Transaction]
    ) -> Transaction? {
        let rowDate = Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000.0)
        let candidates = transactions.filter {
            $0.internalTransferRoute == route
                && isWithinProjectionMatchWindow($0.date, around: rowDate)
        }

        if amountDuffs > 0,
           let exact = candidates.first(where: { $0.dashAmount == amountDuffs }) {
            return exact
        }

        return candidates.count == 1 ? candidates.first : nil
    }

    private static func matchingCoreReceipt(
        amountDuffs: UInt64,
        address: String,
        around date: Date,
        in transactions: [Transaction]
    ) -> Transaction? {
        // Do not require `ShieldedWithdrawalStore` classification here. A
        // restored activity row may be the source that rehydrates that store,
        // while the Core transaction is already persisted and mined.
        let candidates = transactions.filter { transaction in
            transaction.direction == .received
                && transaction.outputReceiveAddresses.contains(address)
        }
        let summaries = candidates.map {
            CoreWithdrawalReceiptCandidate(
                amountDuffs: $0.dashAmount,
                date: $0.date)
        }
        guard let index = CoreWithdrawalReceiptMatchPolicy.selectedIndex(
            expectedAmountDuffs: amountDuffs,
            activityDate: date,
            candidates: summaries)
        else { return nil }
        return candidates[index]
    }

    /// Match the eventual Core receipt without relying on a txid the opaque
    /// shielded-withdraw call does not return. The fresh destination address is
    /// the primary key; principal/time only disambiguate unexpected address
    /// reuse. This tolerates restore-time timestamp skew and amount
    /// reconstruction differences without leaving a mined receipt unmatched.
    private static func hasMatchingCoreReceipt(
        for pending: ShieldedActivityItem,
        address: String,
        in transactions: [Transaction]
    ) -> Bool {
        matchingCoreReceipt(
            amountDuffs: pending.amountDuffs,
            address: address,
            around: pending.date,
            in: transactions) != nil
    }

    private static func isWithinProjectionMatchWindow(_ date: Date, around anchor: Date) -> Bool {
        let delta = date.timeIntervalSince(anchor)
        return delta >= -3600 && delta <= 86_400
    }

    private static func shieldedNoteValueByCmx(
        in context: ModelContext,
        walletId: Data
    ) -> [Data: UInt64] {
        let descriptor = FetchDescriptor<PersistentShieldedNote>(
            predicate: #Predicate { $0.walletId == walletId })
        let rows = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.cmx, $0.value) })
    }

    private static func outgoingShieldedNoteValueByCmx(
        in context: ModelContext,
        walletId: Data
    ) -> [Data: UInt64] {
        let descriptor = FetchDescriptor<PersistentShieldedOutgoingNote>(
            predicate: #Predicate { $0.walletId == walletId })
        let rows = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.cmx, $0.value) })
    }

    private static func sumChunked32Values(
        from data: Data,
        using map: [Data: UInt64]
    ) -> UInt64 {
        guard !data.isEmpty else { return 0 }

        var total: UInt64 = 0
        var index = data.startIndex
        while index < data.endIndex {
            let next = data.index(index, offsetBy: 32, limitedBy: data.endIndex) ?? data.endIndex
            guard data.distance(from: index, to: next) == 32 else { break }
            let chunk = Data(data[index..<next])
            total += map[chunk] ?? 0
            index = next
        }
        return total
    }

    /// Decode an unshield entry's counterparty (21-byte serialized
    /// PlatformAddress) to its bech32m string (`dash1…` / `tdash1…`).
    private static func unshieldDestinationAddress(counterparty: Data) -> String? {
        guard counterparty.count == 21 else { return nil }
        return AddressTransformer.formatAddress(
            counterparty,
            asBech32m: true,
            isTestnet: WalletEnvironment.isTestnet)
    }

    /// Decode a shielded send's counterparty (43-byte raw Orchard address) to
    /// its DIP-0018 display form: HRP `dash`/`tdash`, payload = 0x10 type
    /// byte + the raw address bytes (same encoding as
    /// `PaymentsLandingViewModel.reloadShieldedAddress`). Nil for empty /
    /// non-43-byte counterparties.
    private static func shieldedDestinationAddress(counterparty: Data) -> String? {
        guard counterparty.count == 43 else { return nil }
        return Bech32m.encode(
            hrp: Bech32m.platformHrp(mainnet: !WalletEnvironment.isTestnet),
            data: Data([0x10]) + counterparty)
    }

    /// True when `address` is one of the ACTIVE wallet's own DIP-17
    /// Platform Payment addresses (same active-wallet scoping rationale
    /// as `isActiveWalletCoreAddress`).
    private static func isActiveWalletPlatformAddress(
        _ address: String,
        walletId: Data,
        in context: ModelContext
    ) -> Bool {
        var descriptor = FetchDescriptor<PersistentPlatformAddress>(
            predicate: #Predicate { $0.address == address && $0.walletId == walletId })
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    /// The active wallet's observed incoming Platform-address payments
    /// (app-recorded ledger; see PlatformAddressActivityStore.swift).
    /// Safe from any thread — the DAO's SQLite connection serializes.
    static func fetchPlatformActivity() -> [PlatformAddressActivityItem] {
        let handles: (walletId: Data, networkRaw: Int64)? = onMain {
            guard let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
                  let network = SwiftDashSDKHost.shared.runningNetwork else {
                return nil
            }
            return (walletId, Int64(network.rawValue))
        }
        guard let handles else { return [] }
        return PlatformAddressActivityDAO.shared
            .activities(walletId: handles.walletId, networkRaw: handles.networkRaw)
            .map { PlatformAddressActivityItem(record: $0) }
    }

    /// Decode a withdrawal entry's counterparty (a Core scriptPubKey)
    /// to a Base58Check address. Nil for empty / non-P2PKH/P2SH scripts.
    private static func withdrawalDestinationAddress(counterparty: Data) -> String? {
        guard !counterparty.isEmpty else { return nil }
        let network: PaymentNetwork = WalletEnvironment.isTestnet ? .testnet : .mainnet
        return ScriptAddressCodec.address(forScript: counterparty, network: network)
    }

    /// True when `address` belongs to the ACTIVE wallet's Core address
    /// pools. Scoped to the active wallet on purpose: a withdrawal to
    /// another on-device wallet's address is still external from this
    /// wallet's perspective (this wallet gets no Core receipt row).
    private static func isActiveWalletCoreAddress(
        _ address: String,
        walletId: Data,
        in context: ModelContext
    ) -> Bool {
        var descriptor = FetchDescriptor<PersistentCoreAddress>(
            predicate: #Predicate { $0.address == address })
        descriptor.fetchLimit = 1
        guard let row = (try? context.fetch(descriptor))?.first else { return false }
        return row.account?.wallet.walletId == walletId
    }

    /// Whether an active wallet is configured — the same truth
    /// `fetchCurrentWalletSnapshot() != nil` reports, without materializing
    /// every wallet transaction to learn it.
    static var hasActiveWallet: Bool { hostHandles() != nil }

    /// The host is `@MainActor`-isolated; grab its container + active-wallet
    /// id in one brief main hop (two property reads — unlike the fetches,
    /// cheap enough to block a worker queue on). `ModelContainer` is
    /// `Sendable`, so the caller then opens its own `ModelContext` on its
    /// own thread and all SwiftData work stays there.
    private static func hostHandles() -> (container: ModelContainer, walletId: Data)? {
        onMain {
            guard let container = SwiftDashSDKHost.shared.modelContainer,
                  let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
                return nil
            }
            return (container, walletId)
        }
    }

    /// Main-thread trampoline for the `@MainActor`-isolated host reads.
    /// Internal: `HomeViewModel.coinJoinShieldDestinationAvailable` reuses it
    /// for its host/manager reads.
    static func onMain<T>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(body)
        }
    }

    private static func fetchOne(txid: Data, in context: ModelContext, walletId: Data) -> Transaction? {
        var descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == txid })
        descriptor.fetchLimit = 1
        guard let row = (try? context.fetch(descriptor))?.first,
              isWalletMember(row, walletId: walletId) else {
            return nil
        }
        return wrap(row, walletId: walletId)
    }

    /// Membership can arrive through either side of the SDK's documented
    /// union: wallet-scoped TXOs or an account's involved-transactions
    /// relation. Accept both so an out-of-order receipt is not discarded.
    /// Reads relationships — call on the row's fetch thread.
    /// Internal: also the membership test for the bulk unconfirmed-tx
    /// drop (`UnconfirmedTransactionRemover`).
    static func isWalletMember(_ row: PersistentTransaction, walletId: Data) -> Bool {
        row.outputs.contains(where: { $0.walletId == walletId })
            || row.inputs.contains(where: { $0.walletId == walletId })
            || row.involvedAccounts.contains(where: { $0.wallet.walletId == walletId })
    }

    /// Wrap a fetched row on its fetch thread, stamping the CoinJoin-mixing
    /// classification (cached — see `cachedIsCoinJoinMixingTx`).
    private static func wrap(_ row: PersistentTransaction, walletId: Data) -> Transaction {
        let tx = Transaction(persistentTransaction: row, walletId: walletId)
        tx.sdkCoinJoinMixing = cachedIsCoinJoinMixingTx(row)
        return tx
    }

    /// SQL-scoped timeline fetch: wallet membership is evaluated inside the
    /// store (EXISTS subqueries over the indexed `PersistentTxo.walletId`
    /// denorm and the `involvedAccounts` join) while scanning the `firstSeen`
    /// index newest-first, so only the returned rows are ever materialized —
    /// unlike the full-wallet pass, whose cost is the whole history no matter
    /// how few rows the caller needs.
    ///
    /// If SwiftData fails to translate the membership predicate (an OS
    /// regression, not a data state), the fetch throws and we fall back to
    /// the full-wallet pass — same results, old cost — and log it so the
    /// regression is visible instead of silent.
    private static func scopedNewestFirst(
        in context: ModelContext,
        walletId: Data,
        minFirstSeen: UInt64,
        limit: Int?
    ) -> [Transaction] {
        do {
            return try scopedRows(
                in: context, walletId: walletId,
                minFirstSeen: minFirstSeen, maxFirstSeen: .max,
                updatedAfter: .distantPast, limit: limit)
                .map { wrap($0, walletId: walletId) }
        } catch {
            DWLogger.log("SwiftDashSDKWalletSource: scoped fetch failed (\(error)); falling back to the full wallet pass")
            return fetchAndWrap(in: context, walletId: walletId, minFirstSeen: minFirstSeen, limit: limit)
        }
    }

    /// The shared raw timeline fetch every scoped path goes through: wallet
    /// membership evaluated inside the store, a `firstSeen` range against its
    /// index, an update-stamp floor for delta reconciles, sorted newest-first
    /// with the wrap's relationships prefetched. Throws on predicate
    /// translation failure — callers fall back to the full wallet pass.
    private static func scopedRows(
        in context: ModelContext,
        walletId: Data,
        minFirstSeen: UInt64,
        maxFirstSeen: UInt64,
        updatedAfter: Date,
        limit: Int?
    ) throws -> [PersistentTransaction] {
        // UInt64 round-trips through SQLite's signed Int64: a bound above
        // Int64.max (the `.max` "no upper bound" sentinel) would compare as
        // a NEGATIVE number and match nothing. Clamp — every real timestamp
        // is far below Int64.max, so the clamped bound is still unbounded
        // in practice.
        let maxFirstSeen = min(maxFirstSeen, UInt64(Int64.max))
        var descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { tx in
                tx.firstSeen >= minFirstSeen && tx.firstSeen <= maxFirstSeen
                    && tx.lastUpdated > updatedAfter
                    && (tx.outputs.contains(where: { $0.walletId == walletId })
                        || tx.inputs.contains(where: { $0.walletId == walletId })
                        || tx.involvedAccounts.contains(where: { $0.wallet.walletId == walletId }))
            },
            sortBy: [SortDescriptor(\.firstSeen, order: .reverse)])
        if let limit { descriptor.fetchLimit = limit }
        descriptor.relationshipKeyPathsForPrefetching = [\.outputs, \.inputs]
        return try context.fetch(descriptor)
    }

    /// Whether any wallet row exists at/below `firstSeen` — the "is there
    /// older history" probe behind `WalletTimelineWindow.hasOlderHistory`.
    /// `fetchLimit = 1`, so at most one row is materialized.
    private static func scopedRowExists(
        in context: ModelContext,
        walletId: Data,
        firstSeenAtOrBelow: UInt64
    ) throws -> Bool {
        var descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { tx in
                tx.firstSeen <= firstSeenAtOrBelow
                    && (tx.outputs.contains(where: { $0.walletId == walletId })
                        || tx.inputs.contains(where: { $0.walletId == walletId })
                        || tx.involvedAccounts.contains(where: { $0.wallet.walletId == walletId }))
            })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    /// The home feed's day-completed first page. Safe from any thread.
    static func fetchTimelineWindow(targetRowCount: Int) -> WalletTimelineWindow? {
        guard let (container, walletId) = hostHandles() else { return nil }
        return timelinePage(
            in: ModelContext(container), walletId: walletId,
            maxFirstSeen: .max, targetRowCount: targetRowCount)
    }

    /// The next day-completed page strictly below `dayStartCutoff` (a
    /// previous window's `oldestLoadedDayStart`). Safe from any thread.
    static func fetchOlderTimelinePage(
        endingBefore dayStartCutoff: UInt64,
        targetRowCount: Int
    ) -> WalletTimelineWindow? {
        guard dayStartCutoff > 0, let (container, walletId) = hostHandles() else { return nil }
        return timelinePage(
            in: ModelContext(container), walletId: walletId,
            maxFirstSeen: dayStartCutoff - 1, targetRowCount: targetRowCount)
    }

    /// One timeline page ending at `maxFirstSeen`: fetch `targetRowCount`
    /// rows newest-first, then extend to the start of the boundary row's
    /// calendar day so the page never splits a day. `firstSeen` serves as
    /// both the paging key and the day key — the persister adopts the block
    /// timestamp once a tx is mined, so for settled history it equals the
    /// display date the feed groups by.
    private static func timelinePage(
        in context: ModelContext,
        walletId: Data,
        maxFirstSeen: UInt64,
        targetRowCount: Int
    ) -> WalletTimelineWindow {
        do {
            var rows = try scopedRows(
                in: context, walletId: walletId,
                minFirstSeen: 0, maxFirstSeen: maxFirstSeen,
                updatedAfter: .distantPast, limit: targetRowCount)
            var oldestLoadedDayStart: UInt64 = 0
            var hasOlderHistory = false
            if rows.count >= targetRowCount, let boundary = rows.last?.firstSeen {
                let dayStart = UInt64(max(0, Calendar.current.startOfDay(
                    for: Date(timeIntervalSince1970: TimeInterval(boundary))).timeIntervalSince1970))
                // Finish the boundary day — unconditionally: even when the
                // boundary row sits exactly at midnight, same-stamp rows
                // (same-block bursts) can have been cut off by the fetch
                // limit. The range re-includes rows already fetched at the
                // boundary stamp, so drop the known txids.
                let seen = Set(rows.map(\.txid))
                let tail = try scopedRows(
                    in: context, walletId: walletId,
                    minFirstSeen: dayStart, maxFirstSeen: boundary,
                    updatedAfter: .distantPast, limit: nil)
                    .filter { !seen.contains($0.txid) }
                rows += tail
                if dayStart > 0,
                   try scopedRowExists(in: context, walletId: walletId, firstSeenAtOrBelow: dayStart - 1) {
                    oldestLoadedDayStart = dayStart
                    hasOlderHistory = true
                }
            }
            return WalletTimelineWindow(
                walletId: walletId,
                transactions: rows.map { wrap($0, walletId: walletId) },
                oldestLoadedDayStart: oldestLoadedDayStart,
                hasOlderHistory: hasOlderHistory,
                maxLastUpdated: rows.map(\.lastUpdated).max())
        } catch {
            DWLogger.log("SwiftDashSDKWalletSource: timeline page fetch failed (\(error)); falling back to the full wallet pass")
            return WalletTimelineWindow(
                walletId: walletId,
                transactions: fetchAndWrap(in: context, walletId: walletId),
                oldestLoadedDayStart: 0,
                hasOlderHistory: false,
                maxLastUpdated: nil)
        }
    }

    /// Rows changed after `stamp` within the loaded window (`firstSeen >=
    /// dayStart`) — the home feed's save-tick reconcile. With `stamp ==
    /// .distantPast` this is a complete re-read of the window and the caller
    /// replaces its cache (which is how deletions become visible). Falls
    /// back to the full wallet pass if the predicate ever fails to
    /// translate. Safe from any thread.
    static func fetchTimelineDelta(
        updatedAfter stamp: Date,
        notBefore dayStart: UInt64
    ) -> WalletTimelineDelta? {
        guard let (container, walletId) = hostHandles() else { return nil }
        let context = ModelContext(container)
        do {
            let rows = try scopedRows(
                in: context, walletId: walletId,
                minFirstSeen: dayStart, maxFirstSeen: .max,
                updatedAfter: stamp, limit: nil)
            return WalletTimelineDelta(
                transactions: rows.map { wrap($0, walletId: walletId) },
                maxLastUpdated: rows.map(\.lastUpdated).max(),
                isCompleteWindow: stamp == .distantPast)
        } catch {
            DWLogger.log("SwiftDashSDKWalletSource: timeline delta fetch failed (\(error)); falling back to the full wallet pass")
            return WalletTimelineDelta(
                transactions: fetchAndWrap(in: context, walletId: walletId, minFirstSeen: dayStart),
                maxLastUpdated: nil,
                isCompleteWindow: true)
        }
    }

    /// Whole-history "has any coinbase / masternode special tx" answers for
    /// the home filter's Rewards / Masternode rows, probed with
    /// `fetchLimit = 1` existence queries — at most one row materialized
    /// each, never a wrapped history. Matches the wrapper rules exactly:
    /// `Transaction.isCoinbaseTransaction` / `isMasternodeTransaction` are
    /// pure `transactionTypeKind` checks. Nil when no wallet is active or a
    /// probe fails (callers keep their previous answer). Safe from any thread.
    static func fetchFilterCategoryGates() -> (hasRewards: Bool, hasMasternodes: Bool)? {
        guard let (container, walletId) = hostHandles() else { return nil }
        let context = ModelContext(container)
        let coinbase = coinbaseKindRaw
        let providers = providerKindRaws
        var rewardsDescriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { tx in
                tx.transactionTypeKind == coinbase
                    && (tx.outputs.contains(where: { $0.walletId == walletId })
                        || tx.inputs.contains(where: { $0.walletId == walletId })
                        || tx.involvedAccounts.contains(where: { $0.wallet.walletId == walletId }))
            })
        rewardsDescriptor.fetchLimit = 1
        var masternodeDescriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { tx in
                providers.contains(tx.transactionTypeKind)
                    && (tx.outputs.contains(where: { $0.walletId == walletId })
                        || tx.inputs.contains(where: { $0.walletId == walletId })
                        || tx.involvedAccounts.contains(where: { $0.wallet.walletId == walletId }))
            })
        masternodeDescriptor.fetchLimit = 1
        do {
            let hasRewards = try !context.fetch(rewardsDescriptor).isEmpty
            let hasMasternodes = try !context.fetch(masternodeDescriptor).isEmpty
            return (hasRewards, hasMasternodes)
        } catch {
            DWLogger.log("SwiftDashSDKWalletSource: filter-gate probe failed (\(error))")
            return nil
        }
    }

    /// `TransactionTypeKind` raw values the filter-gate probes match on —
    /// captured outside the predicates (`#Predicate` bodies can't call
    /// `rawValue`).
    private static let coinbaseKindRaw = TransactionTypeKind.coinbase.rawValue
    private static let providerKindRaws = [
        TransactionTypeKind.providerRegistration.rawValue,
        TransactionTypeKind.providerUpdateRegistrar.rawValue,
        TransactionTypeKind.providerUpdateService.rawValue,
        TransactionTypeKind.providerUpdateRevocation.rawValue,
    ]

    /// Everything a wallet-wide wrap needs from the TXO table, computed in
    /// one indexed scan with relationships prefetched: the member-txid union
    /// AND the per-tx CoinJoin-account roles. Replaces the previous shape —
    /// a txid walk plus a per-row `isCoinJoinMixingTx` traversal — whose
    /// per-row relationship faults each cost a separate store round-trip
    /// (multiple seconds of SwiftData CPU on a CoinJoin-heavy wallet).
    private struct WalletTxRollup {
        /// Every txid the wallet participates in: the canonical TXO union
        /// plus `PersistentAccount.involvedTransactions` (payload-only
        /// membership — see the SDK model doc on `PersistentTransaction`).
        var txids: Set<Data> = []
        /// Txids classified as CoinJoin mixing operations — the same rules
        /// as `isCoinJoinMixingTx`, evaluated from the wallet's own TXO
        /// roles (matching DashSync's per-wallet-account grouping; another
        /// on-device wallet's stake in a shared tx doesn't classify ours).
        var mixingTxids: Set<Data> = []
    }

    private static func walletTxRollup(in context: ModelContext, walletId: Data) -> WalletTxRollup {
        var txoDescriptor = FetchDescriptor<PersistentTxo>(
            predicate: #Predicate { $0.walletId == walletId })
        txoDescriptor.relationshipKeyPathsForPrefetching = [
            \.transaction, \.spendingTransaction, \.coreAddress, \.account,
        ]
        let txos = (try? context.fetch(txoDescriptor)) ?? []

        var rollup = WalletTxRollup()
        // The three classification ingredients (rules 1–3 of
        // `isCoinJoinMixingTx`), accumulated per txid.
        var kindOrDepositMixing: Set<Data> = []
        var spendsCoinJoin: Set<Data> = []
        var depositsToStandard: Set<Data> = []
        for txo in txos {
            let ownerType = ownerAccountType(txo)
            if let producing = txo.transaction {
                rollup.txids.insert(producing.txid)
                if producing.typedKind == .coinJoin || ownerType == coinJoinAccountType {
                    kindOrDepositMixing.insert(producing.txid)
                }
                if ownerType == standardAccountType {
                    depositsToStandard.insert(producing.txid)
                }
            }
            if let spending = txo.spendingTransaction {
                rollup.txids.insert(spending.txid)
                if spending.typedKind == .coinJoin {
                    kindOrDepositMixing.insert(spending.txid)
                }
                if ownerType == coinJoinAccountType {
                    spendsCoinJoin.insert(spending.txid)
                }
            }
        }
        rollup.mixingTxids = kindOrDepositMixing
            .union(spendsCoinJoin.subtracting(depositsToStandard))

        // Payload-only membership (e.g. a ProRegTx matched purely through
        // its payload keys) is only representable via
        // `PersistentAccount.involvedTransactions`; union it in, as the SDK
        // model requires. Nearly every row here is already realized by the
        // TXO prefetch above, so this walk no longer faults the store per tx.
        var walletDescriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId })
        walletDescriptor.fetchLimit = 1
        if let wallet = (try? context.fetch(walletDescriptor))?.first {
            for account in wallet.accounts {
                for transaction in account.involvedTransactions {
                    rollup.txids.insert(transaction.txid)
                    if transaction.typedKind == .coinJoin {
                        rollup.mixingTxids.insert(transaction.txid)
                    }
                }
            }
        }
        return rollup
    }

    private static func fetchAndWrap(
        in context: ModelContext,
        walletId: Data,
        minFirstSeen: UInt64 = 0,
        limit: Int? = nil
    ) -> [Transaction] {
        let rollup = walletTxRollup(in: context, walletId: walletId)
        guard !rollup.txids.isEmpty else { return [] }
        let txids = rollup.txids
        var descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { txids.contains($0.txid) && $0.firstSeen >= minFirstSeen },
            sortBy: [SortDescriptor(\.firstSeen, order: .reverse)])
        if let limit { descriptor.fetchLimit = limit }
        // Prefetch what the wrap reads (`SDKSnapshot` walks `outputs` +
        // `inputs`) — without this every wrapped row costs two more store
        // round-trips.
        descriptor.relationshipKeyPathsForPrefetching = [\.outputs, \.inputs]
        let rows: [PersistentTransaction]
        do {
            rows = try context.fetch(descriptor)
        } catch {
            DWLogger.log("HomeViewModel: PersistentTransaction fetch failed: \(error)")
            return []
        }
        return rows.map { row -> Transaction in
            let tx = Transaction(persistentTransaction: row, walletId: walletId)
            let isMixing = rollup.mixingTxids.contains(row.txid)
            tx.sdkCoinJoinMixing = isMixing
            // Seed the per-row cache so subsequent scoped fetches skip the
            // relationship traversal for rows this pass already classified.
            storeMixingClassification(txid: row.txid, stamp: row.lastUpdated, isMixing: isMixing)
            return tx
        }
    }

    // PersistentAccount.accountType discriminants (stable across releases).
    private static let coinJoinAccountType: UInt32 = 1 // 0=Standard(BIP44/BIP32), 1=CoinJoin
    private static let standardAccountType: UInt32 = 0

    /// CoinJoin-mixing classification cache for the per-row (scoped) fetch
    /// paths, keyed by txid and stamped with the row's `lastUpdated` — the
    /// persistence handler bumps that on every re-upsert, so an entry
    /// self-invalidates the next time the SDK actually rewrites the row.
    /// Guarded by `mixingCacheLock` (entries are written from whichever
    /// thread fetched the row). Capacity-bounded: population tracks wallet
    /// size, and blowing the bound just resets to a cold cache.
    private static let mixingCacheLock = NSLock()
    private static var mixingCache: [Data: (stamp: Date, isMixing: Bool)] = [:]
    private static let mixingCacheCapacity = 20_000

    private static func storeMixingClassification(txid: Data, stamp: Date, isMixing: Bool) {
        mixingCacheLock.lock()
        defer { mixingCacheLock.unlock() }
        if mixingCache.count >= mixingCacheCapacity, mixingCache[txid] == nil {
            mixingCache.removeAll(keepingCapacity: true)
        }
        mixingCache[txid] = (stamp, isMixing)
    }

    /// Cached front for `isCoinJoinMixingTx` on the scoped fetch paths: a
    /// hit skips the relationship traversal entirely; a miss computes and
    /// seeds. Must run on the row's fetch thread (the compute path traverses
    /// relationships). The full-wallet pass doesn't call this — it derives
    /// every classification from its single TXO scan and seeds the cache.
    private static func cachedIsCoinJoinMixingTx(_ row: PersistentTransaction) -> Bool {
        let txid = row.txid
        let stamp = row.lastUpdated
        mixingCacheLock.lock()
        let hit = mixingCache[txid]
        mixingCacheLock.unlock()
        if let hit, hit.stamp == stamp { return hit.isMixing }
        let isMixing = isCoinJoinMixingTx(row)
        storeMixingClassification(txid: txid, stamp: stamp, isMixing: isMixing)
        return isMixing
    }

    /// Account type owning a TXO — canonical path is `coreAddress?.account`;
    /// `account` is the fallback used before the address row is linked.
    private static func ownerAccountType(_ txo: PersistentTxo) -> UInt32? {
        (txo.coreAddress?.account ?? txo.account)?.accountType
    }

    /// CoinJoin mixing-operation detection. Traverses SwiftData relationships,
    /// so it must run on the thread that owns the row's `ModelContext` (the
    /// fetch thread). Called per row only on scoped-fetch cache misses (see
    /// `cachedIsCoinJoinMixingTx`); the full-wallet pass evaluates these same
    /// rules set-wise in `walletTxRollup` — keep the two in lockstep.
    /// DashSync grouped by CoinJoin-account *role*, not tx
    /// structure, so the SDK's structural `typedKind` (mixing rounds only) is
    /// too narrow. We classify a tx as a mixing operation when:
    ///   1. it DEPOSITS into the CoinJoin account (≥1 CoinJoin output) — covers
    ///      create-denomination, make-collateral-inputs and the mixing rounds; or
    ///   2. it SPENDS from the CoinJoin account (≥1 CoinJoin input) and deposits
    ///      nothing into a Standard (BIP44/BIP32) account — i.e. a mixing-fee /
    ///      collateral spend (the tiny "Sent 0.0001" txs). A Standard output
    ///      marks the CoinJoin→BIP44 sweep or an internal transfer out, which
    ///      must stay an individual row — matching DashSync's "Send" exclusion.
    private static func isCoinJoinMixingTx(_ p: PersistentTransaction) -> Bool {
        if p.typedKind == .coinJoin { return true }
        if p.outputs.contains(where: { ownerAccountType($0) == coinJoinAccountType }) {
            return true
        }
        let spendsCoinJoin = p.inputs.contains { ownerAccountType($0) == coinJoinAccountType }
        guard spendsCoinJoin else { return false }
        let depositsToStandard = p.outputs.contains { ownerAccountType($0) == standardAccountType }
        return !depositsToStandard
    }
}

#if DEBUG
private struct HomeViewModelPreviewTransactionSource: TransactionSource {
    var allTransactions: [Transaction] { [] }
}
#endif

/// SDK identity data is authoritative for Join DashPay visibility. The
/// DWGlobalOptions fields are a legacy UI mirror and are deliberately cleared
/// at the start of every network switch; requiring that mirror before reading
/// the SDK username creates a short-circuit where the mirror can never
/// self-heal after returning to a network with an existing identity.
enum JoinDashPayRegistrationPolicy {
    static func hasRegisteredUsername(
        hasIdentity: Bool,
        sdkUsername: String?,
        legacyRegistrationCompleted: Bool,
        legacyUsername: String?
    ) -> Bool {
        // The legacy mirror is global, while identities are network-scoped.
        // It can only be a fallback for an identity that exists in the
        // currently-bound SDK context.
        guard hasIdentity else {
            return false
        }
        if sdkUsername?.isEmpty == false {
            return true
        }
        return legacyRegistrationCompleted && legacyUsername?.isEmpty == false
    }
}

enum JoinDashPayBannerPolicy {
    static func shouldShow(
        contextReady: Bool,
        syncDone: Bool,
        dismissed: Bool,
        hasRegisteredUsername: Bool,
        hasRegistrationInProgress: Bool
    ) -> Bool {
        contextReady &&
            syncDone &&
            !dismissed &&
            !hasRegisteredUsername &&
            !hasRegistrationInProgress
    }
}

// MARK: - DashPay

#if DASHPAY
extension HomeViewModel {
    func checkJoinDashPay() {
        let options = DWGlobalOptions.sharedInstance()
        // Read the network-scoped SDK truth unconditionally.
        let identityState = MainActor.assumeIsolated {
            let identity = DWCurrentUserIdentityInfo.shared
            return (
                contextReady: identity.isCurrentNetworkContextReady,
                hasIdentity: identity.hasIdentity,
                username: identity.username
            )
        }
        let hasRegisteredUsername = JoinDashPayRegistrationPolicy.hasRegisteredUsername(
            hasIdentity: identityState.hasIdentity,
            sdkUsername: identityState.username,
            legacyRegistrationCompleted: options.dashpayRegistrationCompleted,
            legacyUsername: options.dashpayUsername)
        // Dismissal is persisted per active wallet + network. It is valid
        // before an identity exists and remains valid when readiness is
        // re-evaluated or the user leaves and returns to this network.
        let identityScopedRegistrationState =
            identityState.hasIdentity &&
            (joinDashPayState == .voting || joinDashPayState == .registered)

        self.showJoinDashpay = JoinDashPayBannerPolicy.shouldShow(
            contextReady: identityState.contextReady,
            syncDone: syncModel.state == .syncDone,
            dismissed: UsernamePrefs.shared.joinDashPayDismissed,
            hasRegisteredUsername: hasRegisteredUsername,
            hasRegistrationInProgress: identityScopedRegistrationState)
    }
    
    private func observeDashPay() {
        NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)
            .sink { [weak self] _ in
                self?.checkJoinDashPay()
                self?.reloadTxsAndShortcuts()
                // Row #18: contact syncing is owned by the SDK DashPay
                // sync loop (PlatformAddressSyncCoordinator).
            }
            .store(in: &cancellableBag)

        // The reload above fires when the identity is adopted, which is before
        // the DashPay sync loop has had a pass to fetch anything — so it runs
        // against an empty payment lookup and was the only DashPay-aware
        // trigger the feed had. The payments themselves land later, written by
        // an app-pulled projection into entities `saveTouchesFeedRows` filters
        // out, and are read through a computed property on rows that were
        // already rendered. Without this the feed kept dash-spv's misread
        // direction and a nameless contact for the rest of the session. The
        // lookup posts only on a real change, so this is not a periodic reload.
        NotificationCenter.default.publisher(for: DashPayPaymentTxLookup.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.txReloadRequests.send()
            }
            .store(in: &cancellableBag)
    }
}
#endif
