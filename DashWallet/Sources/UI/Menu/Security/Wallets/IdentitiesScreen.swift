//
//  IdentitiesScreen.swift
//  DashWallet
//
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
//  "Identities" screen (main menu, under Wallets). Lists the Platform
//  identities known to this device for the current network — modeled on
//  the SwiftExampleApp's Identities tab (name + star for the pinned main
//  DPNS name, balance, truncated id, type/local badges), rendered in the
//  WalletsScreen card style. Tapping a row opens a compact detail sheet
//  with the copyable full id. Pull down to refresh balances/names from
//  Platform. All data access lives in `IdentitiesViewModel`.
//

import SwiftUI
import SwiftDashSDK
import UIKit

struct IdentitiesScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel = IdentitiesViewModel()

    init(vc: UINavigationController) {
        self.vc = vc
    }

    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                if viewModel.rows.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(viewModel.rows) { row in
                                IdentityRowView(row: row)
                                    .contentShape(Rectangle())
                                    .onTapGesture { showDetail(row) }
                                if row.id != viewModel.rows.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color.secondaryBackground)
                        .cornerRadius(12)
                        .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    }
                    .refreshable {
                        await viewModel.refreshFromNetwork()
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .navigationBarHidden(true)
        .onAppear { viewModel.reload() }
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
        // Find-identities outcome ("Found N new identities" / none found).
        .alert(
            NSLocalizedString("Find identities", comment: "Identities"),
            isPresented: Binding(
                get: { viewModel.infoMessage != nil },
                set: { if !$0 { viewModel.infoMessage = nil } })
        ) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(viewModel.infoMessage ?? "")
        }
    }

    // MARK: - Navigation

    /// Push the identity's full detail page (WalletsScreen → accounts
    /// pattern). A page, not a sheet: the detail carries actions
    /// (set-main) and grows with future identity features.
    private func showDetail(_ row: IdentityRowModel) {
        let controller = UIHostingController(
            rootView: IdentityDetailScreen(row: row, vc: vc, viewModel: viewModel))
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: { vc.popViewController(animated: true) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
                }
                Spacer()
                // Explicit Find-identities command: DIP-9 scan of the active
                // wallet against Platform — discovers identities the store
                // has never seen (reinstall / imported phrase / other device).
                Button(action: { Task { await viewModel.discoverIdentities() } }) {
                    if viewModel.isDiscovering {
                        SwiftUI.ProgressView()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
                    }
                }
                .disabled(viewModel.isDiscovering || viewModel.isRefreshing)
                .accessibilityLabel(NSLocalizedString("Find identities", comment: "Identities"))

                Button(action: { Task { await viewModel.refreshFromNetwork() } }) {
                    if viewModel.isRefreshing {
                        SwiftUI.ProgressView()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
                    }
                }
                .disabled(viewModel.isRefreshing || viewModel.isDiscovering)
                .accessibilityLabel(NSLocalizedString("Refresh", comment: ""))
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            HStack {
                Text(NSLocalizedString("Identities", comment: "Identities"))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondaryText)

            Text(NSLocalizedString("No Identities", comment: "Identities"))
                .font(.headline)
                .foregroundColor(.primaryText)

            Text(NSLocalizedString(
                "Your Dash Platform identity appears here once you register a username.",
                comment: "Identities"))
                .font(.caption)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Restored/imported wallet: the identity may already exist on
            // Platform even though this device has never seen it.
            Button(action: { Task { await viewModel.discoverIdentities() } }) {
                HStack(spacing: 6) {
                    if viewModel.isDiscovering {
                        SwiftUI.ProgressView()
                    } else {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                    }
                    Text(NSLocalizedString("Find identities", comment: "Identities"))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.dashBlue)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.dashBlue.opacity(0.1))
                .clipShape(Capsule())
            }
            .disabled(viewModel.isDiscovering)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Row

private struct IdentityRowView: View {
    let row: IdentityRowModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(row.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(row.hasName ? .dashBlue : .primaryText)
                        .lineLimit(1)
                    if row.isMainName {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    if row.isMainIdentity {
                        IdentityBadge(
                            text: NSLocalizedString("Main", comment: "Identities — the wallet's main identity"),
                            icon: "checkmark.seal.fill",
                            color: .dashBlue)
                    }
                }
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                }
                Text(row.idBase58)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                badges
            }
            Spacer(minLength: 8)
            TransferSourceRow.dashBalanceTrailing(row.balanceText)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 60)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if row.type == .masternode {
                IdentityBadge(
                    text: NSLocalizedString("Masternode", comment: "Identities"),
                    icon: "server.rack",
                    color: .purple)
            } else if row.type == .evonode {
                IdentityBadge(
                    text: NSLocalizedString("Evonode", comment: "Identities"),
                    icon: "server.rack",
                    color: .indigo)
            }
            if row.isLocal {
                IdentityBadge(
                    text: NSLocalizedString("Local Only", comment: "Identities"),
                    icon: "location",
                    color: .orange)
            }
        }
    }
}

