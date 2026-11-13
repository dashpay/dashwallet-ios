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
    /// `nil` while it is read, or when it could not be read (`detailsFailed`,
    /// which with details shown says a refresh of them failed).
    let details: ConnectionDetails?
    let detailsFailed: Bool
    /// What the app was given; `nil` while unknown.
    let granted: [String]?
    /// What it was not given.
    let withheld: [String]
    /// Each key with what is left of its budget; `nil` while unknown or not
    /// read.
    let funding: [(title: String, value: String)]?
    /// Platform could not be read for it.
    let fundingFailed: Bool
    /// When the connection was made.
    let connectedAt: Date?
    let isBusy: Bool
    /// What the last action from this sheet ended in.
    let message: ConnectionsScreenMessage?
    let onClose: () -> Void
    /// Confirmed.
    let onDisconnect: () -> Void
    /// Hides a Refused connection: no PIN, nothing written to Platform.
    let onRemove: () -> Void
    /// Whether a row's Disconnect opened the sheet, so it asks at once;
    /// `false` also when it cannot ask (the view model then says why).
    let takeDisconnectQuestion: () -> Bool
    /// Whether the sheet's own Disconnect may ask now.
    let disconnectQuestion: () -> Bool
    /// Reconnect: scans the app's new code.
    let onScan: () -> Void
    let onShowFundingLimitsInfo: () -> Void

    @State private var showsGranted = false
    @State private var showsWithheld = false
    @State private var isConfirmingDisconnect = false

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
                    detailsCard
                    if details == nil {
                        detailsPlaceholder
                    } else if detailsFailed {
                        Text(NSLocalizedString(
                            "The details of this connection could not be read again and may be out of date.",
                            comment: "DashConnect connection sheet: a refresh of details already shown failed"))
                            .dashFont(.footnote)
                            .foregroundColor(Color.dash.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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

            action
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 20)
        }
        .background(Color.dash.secondaryBackground)
        // On the whole sheet: a status change while it asks does not take
        // the question with it; confirming checks what holds then.
        .confirmationDialog(
            String(
                format: NSLocalizedString(
                    "Disconnect %@?", comment: "DashConnect: confirm a disconnect; the app's name"),
                item.name),
            isPresented: $isConfirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Disconnect", comment: "DashConnect"), role: .destructive, action: onDisconnect)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "Its keys are turned off on Platform for good. To connect again, the app asks with a new code.",
                comment: "DashConnect: what a disconnect does, in its confirmation"))
        }
        // After the sheet's own transition: a dialog asked for while it
        // slides in may not show.
        .task {
            do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
            // The user may have asked from the sheet's own button meanwhile.
            guard !isConfirmingDisconnect, takeDisconnectQuestion() else { return }
            ask()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .dashFont(.title1)
                .foregroundColor(Color.dash.primaryText)
            if !item.url.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundColor(Color.dash.blue)
                        .accessibilityHidden(true)
                    Text(item.url)
                        .dashFont(.headline)
                        .foregroundColor(Color.dash.blue)
                }
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
                    .fill(ConnectionStatusBadge.dotColor(for: item.status))
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .dashFont(.callout)
                    .foregroundColor(Color.dash.primaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(isLive ? Color.dash.green.opacity(0.05) : Color.dash.gray300Alpha10)
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

    /// While the details are read, or when they could not be.
    @ViewBuilder
    private var detailsPlaceholder: some View {
        if detailsFailed {
            Text(NSLocalizedString(
                "The details of this connection could not be read.", comment: "DashConnect connection sheet"))
                .dashFont(.footnote)
                .foregroundColor(Color.dash.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // The app declares its own `ProgressView: UIView`.
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(NSLocalizedString(
                    "Reading the details of this connection", comment: "DashConnect connection sheet")))
        }
    }

    @ViewBuilder
    private var limitsCard: some View {
        let access = details?.access
        if access != nil || item.disconnectedAt != nil || connectedAt != nil {
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
                if let funding, !funding.isEmpty, item.connection != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Funding left", comment: "DashConnect connection sheet"))
                            .dashFont(.footnote)
                            .foregroundColor(Color.dash.tertiaryText)
                        ForEach(Array(funding.enumerated()), id: \.offset) { _, line in
                            Text(String(
                                format: NSLocalizedString(
                                    "%1$@: %2$@", comment: "DashConnect connection sheet: a key's name, then its budget"),
                                line.title, line.value))
                                .dashFont(.subhead)
                                .foregroundColor(Color.dash.primaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.leading, 14)
                    .padding(.vertical, 8)
                }
                if fundingFailed, item.connection != nil {
                    Text(NSLocalizedString(
                        "What is left of the keys' budgets could not be read.", comment: "DashConnect connection sheet"))
                        .dashFont(.footnote)
                        .foregroundColor(Color.dash.tertiaryText)
                        .padding(.leading, 14)
                        .padding(.vertical, 8)
                }
                if let connectedAt {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Connected", comment: "DashConnect connection sheet: when the connection was made"))
                            .dashFont(.footnote)
                            .foregroundColor(Color.dash.tertiaryText)
                        Text(Self.dateFormatter.string(from: connectedAt))
                            .dashFont(.subhead)
                            .foregroundColor(Color.dash.primaryText)
                    }
                    .accessibilityElement(children: .combine)
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

    /// The action the status allows (ADR-0019).
    @ViewBuilder
    private var action: some View {
        let actions = AppConnect.StateActions.row(for: item.status).actions
        if actions.contains(.disconnect) {
            disconnectButton
        } else if actions.contains(.remove) {
            DashUIKit.DashButton(
                text: NSLocalizedString("Remove", comment: "DashConnect: takes a refused connection off the list"),
                isEnabled: !isBusy, fillsWidth: true, size: .large, style: .tintedGray, action: onRemove)
        } else if actions.contains(.reconnect) {
            reconnectButton
        }
    }

    private var reconnectButton: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Reconnect", comment: "DashConnect connection sheet"),
            isEnabled: !isBusy, fillsWidth: true, size: .large, style: .filledBlue, action: onScan)
    }

    private var disconnectButton: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Disconnect", comment: "DashConnect"),
            // Enabled even when what it does is not known: the tap reads it
            // again, or says why it cannot ask.
            isEnabled: !isBusy, isLoading: isBusy, fillsWidth: true, size: .large, style: .tintedRed,
            action: askToDisconnect)
    }

    /// Only when the view model lets it ask.
    private func askToDisconnect() {
        guard disconnectQuestion() else { return }
        ask()
    }

    private func ask() {
        // A question that did not show leaves the flag set: it is turned
        // off first, so the button always asks.
        guard isConfirmingDisconnect else {
            isConfirmingDisconnect = true
            return
        }
        isConfirmingDisconnect = false
        Task { @MainActor in isConfirmingDisconnect = true }
    }

    // MARK: - Text

    /// The connection's record is active.
    private var isLive: Bool { item.status == .active }

    /// The status name from the state-to-actions table (ADR-0019).
    private var statusText: String {
        ConnectionStatusBadge.label(for: item.status)
    }

    private var isPast: Bool { item.status == .disconnected }

    private var grantedTitle: String {
        String(
            format: isPast
                ? NSLocalizedString("See what %@ was able to do", comment: "DashConnect connection sheet: the app's name")
                : NSLocalizedString("See what %@ will be able to do", comment: "DashConnect connection sheet: the app's name"),
            item.name)
    }

    private var withheldTitle: String {
        String(
            format: isPast
                ? NSLocalizedString(
                    "See what %@ did NOT have access to", comment: "DashConnect connection sheet: the app's name")
                : NSLocalizedString(
                    "See what %@ will NOT have access to", comment: "DashConnect connection sheet: the app's name"),
            item.name)
    }

    private func fundingLimitText(_ access: ConnectionAccess) -> String {
        if access.hasUnlimitedKey {
            return NSLocalizedString("No limit", comment: "DashConnect connection sheet: a key with no spending limit")
        }
        guard let budget = access.budgetLimit else {
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
        // Whether that time has passed on Platform is not read here.
        return (NSLocalizedString("Connection expiry", comment: "DashConnect connection sheet: the date its keys expire"), expiresAt)
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

private enum ConnectionSheetPreview {
    static let appId = "AyWK6nDVfb8d1ZmkM5MmZZrThbUyWyso1aMeGuuVSfxf"

    static func item(_ status: ConnectionStatus, name: String = "Yappr") -> ConnectionSheetItem {
        ConnectionSheetItem(
            id: appId, name: name, url: "yap.pr", status: status,
            connection: DAppConnection(
                id: appId, name: name, url: "yap.pr", status: status, updatedAt: Date(timeIntervalSince1970: 1_793_000_000)),
            entry: nil, scope: nil)
    }

    static var disconnected: ConnectionSheetItem {
        ConnectionSheetItem(
            id: appId, name: "Yappr", url: "yap.pr", status: .disconnected, connection: nil,
            entry: DisconnectedConnection(
                id: appId, name: "Yappr", url: "yap.pr", identityId: details.identityId, username: "alice",
                disconnectedAt: Date(timeIntervalSince1970: 1_794_000_000), access: details.access,
                connectedAt: Date(timeIntervalSince1970: 1_793_000_000)),
            scope: nil)
    }

    /// One key the app was given, as Platform shows it.
    static let key = AppConnect.PlatformKey(
        id: 10, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
        data: Data(repeating: 3, count: 20), readOnly: false,
        bound: .documentType(contractId: Data(repeating: 1, count: 32), name: "post"), boundKnown: true,
        totalBudget: 1_000_000_000, expiresAt: 1_794_000_000_000, disabledAt: nil)

    static let details = ConnectionDetails(
        appId: appId, identityId: "5DbLwAxEWR695MsqP4KybNQD5n7CUDWydJYNg63FzUo8", username: "alice",
        basis: ConnectionBasis(
            snapshot: AppConnect.IdentitySnapshot(
                identityId: Data(repeating: 2, count: 32), revision: 3, keys: [key], platformTime: 1_793_500_000_000),
            intents: [], unrecorded: [key], administeredGroups: []),
        connectedAt: Date(timeIntervalSince1970: 1_793_000_000))

    static func sheet(
        _ item: ConnectionSheetItem,
        details: ConnectionDetails?,
        detailsFailed: Bool = false,
        granted: [String]? = nil,
        funding: [(title: String, value: String)]? = nil,
        fundingFailed: Bool = false,
        isBusy: Bool = false,
        message: ConnectionsScreenMessage? = nil
    ) -> ConnectionSheet {
        ConnectionSheet(
            item: item, details: details, detailsFailed: detailsFailed, granted: granted,
            withheld: DashConnectPermissionText.withheld, funding: funding, fundingFailed: fundingFailed,
            connectedAt: details?.connectedAt, isBusy: isBusy, message: message, onClose: {}, onDisconnect: {}, onRemove: {},
            takeDisconnectQuestion: { false }, disconnectQuestion: { false }, onScan: {}, onShowFundingLimitsInfo: {})
    }
}

#Preview("Loading") {
    ConnectionSheetPreview.sheet(ConnectionSheetPreview.item(.active), details: nil)
}

#Preview("Loaded") {
    ConnectionSheetPreview.sheet(
        ConnectionSheetPreview.item(.active), details: ConnectionSheetPreview.details,
        granted: ConnectionSheetPreview.details.access.map {
            DashConnectPermissionText.granted($0.granted, appLabel: "Yappr")
        },
        funding: [(title: "App key", value: "0.004 DASH left of 0.01 DASH")])
}

#Preview("Details failed") {
    ConnectionSheetPreview.sheet(ConnectionSheetPreview.item(.active), details: nil, detailsFailed: true)
}

#Preview("Confirming, funding not read") {
    ConnectionSheetPreview.sheet(
        ConnectionSheetPreview.item(.confirming), details: ConnectionSheetPreview.details, fundingFailed: true)
}

#Preview("Not delivered, disconnecting") {
    ConnectionSheetPreview.sheet(
        ConnectionSheetPreview.item(.undelivered, name: "A Very Long Application Name That Wraps"),
        details: ConnectionSheetPreview.details, isBusy: true)
}

#Preview("Error message") {
    ConnectionSheetPreview.sheet(
        ConnectionSheetPreview.item(.active), details: ConnectionSheetPreview.details,
        message: ConnectionsScreenMessage(kind: .error, text: "Could not disconnect: the network did not answer."))
}

#Preview("Disconnected") {
    ConnectionSheetPreview.sheet(
        ConnectionSheetPreview.disconnected, details: ConnectionSheetPreview.details,
        granted: ConnectionSheetPreview.details.access.map {
            DashConnectPermissionText.granted($0.granted, appLabel: "Yappr")
        })
}
