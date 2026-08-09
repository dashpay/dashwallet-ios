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

        var title: String {
            switch self {
            case .find: return NSLocalizedString("Find Names", comment: "Username marketplace: search segment")
            case .mine: return NSLocalizedString("My Names", comment: "Username marketplace: owned names segment")
            }
        }
    }

    @Published var segment: Segment = .find
    @Published var query = ""
    @Published var searchResults: [DpnsMarketplaceName] = []
    @Published var myNames: [DpnsNameStateRow] = []
    @Published var isSearching = false
    @Published var isLoadingMine = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?
    /// Transient success line ("hilawe listed for 0.05 DASH").
    @Published var successMessage: String?
    /// The typed query as a registrable label: valid DPNS label shape
    /// AND no document exists for its normalized form. Set by
    /// `updateSearch` using the SDK's own normalizer (DPNS folds
    /// look-alike characters, so a plain lowercase compare would lie).
    @Published var registrableQueryLabel: String?

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

    /// DPNS label shape: 3–63 characters, letters/digits/hyphen, no
    /// leading or trailing hyphen.
    static func isValidLabel(_ label: String) -> Bool {
        guard (3...63).contains(label.count) else { return false }
        guard label.first != "-", label.last != "-" else { return false }
        return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    func updateSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            registrableQueryLabel = nil
            isSearching = false
            return
        }
        searchResults = []
        registrableQueryLabel = nil
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
        }
    }

    /// Local read — the wallet's own tracked rows, no network.
    func loadMyNames() {
        isLoadingMine = true
        Task { [weak self] in
            guard let self else { return }
            do {
                myNames = try await service.myNames()
            } catch {
                errorMessage = UsernameMarketplaceService.userFacingMessage(for: error)
            }
            isLoadingMine = false
        }
    }

    /// Pull-to-refresh: run one marketplace sync pass, then re-read the
    /// local rows.
    func refreshFromNetwork() async {
        do {
            _ = try await service.syncNow()
        } catch {
            errorMessage = UsernameMarketplaceService.userFacingMessage(for: error)
        }
        loadMyNames()
    }

    /// Run one PIN-gated trade action with shared progress/error/success
    /// handling, then refresh both lists so the new sale state renders.
    func perform(
        successText: String,
        _ operation: @escaping () async throws -> Void
    ) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task { [weak self] in
            guard let self else { return }
            defer { isPerformingAction = false }
            do {
                try await operation()
                withAnimation { successMessage = successText }
                loadMyNames()
                updateSearch()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation {
                    if successMessage == successText { successMessage = nil }
                }
            } catch DWIdentityAuthorizer.AuthError.cancelled {
                // Backing out of the PIN prompt is not an error state.
            } catch {
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

    // MARK: My Names segment

    private var mySection: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if viewModel.isLoadingMine && viewModel.myNames.isEmpty {
                    SwiftUI.ProgressView().padding(.top, 28)
                } else if viewModel.myNames.isEmpty {
                    emptyHint(NSLocalizedString("No usernames on this identity yet. Find one to buy or register on the Find Names tab.", comment: "Username marketplace: empty owned list"))
                } else {
                    ForEach(viewModel.ownedNames) { row in
                        stateRow(row)
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
                if let priceDuffs = name.priceDuffs {
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

    private func registerRow(_ label: String) -> some View {
        Button {
            registerCandidate = RegisterCandidate(label: label)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.dashGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                    Text(NSLocalizedString("Available — register it on your identity", comment: "Username marketplace: unregistered name row"))
                        .font(.system(size: 11))
                        .foregroundColor(.dashGreen)
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
                let expected = name.priceCredits ?? 0
                viewModel.perform(successText: String.localizedStringWithFormat(
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
                viewModel.perform(successText: String.localizedStringWithFormat(
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
                    viewModel.perform(successText: String.localizedStringWithFormat(
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
        guard let wallet = SwiftDashSDKHost.shared.wallet else { return }
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
        viewModel.perform(successText: String.localizedStringWithFormat(
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

    private var isContested: Bool {
        UsernameMarketplaceService.isContestedEligible(normalizedLabel: label.lowercased())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.dashGreen)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Color.dashGreen.opacity(0.1)))
                    .padding(.top, 28)

                Text(String.localizedStringWithFormat(
                    NSLocalizedString("Register “%@”", comment: "Username marketplace: register sheet title"),
                    label))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                    .padding(.top, 14)

                if isContested {
                    Text(NSLocalizedString("This name is short enough to be contested and must be requested through the username flow, where it goes to a network vote.", comment: "Username marketplace"))
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                } else {
                    Text(NSLocalizedString("The name is registered directly on your identity. Registration is a network transaction paid from your identity balance.", comment: "Username marketplace: register sheet body"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)

                    Button {
                        viewModel.perform(successText: String.localizedStringWithFormat(
                            NSLocalizedString("%@ registered", comment: "Username marketplace: registration success"),
                            label)) {
                            try await viewModel.service.register(label: label)
                        }
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("Register", comment: "Username marketplace: confirm register button"))
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
                .padding(.top, isContested ? 20 : 0)
                .padding(.bottom, 10)
            }
        }
        .background(Color.dash.primaryBackground)
    }
}
