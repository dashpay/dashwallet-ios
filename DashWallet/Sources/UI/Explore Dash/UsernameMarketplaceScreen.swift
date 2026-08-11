//
//  UsernameMarketplaceScreen.swift
//  DashWallet
//
//  DPNS username marketplace (Explore tab) over the wallet-level SDK
//  surface (platform #4348): search any name with live sale state, see
//  the names on your identity — including ones that were sold or
//  transferred away — list/re-price/delist yours, buy listed ones with
//  the price pinned at confirmation, gift-transfer, register unclaimed
//  non-contested labels, and read each name's full trade timeline.
//
//  Names offered by other identities are explicitly labeled as sold by
//  an independent user: prices are set by sellers, not by Dash or this
//  app, and the UI says so on the row, in the detail sheet, and in the
//  purchase confirmation.
//
//  Search-driven by design: `$price` is not an indexable system
//  property on Dash Platform, so a global "everything for sale" browse
//  is not buildable at any layer today.
//
//  dashpay target only.
//

import SwiftUI
import SwiftDashSDK
import DashUIKit
import UIKit

// MARK: - UsernameMarketplaceViewModel

@MainActor
final class UsernameMarketplaceViewModel: ObservableObject {

    enum Segment: Int, CaseIterable {
        case find
        case mine
        case browse

        var title: String {
            switch self {
            case .find: return NSLocalizedString("Find Names", comment: "Username marketplace: search segment")
            case .mine: return NSLocalizedString("My Names", comment: "Username marketplace: owned names segment")
            case .browse: return NSLocalizedString("Browse", comment: "Username marketplace: browse-for-sale segment")
            }
        }
    }

    enum BrowseFeed: Int, CaseIterable {
        case priceChanges
        case purchases

        var title: String {
            switch self {
            case .priceChanges: return NSLocalizedString("Price changes", comment: "Username marketplace: browse feed of recent listings and re-prices")
            case .purchases: return NSLocalizedString("Purchases", comment: "Username marketplace: browse feed of recent sales")
            }
        }
    }

    /// One rendered browse-feed row: the historical event plus the
    /// name's label and live state (from the batched domain read).
    struct BrowseEventRow: Identifiable {
        let id: String
        let label: String
        let event: UsernameMarketplaceService.MarketplaceEvent
        let live: UsernameMarketplaceService.LiveDomainName?
    }

    @Published var segment: Segment = .find
    @Published var query = ""
    @Published var searchResults: [DpnsMarketplaceName] = []
    @Published var myNames: [DpnsNameStateRow] = []
    /// Labels this identity is contending for in active network votes.
    @Published var contestedNames: [String] = []
    /// Live vote state per contested label, filled best-effort — a label
    /// with no entry is a contest Platform hasn't indexed yet.
    @Published var contestStates: [String: ContestVoteState] = [:]
    @Published var isSearching = false
    @Published var isLoadingMine = false
    @Published var isPerformingAction = false
    /// Non-nil while a trade action runs: what the wallet is doing right
    /// now ("Submitting your username request…"). Drives the blocking
    /// spinner overlay.
    @Published var activityMessage: String?
    @Published var errorMessage: String?
    /// Transient success line ("hilawe listed for 0.05 DASH").
    @Published var successMessage: String?
    /// The typed query as a registrable label: valid DPNS label shape
    /// AND no document exists for its normalized form. Set by
    /// `updateSearch` using the SDK's own normalizer (DPNS folds
    /// look-alike characters, so a plain lowercase compare would lie).
    @Published var registrableQueryLabel: String?
    /// Network contest state of a contested-eligible `registrableQueryLabel`,
    /// filled best-effort after the search results land. A label with no
    /// DPNS document can still be mid-vote — without this the row would
    /// claim "Available" for a name already being contested.
    @Published var queryContest: UsernameMarketplaceService.ContestPrecheck?

    // MARK: Browse (recent activity) state
    //
    // `$price` is not indexable on Dash Platform, so no query at any
    // layer can order names by price. What the document-history system
    // contract DOES index is RECENCY ([dataContractId, $createdAt]) —
    // so Browse is an honest activity feed: recent price changes
    // (listings / re-prices) and recent purchases, newest first. Each
    // event's price and time are historical facts shown as such; each
    // row also resolves the name's LIVE state for what's true now.

    @Published var browseFeed: BrowseFeed = .priceChanges
    @Published var browsePriceChanges: [BrowseEventRow] = []
    @Published var browsePurchases: [BrowseEventRow] = []
    @Published var isBrowseLoading = false
    @Published var browsePriceChangesExhausted = false
    @Published var browsePurchasesExhausted = false

    /// Per-feed pagination cursors: oldest $createdAt fetched so far.
    /// The service pages with "<=" (a timestamp can span many events),
    /// so pages overlap at the boundary; `browseSeenEventIds` dedupes.
    private var priceChangesCursorMs: UInt64?
    private var purchasesCursorMs: UInt64?
    private var browseSeenEventIds: Set<String> = []
    /// documentId → live domain state, shared across both feeds and
    /// filled by ONE batched read per page — a page costs exactly two
    /// platform queries (events + batched $id lookup) regardless of size.
    private var browseNameCache: [String: UsernameMarketplaceService.LiveDomainName] = [:]
    /// In-flight load — cancelled by a reset so pull-to-refresh can
    /// always restart, never silently bounce off the busy guard. The
    /// generation counter keeps a cancelled task's cleanup from clearing
    /// the loading flag of the load that replaced it.
    private var browseTask: Task<Void, Never>?
    private var browseLoadGeneration = 0
    private static let browseEventsPerPage: UInt32 = 25

    var browseRows: [BrowseEventRow] {
        browseFeed == .priceChanges ? browsePriceChanges : browsePurchases
    }

    var browseFeedExhausted: Bool {
        browseFeed == .priceChanges ? browsePriceChangesExhausted : browsePurchasesExhausted
    }

