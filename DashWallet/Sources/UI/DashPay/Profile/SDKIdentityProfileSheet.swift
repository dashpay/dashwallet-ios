//
//  SDKIdentityProfileSheet.swift
//  DashWallet
//
//  Current-user DashPay profile sheet backed by the app-owned identity
//  snapshot. It displays identity details and routes Edit to the existing
//  SDK-aware profile editor.
//

import SwiftData
import SwiftDashSDK
import SwiftUI
import DashUIKit

struct SDKIdentityProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var identityIdHex: String? = nil
    /// Owner's profile picture, read from the same identity snapshot the rest
    /// of the app renders from. nil → the deterministic initials placeholder.
    @State private var avatarURL: String?
    /// Raw identity id backing the avatar's placeholder derivation, matching
    /// what the contacts list passes for other users.
    @State private var identitySeed = Data()
    @State private var dpnsNames: [String] = []
    @State private var hasIdentity: Bool = false
    @State private var pendingContestedName: String? = nil
    /// Best-known close time of the pending contest. Starts as the
    /// submission-time estimate and is replaced by Platform's
    /// `ContestVoteState.endTime` once the contest is indexed.
    @State private var pendingVotingEndTime: Date? = nil
    @State private var copyToast: String? = nil
    /// The identity's credit balance (credits, 1000 credits = 1 duff),
    /// from the persisted identity row; refreshed by a top-up's returned
    /// post-transition balance. nil until the identity row loads.
    @State private var identityBalanceCredits: UInt64?
    /// 32-byte identity id the top-up transition targets.
    @State private var identityIdData: Data?
    @State private var showingBalanceInfo = false
    @State private var showingTopUp = false

    /// Callback invoked when the user taps Edit. Owner (HomeViewController)
    /// dismisses the sheet and pushes `RootEditProfileViewController`.
    /// Nil → no Edit button is shown (back-compat with callers that
    /// haven't wired up the edit flow yet).
    var onEditTapped: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    Divider()
                    infoSection
                    if !dpnsNames.isEmpty {
                        namesSection
                    }
                    // Edit Profile gated on hasIdentity: the editor's
                    // Save path resolves the identity via the SDK
                    // helper, so without it the button would lead to
                    // a broken screen.
                    if onEditTapped != nil && hasIdentity && pendingContestedName == nil {
                        editButton
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(Color.dash.primaryBackground)
            .navigationTitle(NSLocalizedString("My Profile", comment: "SDK identity profile sheet — title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = copyToast {
                    Text(toast)
                        .font(.subheadline)
                        .foregroundColor(Color.dash.whiteText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.dash.backgroundOverlay)
                        .clipShape(Capsule())
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }
            }
            .onAppear {
                loadIdentityId()
                dpnsNames = DWCurrentUserIdentityInfo.shared.usernames
                hasIdentity = DWCurrentUserIdentityInfo.shared.hasIdentity
                pendingContestedName = DWContestedNameStatusService.shared.pendingLabel
                pendingVotingEndTime = DWContestedNameStatusService.shared.pendingVotingEndTime
                avatarURL = DWCurrentUserIdentityInfo.shared.avatarURL
            }
        }
    }

    // MARK: - Edit button

    private var editButton: some View {
        Button {
            // The sheet's owner (HomeViewController) is responsible for
            // dismissing this sheet AND pushing `RootEditProfileViewController`
            // — keep the SwiftUI side free of UIKit presentation plumbing.
            dismiss()
            onEditTapped?()
        } label: {
            Text(NSLocalizedString("Edit Profile", comment: "SDK identity profile sheet — edit button"))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(Color.dash.whiteText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.dash.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            // Was a hardcoded blue circle with an initial — this screen never
            // rendered the profile picture at all. `ContactAvatarView` is the
            // app's one avatar path (remote image, else the deterministic
            // placeholder that matches Android), so the owner's own profile
            // now looks the same here as it does everywhere they appear.
            ContactAvatarView(
                title: username,
                avatarURL: avatarURL,
                identitySeed: identitySeed,
                size: 96)
            Text(username)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)
            if pendingContestedName != nil {
                VStack(spacing: 2) {
                    Label(
                        NSLocalizedString("Voting in progress", comment: "Usernames"),
                        systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.orange)
                    if let pendingVotingEndTime {
                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("Ends around %@", comment: "Usernames"),
                            DWDateFormatter.sharedInstance.dateAndTime(from: pendingVotingEndTime)))
                            .font(.caption2)
                            .foregroundColor(.dash.secondaryText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Info rows

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoRow(
                title: NSLocalizedString("Identity ID", comment: "SDK identity profile sheet"),
                value: identityIdHex ?? NSLocalizedString("Loading…", comment: ""),
                monospaced: true,
                copyable: identityIdHex != nil
            )
            identityBalanceRow
        }
    }

    /// The identity's own credit balance (NOT the wallet's Platform
    /// address balance — the row this replaces read
    /// `platformPaymentCreditsAsDuffs` under a "Platform Credits" label,
    /// which showed the DIP-17 wallet balance on an identity sheet).
    /// The ⓘ explains the difference; Top Up funds it from a
    /// user-selected balance, Shielded by default.
    private var identityBalanceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(NSLocalizedString("Identity Account Balance", comment: "SDK identity profile sheet — the identity's credit balance"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                Button {
                    showingBalanceInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.dash.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("About the identity account balance", comment: "SDK identity profile sheet — info button"))
            }
            HStack(alignment: .center, spacing: 8) {
                Text(identityBalanceFormatted)
                    .font(.body)
                    .foregroundColor(.dash.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if identityIdData != nil {
                    Button {
                        showingTopUp = true
                    } label: {
                        Text(NSLocalizedString("Top Up", comment: "SDK identity profile sheet — add credits to the identity"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.dash.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.dash.blue.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert(
            NSLocalizedString("Identity Account Balance", comment: "SDK identity profile sheet — the identity's credit balance"),
            isPresented: $showingBalanceInfo
        ) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "This balance pays Dash Platform network fees — usernames, contact requests, profile updates. It belongs to your identity, not your wallet: unlike your Transparent, Platform, and Shielded balances it can't be spent as regular Dash. Topping up converts Dash from a balance you choose — Shielded by default — into identity credits.",
                comment: "SDK identity profile sheet — explains the identity credit balance"))
        }
        .sheet(isPresented: $showingTopUp) {
            if let identityIdData {
                IdentityTopUpSheet(
                    identityId: identityIdData,
                    currentBalanceCredits: identityBalanceCredits ?? 0,
                    onToppedUp: { newBalanceCredits in
                        identityBalanceCredits = newBalanceCredits
                    })
                    // Full-height: the source picker + amount chips +
                    // custom field don't fit a half sheet without
                    // clipping the confirm button.
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: - DPNS names list

    /// Lists every DPNS label `getDpnsNames()` returns for the current
    /// identity (with the pending-contested label filtered out by the
    /// helper). A pending-contested name is shown separately in the header
    /// with an explicit voting status, never in this owned-names list.
    private var namesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("DPNS Names", comment: "SDK identity profile sheet — usernames list"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(dpnsNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Text(name)
                            .font(.body)
                            .foregroundColor(.dash.primaryText)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = name
                            showCopyToast()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.dash.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 12)
                    if index < dpnsNames.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func infoRow(title: String, value: String, monospaced: Bool, copyable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
            HStack(alignment: .top, spacing: 8) {
                Text(value)
                    .font(monospaced ? .system(.body, design: .monospaced) : .body)
                    .foregroundColor(.dash.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if copyable {
                    Button {
                        UIPasteboard.general.string = value
                        showCopyToast()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.dash.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Derivations

    private var username: String {
        pendingContestedName
            ?? DWGlobalOptions.sharedInstance().dashpayUsername
            ?? "—"
    }

    private var identityBalanceFormatted: String {
        guard let credits = identityBalanceCredits else {
            return NSLocalizedString("Loading…", comment: "")
        }
        let duffs = credits / 1000
        if duffs == 0 {
            return NSLocalizedString("0 DASH", comment: "SDK identity profile sheet — zero Platform credits")
        }
        return "\(duffs.dashAmount.formattedDashAmountWithoutCurrencySymbol) DASH"
    }

    // MARK: - Side effects

    private func showCopyToast() {
        copyToast = NSLocalizedString("Copied", comment: "SDK identity profile sheet — copy confirmation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copyToast = nil }
        }
    }

    /// Look up the persisted identity ID from SwiftData. Mirrors the
    /// fetch pattern in `DWIdentityRegistrationCoordinator.lookupExistingIdentityId`
    /// (PersistentIdentity scoped to the active wallet); we render the
    /// 32-byte id as lowercase hex matching the existing coordinator
    /// logs (`identityId.map { String(format: "%02x", $0) }.joined()`).
    private func loadIdentityId() {
        guard
            let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
            let container = SwiftDashSDKHost.shared.modelContainer
        else { return }

        let context = container.mainContext
        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { identity in
                identity.wallet?.walletId == walletId
            }
        )
        descriptor.fetchLimit = 1
        if let identity = try? context.fetch(descriptor).first {
            identityIdHex = identity.identityId.map { String(format: "%02x", $0) }.joined()
            identitySeed = identity.identityId
            identityIdData = identity.identityId
            // Stored as the Int64 bit-pattern of the UInt64 credits (see
            // IdentitiesViewModel's identical read).
            identityBalanceCredits = UInt64(bitPattern: identity.balance)
        }
    }
}

// MARK: - IdentityTopUpViewModel

/// Business side of the profile sheet's Top Up: one PIN/biometric gate,
/// then the funding route the user picked.
///
/// - `.shielded` (default — keeps the identity unlinked from transparent
///   coins): two steps. Step 1 unshields the amount from the Orchard pool
///   to the wallet's own next Platform receive address
///   (`shieldedUnshield`, proven execution). Step 2 claims the landed
///   credits minus the policy fee headroom from that address into an
///   IdentityTopUp (`topUpFromAddresses` — its fee comes out of the
///   supplied credits, so the identity receives "most" of the amount and
///   the unclaimed headroom stays in the Platform balance).
/// - `.platform`: one `topUpFromAddresses` over inputs selected by
///   `PlatformPaymentIdentityFundingPolicy` (same policy the registration
///   coordinator uses).
/// - `.transparent`: one Core asset lock + IdentityTopUp
///   (`topUpIdentityWithFunding`, account 0).
///
/// Returns the identity's post-transition credit balance.
@MainActor
final class IdentityTopUpViewModel: ObservableObject {

    enum FundingSource: CaseIterable {
        case shielded
        case platform
        case transparent

        /// The funding source that spends `network`'s balance — the internal
        /// transfer screen's bridge from its FROM side to this executor.
        init(spending network: ChainNetwork) {
            switch network {
            case .core: self = .transparent
            case .platform: self = .platform
            case .shielded: self = .shielded
            }
        }

        var title: String {
            switch self {
            case .shielded: return NSLocalizedString("Shielded", comment: "Shielded activity: funds moved into the private shielded balance")
            case .platform: return NSLocalizedString("Platform", comment: "Identity top-up sheet — the DIP-17 Platform address balance")
            case .transparent: return NSLocalizedString("Transparent", comment: "Identity top-up sheet — the Core wallet balance")
            }
        }
    }

    @Published var isProcessing = false
    @Published var errorMessage: String?
    /// User-visible progress for the shielded route's two steps.
    @Published var stepLabel: String?

    private let authorizer = DWIdentityAuthorizer()

    enum TopUpError: LocalizedError {
        case noPlatformReceiveAddress

        var errorDescription: String? {
            switch self {
            case .noPlatformReceiveAddress:
                return NSLocalizedString("No Platform receive address is available yet — wait for the Platform sync to finish and try again.", comment: "Identity top-up sheet — missing unshield destination")
            }
        }
    }

    /// Preset top-up amounts (duffs): 0.05 / 0.1 DASH. Small amounts are
    /// deliberately not offered — the fixed fees (especially the shielded
    /// route's unshield step) would be a large share of them. A custom
    /// amount is accepted down to `customMinimumDuffs`.
    static let presetsDuffs: [UInt64] = [5_000_000, 10_000_000]

    /// Floor for the custom amount: 0.01 DASH — well above the Rust-side
    /// minimum top-up asset lock of 50,500 duffs (mirrored from
    /// `DWIdentityRegistrationCoordinator.minimumCoreTopUpDuffs`) and large
    /// enough that the fees below can't consume it.
    static let customMinimumDuffs: UInt64 = 1_000_000

    /// Observed IdentityTopUp/from-addresses transition fee — ~0.0004 DASH
    /// ("required 41500000" credits, the measurement
    /// `PlatformPaymentIdentityFundingPolicy`'s headroom doc cites). The
    /// actual fee is metered at execution; this is the display estimate.
    static let observedTopUpTransitionFeeCredits: UInt64 = 41_500_000

    /// Display fee estimate (credits) for a route: the consensus-pinned
    /// unshield minimum (shielded route only, via the pure
    /// `estimateShieldedFee` FFI) plus the observed top-up transition fee.
    /// The transparent route also pays a small Core miner fee on top.
    /// `nil` when the shielded route's unshield estimate is unavailable —
    /// callers show "no number" rather than only the transition fee.
    static func estimatedFeeCredits(source: FundingSource) -> UInt64? {
        let unshieldFee: UInt64
        if source == .shielded {
            guard let estimate = try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(kind: .unshield, numActions: 2) else {
                return nil
            }
            unshieldFee = estimate
        } else {
            unshieldFee = 0
        }
        return unshieldFee + observedTopUpTransitionFeeCredits
    }

    /// nil = cancelled or failed (errorMessage carries the failure).
    func topUp(identityId: Data, amountDuffs: UInt64, source: FundingSource) async -> UInt64? {
        guard !isProcessing else { return nil }
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            errorMessage = NSLocalizedString("Wallet is not ready", comment: "DashPay")
            return nil
        }
        isProcessing = true
        defer {
            isProcessing = false
            stepLabel = nil
        }
        do {
            try await authorizer.authorize()
        } catch {
            // Backing out of the PIN prompt is not an error state.
            return nil
        }
        do {
            switch source {
            case .transparent:
                return try await wallet.topUpIdentityWithFunding(
                    identityId: identityId,
                    amountDuffs: amountDuffs,
                    accountIndex: 0)

            case .platform:
                let credits = amountDuffs * PlatformPaymentIdentityFundingPolicy.creditsPerDuff
                let candidates = try PlatformPaymentIdentityFundingPolicy.candidates(
                    walletId: wallet.walletId,
                    modelContainer: modelContainer)
                let inputs = try PlatformPaymentIdentityFundingPolicy.makeInputs(
                    candidates: candidates,
                    targetCredits: credits)
                let signer = KeychainSigner(modelContainer: modelContainer)
                return try await wallet.topUpFromAddresses(
                    identityId: identityId,
                    inputs: inputs,
                    addressSigner: signer)

            case .shielded:
                return try await topUpFromShielded(
                    identityId: identityId,
                    amountDuffs: amountDuffs,
                    wallet: wallet,
                    modelContainer: modelContainer)
            }
        } catch let error as PlatformPaymentIdentityFundingPolicy.PlanningError {
            if case .insufficient(let required, let available) = error {
                errorMessage = String.localizedStringWithFormat(
                    NSLocalizedString("Not enough funds in this balance: %@ DASH needed, %@ DASH available.", comment: "Identity top-up sheet — insufficient funding source"),
                    (required / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol,
                    (available / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol)
            } else {
                errorMessage = error.localizedDescription
            }
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// The privacy-default two-step: Shielded → own Platform address →
    /// identity credits.
    private func topUpFromShielded(
        identityId: Data,
        amountDuffs: UInt64,
        wallet: ManagedPlatformWallet,
        modelContainer: ModelContainer
    ) async throws -> UInt64 {
        guard let manager = SwiftDashSDKHost.shared.manager else {
            throw SwiftDashSDKContactsService.ServiceError.noWallet
        }
        guard let destination = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.nextReceiveAddress?.address,
            !destination.isEmpty,
            let storageBytes = AddressTransformer.parseBech32mAddress(destination),
            storageBytes.count == 21 else {
            // Typed so the generic catch surfaces THIS message instead of
            // overwriting it with an unrelated one.
            throw TopUpError.noPlatformReceiveAddress
        }
        let credits = amountDuffs * PlatformPaymentIdentityFundingPolicy.creditsPerDuff

        // Step 1: Orchard notes → own Platform address. `shieldedUnshield`
        // waits for proven execution, so the credits are on-chain at the
        // destination when it returns; the unshield's own fee comes from
        // the shielded side on top of `credits`.
        stepLabel = NSLocalizedString("Step 1 of 2 — moving Dash out of your Shielded balance…", comment: "Identity top-up sheet — shielded route progress")
        try await manager.shieldedUnshield(
            walletId: wallet.walletId,
            resolver: MnemonicResolver(),
            account: 0,
            toPlatformAddress: destination,
            amount: credits)
        // Same post-spend refreshes the transfer coordinator schedules —
        // BLAST stays the source of truth for the persisted balances.
        PlatformAddressSyncCoordinator.shared.refreshShieldedBalanceAfterSpend(using: manager)

        // Step 2: claim the landed credits minus the policy's fee headroom
        // into the identity. The transition's fee is deducted from the
        // supplied credits; the unclaimed headroom stays at the address
        // (it is the wallet's own Platform balance, not lost).
        stepLabel = NSLocalizedString("Step 2 of 2 — topping up your identity…", comment: "Identity top-up sheet — shielded route progress")
        let claim = credits > PlatformPaymentIdentityFundingPolicy.feeHeadroomCredits
            ? credits - PlatformPaymentIdentityFundingPolicy.feeHeadroomCredits
            : credits
        let input = ManagedPlatformWallet.IdentityAddressInput(
            addressType: storageBytes[storageBytes.startIndex],
            hash: Data(storageBytes.dropFirst()),
            credits: claim)
        let signer = KeychainSigner(modelContainer: modelContainer)
        let newBalance = try await wallet.topUpFromAddresses(
            identityId: identityId,
            inputs: [input],
            addressSigner: signer)
        Task { await PlatformAddressSyncCoordinator.shared.syncNow() }
        return newBalance
    }
}

// MARK: - IdentityTopUpSheet

/// Amount + funding-source picker and confirm for topping up the
/// identity's credit balance (Shielded by default). Nothing is signed or
/// broadcast until Confirm passes the PIN gate.
struct IdentityTopUpSheet: View {
    let identityId: Data
    let currentBalanceCredits: UInt64
    let onToppedUp: (UInt64) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = IdentityTopUpViewModel()
    /// nil = the Custom chip is selected and `customText` carries the amount.
    @State private var selectedPresetDuffs: UInt64? = IdentityTopUpViewModel.presetsDuffs[0]
    @State private var customText = ""
    @FocusState private var customFieldFocused: Bool
    /// Shielded is the privacy default; the transparent-side sources are
    /// an explicit opt-in behind the linkability warning.
    @State private var source: IdentityTopUpViewModel.FundingSource = .shielded

    var body: some View {
        // Scrollable so every action stays reachable at large Dynamic
        // Type sizes.
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.dash.blue)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.dash.blue.opacity(0.08)))
                    .padding(.top, 28)

                Text(NSLocalizedString("Top Up Identity Balance", comment: "Identity top-up sheet — title"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                    .padding(.top, 16)

                Text(NSLocalizedString(
                    "Convert Dash into identity credits to pay for Platform actions like contact requests and profile updates.",
                    comment: "Identity top-up sheet — body"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Pay from", comment: "Identity top-up sheet — funding source picker label"))
                        .font(.caption)
                        .foregroundColor(.dash.secondaryText)
                    Picker(NSLocalizedString("Pay from", comment: "Identity top-up sheet — funding source picker label"), selection: $source) {
                        ForEach(IdentityTopUpViewModel.FundingSource.allCases, id: \.self) { candidate in
                            Text(candidate.title).tag(candidate)
                        }
                    }
                    .pickerStyle(.segmented)
                    if source == .shielded {
                        Text(NSLocalizedString(
                            "Recommended: a two-step transfer through your own Platform address keeps your identity unlinked from your transparent coins.",
                            comment: "Identity top-up sheet — shielded source note"))
                            .font(.system(size: 12))
                            .foregroundColor(.dash.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label {
                            Text(NSLocalizedString(
                                "Funding from a transparent balance publicly links those coins to your identity on the Dash chain. For privacy, pay from your Shielded balance.",
                                comment: "Identity top-up sheet — linkability warning for transparent-side sources"))
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                HStack(spacing: 10) {
                    ForEach(IdentityTopUpViewModel.presetsDuffs, id: \.self) { duffs in
                        amountChip(isSelected: selectedPresetDuffs == duffs) {
                            selectedPresetDuffs = duffs
                            customFieldFocused = false
                        } content: {
                            VStack(spacing: 2) {
                                Text("\(duffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(CurrencyExchanger.shared.fiatAmountString(for: duffs.dashAmount))
                                    .font(.system(size: 11))
                                    .opacity(0.75)
                            }
                        }
                    }
                    amountChip(isSelected: selectedPresetDuffs == nil) {
                        selectedPresetDuffs = nil
                        customFieldFocused = true
                    } content: {
                        VStack(spacing: 2) {
                            Text(NSLocalizedString("Custom", comment: "Identity top-up sheet — free amount chip"))
                                .font(.system(size: 15, weight: .semibold))
                            Text(verbatim: "···")
                                .font(.system(size: 11))
                                .opacity(0.75)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                if selectedPresetDuffs == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            NSLocalizedString("Amount in DASH", comment: "Identity top-up sheet — custom amount placeholder"),
                            text: $customText)
                            .keyboardType(.decimalPad)
                            .focused($customFieldFocused)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.dash.secondaryBackground))
                        if let duffs = customDuffs {
                            Text(CurrencyExchanger.shared.fiatAmountString(for: duffs.dashAmount))
                                .font(.system(size: 12))
                                .foregroundColor(.dash.secondaryText)
                        } else if !customText.isEmpty {
                            Text(String.localizedStringWithFormat(
                                NSLocalizedString("Enter at least %@ DASH", comment: "Identity top-up sheet — custom amount below the floor"),
                                IdentityTopUpViewModel.customMinimumDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol))
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                HStack {
                    Text(NSLocalizedString("Estimated fees", comment: "Identity top-up sheet — fee estimate line"))
                        .font(.system(size: 13))
                        .foregroundColor(.dash.secondaryText)
                    Spacer()
                    Text(estimatedFeeText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

                Text(NSLocalizedString("Fees are taken from the amount; from Shielded, a small remainder may stay in your Platform balance.", comment: "Identity top-up sheet — fee note"))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.tertiaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Button {
                    confirm()
                } label: {
                    if viewModel.isProcessing {
                        VStack(spacing: 6) {
                            SwiftUI.ProgressView()
                            if let step = viewModel.stepLabel {
                                Text(step)
                                    .font(.system(size: 12))
                                    .foregroundColor(.dash.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    } else {
                        Text(NSLocalizedString("Top Up", comment: "SDK identity profile sheet — add credits to the identity"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.dash.whiteText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.dash.blue)
                            .cornerRadius(12)
                    }
                }
                .disabled(viewModel.isProcessing || effectiveDuffs == nil)
                .opacity(effectiveDuffs == nil ? 0.55 : 1)
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
                .disabled(viewModel.isProcessing)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
        .background(Color.dash.primaryBackground)
        .interactiveDismissDisabled(viewModel.isProcessing)
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

    /// Shared chip chrome for the preset and Custom amount buttons.
    private func amountChip<Content: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.dash.blue.opacity(0.12) : Color.dash.secondaryBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.dash.blue : .clear, lineWidth: 1.5))
                .foregroundColor(isSelected ? .dash.blue : .dash.primaryText)
        }
        .buttonStyle(.plain)
    }

    /// Parsed custom amount in duffs; nil when absent or below the floor.
    private var customDuffs: UInt64? {
        let normalized = customText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let dash = Decimal(string: normalized), dash > 0, dash <= 1000 else { return nil }
        let duffsDecimal = dash * Decimal(kOneDash)
        guard let duffs = UInt64(exactly: NSDecimalNumber(decimal: duffsDecimal).int64Value),
              duffs >= IdentityTopUpViewModel.customMinimumDuffs else { return nil }
        return duffs
    }

    /// The amount the Top Up button will submit — preset or valid custom.
    private var effectiveDuffs: UInt64? {
        selectedPresetDuffs ?? customDuffs
    }

    private var estimatedFeeText: String {
        guard let credits = IdentityTopUpViewModel.estimatedFeeCredits(source: source) else {
            // Shielded route with the unshield estimate unavailable: show no
            // number rather than one that omits the larger fee component.
            return "—"
        }
        let duffs = credits / 1000
        return String.localizedStringWithFormat(
            NSLocalizedString("~%@ DASH (≈ %@)", comment: "DashPay: estimated network fee — DASH amount, then its local-currency equivalent"),
            duffs.dashAmount.formattedDashAmountWithoutCurrencySymbol,
            CurrencyExchanger.shared.fiatAmountString(for: duffs.dashAmount))
    }

    private func confirm() {
        guard let amountDuffs = effectiveDuffs else { return }
        Task {
            if let newBalance = await viewModel.topUp(
                identityId: identityId,
                amountDuffs: amountDuffs,
                source: source) {
                onToppedUp(newBalance)
                dismiss()
            }
        }
    }
}