/// Compact colored capsule badge — same affordance as the example app's
/// identity row badges.
private struct IdentityBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(4)
    }
}

// MARK: - Detail page

/// Full identity detail page (pushed, not a sheet): copyable id,
/// balance, type, network status, owning wallet, key count, every owned
/// DPNS name — and the main-identity control. The main identity is the
/// one every DashPay surface keys on (username, avatar, contacts).
struct IdentityDetailScreen: View {
    let row: IdentityRowModel
    private let vc: UINavigationController
    @ObservedObject private var viewModel: IdentitiesViewModel

    @State private var copied = false
    /// Local main-state so the page reflects the change immediately;
    /// seeded from the row, flipped on a successful set-main.
    @State private var isMain: Bool
    @State private var confirmSetMain = false

    init(row: IdentityRowModel, vc: UINavigationController, viewModel: IdentitiesViewModel) {
        self.row = row
        self.vc = vc
        self.viewModel = viewModel
        _isMain = State(initialValue: row.isMainIdentity)
    }

    /// Only identities of the active wallet can become main — the pick
    /// re-keys the live DashPay surfaces, which follow the active wallet.
    private var canBecomeMain: Bool {
        !isMain && row.walletId != nil
            && row.walletId == SwiftDashSDKHost.shared.wallet?.walletId
    }

    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                pageHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        idCard
                        infoCard
                        if !row.dpnsNames.isEmpty {
                            namesCard
                        }
                        mainIdentityCard
                    }
                    .padding(20)
                }
            }
        }
        .navigationBarHidden(true)
        .alert(
            NSLocalizedString("Set as Main Identity", comment: "Identities"),
            isPresented: $confirmSetMain
        ) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Set as Main", comment: "Identities")) {
                viewModel.setMainIdentity(row)
                if viewModel.errorMessage == nil {
                    isMain = true
                }
            }
        } message: {
            Text(NSLocalizedString(
                "Your username, profile, and contacts will follow this identity.",
                comment: "Identities"))
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

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: { vc.popViewController(animated: true) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            HStack(spacing: 6) {
                Text(row.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                if isMain {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.dashBlue)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 6)
        }
    }

    /// Main-identity control: a checked state when this IS the main,
    /// a Set button when it can become it, and an explanatory line when
    /// it can't (other wallet's identity).
    private var mainIdentityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isMain {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.dashBlue)
                    Text(NSLocalizedString("This is your main identity", comment: "Identities"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primaryText)
                }
                Text(NSLocalizedString(
                    "Your username, profile, and contacts follow this identity.",
                    comment: "Identities"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
            } else if canBecomeMain {
                Button(action: { confirmSetMain = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                        Text(NSLocalizedString("Set as Main Identity", comment: "Identities"))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.dashBlue)
                    .cornerRadius(12)
                }
            } else {
                Text(NSLocalizedString(
                    "The main identity can only be chosen from the active wallet",
                    comment: "Identities"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var idCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Identity ID", comment: "Identities"))
                .font(.caption)
                .foregroundColor(.secondaryText)
            Text(row.idBase58)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.primaryText)
                .textSelection(.enabled)

            Button(action: copyId) {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied
                        ? NSLocalizedString("Copied", comment: "")
                        : NSLocalizedString("Copy", comment: ""))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.dashBlue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            detailRow(
                label: NSLocalizedString("Balance", comment: ""),
                value: row.balanceDetailText)
            divider
            detailRow(
                label: NSLocalizedString("Type", comment: "Identities"),
                value: typeName)
            divider
            detailRow(
                label: NSLocalizedString("Status", comment: ""),
                value: row.isLocal
                    ? NSLocalizedString("Local Only", comment: "Identities")
                    : NSLocalizedString("On Network", comment: "Identities"))
            if let walletName = row.walletName {
                divider
                detailRow(
                    label: NSLocalizedString("Wallet", comment: "Identities"),
                    value: walletName)
            }
            divider
            detailRow(
                label: NSLocalizedString("Identity index", comment: "Identities"),
                value: "#\(row.identityIndex)")
            divider
            detailRow(
                label: NSLocalizedString("Public keys", comment: "Identities"),
                value: "\(row.publicKeyCount)")
        }
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var namesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Usernames", comment: "Identities"))
                .font(.caption)
                .foregroundColor(.secondaryText)
            ForEach(row.dpnsNames, id: \.self) { name in
                Text(name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var typeName: String {
        switch row.type {
        case .user: return NSLocalizedString("User", comment: "Identities")
        case .masternode: return NSLocalizedString("Masternode", comment: "Identities")
        case .evonode: return NSLocalizedString("Evonode", comment: "Identities")
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray300.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func copyId() {
        UIPasteboard.general.string = row.idBase58
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
