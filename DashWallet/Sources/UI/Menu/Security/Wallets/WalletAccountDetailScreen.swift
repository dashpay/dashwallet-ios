//
//  WalletAccountDetailScreen.swift
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
//  Account detail screen (Wallets → wallet → tap an account). Shows the
//  account's overview, balance, address-pool stats, per-pool address lists
//  (tap an address to copy it), and the extended public key for provider
//  key accounts — the same information as the SwiftExampleApp's
//  `AccountDetailView`, in the app's house style. All logic lives in
//  `WalletAccountDetailViewModel`; this view only renders.
//

import SwiftUI
import DashUIKit
import UIKit

struct WalletAccountDetailScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel: WalletAccountDetailViewModel
    /// Address string just copied, for a transient "Copied" confirmation.
    @State private var copiedAddress: String? = nil

    init(vc: UINavigationController, walletId: Data, account: WalletAccountRow) {
        self.vc = vc
        _viewModel = StateObject(
            wrappedValue: WalletAccountDetailViewModel(walletId: walletId, account: account))
    }

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                if let detail = viewModel.detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            overviewCard(detail)

                            if detail.isProviderKeyAccount {
                                extendedPublicKeyCard(detail)
                            } else if detail.showsBalance {
                                balanceCard(detail)
                            }

                            if !detail.isProviderKeyAccount {
                                poolSummaryCard(detail)
                            }

                            ForEach(detail.addressSections) { section in
                                addressListCard(section, isPlatform: detail.isPlatformPayment)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    }
                } else {
                    ContentUnavailableView(
                        NSLocalizedString("Account Not Found", comment: "Wallet accounts"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(NSLocalizedString(
                            "This account is no longer in the wallet's store.",
                            comment: "Wallet accounts")))
                }

                Spacer(minLength: 0)
            }
        }
        .navigationBarHidden(true)
        .onAppear { viewModel.reload() }
    }

    // MARK: - Header

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
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.detail?.typeName ?? NSLocalizedString("Account", comment: "Wallet accounts"))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.dash.primaryText)
                if let detail = viewModel.detail, detail.showsBalance {
                    Text("#\(detail.accountIndex)")
                        .font(.subheadline)
                        .foregroundColor(.dash.secondaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Cards

    private func overviewCard(_ detail: WalletAccountDetail) -> some View {
        card(
            title: NSLocalizedString("Account Information", comment: "Wallet accounts"),
            systemImage: "info.circle.fill"
        ) {
            infoRow(NSLocalizedString("Type", comment: "Wallet accounts"), detail.typeName)
            infoRow(NSLocalizedString("Index", comment: "Wallet accounts"), "#\(detail.accountIndex)", monospaced: true)
            infoRow(NSLocalizedString("Network", comment: "Wallet accounts"), detail.networkName)
        }
    }

    private func balanceCard(_ detail: WalletAccountDetail) -> some View {
        card(
            title: NSLocalizedString("Balance", comment: ""),
            systemImage: detail.isPlatformPayment ? "creditcard" : "circle.hexagongrid.fill"
        ) {
            if detail.isPlatformPayment {
                infoRow(
                    NSLocalizedString("Platform Credits", comment: "Wallet accounts"),
                    Self.formatCredits(detail.platformCredits))
                infoRow(
                    NSLocalizedString("Raw Credits", comment: "Wallet accounts"),
                    "\(detail.platformCredits)",
                    monospaced: true)
            } else {
                infoRow(NSLocalizedString("Confirmed", comment: "Wallet accounts"), detail.confirmed.formattedDashAmount)
                if detail.unconfirmed > 0 {
                    infoRow(NSLocalizedString("Pending", comment: "Wallet accounts"), detail.unconfirmed.formattedDashAmount)
                }
                Divider()
                HStack {
                    Text(NSLocalizedString("Total Balance", comment: "Wallet accounts"))
                        .font(.footnote)
                        .foregroundColor(.dash.secondaryText)
                    Spacer()
                    Text((detail.confirmed + detail.unconfirmed).formattedDashAmount)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.dash.primaryText)
                }
            }
        }
    }

    private func poolSummaryCard(_ detail: WalletAccountDetail) -> some View {
        card(
            title: NSLocalizedString("Address Pool", comment: "Wallet accounts"),
            systemImage: "square.stack.3d.up.fill"
        ) {
            if detail.isPlatformPayment {
                // DIP-17 pools are flat — no external/internal split, no
                // core transactions, no UTXOs.
                infoRow(NSLocalizedString("Total Addresses", comment: "Wallet accounts"), "\(detail.platformAddressesTotal)")
                infoRow(NSLocalizedString("Addresses Used", comment: "Wallet accounts"), "\(detail.platformAddressesUsed)")
                infoRow(
                    NSLocalizedString("Highest Used", comment: "Wallet accounts"),
                    detail.platformHighestUsed.map { "\($0)" } ?? "—")
            } else {
                if detail.externalPoolSize > 0 {
                    infoRow(NSLocalizedString("Pool Size (External)", comment: "Wallet accounts"), "\(detail.externalPoolSize)")
                }
                if detail.internalPoolSize > 0 {
                    infoRow(NSLocalizedString("Pool Size (Internal)", comment: "Wallet accounts"), "\(detail.internalPoolSize)")
                }
                infoRow(
                    NSLocalizedString("Highest Used (External)", comment: "Wallet accounts"),
                    detail.externalHighestUsed.map { "\($0)" } ?? "—")
                infoRow(
                    NSLocalizedString("Highest Used (Internal)", comment: "Wallet accounts"),
                    detail.internalHighestUsed.map { "\($0)" } ?? "—")
                infoRow(NSLocalizedString("Transactions", comment: ""), "\(detail.transactionCount)")
                infoRow(NSLocalizedString("TXOs", comment: "Wallet accounts"), "\(detail.txoCount)")
            }
        }
    }

    private func addressListCard(_ section: AccountAddressSection, isPlatform: Bool) -> some View {
        card(
            title: String(
                format: NSLocalizedString("%@ Addresses (%d)", comment: "Wallet accounts — pool name + count"),
                section.name, section.items.count),
            systemImage: Self.poolIcon(for: section.name)
        ) {
            ForEach(Array(section.items.enumerated()), id: \.element.id) { idx, item in
                addressRow(item, isPlatform: isPlatform)
                if idx < section.items.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func addressRow(_ item: AccountAddressItem, isPlatform: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.address)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.dash.primaryText)
                HStack(spacing: 6) {
                    Text("#\(item.index)")
                    if item.isUsed {
                        Text("• " + NSLocalizedString("used", comment: "Wallet accounts — address flag"))
                    }
                    if item.balance > 0 {
                        Text(isPlatform
                            ? "• \(item.balance) credits"
                            : "• \(item.balance.formattedDashAmount)")
                    }
                }
                .font(.caption2)
                .foregroundColor(.dash.secondaryText)
            }
            Spacer()
            if copiedAddress == item.address {
                Label(NSLocalizedString("Copied", comment: ""), systemImage: "checkmark")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundColor(.dash.blue)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { copy(item.address) }
    }

    /// Extended-public-key card for provider key-material accounts
    /// (operator = BLS, platform node = Ed25519). These accounts derive
    /// masternode / platform-node keys and hold no on-chain addresses or
    /// balance. The per-index derived keys live in Tools → Masternode Keys.
    private func extendedPublicKeyCard(_ detail: WalletAccountDetail) -> some View {
        card(
            title: NSLocalizedString("Extended Public Key", comment: "Wallet accounts"),
            systemImage: "key.horizontal.fill"
        ) {
            if let hex = detail.extendedPublicKeyHex, !hex.isEmpty {
                Text(NSLocalizedString(
                    "This account derives masternode keys. It has no on-chain addresses or balance.",
                    comment: "Wallet accounts"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                Text(hex)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.dash.primaryText)
                    .textSelection(.enabled)
            } else {
                Text(NSLocalizedString(
                    "No extended public key has been persisted for this account yet.",
                    comment: "Wallet accounts"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
            }
        }
    }

    // MARK: - Building blocks

    private func card(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.dash.primaryText)
            Divider()
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
        .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
    }

    private func infoRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .system(.footnote))
                .fontWeight(.medium)
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func copy(_ address: String) {
        UIPasteboard.general.string = address
        copiedAddress = address
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedAddress == address { copiedAddress = nil }
        }
    }

    private static func poolIcon(for name: String) -> String {
        switch name {
        case "External": return "arrow.down.circle"
        case "Internal": return "arrow.triangle.2.circlepath"
        case NSLocalizedString("Platform Addresses", comment: "Wallet accounts"): return "creditcard"
        default: return "square.stack"
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
