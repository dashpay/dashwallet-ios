//
//  WalletsScreen.swift
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
//  "Wallets" screen (main menu). Lists the on-device SwiftDashSDK wallets
//  for the current network, one marked active. Tapping a wallet opens its
//  per-account breakdown (`WalletAccountsScreen`); switch, rename, and
//  per-wallet remove live in the row's menu. All logic lives in
//  `WalletsViewModel`; this view only renders.
//

import SwiftUI
import DashUIKit
import UIKit

struct WalletsScreen: View {
    private let vc: UINavigationController
    private let resetDelegate: ResetDelegate

    @StateObject private var viewModel = WalletsViewModel()

    /// The wallet a confirmation/rename/remove flow is currently targeting.
    @State private var pendingSwitch: WalletRow? = nil
    @State private var renameTarget: WalletRow? = nil
    @State private var renameText: String = ""
    @State private var removeTarget: WalletRow? = nil
    /// True while the "Add Wallet" sheet (create / import) is presented.
    @State private var showAddWallet = false

    init(vc: UINavigationController, wipeDelegate: DWWipeDelegate? = nil) {
        self.vc = vc
        self.resetDelegate = ResetDelegate(onFinish: { [weak vc] in
            vc?.popViewController(animated: true)
        }, wipeDelegate: wipeDelegate)
    }

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.rows) { row in
                            WalletRowView(
                                row: row,
                                onSwitch: { pendingSwitch = row },
                                onRename: {
                                    renameText = row.displayName
                                    renameTarget = row
                                },
                                onRemove: { beginRemove(row) })
                                .contentShape(Rectangle())
                                .onTapGesture { showAccounts(row) }
                                .contextMenu {
                                    if !row.isActive {
                                        Button {
                                            pendingSwitch = row
                                        } label: {
                                            Label(NSLocalizedString("Switch to this wallet", comment: "Wallets"), systemImage: "arrow.left.arrow.right")
                                        }
                                    }
                                    Button {
                                        renameText = row.displayName
                                        renameTarget = row
                                    } label: {
                                        Label(NSLocalizedString("Rename", comment: "Wallets"), systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        beginRemove(row)
                                    } label: {
                                        Label(NSLocalizedString("Remove", comment: "Wallets"), systemImage: "trash")
                                    }
                                }
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

                Spacer(minLength: 0)
            }

            if viewModel.switchInProgress || viewModel.removeInProgress {
                progressOverlay
            }
        }
        .navigationBarHidden(true)
        .onAppear { viewModel.reload() }
        // Switch confirmation
        .alert(
            NSLocalizedString("Switch Wallet", comment: "Wallets"),
            isPresented: Binding(
                get: { pendingSwitch != nil },
                set: { if !$0 { pendingSwitch = nil } })
        ) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { pendingSwitch = nil }
            Button(NSLocalizedString("Switch", comment: "Wallets")) {
                if let target = pendingSwitch { viewModel.switchWallet(to: target.walletId) }
                pendingSwitch = nil
            }
        } message: {
            Text(String(
                format: NSLocalizedString("Switch to \"%@\"? The app will reload with this wallet active.", comment: "Wallets"),
                pendingSwitch?.displayName ?? ""))
        }
        // Rename
        .alert(
            NSLocalizedString("Rename Wallet", comment: "Wallets"),
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } })
        ) {
            TextField(NSLocalizedString("Wallet name", comment: "Wallets"), text: $renameText)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { renameTarget = nil }
            Button(NSLocalizedString("Save", comment: "Wallets")) {
                if let target = renameTarget { viewModel.rename(walletId: target.walletId, to: renameText) }
                renameTarget = nil
            }
        } message: {
            Text(NSLocalizedString("Leave the name empty to reset it to the default.", comment: "Wallets"))
        }
        // Add Wallet (create / import)
        .sheet(isPresented: $showAddWallet) {
            AddWalletSheet(
                viewModel: viewModel,
                onFinished: { showAddWallet = false },
                onSwitchToExisting: { walletId in
                    showAddWallet = false
                    viewModel.switchWallet(to: walletId)
                })
        }
        // Remove (recovery-phrase confirmation sheet)
        .sheet(item: $removeTarget) { target in
            RemoveWalletSheet(
                row: target,
                verify: { phrase in viewModel.recoveryPhraseMatches(phrase, walletId: target.walletId) },
                onConfirmed: {
                    removeTarget = nil
                    Task { await viewModel.removeWallet(walletId: target.walletId) }
                },
                onCancel: { removeTarget = nil })
        }
        // Errors
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
                Button(action: { showAddWallet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color.dash.primaryText)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
                }
                .accessibilityLabel(NSLocalizedString("Add Wallet", comment: "Wallets"))
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            HStack {
                Text(NSLocalizedString("Wallets", comment: "Wallets"))
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

    private var progressOverlay: some View {
        ZStack {
            Color.dash.backgroundOverlay.ignoresSafeArea()
            VStack(spacing: 14) {
                // Fully qualified: the app has a UIKit `ProgressView: UIView`
                // that otherwise shadows SwiftUI's.
                SwiftUI.ProgressView()
                    .tint(Color.dash.whiteText)
                Text(viewModel.removeInProgress
                    ? NSLocalizedString("Removing wallet…", comment: "Wallets")
                    : NSLocalizedString("Switching wallet…", comment: "Wallets"))
                    .font(.subheadline)
                    .foregroundColor(Color.dash.whiteText)
            }
            .padding(24)
            .background(Color.dash.backgroundOverlay)
            .cornerRadius(14)
        }
    }

    // MARK: - Accounts

    /// Push the tapped wallet's per-account breakdown.
    private func showAccounts(_ row: WalletRow) {
        let controller = UIHostingController(
            rootView: WalletAccountsScreen(vc: vc, walletId: row.walletId, walletName: row.displayName))
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }

    // MARK: - Remove routing

    /// The last remaining wallet routes to the existing full reset flow
    /// (`DWResetWalletInfoViewController`), preserving today's reset semantics;
    /// any other wallet gets the per-wallet recovery-phrase remove sheet.
    private func beginRemove(_ row: WalletRow) {
        if viewModel.removalRoutesToFullReset(walletId: row.walletId) {
            let controller = DWResetWalletInfoViewController.make()
            controller.delegate = resetDelegate
            vc.pushViewController(controller, animated: true)
        } else {
            removeTarget = row
        }
    }
}

