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
import DashUIKit

// MARK: - HomeBalanceViewState

enum HomeBalanceViewState: Int {
    case `default`
    case syncing
}

// MARK: - HomeBalanceView

/// Home header: the combined total (transparent + platform + shielded)
/// as the hero amount, and — in Advanced mode only — one row per balance
/// with its fiat value.
///
/// The rows are a readout, not a control surface. They used to carry an
/// in/out arrow pair opening the pinned receive/send sheets; the transfer
/// routes those reached are all on the payments tab, and a second, denser
/// entry to them on the balance header was two taps the header did not need.
struct HomeBalanceView: View {
    @ObservedObject var viewModel: BalanceModel
    @ObservedObject private var platformSync = PlatformAddressSyncCoordinator.shared
    @ObservedObject private var shieldedSync = ShieldedSyncMonitor.shared
    @State private var opacity: Double = 0.3
    var onLongPress: () -> Void
    /// Tap on a row: opens the what-is-this-balance info sheet.
    var onInfo: (ChainNetwork) -> Void = { _ in }
    /// The breakdown is one of the three surfaces Advanced mode unlocks —
    /// without it the wallet has one balance, and naming its parts invites
    /// questions the simple mode is there to avoid.
    var showsBreakdown: Bool = true

    // Header nav-bar (SB-11) inputs, threaded in by HomeView from the same
    // app-owned identity snapshot the UIKit nav-bar avatar reads. A nil
    // `username` hides the leading row (no registered identity). These are
    // plain values so the view stays dumb; only the DASHPAY nav bar below
    // reads them.
    var username: String? = nil
    var avatarURL: String? = nil
    var identitySeed: Data = Data()
    var hasUnreadNotifications: Bool = false
    var onProfileTap: () -> Void = {}
    var onNotificationsTap: () -> Void = {}

    private var platformDuffs: UInt64 { platformSync.platformBalance / 1_000 }
    private var shieldedDuffs: UInt64 { platformSync.shieldedBalance / 1_000 }
    private var totalDuffs: UInt64 { viewModel.value + platformDuffs + shieldedDuffs }

    var body: some View {
        VStack(spacing: 0) {
            // Home nav bar (avatar/username · Dash logo · notifications).
            // DashPay-only: the leading row and the bell are identity
            // features, so the whole bar is compiled out of the non-DashPay
            // build.
            #if DASHPAY
            DashUIKit.NavigationBar(
                leading: { navLeading },
                central: { dashLogo },
                trailing: { notificationButton }
            )
            #endif

            if viewModel.isTestnet {
                testnetBadge
            }

            ZStack {
                if !viewModel.isBalanceHidden && viewModel.state == .syncing {
                    Text(NSLocalizedString("Syncing Balance", comment: ""))
                        .font(.caption)
                        .foregroundColor(Color.dash.whiteText)
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
                        .foregroundColor(Color.dash.whiteText)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.dash.black.opacity(0.2))
                        )
                        .frame(width: 58, height: 58)
                } else {
                    VStack(spacing: 0) {
                        DashAmount(amount: Int64(totalDuffs), font: .largeTitle, dashSymbolFactor: 0.7, showDirection: false)
                            .foregroundColor(Color.dash.whiteText)
                        Text(viewModel.fiatString(forDuffs: totalDuffs))
                            .font(.subhead)
                            .foregroundColor(Color.dash.whiteText)

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

            if showsBreakdown && !viewModel.isBalanceHidden && platformSync.isRunning {
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

    #if DASHPAY
    /// Leading slot: the persistent username entry point. Empty (the nav bar
    /// keeps its layout) until an identity with a username is registered.
    @ViewBuilder
    private var navLeading: some View {
        if let username {
            HomeUsernameRow(
                username: username,
                avatarURL: avatarURL,
                identitySeed: identitySeed,
                onTap: onProfileTap)
        }
    }

    /// Central slot: the full Dash wordmark. `logo` is the blue-on-transparent
    /// wordmark asset; rendered as a template so it reads white on the blue
    /// header, per the design-system nav bar. Height 22 matches the spec.
    private var dashLogo: some View {
        Image("logo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: 22)
            .foregroundColor(Color.dash.whiteText)
            .accessibilityLabel(Text(verbatim: "Dash"))
    }

    /// Trailing slot: bell in a translucent circle (spec: 34pt circle,
    /// white/alpha-20 fill). Reuses the app's white bell assets;
    /// `icon_bell_active` carries the unread indicator, so it renders as-is
    /// while the plain bell is tinted white.
    private var notificationButton: some View {
        Button(action: onNotificationsTap) {
            Image(hasUnreadNotifications ? "icon_bell_active" : "icon_bell")
                .renderingMode(hasUnreadNotifications ? .original : .template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 18)
                .foregroundColor(Color.dash.whiteText)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.dash.white.opacity(0.2)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(NSLocalizedString("Notifications", comment: "Home nav bar")))
    }
    #endif

    private var breakdownCard: some View {
        VStack(spacing: 0) {
            balanceRow(
                icon: "wallet.pass",
                title: NSLocalizedString("Transparent", comment: "Balance breakdown"),
                duffs: viewModel.value,
                infoAction: { onInfo(.core) })
            rowDivider
            balanceRow(
                icon: "cloud",
                title: NSLocalizedString("Platform", comment: ""),
                duffs: platformDuffs,
                infoAction: { onInfo(.platform) })
            rowDivider
            balanceRow(
                icon: "shield",
                title: NSLocalizedString("Shielded", comment: ""),
                duffs: shieldedDuffs,
                isSyncing: shieldedSync.isSyncing || platformSync.isShieldedBalanceReconciling,
                infoAction: { onInfo(.shielded) })
        }
        .padding(.horizontal, 12)
        .background(Color.dash.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Unmissable "these are not real funds" marker while the wallet runs
    /// on testnet.
    private var testnetBadge: some View {
        Text(NSLocalizedString("TESTNET", comment: "Badge on the home balance while the wallet runs on testnet"))
            .font(.system(size: 11, weight: .bold))
            .kerning(1.2)
            .foregroundColor(Color.dash.whiteText)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.9)))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.dash.white.opacity(0.18))
            .frame(height: 0.5)
    }

    private func balanceRow(
        icon: String,
        title: String,
        duffs: UInt64,
        isSyncing: Bool = false,
        infoAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(Color.dash.whiteText)
                        if isSyncing {
                            SwiftUI.ProgressView()
                                .scaleEffect(0.7)
                                .tint(Color.dash.whiteText)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(
                        isSyncing
                            ? NSLocalizedString("Syncing", comment: "Shielded balance")
                            : viewModel.fiatString(forDuffs: duffs)
                    )
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer(minLength: 8)
                DashAmount(amount: Int64(duffs), font: .footnote, dashSymbolFactor: 0.8, showDirection: false)
                    .foregroundColor(Color.dash.whiteText)
            }
            .contentShape(Rectangle())
            .onTapGesture { infoAction() }
        }
        .padding(.vertical, 9)
    }

}
