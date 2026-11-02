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
    /// `nil` while it is read, or when it could not be read (`detailsFailed`).
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
    /// Where the expiry check of the rows is.
    let expiryCheck: ConnectionExpiries.Check
    /// What the last action from this sheet ended in.
    let message: ConnectionsScreenMessage?
    let onClose: () -> Void
    /// Confirmed, with what the question said a disconnect does.
    let onDisconnect: (DashConnectDisconnectEffect) -> Void
    /// The question a row's Disconnect opened the sheet for, read when it
    /// is asked: what a disconnect does. `nil` when there is none to ask, or
    /// when it cannot ask (the view model then says why).
    let takeDisconnectQuestion: () -> DashConnectDisconnectEffect?
    /// The question of the sheet's own Disconnect, read when it is asked.
    let disconnectQuestion: () -> DashConnectDisconnectEffect?
    /// Scans the app's code.
    let onScan: () -> Void
    let onMockScan: () -> Void
    let onShowFundingLimitsInfo: () -> Void

    @State private var showsGranted = false
    @State private var showsWithheld = false
    @State private var isConfirmingDisconnect = false
    /// What the open question says a disconnect does; kept while it closes.
    @State private var askedEffect: DashConnectDisconnectEffect?

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
                        ScanToCompleteBanner(onScanQR: onScan, onMockScan: onMockScan)
                    }
                    detailsCard
                    if details == nil {
                        detailsPlaceholder
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

            actionButton
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
            titleVisibility: .visible,
            presenting: askedEffect
        ) { asked in
            Button(NSLocalizedString("Disconnect", comment: "DashConnect"), role: .destructive) {
                onDisconnect(asked)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: { asked in
            Text(Self.disconnectConsequence(asked))
        }
        // After the sheet's own transition: a dialog asked for while it
        // slides in may not show.
        .task {
            do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
            // The user may have asked from the sheet's own button meanwhile.
            guard !isConfirmingDisconnect, let effect = takeDisconnectQuestion() else { return }
            ask(effect)
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
                    .fill(isLive ? Color.dash.green : Color.dash.gray300Alpha90)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .dashFont(.callout)
                    .foregroundColor(Color.dash.primaryText)
            }
            if let expiryNote {
                Text(expiryNote)
                    .dashFont(.caption1)
                    .foregroundColor(Color.dash.tertiaryText)
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

    @ViewBuilder
    private var actionButton: some View {
        switch item.status {
        case .disconnected:
            reconnectButton
        case .expired:
            // Its live keys are past their expiry by the Core tip with its
            // margin, whatever this phone's clock says, and stay on Platform
            // until a disconnect, or a renewal of the same connection, turns
            // them off: both are offered.
            VStack(spacing: 10) {
                reconnectButton
                disconnectButton
            }
        case .waitingForSecondScan:
            // The second code is the way forward.
            EmptyView()
        case .active, .confirming:
            disconnectButton
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
            isEnabled: !isBusy, isLoading: isBusy, fillsWidth: true, size: .large, style: .plainRed,
            action: askToDisconnect)
            .background(Color.dash.redAlpha5)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // DashUIKit has no tinted red style: the plain red one has a
            // clear background, so only its title would take the tap.
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Only where Disconnect is offered, and with what it will do known.
    private func askToDisconnect() {
        guard let effect = disconnectQuestion() else { return }
        ask(effect)
    }

    private func ask(_ effect: DashConnectDisconnectEffect) {
        askedEffect = effect
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

    /// What a disconnect will do, as the data source will run it: one that
    /// only changes the local status, one that turns the keys off and may
    /// take unattributed DashPay profile keys with it, or either, as the
    /// identity shows once it is read.
    private static func disconnectConsequence(_ effect: DashConnectDisconnectEffect) -> String {
        switch effect {
        case .revokesKeys:
            return NSLocalizedString(
                "Its keys are turned off on Platform for good. DashPay profile keys not linked to any connection may be turned off too, so another app using one would have to ask again.",
                comment: "DashConnect: what a disconnect does, in its confirmation")
        case .localOnly:
            return NSLocalizedString(
                "It is turned off on this device. Approving the app's code again turns it back on.",
                comment: "DashConnect: what disconnecting a two-QR connection does, in its confirmation")
        case .dependsOnPlatform:
            return NSLocalizedString(
                "Depending on the keys Dash Platform shows for this identity, its keys are turned off on Platform for good, or it is turned off on this device only. DashPay profile keys not linked to any connection may be turned off too.",
                comment: "DashConnect: what a disconnect of a two-QR connection with an earlier grant does, in its confirmation")
        }
    }

    /// The connection's record is active, and its keys are not all off.
    private var isLive: Bool { item.status == .active && item.expiry != .keysOff }

    private var statusText: String {
        switch item.status {
        case .active where item.expiry == .keysOff:
            return NSLocalizedString("Keys turned off", comment: "DashConnect connection status: every key of the app is off")
        case .active: return NSLocalizedString("Active", comment: "DashConnect connection status")
        case .expired: return NSLocalizedString("Expired", comment: "DashConnect connection status")
        case .confirming: return NSLocalizedString("Confirming", comment: "DashConnect")
        case .waitingForSecondScan:
            return NSLocalizedString("Waiting for the second code", comment: "DashConnect connection status")
        case .disconnected: return NSLocalizedString("Disconnected", comment: "DashConnect connection status")
        }
    }

    /// What the expiry check told of an active row beyond its status; `nil`
    /// when it has nothing to add (the keys can still sign, or there is
    /// nothing to judge), and before a check has ended.
    var expiryNote: String? {
        guard item.status == .active else { return nil }
        switch item.expiry {
        case .keysOff?:
            return NSLocalizedString(
                "The keys this wallet recorded for this connection are already turned off on Platform.",
                comment: "DashConnect connection sheet")
        case .pastByPhone?:
            return NSLocalizedString(
                "The keys' expiry time has passed, but the network has not shown it yet.",
                comment: "DashConnect connection sheet")
        case .undecided?:
            return NSLocalizedString(
                "A key on this identity could not be matched to an app, so whether this connection has expired is not known.",
                comment: "DashConnect connection sheet")
        case .unknown?, nil:
            guard expiryCheck == .read || expiryCheck == .failed || expiryCheck == .unavailable else { return nil }
            return NSLocalizedString(
                "Whether this connection has expired could not be checked.", comment: "DashConnect connection sheet")
        case .current?, .notJudged?, .expired?:
            return nil
        }
    }

    private var isPast: Bool { item.status == .disconnected || item.status == .expired }

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
        // Past only once the expiry check found every live key past it by
        // the Core tip with its margin, whatever this phone's clock says.
        return item.status == .expired
            ? (NSLocalizedString("Connection expired", comment: "DashConnect connection sheet"), expiresAt)
            : (NSLocalizedString("Connection expiry", comment: "DashConnect connection sheet: the date its keys expire"), expiresAt)
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