    /// Load the next page of the CURRENT feed. `reset` cancels any
    /// in-flight load and restarts both feeds from the newest event
    /// (pull-to-refresh) so live states and prices re-read fresh.
    func loadBrowse(reset: Bool = false) {
        if reset {
            browseTask?.cancel()
            browsePriceChanges = []
            browsePurchases = []
            priceChangesCursorMs = nil
            purchasesCursorMs = nil
            browsePriceChangesExhausted = false
            browsePurchasesExhausted = false
            browseSeenEventIds = []
            browseNameCache = [:]
        } else {
            guard !isBrowseLoading else { return }
        }
        let feed = browseFeed
        guard !browseFeedExhausted else { return }
        isBrowseLoading = true
        browseLoadGeneration += 1
        let generation = browseLoadGeneration
        browseTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.browseLoadGeneration == generation {
                    self.isBrowseLoading = false
                }
            }
            do {
                // Price changes is a FOR-SALE feed: rows whose name was
                // since delisted or sold are dropped, and each name
                // renders once (its newest event — whose price, by
                // consensus, IS the live price of a still-listed name).
                // Dropped rows can leave a page thin, so keep paging
                // within a bounded pass until something showed.
                var pagesLeft = feed == .priceChanges ? 4 : 1
                while pagesLeft > 0 {
                    pagesLeft -= 1
                    let cursor = feed == .priceChanges ? priceChangesCursorMs : purchasesCursorMs
                    let rawEvents = feed == .priceChanges
                        ? try await service.recentPriceChanges(beforeMs: cursor, limit: Self.browseEventsPerPage)
                        : try await service.recentPurchases(beforeMs: cursor, limit: Self.browseEventsPerPage)
                    guard !Task.isCancelled else { return }
                    // Boundary rows reappear by design (the "<=" cursor);
                    // the event-id set drops what was already consumed.
                    let events = rawEvents.filter { !browseSeenEventIds.contains($0.eventIdBase58) }
                    events.forEach { browseSeenEventIds.insert($0.eventIdBase58) }
                    // One batched $id lookup covers every name this page
                    // mentions that we haven't resolved yet.
                    let unknownIds = Array(Set(events.map(\.dpnsDocumentIdBase58)
                        .filter { browseNameCache[$0] == nil }))
                    if !unknownIds.isEmpty {
                        for (id, live) in try await service.liveDomainNames(forDocumentIds: unknownIds) {
                            browseNameCache[id] = live
                        }
                    }
                    guard !Task.isCancelled else { return }
                    var rows: [BrowseEventRow] = []
                    for event in events {
                        // Absent from the batch = the document is gone.
                        guard let live = browseNameCache[event.dpnsDocumentIdBase58] else { continue }
                        let row = BrowseEventRow(
                            id: event.eventIdBase58,
                            label: live.label,
                            event: event,
                            live: live)
                        if feed == .priceChanges {
                            guard live.isForSale,
                                  !browsePriceChanges.contains(where: { $0.event.dpnsDocumentIdBase58 == event.dpnsDocumentIdBase58 }),
                                  !rows.contains(where: { $0.event.dpnsDocumentIdBase58 == event.dpnsDocumentIdBase58 })
                            else { continue }
                        }
                        rows.append(row)
                    }
                    // Exhaustion reads the RAW page: a short page means the
                    // trail ended. A full page of only-seen rows means the
                    // cursor cannot advance (>page-size events sharing one
                    // timestamp) — stop rather than spin.
                    let exhausted = rawEvents.count < Int(Self.browseEventsPerPage)
                        || (events.isEmpty && rawEvents.count == Int(Self.browseEventsPerPage))
                    if feed == .priceChanges {
                        browsePriceChanges.append(contentsOf: rows)
                        priceChangesCursorMs = rawEvents.last?.createdAtMs ?? cursor
                        if exhausted { browsePriceChangesExhausted = true }
                    } else {
                        browsePurchases.append(contentsOf: rows)
                        purchasesCursorMs = rawEvents.last?.createdAtMs ?? cursor
                        if exhausted { browsePurchasesExhausted = true }
                    }
                    if exhausted || !rows.isEmpty { break }
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = UsernameMarketplaceService.userFacingMessage(for: error)
            }
        }
    }

    /// Awaitable refresh for `.refreshable` — the spinner stays until
    /// the restarted load actually finishes.
    func refreshBrowse() async {
        loadBrowse(reset: true)
        await browseTask?.value
    }

    let service = UsernameMarketplaceService()
    private var searchTask: Task<Void, Never>?

    var ownIdentityId: Data? { DWCurrentUserIdentityInfo.shared.identityId }

    var ownedNames: [DpnsNameStateRow] {
        myNames.filter { if case .owned = $0.status { return true }; return false }
    }

    /// Retained rows for names that left this identity — sold or
    /// transferred away — kept by the SDK so the departure is visible.
    var departedNames: [DpnsNameStateRow] {
        myNames.filter { if case .owned = $0.status { return false }; return true }
    }

    /// DPNS label shape: 3–63 characters, ASCII letters/digits/hyphen,
    /// no leading or trailing hyphen. ASCII only — `isLetter` alone
    /// would admit unregistrable labels like "café".
    static func isValidLabel(_ label: String) -> Bool {
        guard (3...63).contains(label.count) else { return false }
        guard label.first != "-", label.last != "-" else { return false }
        return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    func updateSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            registrableQueryLabel = nil
            queryContest = nil
            isSearching = false
            return
        }
        searchResults = []
        registrableQueryLabel = nil
        queryContest = nil
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            do {
                let results = try await service.search(prefix: trimmed)
                guard !Task.isCancelled else { return }
                searchResults = results
                if UsernameMarketplaceViewModel.isValidLabel(trimmed),
                   let sdk = SwiftDashSDKHost.shared.sdk {
                    let normalized = (try? sdk.dpnsNormalizeLabel(trimmed)) ?? trimmed.lowercased()
                    registrableQueryLabel = results.contains { $0.normalizedLabel == normalized }
                        ? nil
                        : trimmed
                } else {
                    registrableQueryLabel = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = UsernameMarketplaceService.userFacingMessage(for: error)
            }
            isSearching = false
            // A contested-eligible unregistered label can already be
            // mid-vote (no document exists until the vote resolves) —
            // check after the row is showing and refine its subtitle.
            // Skipped for own requests: those are answered locally.
            if let candidate = registrableQueryLabel,
               UsernameMarketplaceService.isContested(candidate),
               !hasRequestedContest(for: candidate) {
                let state = await service.contestPrecheck(label: candidate)
                guard !Task.isCancelled, registrableQueryLabel == candidate else { return }
                queryContest = state
            }
        }
    }

    /// This identity already has a contested request in for `label` — from
    /// the SDK's contested-names cache, or the app's submission bookmark
    /// when that cache hasn't synced yet.
    func hasRequestedContest(for label: String) -> Bool {
        contestedNames.contains { DWContestedNameStatusService.labelsMatch($0, label) }
            || DWContestedNameStatusService.shared.isPendingLabel(label)
    }

    /// The variant the user actually typed for a contested label the
    /// network reports in NORMALIZED form — DPNS folds look-alike
    /// characters (i/l → 1, o → 0), so requesting "quiet" registers
    /// "qu1et". Recovered from the submission bookmarks by normalizing
    /// each through the SDK; nil when no bookmark differs from the
    /// normalized form (nothing worth showing twice).
    func requestedVariant(forNormalized label: String) -> String? {
        guard let sdk = SwiftDashSDKHost.shared.sdk else { return nil }
        let target = label.lowercased()
        for pending in DWContestedNameStatusService.shared.pendingLabels {
            guard pending.lowercased() != target else { continue }
            let normalized = (try? sdk.dpnsNormalizeLabel(pending)) ?? pending.lowercased()
            if normalized == target {
                return pending
            }
        }
        return nil
    }

    /// Local read — the wallet's own tracked rows plus the contested
    /// labels cache, no network. Vote states for contested labels are
    /// filled in best-effort afterward (those are live queries).
    func loadMyNames() {
        isLoadingMine = true
        Task { [weak self] in
            guard let self else { return }
            do {
                myNames = try await service.myNames()
            } catch {
                errorMessage = UsernameMarketplaceService.userFacingMessage(for: error)
            }
            contestedNames = await service.myContestedNames()
            isLoadingMine = false
            for label in contestedNames where contestStates[label] == nil {
                if let state = await service.contestState(label: label) {
                    contestStates[label] = state
                }
            }
        }
    }

    /// Pull-to-refresh: run one marketplace sync pass and refresh the
    /// contested cache, then re-read the local rows.
    func refreshFromNetwork() async {
        do {
            _ = try await service.syncNow()
        } catch {
            errorMessage = UsernameMarketplaceService.userFacingMessage(for: error)
        }
        contestStates = [:]
        _ = await service.myContestedNames(syncFirst: true)
        loadMyNames()
    }

    /// Run one PIN-gated trade action with shared progress/error/success
    /// handling, then refresh both lists so the new sale state renders.
    /// `progressText` drives the blocking activity overlay on the
    /// marketplace screen — the sheets dismiss themselves as the action
    /// starts, and a Platform transition takes seconds; without it the
    /// screen sat silent until the success banner.
    func perform(
        progressText: String,
        successText: String,
        _ operation: @escaping () async throws -> Void
    ) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        withAnimation { activityMessage = progressText }
        Task { [weak self] in
            guard let self else { return }
            defer { withAnimation { self.activityMessage = nil } }
            do {
                try await operation()
                isPerformingAction = false
                withAnimation { successMessage = successText }
                loadMyNames()
                updateSearch()
                // Auto-hide in a detached task so the banner's 2.5 s
                // doesn't keep the action buttons disabled.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard let self else { return }
                    withAnimation {
                        if successMessage == successText { successMessage = nil }
                    }
                }
            } catch UsernameMarketplaceService.ServiceError.authCancelled {
                // Backing out of the PIN prompt is not an error state.
                isPerformingAction = false
            } catch {
                isPerformingAction = false
                errorMessage = UsernameMarketplaceService.userFacingMessage(for: error)
            }
        }
    }
}

