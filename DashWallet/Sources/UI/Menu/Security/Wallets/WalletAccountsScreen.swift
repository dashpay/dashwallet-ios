//
//  WalletAccountsScreen.swift
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
//  Per-wallet Accounts screen (Wallets → tap a wallet). Lists every account
//  of the wallet — type, per-account balance, and address-pool usage —
//  modeled on the SwiftExampleApp's `AccountListView`. Read-only: adding an
//  extra account is not supported yet, so there is deliberately no Add
//  control. All logic lives in `WalletAccountsViewModel`; this view only
//  renders.
//

import SwiftUI
import DashUIKit
import UIKit

struct WalletAccountsScreen: View {
    private let vc: UINavigationController
    private let walletId: Data

    @StateObject private var viewModel: WalletAccountsViewModel

    init(vc: UINavigationController, walletId: Data, walletName: String) {
        self.vc = vc
        self.walletId = walletId
        _viewModel = StateObject(
            wrappedValue: WalletAccountsViewModel(walletId: walletId, walletName: walletName))
    }

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                if viewModel.rows.isEmpty {
                    ContentUnavailableView(
                        NSLocalizedString("No Accounts", comment: "Wallet accounts"),
                        systemImage: "folder",
                        description: Text(NSLocalizedString(
                            "Accounts are created automatically when the wallet syncs.",
                            comment: "Wallet accounts")))
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(viewModel.rows) { row in
                                AccountRowView(row: row)
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
                }

                Spacer(minLength: 0)
            }
        }
        .navigationBarHidden(true)
        .onAppear { viewModel.reload() }
    }

    /// Push the tapped account's detail screen.
    private func showDetail(_ row: WalletAccountRow) {
        let controller = UIHostingController(
            rootView: WalletAccountDetailScreen(vc: vc, walletId: walletId, account: row))
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationBar(
                leading: { NavigationBarElement.back.button { vc.popViewController(animated: true) } },
                central: {
                    Text(viewModel.walletName)
                        .font(.headline)
                        .foregroundColor(.dash.primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 60)
                }
            )

            HStack {
                Text(NSLocalizedString("Accounts", comment: "Wallet accounts"))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.dash.primaryText)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Row

/// One account: colored icon + name, type chip, then a balance breakdown for
/// funds accounts (Standard / CoinJoin / PlatformPayment) or a
/// special-purpose caption, and an address-pool usage footer. Mirrors the
/// SwiftExampleApp's `AccountRowView` in the app's house style.
private struct AccountRowView: View {
    let row: WalletAccountRow

    private var label: String {
        row.showsBalance ? "\(row.typeName) #\(row.accountIndex)" : row.typeName
    }

    private var iconName: String {
        switch row.accountType {
        case 0:
            return row.standardTag == 0 ? "star.circle.fill" : "tray.full"
        case 1: return "shuffle.circle"
        case 14: return "creditcard"
        case 2, 3, 4, 5: return "person.crop.circle"
        case 6, 7: return "arrow.up.circle"
        case 8: return "key.viewfinder"
        case 9: return "key.horizontal"
        case 10: return "wrench.and.screwdriver"
        case 11: return "network"
        default: return "folder"
        }
    }

    private var iconColor: Color {
        switch row.accountType {
        case 0: return row.standardTag == 0
            ? (row.accountIndex == 0 ? .green : .blue)
            : .teal
        case 1: return .orange
        case 14: return .indigo
        case 2, 3, 4, 5, 6, 7: return .purple
        case 8: return .red
        case 9: return .pink
        case 10: return .indigo
        case 11: return .cyan
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(label, systemImage: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
                    .lineLimit(1)

                Spacer()

                Text(row.typeName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(iconColor.opacity(0.2))
                    .cornerRadius(4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.dash.secondaryText)
            }

            if row.isPlatformPayment {
                platformBalanceRow
            } else if row.showsBalance {
                coreBalanceRow
            } else {
                Text(NSLocalizedString("Special Purpose Account", comment: "Wallet accounts"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                    .italic()
            }

            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var coreBalanceRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Confirmed", comment: "Wallet accounts"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                Text(row.confirmed.formattedDashAmount)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.dash.primaryText)
            }

            if row.unconfirmed > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Pending", comment: "Wallet accounts"))
                        .font(.caption)
                        .foregroundColor(.dash.secondaryText)
                    Text(row.unconfirmed.formattedDashAmount)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(NSLocalizedString("Total", comment: "Wallet accounts"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                Text((row.confirmed + row.unconfirmed).formattedDashAmount)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(iconColor)
            }
        }
    }

    /// PlatformPayment balance is held in credits (1 DASH = 100 000 000 000
    /// credits), so it can't reuse the duff formatter.
    private var platformBalanceRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Balance", comment: "Wallet accounts"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                Text(Self.formatCredits(row.platformCredits))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(iconColor)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if row.isPlatformPayment {
            // DIP-17 pools are flat — no external/internal split.
            HStack(spacing: 16) {
                Label(
                    String(format: NSLocalizedString("%d used", comment: "Wallet accounts — address pool"), row.platformAddressesUsed),
                    systemImage: "checkmark.circle")
                Label(
                    String(format: NSLocalizedString("%d total", comment: "Wallet accounts — address pool"), row.platformAddressesTotal),
                    systemImage: "tray.full")
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.dash.secondaryText)
        } else if row.receiveAddressCount > 0 || row.changeAddressCount > 0 {
            HStack(spacing: 16) {
                if row.receiveAddressCount > 0 {
                    Label(
                        String(format: NSLocalizedString("%d receive", comment: "Wallet accounts — address pool"), row.receiveAddressCount),
                        systemImage: "arrow.down.circle")
                }
                if row.changeAddressCount > 0 {
                    Label(
                        String(format: NSLocalizedString("%d change", comment: "Wallet accounts — address pool"), row.changeAddressCount),
                        systemImage: "arrow.up.arrow.down.circle")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.dash.secondaryText)
        }
    }

    private static func formatCredits(_ credits: UInt64) -> String {
        let dash = Double(credits) / 100_000_000_000.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        let number = formatter.string(from: NSNumber(value: dash)) ?? String(format: "%.8f", dash)
        return "\(number) DASH"
    }
}
