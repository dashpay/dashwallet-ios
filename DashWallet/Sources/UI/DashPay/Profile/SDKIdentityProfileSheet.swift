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
    @StateObject private var walletState = SwiftDashSDKWalletState.shared
    @State private var identityIdHex: String? = nil
    @State private var dpnsNames: [String] = []
    @State private var hasIdentity: Bool = false
    @State private var pendingContestedName: String? = nil
    @State private var copyToast: String? = nil

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
                walletState.refreshPlatformPaymentCredits()
                loadIdentityId()
                dpnsNames = DWCurrentUserIdentityInfo.shared.usernames
                hasIdentity = DWCurrentUserIdentityInfo.shared.hasIdentity
                pendingContestedName = DWContestedNameStatusService.shared.pendingLabel
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
            ZStack {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 96, height: 96)
                Text(initial)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
            }
            Text(username)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)
            if pendingContestedName != nil {
                Label(
                    NSLocalizedString("Voting in progress", comment: "Usernames"),
                    systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.orange)
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
            infoRow(
                title: NSLocalizedString("Platform Credits", comment: "SDK identity profile sheet"),
                value: platformCreditsFormatted,
                monospaced: false,
                copyable: false
            )
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

    private var initial: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }

    private var platformCreditsFormatted: String {
        let duffs = walletState.platformPaymentCreditsAsDuffs
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
        }
    }
}
