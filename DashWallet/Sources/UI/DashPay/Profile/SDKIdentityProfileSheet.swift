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
    /// The ⓘ explains the difference; Top Up funds it from the
    /// Transparent balance via a Core asset lock.
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
                "This balance pays Dash Platform network fees — usernames, contact requests, profile updates. It belongs to your identity, not your wallet: unlike your Transparent, Platform, and Shielded balances it can't be spent as regular Dash. Topping up converts Dash from your Transparent balance into identity credits.",
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
                    .presentationDetents([.medium, .large])
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

/// Business side of the profile sheet's Top Up: PIN/biometric gate, then
/// one Core asset lock + IdentityTopUp transition via the SDK
/// (`topUpIdentityWithFunding` — funded from the wallet's Transparent
/// balance, account 0). Returns the identity's post-transition credit
/// balance for the sheet to display.
@MainActor
final class IdentityTopUpViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var errorMessage: String?

    private let authorizer = DWIdentityAuthorizer()

    /// Preset top-up amounts (duffs): 0.01 / 0.05 / 0.1 DASH, all well
    /// above the Rust-side minimum top-up asset lock of 50,500 duffs
    /// (mirrored from `DWIdentityRegistrationCoordinator.minimumCoreTopUpDuffs`).
    static let presetsDuffs: [UInt64] = [1_000_000, 5_000_000, 10_000_000]

    /// nil = cancelled or failed (errorMessage carries the failure).
    func topUp(identityId: Data, amountDuffs: UInt64) async -> UInt64? {
        guard !isProcessing else { return nil }
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            errorMessage = NSLocalizedString("Wallet is not ready", comment: "DashPay")
            return nil
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await authorizer.authorize()
        } catch {
            // Backing out of the PIN prompt is not an error state.
            return nil
        }
        do {
            return try await wallet.topUpIdentityWithFunding(
                identityId: identityId,
                amountDuffs: amountDuffs,
                accountIndex: 0)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

// MARK: - IdentityTopUpSheet

/// Amount picker + confirm for topping up the identity's credit balance
/// from the Transparent balance. Nothing is signed or broadcast until
/// Confirm passes the PIN gate.
struct IdentityTopUpSheet: View {
    let identityId: Data
    let currentBalanceCredits: UInt64
    let onToppedUp: (UInt64) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = IdentityTopUpViewModel()
    @State private var selectedDuffs: UInt64 = IdentityTopUpViewModel.presetsDuffs[0]

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
                    "Convert Dash from your Transparent balance into identity credits to pay for Platform actions like contact requests and profile updates.",
                    comment: "Identity top-up sheet — body"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)

                HStack(spacing: 10) {
                    ForEach(IdentityTopUpViewModel.presetsDuffs, id: \.self) { duffs in
                        Button {
                            selectedDuffs = duffs
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(duffs.dashAmount.formattedDashAmountWithoutCurrencySymbol)")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(CurrencyExchanger.shared.fiatAmountString(for: duffs.dashAmount))
                                    .font(.system(size: 11))
                                    .opacity(0.75)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedDuffs == duffs
                                        ? Color.dash.blue.opacity(0.12)
                                        : Color.dash.secondaryBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(selectedDuffs == duffs ? Color.dash.blue : .clear, lineWidth: 1.5))
                            .foregroundColor(selectedDuffs == duffs ? .dash.blue : .dash.primaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Text(NSLocalizedString("Paid from your Transparent balance, plus the network fee.", comment: "Identity top-up sheet — funding source note"))
                    .font(.system(size: 12))
                    .foregroundColor(.dash.tertiaryText)
                    .padding(.top, 8)

                Button {
                    confirm()
                } label: {
                    if viewModel.isProcessing {
                        SwiftUI.ProgressView()
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
                .disabled(viewModel.isProcessing)
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

    private func confirm() {
        Task {
            if let newBalance = await viewModel.topUp(
                identityId: identityId,
                amountDuffs: selectedDuffs) {
                onToppedUp(newBalance)
                dismiss()
            }
        }
    }
}
