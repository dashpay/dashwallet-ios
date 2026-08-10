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
import DashUIKit
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
            Color.dash.primaryBackground.ignoresSafeArea()

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
                        .background(Color.dash.secondaryBackground)
                        .cornerRadius(12)
                        .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
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
                        .foregroundColor(Color.dash.primaryText)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
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
                            .foregroundColor(Color.dash.primaryText)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
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
                            .foregroundColor(Color.dash.primaryText)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
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
                    .foregroundColor(.dash.primaryText)
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
                .foregroundColor(.dash.secondaryText)

            Text(NSLocalizedString("No Identities", comment: "Identities"))
                .font(.headline)
                .foregroundColor(.dash.primaryText)

            Text(NSLocalizedString(
                "Your Dash Platform identity appears here once you register a username.",
                comment: "Identities"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
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
                .foregroundColor(.dash.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.dash.blue.opacity(0.1))
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
                        .foregroundColor(row.hasName ? .dash.blue : .dash.primaryText)
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
                            color: .dash.blue)
                    }
                }
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.dash.secondaryText)
                        .lineLimit(1)
                }
                Text(row.idBase58)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.dash.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                badges
            }
            Spacer(minLength: 8)
            TransferSourceRow.dashBalanceTrailing(row.balanceText)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dash.secondaryText)
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
            if row.pendingContestedName != nil {
                IdentityBadge(
                    text: NSLocalizedString("Voting", comment: "Usernames"),
                    icon: "clock",
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

    /// Live projection of this identity from the shared view model —
    /// `row` is the push-time capture, so name-pick changes (which
    /// reload the view model) re-render through this instead.
    private var currentRow: IdentityRowModel {
        viewModel.rows.first(where: { $0.identityId == row.identityId }) ?? row
    }

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                pageHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        idCard
                        infoCard
                        if row.pendingContestedName != nil {
                            pendingNameCard
                        }
                        if !currentRow.dpnsNames.isEmpty {
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
                        .foregroundColor(Color.dash.primaryText)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            HStack(spacing: 6) {
                Text(currentRow.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                if isMain {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.dash.blue)
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
                        .foregroundColor(.dash.blue)
                    Text(NSLocalizedString("This is your main identity", comment: "Identities"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.dash.primaryText)
                }
                Text(
                    row.pendingContestedName == nil
                        ? NSLocalizedString(
                            "Your username, profile, and contacts follow this identity.",
                            comment: "Identities")
                        : NSLocalizedString(
                            "This identity is being used for your pending username request.",
                            comment: "Identities")
                )
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
            } else if canBecomeMain {
                Button(action: { confirmSetMain = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                        Text(NSLocalizedString("Set as Main Identity", comment: "Identities"))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.dash.blue)
                    .cornerRadius(12)
                }
            } else {
                Text(NSLocalizedString(
                    "The main identity can only be chosen from the active wallet",
                    comment: "Identities"))
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var idCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Identity ID", comment: "Identities"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
            Text(row.idBase58)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.dash.primaryText)
                .textSelection(.enabled)

            Button(action: copyId) {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied
                        ? NSLocalizedString("Copied", comment: "")
                        : NSLocalizedString("Copy", comment: ""))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.dash.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dash.secondaryBackground)
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
            Button(action: showPublicKeys) {
                HStack {
                    Text(NSLocalizedString("Public keys", comment: "Identities"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.secondaryText)
                    Spacer()
                    Text("\(row.publicKeys.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.dash.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(row.publicKeys.isEmpty)
        }
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    /// Push the identity's public-keys page (same push pattern as the
    /// list → detail navigation).
    private func showPublicKeys() {
        let controller = UIHostingController(
            rootView: IdentityPublicKeysScreen(row: row, vc: vc))
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }

    /// Owned DPNS names as a radio-style picker: the checked row is the
    /// name the identity displays everywhere (`mainDpnsName` pick, with
    /// the same fallback the row title uses); tapping another row
    /// persists it via `IdentitiesViewModel.setMainName`.
    private var namesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Usernames", comment: "Identities"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
            ForEach(currentRow.dpnsNames, id: \.self) { name in
                let isDisplayed = currentRow.displayedDpnsName.map {
                    DWContestedNameStatusService.labelsMatch(name, $0)
                } ?? false
                Button(action: { viewModel.setMainName(name, for: currentRow) }) {
                    HStack {
                        Text(name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.dash.primaryText)
                        Spacer()
                        Image(systemName: isDisplayed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(isDisplayed ? .dash.blue : Color.dash.gray300.opacity(0.6))
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isDisplayed ? [.isSelected] : [])
            }
            if currentRow.dpnsNames.count > 1 {
                Text(NSLocalizedString(
                    "Select the username to display for this identity.",
                    comment: "Identities"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var pendingNameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Username request", comment: "Usernames"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
            HStack {
                Text(row.pendingContestedName ?? "")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.dash.primaryText)
                Spacer()
                IdentityBadge(
                    text: NSLocalizedString("Voting", comment: "Usernames"),
                    icon: "clock",
                    color: .orange)
            }
            // A "Voting" badge with no end time leaves the user with nothing
            // to act on. The deadline is known from submission onward — an
            // estimate first, Platform's own `endTime` once it indexes the
            // contest — so show it here too.
            if let endTime = row.pendingVotingEndTime {
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("Voting ends around %@", comment: "Usernames"),
                    DWDateFormatter.sharedInstance.dateAndTime(from: endTime)))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dash.secondaryBackground)
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
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.dash.gray300.opacity(0.3))
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

// MARK: - IdentityPublicKeysScreen

/// The identity's DPP public keys (pushed from the detail's "Public keys"
/// row): one card per key with its id, purpose, security level, key type,
/// state badges, and the copyable key material. Read-only — key management
/// happens on Platform, not here.
struct IdentityPublicKeysScreen: View {
    let row: IdentityRowModel
    let vc: UINavigationController

    /// Key id whose Copy button just fired (transient checkmark).
    @State private var copiedKeyId: Int32?

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(row.publicKeys) { key in
                            keyCard(key)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    vc.popViewController(animated: true)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color.dash.primaryText)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            Text(NSLocalizedString("Public keys", comment: "Identities"))
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.dash.primaryText)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Text(row.title)
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 12)
        }
    }

    private func keyCard(_ key: IdentityKeyRowModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("Key #%d", comment: "Identities: one identity public key, by its DPP key id"),
                    key.keyId))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Spacer()
                if key.isDisabled {
                    IdentityBadge(
                        text: NSLocalizedString("Disabled", comment: "Identities: this identity key was disabled on Platform"),
                        icon: "nosign",
                        color: .red)
                } else if key.readOnly {
                    IdentityBadge(
                        text: NSLocalizedString("Read-only", comment: "Identities: key visible to the wallet but not usable for signing"),
                        icon: "eye",
                        color: .orange)
                }
            }

            VStack(spacing: 0) {
                attributeRow(
                    label: NSLocalizedString("Purpose", comment: "Identities: what a public key is used for"),
                    value: key.purposeText)
                attributeRow(
                    label: NSLocalizedString("Security level", comment: "Identities: DPP security level of a public key"),
                    value: key.securityLevelText)
                attributeRow(
                    label: NSLocalizedString("Type", comment: "Identities"),
                    value: key.keyTypeText)
            }

            Text(NSLocalizedString("Key data", comment: "Identities: the public key bytes"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
            Text(key.publicKeyHex)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.dash.primaryText)
                .textSelection(.enabled)

            Button {
                copy(key)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copiedKeyId == key.keyId ? "checkmark" : "doc.on.doc")
                    Text(copiedKeyId == key.keyId
                        ? NSLocalizedString("Copied", comment: "")
                        : NSLocalizedString("Copy", comment: ""))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.dash.blue)
            }

            if !key.contractBoundIds.isEmpty {
                Text(key.contractBoundDocumentType == nil
                    ? NSLocalizedString("Bound to contract", comment: "Identities: this key only signs for one data contract")
                    : String.localizedStringWithFormat(
                        NSLocalizedString("Bound to contract, document type “%@”", comment: "Identities: this key only signs one document type of one data contract"),
                        key.contractBoundDocumentType ?? ""))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                ForEach(key.contractBoundIds, id: \.self) { contractId in
                    Text(contractId)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.dash.secondaryText)
                        .textSelection(.enabled)
                }
            }

            if let path = key.derivationPath {
                Text(NSLocalizedString("Derivation path", comment: "Identities: BIP-32 style derivation path of this key"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                Text(path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.dash.secondaryText)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private func attributeRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }

    private func copy(_ key: IdentityKeyRowModel) {
        UIPasteboard.general.string = key.publicKeyHex
        copiedKeyId = key.keyId
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedKeyId == key.keyId { copiedKeyId = nil }
        }
    }
}