// MARK: - Row

private struct WalletRowView: View {
    let row: WalletRow
    let onSwitch: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                if let username = row.username {
                    Text("@\(username)")
                        .font(.system(size: 13))
                        .foregroundColor(.dash.blue)
                        .lineLimit(1)
                }
                if let balance = row.balanceText {
                    Text(balance)
                        .font(.system(size: 13))
                        .foregroundColor(.dash.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if row.isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.dash.blue)
            }
            // Visible entry point for switch/rename/remove — the long-press
            // context menu duplicates these but is undiscoverable on its own.
            Menu {
                if !row.isActive {
                    Button {
                        onSwitch()
                    } label: {
                        Label(NSLocalizedString("Switch to this wallet", comment: "Wallets"), systemImage: "arrow.left.arrow.right")
                    }
                }
                Button {
                    onRename()
                } label: {
                    Label(NSLocalizedString("Rename", comment: "Wallets"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label(NSLocalizedString("Remove", comment: "Wallets"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.dash.secondaryText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dash.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 60)
    }
}

// MARK: - Remove sheet

/// Recovery-phrase remove confirmation. Warns exactly what removal destroys
/// (this device's copy of the wallet; funds recoverable only with the phrase)
/// and requires typing the wallet's own recovery phrase, verified by deriving
/// its walletId from the entered mnemonic (`WalletsViewModel.recoveryPhraseMatches`).
private struct RemoveWalletSheet: View {
    let row: WalletRow
    let verify: (String) -> Bool
    let onConfirmed: () -> Void
    let onCancel: () -> Void

    @State private var phrase: String = ""
    @State private var showMismatch = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(String(
                            format: NSLocalizedString("Remove \"%@\"", comment: "Wallets"),
                            row.displayName))
                            .font(.title2).fontWeight(.bold)
                            .foregroundColor(.dash.primaryText)

                        Text(NSLocalizedString(
                            "This removes this device's copy of the wallet, including its keys and synced data. Your funds are NOT deleted — they remain on the Dash network and can only be recovered with this wallet's recovery phrase. If you have not backed up the phrase, you will lose access to these funds.",
                            comment: "Wallets"))
                            .font(.subheadline)
                            .foregroundColor(.dash.secondaryText)

                        Text(NSLocalizedString(
                            "Type this wallet's recovery phrase to confirm.",
                            comment: "Wallets"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.dash.primaryText)

                        TextEditor(text: $phrase)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.dash.secondaryBackground)
                            .cornerRadius(10)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)

                        if showMismatch {
                            Text(NSLocalizedString(
                                "That is not this wallet's recovery phrase.",
                                comment: "Wallets"))
                                .font(.footnote)
                                .foregroundColor(.dash.red)
                        }

                        Button(action: confirm) {
                            Text(NSLocalizedString("Remove Wallet", comment: "Wallets"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.dash.whiteText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(canConfirm ? Color.dash.red : Color.dash.red.opacity(0.4))
                                .cornerRadius(12)
                        }
                        .disabled(!canConfirm)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(NSLocalizedString("Remove Wallet", comment: "Wallets"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { onCancel() }
                }
            }
        }
    }

    private var canConfirm: Bool {
        !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func confirm() {
        if verify(phrase) {
            onConfirmed()
        } else {
            showMismatch = true
        }
    }
}

// MARK: - Add Wallet sheet

/// "Add Wallet" flow: a chooser between creating a brand-new wallet (generate a
/// 12-word phrase, show it, require a written-down confirmation) and importing
/// one from an existing recovery phrase. Both paths add the wallet additively
/// via `WalletsViewModel.addWallet` and switch to it on success. All SDK work
/// (generate / validate / add / switch) lives in the ViewModel; this view only
/// drives the steps and renders (SwiftUI-first guardrail).
private struct AddWalletSheet: View {
    @ObservedObject var viewModel: WalletsViewModel
    let onFinished: () -> Void
    /// Called with an existing wallet's id when the imported phrase is already
    /// on this device and the user chooses to switch to it instead.
    let onSwitchToExisting: (Data) -> Void

    private enum Step: Equatable {
        case chooser
        case create
        case importPhrase
    }

    @State private var step: Step = .chooser

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                content
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { onFinished() }
                        .disabled(viewModel.addInProgress || viewModel.switchInProgress)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.addInProgress || viewModel.switchInProgress)
    }

    private var navigationTitle: String {
        switch step {
        case .chooser: return NSLocalizedString("Add Wallet", comment: "Wallets")
        case .create: return NSLocalizedString("New Wallet", comment: "Wallets")
        case .importPhrase: return NSLocalizedString("Import Wallet", comment: "Wallets")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .chooser:
            chooser
        case .create:
            CreateWalletView(
                viewModel: viewModel,
                onFinished: onFinished)
        case .importPhrase:
            ImportWalletView(
                viewModel: viewModel,
                onFinished: onFinished,
                onSwitchToExisting: onSwitchToExisting)
        }
    }

    private var chooser: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)
            Text(NSLocalizedString(
                "Add another wallet to this device. You can create a brand-new wallet or restore one from its recovery phrase.",
                comment: "Wallets"))
                .font(.subheadline)
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: { step = .create }) {
                chooserRow(
                    title: NSLocalizedString("Create New Wallet", comment: "Wallets"),
                    subtitle: NSLocalizedString("Generate a new recovery phrase", comment: "Wallets"),
                    systemImage: "plus.circle")
            }
            Button(action: { step = .importPhrase }) {
                chooserRow(
                    title: NSLocalizedString("Import from Phrase", comment: "Wallets"),
                    subtitle: NSLocalizedString("Restore an existing wallet", comment: "Wallets"),
                    systemImage: "square.and.arrow.down")
            }
            Spacer()
        }
        .padding(20)
    }

    private func chooserRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundColor(.dash.blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dash.secondaryText)
        }
        .padding(16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }
}

