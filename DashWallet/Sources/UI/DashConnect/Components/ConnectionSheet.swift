//
//  ConnectionSheet.swift
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

import DashUIKit
import SwiftUI

/// One connection: its status, the app and identity, what the app was
/// given, and the action that fits its status.
struct ConnectionSheet: View {
    let item: ConnectionSheetItem
    /// `nil` while it is read.
    let details: ConnectionDetails?
    let isBusy: Bool
    /// Platform is being read for the expiry.
    let isCheckingStatus: Bool
    /// What the last action from this sheet ended in.
    let message: ConnectionsScreenMessage?
    let onClose: () -> Void
    let onDisconnect: () -> Void
    let onReconnect: () -> Void
    let onMockScan: () -> Void
    let onShowFundingLimitsInfo: () -> Void

    @State private var showsGranted = false
    @State private var showsWithheld = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                DashUIKit.NavigationBarElement.close.button(action: onClose)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statusCard
                    if item.status == .waitingForSecondScan {
                        ScanToCompleteBanner(onScanQR: onReconnect, onMockScan: onMockScan)
                    }
                    detailsCard
                    limitsCard
                    if let granted {
                        collapsible(title: grantedTitle, isExpanded: $showsGranted) {
                            ForEach(Array(granted.enumerated()), id: \.offset) {
                                PermissionRow(icon: .custom("dashconnect.check.circle", maxHeight: 18), text: $0.element)
                            }
                        }
                        collapsible(title: withheldTitle, isExpanded: $showsWithheld) {
                            ForEach(withheld, id: \.self) {
                                PermissionRow(icon: .custom("dashconnect.xmark.circle", maxHeight: 18), text: $0)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
            }

            if let message {
                Text(message.text)
                    .dashFont(.footnote)
                    .foregroundColor(message.kind == .error ? Color.dash.red : Color.dash.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.top, 12)
            }

            actionButton
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 20)
        }
        .background(Color.dash.secondaryBackground)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .dashFont(.title1)
                .foregroundColor(Color.dash.primaryText)
            if !item.url.isEmpty {
                Text(item.url)
                    .dashFont(.headline)
                    .foregroundColor(Color.dash.blue)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(NSLocalizedString("Status", comment: "DashConnect connection sheet"))
                .dashFont(.caption1)
                .foregroundColor(Color.dash.tertiaryText)
            HStack(spacing: 6) {
                Circle()
                    .fill(item.status == .active ? Color.dash.green : Color.dash.gray300Alpha90)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .dashFont(.callout)
                    .foregroundColor(Color.dash.primaryText)
            }
            if !item.isStatusChecked, !isCheckingStatus {
                Text(NSLocalizedString(
                    "Whether this connection has expired could not be checked.",
                    comment: "DashConnect connection sheet"))
                    .dashFont(.caption1)
                    .foregroundColor(Color.dash.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(item.status == .active ? Color.dash.green.opacity(0.05) : Color.dash.gray300Alpha10)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var detailsCard: some View {
        VStack(spacing: 2) {
            DetailLine(title: NSLocalizedString("App ID", comment: "DashConnect connection sheet"), value: item.id)
            if let username = details?.username, !username.isEmpty {
                DetailLine(title: NSLocalizedString("Username", comment: "DashConnect connection sheet"), value: username)
            }
            if let identityId = details?.identityId {
                DetailLine(
                    title: NSLocalizedString("Identity", comment: "DashConnect connection sheet"),
                    value: DashConnectIdentifierFormatting.truncateMiddle(identityId))
            }
        }
        .padding(6)
        .background(Color.dash.gray300Alpha10)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var limitsCard: some View {
        let access = details?.access
        if access != nil || item.disconnectedAt != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let access {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Identity funding limits", comment: "DashConnect connection sheet"))
                                .dashFont(.footnote)
                                .foregroundColor(Color.dash.tertiaryText)
                            Button(action: onShowFundingLimitsInfo) {
                                InfoRoundIcon(size: 13, color: Color.dash.gray300Alpha90)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .frame(width: 18, height: 18)
                            .accessibilityLabel(Text(NSLocalizedString(
                                "What are identity funding limits?", comment: "DashConnect connection sheet")))
                        }
                        Text(fundingLimitText(access))
                            .dashFont(.subhead)
                            .foregroundColor(Color.dash.primaryText)
                    }
                    .padding(.leading, 14)
                    .padding(.vertical, 8)
                }
                if let date = dateLine {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(date.title)
                            .dashFont(.footnote)
                            .foregroundColor(Color.dash.tertiaryText)
                        Text(Self.dateFormatter.string(from: date.date))
                            .dashFont(.subhead)
                            .foregroundColor(Color.dash.primaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.leading, 14)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.dash.gray300Alpha20, lineWidth: 2))
        }
    }

    private func collapsible<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { isExpanded.wrappedValue.toggle() } }) {
                HStack(spacing: 20) {
                    Text(title)
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ChevronIcon(direction: isExpanded.wrappedValue ? .up : .down, size: 10, color: Color.dash.primaryText)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.dash.gray300Alpha10))
                }
                .padding(.leading, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(Text(isExpanded.wrappedValue
                ? NSLocalizedString("Expanded", comment: "Accessibility: a section that is open")
                : NSLocalizedString("Collapsed", comment: "Accessibility: a section that is closed")))

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 12) { content() }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.dash.gray300Alpha20, lineWidth: 2))
    }

    @ViewBuilder
    private var actionButton: some View {
        switch item.status {
        case .disconnected:
            DashUIKit.DashButton(
                text: NSLocalizedString("Reconnect", comment: "DashConnect connection sheet"),
                isEnabled: !isBusy, fillsWidth: true, size: .large, style: .filledBlue, action: onReconnect)
        case .waitingForSecondScan:
            // A disconnect only turns a two-QR row back into this state: the
            // second code is the way forward.
            EmptyView()
        case .active, .expired, .confirming:
            DashUIKit.DashButton(
                text: NSLocalizedString("Disconnect", comment: "DashConnect"),
                isEnabled: !isBusy, isLoading: isBusy, fillsWidth: true, size: .large, style: .plainRed,
                action: onDisconnect)
                .background(Color.dash.redAlpha5)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Text

    private var statusText: String {
        switch item.status {
        case .active: return NSLocalizedString("Active", comment: "DashConnect connection status")
        case .confirming: return NSLocalizedString("Confirming", comment: "DashConnect")
        case .waitingForSecondScan:
            return NSLocalizedString("Waiting for the second code", comment: "DashConnect connection status")
        case .expired: return NSLocalizedString("Expired", comment: "DashConnect connection status")
        case .disconnected: return NSLocalizedString("Disconnected", comment: "DashConnect connection status")
        }
    }

    private var isPast: Bool { item.status == .disconnected || item.status == .expired }

    private var grantedTitle: String {
        String(
            format: isPast
                ? NSLocalizedString("See what %@ could do", comment: "DashConnect connection sheet: the app's name")
                : NSLocalizedString("See what %@ can do", comment: "DashConnect connection sheet: the app's name"),
            item.name)
    }

    private var withheldTitle: String {
        String(
            format: isPast
                ? NSLocalizedString("See what %@ could not access", comment: "DashConnect connection sheet: the app's name")
                : NSLocalizedString("See what %@ cannot access", comment: "DashConnect connection sheet: the app's name"),
            item.name)
    }

    /// The lines of what the app was given; `nil` while unknown.
    private var granted: [String]? {
        guard let keys = details?.access?.keys else { return nil }
        return DashConnectPermissionText.granted(
            AppConnect.GrantedAccess(
                keys: keys, receivesMessages: details?.access?.receivesMessages ?? false,
                isSessionKeyLogin: details?.access?.isSessionKeyLogin ?? false),
            appLabel: item.name)
    }

    private var withheld: [String] {
        details?.access?.isSessionKeyLogin == true
            ? DashConnectPermissionText.sessionKeyWithheld : DashConnectPermissionText.withheld
    }

    private func fundingLimitText(_ access: ConnectionAccess) -> String {
        if access.hasUnlimitedKey {
            return NSLocalizedString("No limit", comment: "DashConnect connection sheet: a key with no spending limit")
        }
        guard let budget = access.largestBudget else {
            return NSLocalizedString("Not known", comment: "DashConnect connection sheet")
        }
        return String(
            format: NSLocalizedString(
                "Maximum of %@", comment: "DashConnect connection sheet: an amount with its unit, e.g. 0.5 DASH"),
            PlatformCreditsFormatter.dashString(budget))
    }

    private var dateLine: (title: String, date: Date)? {
        if let disconnectedAt = item.disconnectedAt {
            return (NSLocalizedString("Connection disconnected", comment: "DashConnect connection sheet"), disconnectedAt)
        }
        guard let expiresAt = details?.access?.expiresAt else { return nil }
        return item.status == .expired
            ? (NSLocalizedString("Connection expired", comment: "DashConnect connection sheet"), expiresAt)
            : (NSLocalizedString("Connection will expire", comment: "DashConnect connection sheet"), expiresAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

/// A caption over its value.
private struct DetailLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .dashFont(.caption1)
                .foregroundColor(Color.dash.tertiaryText)
            Text(value)
                .dashFont(.callout)
                .foregroundColor(Color.dash.primaryText)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
