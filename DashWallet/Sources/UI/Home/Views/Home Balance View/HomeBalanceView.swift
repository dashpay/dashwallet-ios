//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

import SwiftUI

// MARK: - HomeBalanceViewState

enum HomeBalanceViewState: Int {
    case `default`
    case syncing
}

// MARK: - HomeBalanceView

/// Home header: the combined total (transparent + platform + shielded)
/// as the hero amount, then one row per balance with its fiat value and
/// circular in/out transfer buttons. Every row's in-arrow opens the
/// payments landing on the Receive tab with that balance's network
/// preselected (its hero tabs keep Internal transfer one tap away);
/// the out-arrows keep their direct routes:
///   - Transparent: out = Send (external money);
///   - Platform:    out = Platform → Shielded;
///   - Shielded:    out = Shielded → Transparent.
struct HomeBalanceView: View {
    @ObservedObject var viewModel: BalanceModel
    @ObservedObject private var platformSync = PlatformAddressSyncCoordinator.shared
    @State private var opacity: Double = 0.3
    var onLongPress: () -> Void
    var onReceive: (ChainNetwork) -> Void = { _ in }
    var onSend: () -> Void = {}
    var onTransfer: (InternalTransferDirection, InternalTransferSource) -> Void = { _, _ in }
    /// Tap on a row's body (icon/title/amount — not the arrows): opens the
    /// what-is-this-balance info sheet for that balance.
    var onInfo: (ChainNetwork) -> Void = { _ in }

    private var platformDuffs: UInt64 { platformSync.platformBalance / 1_000 }
    private var shieldedDuffs: UInt64 { platformSync.shieldedBalance / 1_000 }
    private var totalDuffs: UInt64 { viewModel.value + platformDuffs + shieldedDuffs }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if !viewModel.isBalanceHidden && viewModel.state == .syncing {
                    Text(NSLocalizedString("Syncing Balance", comment: ""))
                        .font(.caption)
                        .foregroundColor(.white)
                        .opacity(opacity)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 0.8)
                                    .repeatForever(autoreverses: true)
                            ) {
                                opacity = 0.7
                            }
                        }
                }
            }
            .frame(height: 15)

            ZStack {
                if viewModel.isBalanceHidden {
                    Image(systemName: "eye.slash.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.2))
                        )
                        .frame(width: 58, height: 58)
                } else {
                    VStack(spacing: 0) {
                        DashAmount(amount: Int64(totalDuffs), font: .largeTitle, dashSymbolFactor: 0.7, showDirection: false)
                            .foregroundColor(.white)
                        Text(viewModel.fiatString(forDuffs: totalDuffs))
                            .font(.subhead)
                            .foregroundColor(.white)

                        ZStack {
                            if viewModel.shouldShowTapToHideBalance {
                                Text(NSLocalizedString("Tap to hide balance", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .frame(height: 12)
                        .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.navigationBarColor)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isBalanceHidden)
            .onTapGesture {
                viewModel.toggleBalanceVisibility()
            }
            .onLongPressGesture {
                onLongPress()
            }

            if !viewModel.isBalanceHidden && platformSync.isRunning {
                breakdownCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
        }
        .onAppear {
            viewModel.reloadBalance()
        }
        .onDisappear {
            viewModel.hideBalanceIfNeeded()
        }
    }

    private var breakdownCard: some View {
        VStack(spacing: 0) {
            balanceRow(
                icon: "wallet.pass",
                title: NSLocalizedString("Transparent", comment: "Balance breakdown"),
                duffs: viewModel.value,
                infoAction: { onInfo(.core) },
                inAction: { onReceive(.core) },
                outAction: onSend)
            rowDivider
            balanceRow(
                icon: "cloud",
                title: NSLocalizedString("Platform", comment: ""),
                duffs: platformDuffs,
                infoAction: { onInfo(.platform) },
                inAction: { onReceive(.platform) },
                outAction: { onTransfer(.toShielded, .platform) })
            rowDivider
            balanceRow(
                icon: "shield",
                title: NSLocalizedString("Shielded", comment: ""),
                duffs: shieldedDuffs,
                infoAction: { onInfo(.shielded) },
                inAction: { onReceive(.shielded) },
                outAction: { onTransfer(.fromShielded, .core) })
        }
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(height: 0.5)
    }

    private func balanceRow(
        icon: String,
        title: String,
        duffs: UInt64,
        infoAction: @escaping () -> Void,
        inAction: @escaping () -> Void,
        outAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            // The row body is its own tap target (info sheet); keeping it a
            // sibling of the arrow buttons means it can't swallow their taps.
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Text(viewModel.fiatString(forDuffs: duffs))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer(minLength: 8)
                DashAmount(amount: Int64(duffs), font: .footnote, dashSymbolFactor: 0.8, showDirection: false)
                    .foregroundColor(.white)
            }
            .contentShape(Rectangle())
            .onTapGesture { infoAction() }

            transferButton(systemName: "arrow.down",
                           label: NSLocalizedString("Transfer in", comment: "Balance breakdown"),
                           action: inAction)
            transferButton(systemName: "arrow.up",
                           label: NSLocalizedString("Transfer out", comment: "Balance breakdown"),
                           action: outAction)
        }
        .padding(.vertical, 9)
    }

    private func transferButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.18)))
                // Keep the visual small but the tap target comfortable.
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