// MARK: - Create wallet step

/// Generates a 12-word phrase, shows it in a grid, and requires an explicit
/// "I've written it down" confirmation before adding the wallet.
private struct CreateWalletView: View {
    @ObservedObject var viewModel: WalletsViewModel
    let onFinished: () -> Void

    @State private var mnemonic: String? = nil
    @State private var confirmedWrittenDown = false

    private var words: [String] {
        mnemonic.map { $0.split(separator: " ").map(String.init) } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(NSLocalizedString(
                    "Write down these 12 words in order and keep them somewhere safe. They are the ONLY way to recover this wallet. Anyone with them can spend your funds.",
                    comment: "Wallets"))
                    .font(.subheadline)
                    .foregroundColor(.dash.secondaryText)

                phraseGrid

                Toggle(isOn: $confirmedWrittenDown) {
                    Text(NSLocalizedString("I have written down my recovery phrase.", comment: "Wallets"))
                        .font(.system(size: 15))
                        .foregroundColor(.dash.primaryText)
                }
                .disabled(mnemonic == nil || viewModel.addInProgress || viewModel.switchInProgress)

                Button(action: create) {
                    HStack {
                        if viewModel.addInProgress || viewModel.switchInProgress {
                            SwiftUI.ProgressView().tint(Color.dash.whiteText)
                        }
                        Text(NSLocalizedString("Create Wallet", comment: "Wallets"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.dash.whiteText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canCreate ? Color.dash.blue : Color.dash.blue.opacity(0.4))
                    .cornerRadius(12)
                }
                .disabled(!canCreate)
            }
            .padding(20)
        }
        .onAppear {
            if mnemonic == nil { mnemonic = viewModel.generateMnemonic() }
        }
    }

