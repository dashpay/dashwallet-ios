//
//  UsernameMarketplaceScreen.swift
//  DashWallet
//
//  DPNS username marketplace (Explore tab): search any name and see its
//  live sale state, browse the names on your identity, list/delist/
//  re-price yours, buy listed ones, gift-transfer, and register
//  unclaimed non-contested labels. All reads and trade actions go
//  through `UsernameMarketplaceService`; every mutation is PIN-gated
//  there and nothing broadcasts before the user confirms a concrete
//  price. Search-driven by design: the DPNS contract has no `$price`
//  index yet, so a global "everything for sale" browse isn't queryable
//  (tracked in the platform marketplace task).
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
    @Published var searchResults: [MarketplaceName] = []
    @Published var myNames: [MarketplaceName] = []
    @Published var isSearching = false
    @Published var isLoadingMine = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?
    /// Transient success line ("hilawe listed for 0.05 DASH").
    @Published var successMessage: String?

    let service = UsernameMarketplaceService()
    private var searchTask: Task<Void, Never>?

    var ownIdentityId: Data? { DWCurrentUserIdentityInfo.shared.identityId }
    var ownIdentityIdBase58: String? { ownIdentityId?.toBase58String() }

    /// The typed query as a registrable label: valid DPNS label shape
    /// AND no document exists for its normalized form. Set by
    /// `updateSearch` using the SDK's own normalizer (DPNS folds
    /// look-alike characters, so a plain lowercase compare would lie).
    @Published var registrableQueryLabel: String?

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
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    func loadMyNames() {
        guard let ownBase58 = ownIdentityIdBase58 else { return }
        isLoadingMine = true
        Task { [weak self] in
            guard let self else { return }
            do {
                myNames = try await service.names(ownedBy: ownBase58)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingMine = false
        }
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
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - UsernameMarketplaceScreen

struct UsernameMarketplaceScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel = UsernameMarketplaceViewModel()
    @State private var selectedName: MarketplaceName?
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
        .sheet(item: $selectedName) { name in
            MarketplaceNameDetailSheet(name: name, viewModel: viewModel)
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
                            nameRow(name)
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
                    ForEach(viewModel.myNames) { name in
                        nameRow(name)
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable { viewModel.loadMyNames() }
    }

    // MARK: Rows

    private func nameRow(_ name: MarketplaceName) -> some View {
        let isMine = name.isOwned(by: viewModel.ownIdentityId)
        return Button {
            selectedName = name
        } label: {
            HStack(spacing: 10) {
                ContactAvatarView(
                    title: name.label,
                    avatarURL: nil,
                    identitySeed: Data.identifier(fromBase58: name.ownerIdBase58) ?? Data())
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                        .lineLimit(1)
                    Text(isMine
                        ? NSLocalizedString("Owned by you", comment: "Username marketplace")
                        : String(name.ownerIdBase58.prefix(8)) + "…" + String(name.ownerIdBase58.suffix(4)))
                        .font(.system(size: 11))
                        .foregroundColor(.dash.tertiaryText)
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

/// Identifiable wrapper so `.sheet(item:)` can present a register
/// candidate without a retroactive String conformance.
struct RegisterCandidate: Identifiable {
    let label: String
    var id: String { label }
}

// MARK: - MarketplaceNameDetailSheet

/// State-driven detail: what the name is, who owns it, its sale state,
/// and exactly the actions that state allows.
private struct MarketplaceNameDetailSheet: View {
    let name: MarketplaceName
    @ObservedObject var viewModel: UsernameMarketplaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingSetPrice = false
    @State private var showingTransfer = false
    @State private var confirmBuy = false
    @State private var confirmDelist = false

    private var isMine: Bool { name.isOwned(by: viewModel.ownIdentityId) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ContactAvatarView(
                    title: name.label,
                    avatarURL: nil,
                    identitySeed: Data.identifier(fromBase58: name.ownerIdBase58) ?? Data(),
                    size: 72)
                    .padding(.top, 28)

                Text(name.label)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                    .padding(.top, 10)

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

                infoCard
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                actions
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
            }
        }
        .background(Color.dash.primaryBackground)
        .sheet(isPresented: $showingSetPrice) {
            SetNamePriceSheet(name: name, viewModel: viewModel, onDone: { dismiss() })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingTransfer) {
            TransferNameSheet(name: name, viewModel: viewModel, onDone: { dismiss() })
                .presentationDetents([.medium, .large])
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            detailRow(
                NSLocalizedString("Owner", comment: "Username marketplace"),
                isMine
                    ? NSLocalizedString("You", comment: "Username marketplace: owner is the current user")
                    : String(name.ownerIdBase58.prefix(10)) + "…" + String(name.ownerIdBase58.suffix(6)))
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
            // Full pricing/transfer/purchase timeline requires the SDK's
            // document-revision history query (in progress); until then
            // this sheet shows only the facts the current document carries.
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.dash.secondaryBackground))
    }

    @ViewBuilder
    private var actions: some View {
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
                identityBalanceLine
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
                name.label),
            isPresented: $confirmBuy,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Buy", comment: "Username marketplace"), role: .none) {
                let expected = name.priceCredits ?? 0
                viewModel.perform(successText: String.localizedStringWithFormat(
                    NSLocalizedString("%@ is now yours", comment: "Username marketplace: purchase success"),
                    name.label)) {
                    try await viewModel.service.purchase(name: name, expectedPriceCredits: expected)
                }
                dismiss()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("The price plus a small network fee is paid from your identity balance. The name moves to your identity immediately.", comment: "Username marketplace: purchase confirmation body"))
        }
        .confirmationDialog(
            String.localizedStringWithFormat(
                NSLocalizedString("Remove “%@” from sale?", comment: "Username marketplace: delist confirmation title"),
                name.label),
            isPresented: $confirmDelist,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Remove From Sale", comment: "Username marketplace"), role: .destructive) {
                viewModel.perform(successText: String.localizedStringWithFormat(
                    NSLocalizedString("%@ is no longer for sale", comment: "Username marketplace: delist success"),
                    name.label)) {
                    try await viewModel.service.removeFromSale(name: name)
                }
                dismiss()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Removing the listing is a network transaction with a small fee, paid from your identity balance. You keep the name.", comment: "Username marketplace: delist confirmation body"))
        }
    }

    /// Buyer-side affordability line, from the same persisted identity
    /// balance the profile sheet shows.
    @ViewBuilder
    private var identityBalanceLine: some View {
        if let identityId = viewModel.ownIdentityId,
           let container = SwiftDashSDKHost.shared.modelContainer {
            let available = UsernameMarketplaceService.identityBalanceCredits(
                identityId: identityId, container: container)
            let needed = (name.priceCredits ?? 0) + UsernameMarketplaceService.purchaseFeeReserveCredits
            HStack {
                Text(NSLocalizedString("Identity Account Balance", comment: "SDK identity profile sheet — the identity's credit balance"))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.secondaryText)
                Spacer()
                Text("\((available / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol) DASH")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(available >= needed ? .dash.primaryText : .orange)
            }
            if available < needed {
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
    let name: MarketplaceName
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
                    name.label))
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
                        name.label,
                        duffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)) {
                        try await viewModel.service.setPrice(name: name, priceDuffs: duffs)
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
    let name: MarketplaceName
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
                    name.label))
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
                resolveError = error.localizedDescription
            }
        }
    }

    private func run(recipientBase58: String) {
        viewModel.perform(successText: String.localizedStringWithFormat(
            NSLocalizedString("%@ transferred", comment: "Username marketplace: transfer success"),
            name.label)) {
            try await viewModel.service.transfer(name: name, toIdentityBase58: recipientBase58)
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
