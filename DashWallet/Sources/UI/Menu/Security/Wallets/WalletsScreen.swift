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
//  "Wallets" screen (Security menu). Lists the on-device SwiftDashSDK wallets
//  for the current network, one marked active, and offers switch-on-tap,
//  rename, and per-wallet remove. Add Wallet is Phase 3 and is intentionally
//  absent. All logic lives in `WalletsViewModel`; this view only renders.
//

import SwiftUI
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

    init(vc: UINavigationController) {
        self.vc = vc
        self.resetDelegate = ResetDelegate(onFinish: { [weak vc] in
            vc?.popViewController(animated: true)
        })
    }

    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.rows) { row in
                            WalletRowView(row: row)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !row.isActive { pendingSwitch = row }
                                }
                                .contextMenu {
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
                    .background(Color.secondaryBackground)
                    .cornerRadius(12)
                    .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }

            if viewModel.switchInProgress {
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
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            HStack {
                Text(NSLocalizedString("Wallets", comment: "Wallets"))
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

    private var progressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                // Fully qualified: the app has a UIKit `ProgressView: UIView`
                // that otherwise shadows SwiftUI's.
                SwiftUI.ProgressView()
                    .tint(.white)
                Text(NSLocalizedString("Switching wallet…", comment: "Wallets"))
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(Color.black.opacity(0.6))
            .cornerRadius(14)
        }
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                if let username = row.username {
                    Text("@\(username)")
                        .font(.system(size: 13))
                        .foregroundColor(.dashBlue)
                        .lineLimit(1)
                }
                if let balance = row.balanceText {
                    Text(balance)
                        .font(.system(size: 13))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if row.isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.dashBlue)
            }
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
                Color.primaryBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(String(
                            format: NSLocalizedString("Remove \"%@\"", comment: "Wallets"),
                            row.displayName))
                            .font(.title2).fontWeight(.bold)
                            .foregroundColor(.primaryText)

                        Text(NSLocalizedString(
                            "This removes this device's copy of the wallet, including its keys and synced data. Your funds are NOT deleted — they remain on the Dash network and can only be recovered with this wallet's recovery phrase. If you have not backed up the phrase, you will lose access to these funds.",
                            comment: "Wallets"))
                            .font(.subheadline)
                            .foregroundColor(.secondaryText)

                        Text(NSLocalizedString(
                            "Type this wallet's recovery phrase to confirm.",
                            comment: "Wallets"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primaryText)

                        TextEditor(text: $phrase)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.secondaryBackground)
                            .cornerRadius(10)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)

                        if showMismatch {
                            Text(NSLocalizedString(
                                "That is not this wallet's recovery phrase.",
                                comment: "Wallets"))
                                .font(.footnote)
                                .foregroundColor(.systemRed)
                        }

                        Button(action: confirm) {
                            Text(NSLocalizedString("Remove Wallet", comment: "Wallets"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(canConfirm ? Color.systemRed : Color.systemRed.opacity(0.4))
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

// MARK: - Reset flow delegate

extension WalletsScreen {
    /// Bridges the last-wallet full reset flow (`DWResetWalletInfoViewController`)
    /// back to this screen's navigation, popping on completion or cancel.
    final class ResetDelegate: NSObject, DWWipeDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func didWipeWallet() { onFinish() }
    }
}