// MARK: - UsernameMarketplaceScreen

struct UsernameMarketplaceScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel = UsernameMarketplaceViewModel()
    @State private var selectedLabel: SelectedMarketplaceLabel?
    @State private var registerCandidate: RegisterCandidate?

    init(vc: UINavigationController) {
        self.vc = vc
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                vc.popViewController(animated: true)
            }

            TopIntro(
                title: NSLocalizedString("Username Marketplace", comment: "Username marketplace"),
                subtitle: NSLocalizedString("Search usernames, buy ones that are for sale, and sell or transfer your own.", comment: "Username marketplace: screen subtitle")
            )
            .padding(.leading, 20)
            .padding(.trailing, 60)
            .padding(.top, 10)
            .padding(.bottom, 12)

            Picker("", selection: $viewModel.segment) {
                ForEach(UsernameMarketplaceViewModel.Segment.allCases, id: \.self) { segment in
                    Text(segment.title).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            switch viewModel.segment {
            case .find:
                findSection
            case .mine:
                mySection
            case .browse:
                browseSection
            }

            Spacer(minLength: 0)
        }
        .background(Color.dash.primaryBackground.ignoresSafeArea())
        .onAppear { viewModel.loadMyNames() }
        .sheet(item: $selectedLabel) { selected in
            MarketplaceNameDetailSheet(label: selected.label, viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $registerCandidate) { candidate in
            RegisterNameSheet(label: candidate.label, viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .overlay {
            // Blocking activity overlay while a trade transition is in
            // flight — the action sheets dismiss themselves as the action
            // starts, so this is the only feedback until success/error.
            // (The PIN prompt is a UIKit modal and presents above it.)
            if let activity = viewModel.activityMessage {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 14) {
                        SwiftUI.ProgressView()
                            .scaleEffect(1.3)
                        Text(activity)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.dash.primaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.dash.secondaryBackground)
                            .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 6))
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let success = viewModel.successMessage {
                Label(success, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dashGreen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.dash.secondaryBackground)
                        .shadow(color: Color.dash.shadow, radius: 16, x: 0, y: 4))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert(
            NSLocalizedString("Error", comment: ""),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } })
        ) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: Find segment

    private var findSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ContactsSearchField(
                placeholder: NSLocalizedString("Search usernames", comment: "Username marketplace: search placeholder"),
                text: $viewModel.query)
                .padding(.horizontal, 20)
                .onChange(of: viewModel.query) { _, _ in viewModel.updateSearch() }

            ScrollView {
                LazyVStack(spacing: 6) {
                    if viewModel.isSearching && viewModel.searchResults.isEmpty {
                        SwiftUI.ProgressView().padding(.top, 28)
                    } else if viewModel.query.trimmingCharacters(in: .whitespaces).count < 2 {
                        emptyHint(NSLocalizedString("Type at least 2 characters to search usernames", comment: "DashPay Contacts"))
                    } else {
                        ForEach(viewModel.searchResults) { name in
                            searchRow(name)
                        }
                        if let candidate = viewModel.registrableQueryLabel, !viewModel.isSearching {
                            registerRow(candidate)
                        }
                        if viewModel.searchResults.isEmpty && !viewModel.isSearching
                            && viewModel.registrableQueryLabel == nil {
                            emptyHint(NSLocalizedString("No usernames found", comment: "DashPay Contacts"))
                        }
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Browse segment

    /// Recent marketplace activity, newest first: price changes
    /// (listings / re-prices) and purchases, straight off the
    /// document-history trail's [dataContractId, $createdAt] index.
    /// Event price and time are historical facts; the trailing badge is
    /// the name's LIVE state, so a stale listing can't read as an offer.
    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $viewModel.browseFeed) {
                ForEach(UsernameMarketplaceViewModel.BrowseFeed.allCases, id: \.self) { feed in
                    Text(feed.title).tag(feed)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .onChange(of: viewModel.browseFeed) { _, _ in
                if viewModel.browseRows.isEmpty {
                    viewModel.loadBrowse()
                }
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.browseRows) { row in
                        browseEventRow(row)
                    }
                    if viewModel.browseRows.isEmpty && !viewModel.isBrowseLoading {
                        emptyHint(viewModel.browseFeed == .priceChanges
                            ? NSLocalizedString("No names are for sale in the recent listing activity. Show more reaches further back.", comment: "Username marketplace: price-changes feed found no live listings yet")
                            : NSLocalizedString("No purchases on the network yet.", comment: "Username marketplace: empty purchases feed"))
                    }
                    if viewModel.isBrowseLoading {
                        HStack(spacing: 8) {
                            SwiftUI.ProgressView()
                            Text(NSLocalizedString("Loading activity…", comment: "Username marketplace: browse feed loading"))
                                .font(.system(size: 12))
                                .foregroundColor(.dash.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    } else if !viewModel.browseFeedExhausted && !viewModel.browseRows.isEmpty {
                        Button {
                            viewModel.loadBrowse()
                        } label: {
                            Text(NSLocalizedString("Show more", comment: "Username marketplace: load older browse activity"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.dash.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .refreshable {
                await viewModel.refreshBrowse()
            }
        }
        .onAppear {
            if viewModel.browseRows.isEmpty {
                viewModel.loadBrowse()
            }
        }
    }

    private func browseEventRow(_ row: UsernameMarketplaceViewModel.BrowseEventRow) -> some View {
        let eventDash = (row.event.priceCredits / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol
        let eventDate = DWDateFormatter.sharedInstance.shortStringFromDate(
            Date(timeIntervalSince1970: Double(row.event.createdAtMs) / 1000))
        let subtitle: String
        if viewModel.browseFeed == .priceChanges {
            subtitle = String.localizedStringWithFormat(
                NSLocalizedString("Listed for %1$@ DASH · %2$@", comment: "Username marketplace: price-change feed row — event price, then date"),
                eventDash, eventDate)
        } else if let seller = row.event.sellerIdBase58, let buyer = row.event.buyerIdBase58 {
            subtitle = String.localizedStringWithFormat(
                NSLocalizedString("Sold for %1$@ DASH · %2$@ · %3$@ → %4$@", comment: "Username marketplace: purchases feed row — price paid, date, then seller → buyer short ids"),
                eventDash, eventDate, shortBase58(seller), shortBase58(buyer))
        } else {
            subtitle = String.localizedStringWithFormat(
                NSLocalizedString("Sold for %1$@ DASH · %2$@", comment: "Username marketplace: purchases feed row — price paid, then date"),
                eventDash, eventDate)
        }
        return Button {
            selectedLabel = SelectedMarketplaceLabel(label: row.label)
        } label: {
            HStack(spacing: 10) {
                ContactAvatarView(
                    title: row.label,
                    avatarURL: nil,
                    identitySeed: row.live?.ownerId ?? Data())
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.dash.tertiaryText)
                        .lineLimit(1)
                }
                Spacer()
                if let live = row.live, live.isForSale, let priceDuffs = live.priceDuffs {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(NSLocalizedString("For sale", comment: "Username marketplace: listed badge"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.dashGolden)
                        Text("\(priceDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol) DASH")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.dash.primaryText)
                    }
                } else {
                    Text(NSLocalizedString("Not for sale now", comment: "Username marketplace: browse row whose name is no longer listed"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.dash.tertiaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dash.secondaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.dash.secondaryBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: My Names segment

    private var mySection: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if viewModel.isLoadingMine && viewModel.myNames.isEmpty && viewModel.contestedNames.isEmpty {
                    SwiftUI.ProgressView().padding(.top, 28)
                } else if viewModel.myNames.isEmpty && viewModel.contestedNames.isEmpty {
                    emptyHint(NSLocalizedString("No usernames on this identity yet. Find one to buy or register on the Find Names tab.", comment: "Username marketplace: empty owned list"))
                } else {
                    ForEach(viewModel.ownedNames) { row in
                        stateRow(row)
                    }
                    if !viewModel.contestedNames.isEmpty {
                        sectionHeader(NSLocalizedString("In network vote", comment: "Username marketplace: section of contested-name requests awaiting the masternode vote"))
                        ForEach(viewModel.contestedNames, id: \.self) { label in
                            contestedRow(label)
                        }
                    }
                    if !viewModel.departedNames.isEmpty {
                        sectionHeader(NSLocalizedString("No longer yours", comment: "Username marketplace: names that were sold or transferred away"))
                        ForEach(viewModel.departedNames) { row in
                            stateRow(row)
                        }
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable { await viewModel.refreshFromNetwork() }
    }

    // MARK: Rows

    private func searchRow(_ name: DpnsMarketplaceName) -> some View {
        let isMine = name.isOwned(by: viewModel.ownIdentityId)
        return Button {
            selectedLabel = SelectedMarketplaceLabel(label: name.label)
        } label: {
            HStack(spacing: 10) {
                ContactAvatarView(
                    title: name.label,
                    avatarURL: nil,
                    identitySeed: name.ownerId)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                        .lineLimit(1)
                    // The seller-clarity line: a listed name that isn't
                    // ours is being sold by an independent user — not by
                    // Dash, not by this app.
                    Text(subtitle(for: name, isMine: isMine))
                        .font(.system(size: 11))
                        .foregroundColor(name.isForSale && !isMine ? .dashGolden : .dash.tertiaryText)
                        .lineLimit(1)
                }
                Spacer()
                if name.isForSale, let priceDuffs = name.priceDuffs {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(NSLocalizedString("For sale", comment: "Username marketplace: listed badge"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.dashGolden)
                        Text("\(priceDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol) DASH")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.dash.primaryText)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dash.secondaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.dash.secondaryBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for name: DpnsMarketplaceName, isMine: Bool) -> String {
        if isMine {
            return NSLocalizedString("Owned by you", comment: "Username marketplace")
        }
        if name.isForSale {
            return NSLocalizedString("For sale by an independent user", comment: "Username marketplace: seller-clarity row line — the seller is another user, not Dash or the app")
        }
        let owner = name.ownerId.toBase58String()
        return String(owner.prefix(8)) + "…" + String(owner.suffix(4))
    }

    private func stateRow(_ row: DpnsNameStateRow) -> some View {
        Button {
            selectedLabel = SelectedMarketplaceLabel(label: row.label)
        } label: {
            HStack(spacing: 10) {
                ContactAvatarView(
                    title: row.label,
                    avatarURL: nil,
                    identitySeed: row.walletIdentityId)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                        .lineLimit(1)
                    Text(stateLine(for: row))
                        .font(.system(size: 11))
                        .foregroundColor(.dash.tertiaryText)
                        .lineLimit(1)
                }
                Spacer()
                if row.isForSale, let priceDuffs = row.priceDuffs {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(NSLocalizedString("For sale", comment: "Username marketplace: listed badge"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.dashGolden)
                        Text("\(priceDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol) DASH")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.dash.primaryText)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dash.secondaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.dash.secondaryBackground))
            .contentShape(Rectangle())
            .opacity({ if case .owned = row.status { return 1 } else { return 0.65 } }())
        }
        .buttonStyle(.plain)
    }

    private func stateLine(for row: DpnsNameStateRow) -> String {
        switch row.status {
        case .owned:
            return row.isForSale
                ? NSLocalizedString("Listed by you", comment: "Username marketplace: own listed name")
                : NSLocalizedString("Owned by you", comment: "Username marketplace")
        case .sold(let buyer):
            return String.localizedStringWithFormat(
                NSLocalizedString("Sold to %@", comment: "Username marketplace: departed-name line — buyer identity"),
                shortId(buyer))
        case .transferred(let recipient):
            return String.localizedStringWithFormat(
                NSLocalizedString("Transferred to %@", comment: "Username marketplace: departed-name line — recipient identity"),
                shortId(recipient))
        }
    }

    private func shortId(_ id: Data) -> String {
        let base58 = id.toBase58String()
        return String(base58.prefix(8)) + "…" + String(base58.suffix(4))
    }

    /// A contested request awaiting the masternode vote. Not tappable —
    /// there is no document to act on until the vote resolves. When the
    /// requested variant normalizes differently ("quiet" → "qu1et"),
    /// both are shown: the variant is what the user asked for, the
    /// normalized form is what the network actually registers.
    private func contestedRow(_ label: String) -> some View {
        let variant = viewModel.requestedVariant(forNormalized: label)
        return HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.dashGolden)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.dashGolden.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(variant ?? label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                        .lineLimit(1)
                    if variant != nil {
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.dash.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Text(contestedLine(for: label))
                    .font(.system(size: 11))
                    .foregroundColor(.dash.tertiaryText)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dash.secondaryBackground))
    }

    private func contestedLine(for label: String) -> String {
        guard let state = viewModel.contestStates[label] else {
            return NSLocalizedString("Requested — waiting for the network vote", comment: "Username marketplace: contested request not yet indexed by Platform")
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("Network vote ends %@", comment: "Username marketplace: contested request line — voting deadline"),
            DWDateFormatter.sharedInstance.shortStringFromDate(state.endTime))
    }

    private func registerRow(_ label: String) -> some View {
        let contested = UsernameMarketplaceService.isContested(label)
        // What the row claims must match the contest reality, not just
        // document existence: a label mid-vote has no document yet but is
        // NOT plainly available. Own requests answer locally; foreign
        // contest state comes from the view model's best-effort precheck.
        let icon: String
        let tint: Color
        let subtitle: String
        if contested, viewModel.hasRequestedContest(for: label) {
            icon = "hourglass"
            tint = .dashGolden
            subtitle = NSLocalizedString("Requested by you — the network vote is in progress", comment: "Username marketplace: search row for a contested label this identity already requested")
        } else if contested, case .activeContest = viewModel.queryContest {
            icon = "person.2.fill"
            tint = .dashGolden
            subtitle = NSLocalizedString("In a network vote — you can join as a contender", comment: "Username marketplace: search row for a contested label with an active vote by others")
        } else if contested, viewModel.queryContest == .locked {
            icon = "lock.fill"
            tint = Color.dash.secondaryText
            subtitle = NSLocalizedString("Locked by a network vote — nobody can register it", comment: "Username marketplace: search row for a label a past vote locked")
        } else if contested {
            icon = "plus.circle.fill"
            tint = .dashGolden
            subtitle = NSLocalizedString("Available — short names are decided by a network vote", comment: "Username marketplace: unregistered contested-eligible name row")
        } else {
            icon = "plus.circle.fill"
            tint = .dashGreen
            subtitle = NSLocalizedString("Available — register it on your identity", comment: "Username marketplace: unregistered name row")
        }
        return Button {
            registerCandidate = RegisterCandidate(label: label)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(icon == "plus.circle.fill" ? .dashGreen : tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(tint)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dash.secondaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.dash.secondaryBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortBase58(_ base58: String) -> String {
        String(base58.prefix(8)) + "…" + String(base58.suffix(4))
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.dash.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.dash.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .padding(.horizontal, 24)
    }
}

/// Identifiable wrappers for `.sheet(item:)`.
struct SelectedMarketplaceLabel: Identifiable {
    let label: String
    var id: String { label }
}

struct RegisterCandidate: Identifiable {
    let label: String
    var id: String { label }
}

// MARK: - MarketplaceNameDetailSheet

/// Authoritative detail for one name: loads the live document state and
/// the full trade timeline on appear, then offers exactly the actions
/// the state allows. Works for departed names too (the history query
/// covers names that already left the wallet).
private struct MarketplaceNameDetailSheet: View {
    let label: String
    @ObservedObject var viewModel: UsernameMarketplaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var liveName: DpnsMarketplaceName?
    @State private var history: [DpnsNameHistoryEvent] = []
    @State private var isLoading = true
    @State private var showingSetPrice = false
    @State private var showingTransfer = false
    @State private var confirmBuy = false
    @State private var confirmDelist = false

    private var isMine: Bool { liveName?.isOwned(by: viewModel.ownIdentityId) ?? false }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ContactAvatarView(
                    title: label,
                    avatarURL: nil,
                    identitySeed: liveName?.ownerId ?? Data(),
                    size: 72)
                    .padding(.top, 28)

                Text(label)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                    .padding(.top, 10)

                if isLoading {
                    SwiftUI.ProgressView().padding(.top, 20)
                } else if let name = liveName {
                    saleState(name)
                    if name.isForSale && !isMine {
                        independentSellerCallout
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    infoCard(name)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    if !history.isEmpty {
                        historyCard
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    actions(name)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 16)
                } else {
                    Text(NSLocalizedString("This name is not registered.", comment: "Username marketplace: detail for an unregistered name"))
                        .font(.system(size: 13))
                        .foregroundColor(.dash.secondaryText)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(Color.dash.primaryBackground)
        .task { await load() }
        .sheet(isPresented: $showingSetPrice) {
            SetNamePriceSheet(label: label, viewModel: viewModel, onDone: { dismiss() })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingTransfer) {
            TransferNameSheet(label: label, viewModel: viewModel, onDone: { dismiss() })
                .presentationDetents([.medium, .large])
        }
    }

    private func load() async {
        isLoading = true
        // Live state and timeline are independent reads; a history
        // failure must not blank the sale state (and vice versa).
        do {
            liveName = try await viewModel.service.nameState(label)
        } catch {
            viewModel.errorMessage = UsernameMarketplaceService.userFacingMessage(for: error)
        }
        history = (try? await viewModel.service.history(label)) ?? []
        isLoading = false
    }

    @ViewBuilder
    private func saleState(_ name: DpnsMarketplaceName) -> some View {
        if let priceDuffs = name.priceDuffs {
            VStack(spacing: 2) {
                Text(NSLocalizedString("For sale", comment: "Username marketplace: listed badge"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dashGolden)
                Text("\(priceDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol) DASH")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                Text(CurrencyExchanger.shared.fiatAmountString(for: priceDuffs.dashAmount))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.secondaryText)
            }
            .padding(.top, 8)
        } else {
            Text(isMine
                ? NSLocalizedString("Not listed for sale", comment: "Username marketplace: own unlisted name")
                : NSLocalizedString("Not for sale", comment: "Username marketplace: someone else's unlisted name"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.dash.secondaryText)
                .padding(.top, 8)
        }
    }

    /// The seller-clarity callout: this offer comes from an independent
    /// user, not from Dash or the app.
    private var independentSellerCallout: some View {
        Label {
            Text(NSLocalizedString("This name is offered by an independent user on the Dash network — not by Dash or this app. The seller sets the price.", comment: "Username marketplace: seller-clarity callout on the detail sheet"))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 13))
        }
        .foregroundColor(.dash.secondaryText)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.dashGolden.opacity(0.1)))
    }

    private func infoCard(_ name: DpnsMarketplaceName) -> some View {
        VStack(spacing: 0) {
            detailRow(
                NSLocalizedString("Owner", comment: "Username marketplace"),
                isMine
                    ? NSLocalizedString("You", comment: "Username marketplace: owner is the current user")
                    : shortId(name.ownerId))
            if let createdAtMs = name.createdAtMs {
                detailRow(
                    NSLocalizedString("Registered", comment: "Username marketplace: registration date"),
                    DWDateFormatter.sharedInstance.shortStringFromDate(
                        Date(timeIntervalSince1970: Double(createdAtMs) / 1000)))
            }
            if let transferredAtMs = name.transferredAtMs {
                detailRow(
                    NSLocalizedString("Last transferred", comment: "Username marketplace: latest ownership change"),
                    DWDateFormatter.sharedInstance.shortStringFromDate(
                        Date(timeIntervalSince1970: Double(transferredAtMs) / 1000)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.dash.secondaryBackground))
    }

    // MARK: Trade history

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("Trade history", comment: "Username marketplace: timeline card title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.dash.secondaryText)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(Array(history.enumerated().reversed()), id: \.offset) { _, event in
                historyRow(event)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.dash.secondaryBackground))
    }

    private func historyRow(_ event: DpnsNameHistoryEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: historyIcon(event))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.dash.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(historyText(event))
                    .font(.system(size: 13))
                    .foregroundColor(.dash.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(DWDateFormatter.sharedInstance.shortStringFromDate(
                    Date(timeIntervalSince1970: Double(event.atMs) / 1000)))
                    .font(.system(size: 11))
                    .foregroundColor(.dash.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func historyIcon(_ event: DpnsNameHistoryEvent) -> String {
        switch event {
        case .registered: return "plus.circle"
        case .priceSet: return "tag"
        case .purchased: return "cart"
        case .transferred(let from, let to, _, _):
            return from == to ? "tag.slash" : "arrow.right.circle"
        }
    }

    private func historyText(_ event: DpnsNameHistoryEvent) -> String {
        switch event {
        case .registered:
            return NSLocalizedString("Registered", comment: "Username marketplace: registration date")
        case .priceSet(let price, _, _):
            return String.localizedStringWithFormat(
                NSLocalizedString("Listed for %@ DASH", comment: "Username marketplace: history — price set"),
                (price / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol)
        case .purchased(let price, let seller, let buyer, _, _):
            return String.localizedStringWithFormat(
                NSLocalizedString("Bought by %1$@ from %2$@ for %3$@ DASH", comment: "Username marketplace: history — purchase with buyer, seller, price"),
                participant(buyer), participant(seller),
                (price / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol)
        case .transferred(let from, let to, _, _):
            if from == to {
                return NSLocalizedString("Removed from sale", comment: "Username marketplace: history — delist (transfer to self)")
            }
            return String.localizedStringWithFormat(
                NSLocalizedString("Transferred from %1$@ to %2$@", comment: "Username marketplace: history — transfer with both identities"),
                participant(from), participant(to))
        }
    }

    private func participant(_ id: Data) -> String {
        id == viewModel.ownIdentityId
            ? NSLocalizedString("you", comment: "Username marketplace: history participant is the current user")
            : shortId(id)
    }

    private func shortId(_ id: Data) -> String {
        let base58 = id.toBase58String()
        return String(base58.prefix(8)) + "…" + String(base58.suffix(4))
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ name: DpnsMarketplaceName) -> some View {
        VStack(spacing: 10) {
            if isMine {
                if name.isForSale {
                    primaryButton(NSLocalizedString("Change Price", comment: "Username marketplace")) {
                        showingSetPrice = true
                    }
                    secondaryButton(NSLocalizedString("Remove From Sale", comment: "Username marketplace")) {
                        confirmDelist = true
                    }
                } else {
                    primaryButton(NSLocalizedString("Put Up For Sale", comment: "Username marketplace")) {
                        showingSetPrice = true
                    }
                }
                secondaryButton(NSLocalizedString("Transfer to Another Identity", comment: "Username marketplace")) {
                    showingTransfer = true
                }
            } else if name.isForSale, let priceDuffs = name.priceDuffs {
                identityBalanceLine(name)
                primaryButton(String.localizedStringWithFormat(
                    NSLocalizedString("Buy for %@ DASH", comment: "Username marketplace: purchase button"),
                    priceDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)) {
                    confirmBuy = true
                }
            }
        }
        .disabled(viewModel.isPerformingAction)
        .confirmationDialog(
            String.localizedStringWithFormat(
                NSLocalizedString("Buy “%@”?", comment: "Username marketplace: purchase confirmation title"),
                label),
            isPresented: $confirmBuy,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Buy", comment: "Username marketplace"), role: .none) {
                // The Buy button only renders for a listed name, but never
                // let a nil price fall through as a 0-credit purchase.
                guard let expected = name.priceCredits else {
                    viewModel.errorMessage = NSLocalizedString("This username is not for sale.", comment: "Username marketplace")
                    return
                }
                viewModel.perform(
                    progressText: NSLocalizedString("Completing your purchase…", comment: "Username marketplace: activity overlay while the purchase transition runs"),
                    successText: String.localizedStringWithFormat(
                    NSLocalizedString("%@ is now yours", comment: "Username marketplace: purchase success"),
                    label)) {
                    try await viewModel.service.purchase(name: label, expectedPriceCredits: expected)
                }
                dismiss()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("You are buying from an independent user, not from Dash or this app. The price plus a small network fee is paid from your identity balance, and the name moves to your identity immediately.", comment: "Username marketplace: purchase confirmation body with seller clarity"))
        }
        .confirmationDialog(
            String.localizedStringWithFormat(
                NSLocalizedString("Remove “%@” from sale?", comment: "Username marketplace: delist confirmation title"),
                label),
            isPresented: $confirmDelist,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Remove From Sale", comment: "Username marketplace"), role: .destructive) {
                viewModel.perform(
                    progressText: NSLocalizedString("Removing the listing…", comment: "Username marketplace: activity overlay while the delist transition runs"),
                    successText: String.localizedStringWithFormat(
                    NSLocalizedString("%@ is no longer for sale", comment: "Username marketplace: delist success"),
                    label)) {
                    try await viewModel.service.removeFromSale(name: label)
                }
                dismiss()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Removing the listing is a network transaction with a small fee, paid from your identity balance. You keep the name.", comment: "Username marketplace: delist confirmation body"))
        }
    }

    /// Buyer-side affordability line, from the same persisted identity
    /// balance the profile sheet shows. The SDK re-checks
    /// authoritatively at purchase time.
    @ViewBuilder
    private func identityBalanceLine(_ name: DpnsMarketplaceName) -> some View {
        if let identityId = viewModel.ownIdentityId,
           let container = SwiftDashSDKHost.shared.modelContainer {
            let available = UsernameMarketplaceService.identityBalanceCredits(
                identityId: identityId, container: container)
            let needed = name.priceCredits ?? 0
            HStack {
                Text(NSLocalizedString("Identity Account Balance", comment: "SDK identity profile sheet — the identity's credit balance"))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.secondaryText)
                Spacer()
                Text("\((available / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol) DASH")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(available > needed ? .dash.primaryText : .orange)
            }
            if available <= needed {
                Text(NSLocalizedString("Not enough identity credits for this purchase — top up from My Profile first.", comment: "Username marketplace: insufficient balance hint"))
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.dash.whiteText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.dash.blue)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.dash.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.dash.blue.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SetNamePriceSheet

private struct SetNamePriceSheet: View {
    let label: String
    @ObservedObject var viewModel: UsernameMarketplaceViewModel
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @FocusState private var fieldFocused: Bool

    private var priceDuffs: UInt64? {
        let normalized = priceText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let dash = Decimal(string: normalized), dash > 0, dash <= 100_000 else { return nil }
        let duffsDecimal = dash * Decimal(kOneDash)
        return UInt64(exactly: NSDecimalNumber(decimal: duffsDecimal).int64Value)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("Set a price for “%@”", comment: "Username marketplace: set price sheet title"),
                    label))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)
                    .padding(.horizontal, 24)

                Text(NSLocalizedString("Anyone will be able to buy the name for this exact price. The proceeds arrive as credits on your identity balance.", comment: "Username marketplace: set price sheet body"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 4) {
                    TextField(
                        NSLocalizedString("Price in DASH", comment: "Username marketplace: price placeholder"),
                        text: $priceText)
                        .keyboardType(.decimalPad)
                        .focused($fieldFocused)
                        .font(.system(size: 18, weight: .semibold))
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.dash.secondaryBackground))
                    if let duffs = priceDuffs {
                        Text(CurrencyExchanger.shared.fiatAmountString(for: duffs.dashAmount))
                            .font(.system(size: 12))
                            .foregroundColor(.dash.secondaryText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Text(NSLocalizedString("Listing is a network transaction with a small fee, paid from your identity balance.", comment: "Username marketplace: set price fee note"))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                Button {
                    guard let duffs = priceDuffs else { return }
                    viewModel.perform(
                        progressText: NSLocalizedString("Listing for sale…", comment: "Username marketplace: activity overlay while the set-price transition runs"),
                        successText: String.localizedStringWithFormat(
                        NSLocalizedString("%1$@ listed for %2$@ DASH", comment: "Username marketplace: listing success — name, then price"),
                        label,
                        duffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)) {
                        try await viewModel.service.setPrice(name: label, priceDuffs: duffs)
                    }
                    dismiss()
                    onDone()
                } label: {
                    Text(NSLocalizedString("List For Sale", comment: "Username marketplace: confirm listing button"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.dash.whiteText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.dash.blue)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(priceDuffs == nil || viewModel.isPerformingAction)
                .opacity(priceDuffs == nil ? 0.55 : 1)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("Cancel", comment: ""))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.dash.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
        .background(Color.dash.primaryBackground)
        .onAppear { fieldFocused = true }
    }
}

// MARK: - TransferNameSheet

private struct TransferNameSheet: View {
    let label: String
    @ObservedObject var viewModel: UsernameMarketplaceViewModel
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipientText = ""
    @State private var isResolving = false
    @State private var resolveError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("Transfer “%@”", comment: "Username marketplace: transfer sheet title"),
                    label))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                    .padding(.top, 28)

                Text(NSLocalizedString("Send this name to another identity for free. The transfer also removes any sale listing. This can't be undone — the new owner would have to transfer it back.", comment: "Username marketplace: transfer sheet body"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 4) {
                    TextField(
                        NSLocalizedString("Recipient username or identity ID", comment: "Username marketplace: transfer recipient placeholder"),
                        text: $recipientText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 15))
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.dash.secondaryBackground))
                    if let resolveError {
                        Text(resolveError)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Button {
                    transfer()
                } label: {
                    if isResolving {
                        SwiftUI.ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text(NSLocalizedString("Transfer", comment: "Username marketplace: confirm transfer button"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.dash.whiteText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.dash.blue)
                            .cornerRadius(12)
                    }
                }
                .buttonStyle(.plain)
                .disabled(recipientText.trimmingCharacters(in: .whitespaces).isEmpty
                    || isResolving || viewModel.isPerformingAction)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("Cancel", comment: ""))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.dash.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
        .background(Color.dash.primaryBackground)
    }

    /// Accepts a base58 identity id directly, or resolves a username via
    /// DPNS. Never guesses: unresolvable input surfaces an error and no
    /// transition is attempted.
    private func transfer() {
        let input = recipientText.trimmingCharacters(in: .whitespaces)
        resolveError = nil
        if let direct = Data.identifier(fromBase58: input), direct.count == 32 {
            run(recipientBase58: input)
            return
        }
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            resolveError = NSLocalizedString("Wallet is not ready", comment: "DashPay")
            return
        }
        isResolving = true
        Task {
            defer { isResolving = false }
            do {
                guard let identityId = try await wallet.resolveDpnsName(input) else {
                    resolveError = NSLocalizedString("No identity owns that username.", comment: "Username marketplace: unresolvable transfer recipient")
                    return
                }
                run(recipientBase58: identityId.toBase58String())
            } catch {
                resolveError = UsernameMarketplaceService.userFacingMessage(for: error)
            }
        }
    }

    private func run(recipientBase58: String) {
        viewModel.perform(
            progressText: NSLocalizedString("Transferring the username…", comment: "Username marketplace: activity overlay while the transfer transition runs"),
            successText: String.localizedStringWithFormat(
            NSLocalizedString("%@ transferred", comment: "Username marketplace: transfer success"),
            label)) {
            try await viewModel.service.transfer(name: label, toIdentityBase58: recipientBase58)
        }
        dismiss()
        onDone()
    }
}

// MARK: - RegisterNameSheet

private struct RegisterNameSheet: View {
    let label: String
    @ObservedObject var viewModel: UsernameMarketplaceViewModel
    @Environment(\.dismiss) private var dismiss

    /// Pre-submit network state for contested labels; nil while loading.
    @State private var precheck: UsernameMarketplaceService.ContestPrecheck?
    /// Live vote tallies for an active contest on this label (yours or
    /// anyone's); nil while loading, unavailable, or no contest exists.
    @State private var voteState: ContestVoteState?

    private var isContested: Bool {
        UsernameMarketplaceService.isContested(label)
    }

    /// This identity already has a request in for this label — the vote
    /// is in progress and a second submission would just fail.
    private var alreadyRequested: Bool {
        viewModel.hasRequestedContest(for: label)
    }

    /// Whether the identity balance covers the vote-resolution fund —
    /// the same check `requestCostCard` renders, reused to keep the
    /// submit button from offering a request that must fail.
    private var canAffordRequest: Bool {
        guard let identityId = viewModel.ownIdentityId,
              let container = SwiftDashSDKHost.shared.modelContainer else { return false }
        return UsernameMarketplaceService.identityBalanceCredits(
            identityId: identityId, container: container)
            > UsernameMarketplaceService.contestedFundCredits
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: isContested ? "checkmark.seal" : "plus.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(isContested ? .dashGolden : .dashGreen)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill((isContested ? Color.dashGolden : Color.dashGreen).opacity(0.1)))
                    .padding(.top, 28)

                Text(String.localizedStringWithFormat(
                    isContested
                        ? NSLocalizedString("Request “%@”", comment: "Username marketplace: contested register sheet title")
                        : NSLocalizedString("Register “%@”", comment: "Username marketplace: register sheet title"),
                    label))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                    .padding(.top, 14)

                if isContested {
                    contestedContent
                } else {
                    Text(NSLocalizedString("The name is registered directly on your identity. Registration is a network transaction paid from your identity balance.", comment: "Username marketplace: register sheet body"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)

                    confirmButton(NSLocalizedString("Register", comment: "Username marketplace: confirm register button")) {
                        viewModel.perform(
                            progressText: NSLocalizedString("Registering the username…", comment: "Username marketplace: activity overlay while the registration transition runs"),
                            successText: String.localizedStringWithFormat(
                            NSLocalizedString("%@ registered", comment: "Username marketplace: registration success"),
                            label)) {
                            try await viewModel.service.register(label: label)
                        }
                        dismiss()
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("Cancel", comment: ""))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.dash.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
        }
        .background(Color.dash.primaryBackground)
        .task {
            guard isContested else { return }
            if precheck == nil {
                precheck = await viewModel.service.contestPrecheck(label: label)
            }
            if voteState == nil {
                voteState = await viewModel.service.contestState(label: label)
            }
        }
    }

    // MARK: Contested request

    @ViewBuilder private var contestedContent: some View {
        Text(NSLocalizedString("Short names — 19 characters or fewer, letters and numbers only — aren't registered instantly. The Dash network votes on who gets them.", comment: "Username marketplace: contested request explainer, paragraph 1"))
            .font(.system(size: 14))
            .foregroundColor(.dash.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
            .padding(.top, 8)

        if alreadyRequested {
            statusCallout(
                icon: "hourglass",
                text: NSLocalizedString("You already requested this name — the network vote is in progress. You'll find it under My Names.", comment: "Username marketplace: contested request already submitted by this identity"))
            contestVotesCard
        } else if precheck == nil {
            SwiftUI.ProgressView()
                .padding(.top, 20)
                .padding(.bottom, 8)
        } else if precheck == .locked {
            statusCallout(
                icon: "lock",
                text: NSLocalizedString("The network voted to lock this name, so nobody can register it. Choose a different name.", comment: "Username marketplace: contested label locked by a past vote"))
        } else {
            Text(NSLocalizedString("Your request enters a public vote by masternodes for about two weeks. Others can request the same name; when the vote ends, the name goes to the winner — or to nobody, if the network votes to lock it.", comment: "Username marketplace: contested request explainer, paragraph 2"))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 10)

            if case .activeContest = precheck {
                statusCallout(
                    icon: "person.2",
                    text: NSLocalizedString("This name is already in an active network vote. Your request joins it as another contender.", comment: "Username marketplace: contested label already has an active vote"))
                contestVotesCard
            }

            requestCostCard
                .padding(.horizontal, 20)
                .padding(.top, 14)

            confirmButton(NSLocalizedString("Request Username", comment: "Username marketplace: confirm contested request button")) {
                viewModel.perform(
                    progressText: NSLocalizedString("Submitting your username request…", comment: "Username marketplace: activity overlay while the contested request transition runs"),
                    successText: String.localizedStringWithFormat(
                    NSLocalizedString("Request for %@ submitted — masternodes now vote on it", comment: "Username marketplace: contested request success"),
                    label)) {
                    try await viewModel.service.requestContestedName(label: label)
                }
                dismiss()
            }
            .disabled(!canAffordRequest)
            .opacity(canAffordRequest ? 1 : 0.55)
        }
    }

    /// The vote-resolution fund the request locks from the identity
    /// balance (a protocol constant), next to what's available.
    @ViewBuilder private var requestCostCard: some View {
        let fund = UsernameMarketplaceService.contestedFundCredits
        let available: UInt64 = {
            guard let identityId = viewModel.ownIdentityId,
                  let container = SwiftDashSDKHost.shared.modelContainer else { return 0 }
            return UsernameMarketplaceService.identityBalanceCredits(
                identityId: identityId, container: container)
        }()
        VStack(spacing: 0) {
            HStack {
                Text(NSLocalizedString("Request cost", comment: "Username marketplace: contested request cost row"))
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                Spacer()
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("%@ DASH + network fee", comment: "Username marketplace: contested request cost value — the vote-resolution fund amount"),
                    (fund / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            HStack {
                Text(NSLocalizedString("Identity Account Balance", comment: "SDK identity profile sheet — the identity's credit balance"))
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                Spacer()
                Text("\((available / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol) DASH")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(available > fund ? .dash.primaryText : .orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Text(NSLocalizedString("The cost is paid from your identity balance. It funds the network vote and isn't returned if another contender wins.", comment: "Username marketplace: contested request cost footnote"))
                .font(.system(size: 11))
                .foregroundColor(.dash.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            if available <= fund {
                Text(NSLocalizedString("Not enough identity credits for this request — top up from My Profile first.", comment: "Username marketplace: insufficient balance hint for a contested request"))
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.dash.secondaryBackground))
    }

    /// Live state of the vote: every contender with their tally (own
    /// identity labeled), abstain and lock counts, the voting deadline,
    /// and until when new contenders can still join. Renders nothing
    /// while the state is loading or Platform hasn't indexed the
    /// contest — never a fabricated zero-tally.
    @ViewBuilder private var contestVotesCard: some View {
        if let state = voteState, case .none = state.winner {
            VStack(alignment: .leading, spacing: 0) {
                Text(NSLocalizedString("Network vote so far", comment: "Username marketplace: contest tallies card title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.dash.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                if state.totalVotes == 0 {
                    Text(NSLocalizedString("No votes cast yet", comment: "Username marketplace: contest with zero masternode votes so far"))
                        .font(.system(size: 12))
                        .foregroundColor(.dash.tertiaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                ForEach(state.contenders.sorted { $0.voteTally > $1.voteTally }) { contender in
                    voteRow(
                        contender.identityId == viewModel.ownIdentityId
                            ? NSLocalizedString("You", comment: "Username marketplace: owner is the current user")
                            : shortId(contender.identityId),
                        tally: contender.voteTally,
                        emphasized: contender.identityId == viewModel.ownIdentityId)
                }
                voteRow(NSLocalizedString("Abstain", comment: "Username marketplace: masternode abstain votes"), tally: state.abstainVotes, emphasized: false)
                voteRow(NSLocalizedString("Lock the name", comment: "Username marketplace: masternode votes to lock the name so nobody wins"), tally: state.lockVotes, emphasized: false)
                Divider().padding(.horizontal, 14).padding(.vertical, 4)
                deadlineRow(
                    NSLocalizedString("Vote ends", comment: "Username marketplace: contest voting deadline row"),
                    value: Self.deadlineText(state.endTime))
                let joinDeadline = UsernameMarketplaceService.contenderJoinDeadline(voteEnd: state.endTime)
                deadlineRow(
                    NSLocalizedString("New contenders", comment: "Username marketplace: until when other identities can join the contest"),
                    value: joinDeadline > Date()
                        ? String.localizedStringWithFormat(
                            NSLocalizedString("can join until %@", comment: "Username marketplace: join deadline still open — value of the New contenders row"),
                            Self.deadlineText(joinDeadline))
                        : NSLocalizedString("joining closed", comment: "Username marketplace: the contest's join window has passed — value of the New contenders row"))
                    .padding(.bottom, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.dash.secondaryBackground))
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func voteRow(_ title: String, tally: UInt32, emphasized: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: emphasized ? .semibold : .regular))
                .foregroundColor(.dash.primaryText)
            Spacer()
            Text(String.localizedStringWithFormat(
                NSLocalizedString("%d votes", comment: "Username marketplace: masternode vote tally for one contest row"),
                Int(tally)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.dash.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func deadlineRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    /// Date + time — contest windows on testnet are minutes long, so a
    /// date alone ("Today") wouldn't say anything actionable.
    private static func deadlineText(_ date: Date) -> String {
        let formatter = DWDateFormatter.sharedInstance
        return "\(formatter.shortStringFromDate(date)) \(formatter.timeOnly(from: date))"
    }

    private func shortId(_ id: Data) -> String {
        let base58 = id.toBase58String()
        return String(base58.prefix(8)) + "…" + String(base58.suffix(4))
    }

    private func statusCallout(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 13))
        }
        .foregroundColor(.dash.secondaryText)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.dashGolden.opacity(0.1)))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func confirmButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.dash.whiteText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.dash.blue)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPerformingAction)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}
