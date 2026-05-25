//
//  SDKIdentityProfileSheet.swift
//  DashWallet
//
//  Read-only profile sheet for SwiftDashSDK-registered DashPay
//  identities (row #17 stage A). Shown by `HomeViewController`'s
//  avatar tap when the user has an SDK identity but no DashSync
//  `defaultBlockchainIdentity` — which is the normal case for
//  Platform-Payment-funded registrations (no Core-chain footprint
//  for DashSync's scanner to pick up).
//
//  The legacy `RootEditProfileViewController` opens for DashSync-
//  side identities. This sheet is the SDK-side counterpart and
//  is intentionally minimal — username + identity ID + Platform
//  credits + a "coming soon" hint for profile editing. Row #17
//  proper replaces this with a real SDK-aware editor.
//

import SwiftData
import SwiftDashSDK
import SwiftUI

struct SDKIdentityProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var walletState = SwiftDashSDKWalletState.shared
    @State private var identityIdHex: String? = nil
    @State private var dpnsNames: [String] = []
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
                    if onEditTapped != nil {
                        editButton
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(Color.primaryBackground)
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
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }
            }
            .onAppear {
                walletState.refreshPlatformPaymentCredits()
                loadIdentityId()
                dpnsNames = DWCurrentUserIdentityInfo.shared.usernames
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
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.dashBlue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dashBlue)
                    .frame(width: 96, height: 96)
                Text(initial)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(username)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primaryText)
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
    /// helper). Pending-contested names show in the dedicated
    /// `ContestedNameStatusView` instead, not here.
    private var namesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("DPNS Names", comment: "SDK identity profile sheet — usernames list"))
                .font(.caption)
                .foregroundColor(.secondaryText)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(dpnsNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Text(name)
                            .font(.body)
                            .foregroundColor(.primaryText)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = name
                            showCopyToast()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.secondaryText)
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
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func infoRow(title: String, value: String, monospaced: Bool, copyable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondaryText)
            HStack(alignment: .top, spacing: 8) {
                Text(value)
                    .font(monospaced ? .system(.body, design: .monospaced) : .body)
                    .foregroundColor(.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if copyable {
                    Button {
                        UIPasteboard.general.string = value
                        showCopyToast()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Derivations

    private var username: String {
        DWGlobalOptions.sharedInstance().dashpayUsername ?? "—"
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
