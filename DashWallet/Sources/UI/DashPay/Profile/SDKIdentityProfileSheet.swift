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
    @State private var copyToast: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    Divider()
                    infoSection
                    Spacer(minLength: 24)
                    Text(NSLocalizedString("Profile editing for SwiftDashSDK-registered identities will land in a future update.",
                                            comment: "SDK identity profile sheet — hint"))
                        .font(.footnote)
                        .foregroundColor(.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
            }
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