    private var phraseGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.dash.secondaryText)
                        .frame(width: 22, alignment: .trailing)
                    Text(word)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.dash.primaryText)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.dash.secondaryBackground)
                .cornerRadius(10)
            }
        }
    }

    private var canCreate: Bool {
        mnemonic != nil && confirmedWrittenDown && !viewModel.addInProgress && !viewModel.switchInProgress
    }

    private func create() {
        guard let mnemonic else { return }
        Task {
            let outcome = await viewModel.addWallet(mnemonic: mnemonic, origin: .fresh)
            if outcome == .switched { onFinished() }
            // A brand-new phrase can't already exist, and on error the sheet
            // stays open (the ViewModel surfaces the message).
        }
    }
}

// MARK: - Import wallet step

/// Multiline recovery-phrase entry with BIP39 validation. On import, if the
/// derived wallet is already on this device, offers switching to it instead of
/// reporting a fabricated success.
private struct ImportWalletView: View {
    @ObservedObject var viewModel: WalletsViewModel
    let onFinished: () -> Void
    let onSwitchToExisting: (Data) -> Void

    @State private var phrase: String = ""
    @State private var existingWalletId: Data? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(NSLocalizedString(
                    "Enter the recovery phrase of the wallet you want to add.",
                    comment: "Wallets"))
                    .font(.subheadline)
                    .foregroundColor(.dash.secondaryText)

                TextEditor(text: $phrase)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.dash.secondaryBackground)
                    .cornerRadius(10)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .disabled(viewModel.addInProgress || viewModel.switchInProgress)

                if let existingWalletId {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString(
                            "This wallet is already on this device.",
                            comment: "Wallets"))
                            .font(.footnote)
                            .foregroundColor(.dash.secondaryText)
                        Button(NSLocalizedString("Switch to it", comment: "Wallets")) {
                            onSwitchToExisting(existingWalletId)
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.dash.blue)
                    }
                }

                Button(action: importWallet) {
                    HStack {
                        if viewModel.addInProgress || viewModel.switchInProgress {
                            SwiftUI.ProgressView().tint(Color.dash.whiteText)
                        }
                        Text(NSLocalizedString("Import Wallet", comment: "Wallets"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.dash.whiteText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canImport ? Color.dash.blue : Color.dash.blue.opacity(0.4))
                    .cornerRadius(12)
                }
                .disabled(!canImport)
            }
            .padding(20)
        }
    }

    private var canImport: Bool {
        viewModel.isValidMnemonic(phrase) && !viewModel.addInProgress && !viewModel.switchInProgress
    }

    private func importWallet() {
        existingWalletId = nil
        Task {
            let outcome = await viewModel.addWallet(mnemonic: phrase, origin: .userRestore)
            switch outcome {
            case .switched:
                onFinished()
            case .alreadyOnDevice(let walletId):
                existingWalletId = walletId
            case .none:
                break // error surfaced by the ViewModel; sheet stays open
            }
        }
    }
}

// MARK: - Reset flow delegate

extension WalletsScreen {
    /// Bridges the last-wallet full reset flow (`DWResetWalletInfoViewController`).
    /// A completed wipe invalidates the entire main UI: route to the app-level
    /// DWWipeDelegate chain (MainTabbar → root VC), which transitions to
    /// onboarding and drops the whole main stack. Popping back to this screen
    /// is only the fallback when no chain was provided.
    final class ResetDelegate: NSObject, DWWipeDelegate {
        private let onFinish: () -> Void
        private weak var wipeDelegate: DWWipeDelegate?

        init(onFinish: @escaping () -> Void, wipeDelegate: DWWipeDelegate? = nil) {
            self.onFinish = onFinish
            self.wipeDelegate = wipeDelegate
        }

        func didWipeWallet() {
            if let wipeDelegate {
                wipeDelegate.didWipeWallet()
            } else {
                onFinish()
            }
        }
    }
}
