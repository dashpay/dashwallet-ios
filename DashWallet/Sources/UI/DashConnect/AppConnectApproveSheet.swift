//
//  AppConnectApproveSheet.swift
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

/// The approval of an App Connect v2 request: who asks, the funding limit
/// and expiry the user can change, and what the app will and will not be
/// able to do. The terms live in the view model; this view only shows them.
struct AppConnectApproveSheet: View {
    @ObservedObject var viewModel: ConnectionsViewModel
    let request: ConnectionRequest
    let plan: AppConnect.GrantPlan
    let onTopUp: () -> Void

    @State private var showsGranted = true
    @State private var showsWithheld = false
    @State private var termsSheet: TermsSheet?

    private enum TermsSheet: String, Identifiable {
        case funding, expiry, fundingInfo, spendableInfo
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.dash.gray300Alpha50)
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 24)
                .accessibilityHidden(true)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if viewModel.pendingIsFirstConnection {
                        SystemMessageView(
                            title: String(
                                format: NSLocalizedString(
                                    "You have never connected to this app before. Only approve if you trust %@.",
                                    comment: "DashConnect approve sheet: the app's name"),
                                request.appLabel),
                            backgroundColor: Color.dash.yellowAlpha10)
                    }
                    detailsCard
                    originNote
                    termsCard
                    if let granted = viewModel.approvalGrantedLines {
                        DashConnectCollapsibleCard(
                            title: String(
                                format: NSLocalizedString(
                                    "See what %@ will be able to do", comment: "DashConnect: the app's name"),
                                request.appLabel),
                            isExpanded: $showsGranted) {
                                ForEach(Array(granted.enumerated()), id: \.offset) {
                                    PermissionRow(icon: .custom("dashconnect.check.circle", maxHeight: 18), text: $0.element)
                                }
                            }
                    }
                    DashConnectCollapsibleCard(
                        title: String(
                            format: NSLocalizedString(
                                "See what %@ will NOT have access to", comment: "DashConnect: the app's name"),
                            request.appLabel),
                        isExpanded: $showsWithheld) {
                            ForEach(DashConnectPermissionText.withheld, id: \.self) {
                                PermissionRow(icon: .custom("dashconnect.xmark.circle", maxHeight: 18), text: $0)
                            }
                            spendableRow
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }

            footer
        }
        .background(Color.dash.secondaryBackground)
        .sheet(item: $termsSheet) { sheet in
            switch sheet {
            case .funding:
                FundingLimitSheet(viewModel: viewModel, onClose: { termsSheet = nil })
                    .presentationDetents([.medium, .large])
            case .expiry:
                ExpirySheet(viewModel: viewModel, onClose: { termsSheet = nil })
                    .presentationDetents([.medium, .large])
            case .fundingInfo:
                FundingLimitsInfoSheet(onClose: { termsSheet = nil })
                    .presentationDetents([.medium, .large])
            case .spendableInfo:
                SpendableDashInfoSheet(onClose: { termsSheet = nil })
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(
                format: NSLocalizedString("Approve connection to %@?", comment: "DashConnect"), request.appLabel))
                .dashFont(.title1)
                .foregroundColor(Color.dash.primaryText)
            if !request.appUrl.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundColor(Color.dash.blue)
                        .accessibilityHidden(true)
                    Text(request.appUrl)
                        .dashFont(.headline)
                        .foregroundColor(Color.dash.blue)
                }
            }
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 2) {
            DashConnectDetailLine(title: NSLocalizedString("App ID", comment: "DashConnect connection sheet"), value: request.appContractId)
            DashConnectDetailLine(
                title: NSLocalizedString("Requested", comment: "DashConnect approve sheet: when the app asked"),
                value: viewModel.approvalRequestAge ?? "")
            if let username = request.walletUsername {
                DashConnectDetailLine(title: NSLocalizedString("Username", comment: "DashConnect"), value: username)
            }
            if let identityId = request.walletIdentityId {
                DashConnectDetailLine(
                    title: NSLocalizedString("Identity", comment: "DashConnect"),
                    value: DashConnectIdentifierFormatting.truncateMiddle(identityId))
            }
        }
        .padding(6)
        .background(Color.dash.gray300Alpha10)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Where the request returns and what the wallet cannot vouch for: the
    /// user's signals that a request did not come from the app.
    @ViewBuilder
    private var originNote: some View {
        let lines = viewModel.approvalOriginLines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .dashFont(.footnote)
                        .fontWeight(index == 0 && viewModel.approvalHasOriginWarning ? .semibold : .regular)
                        .foregroundColor(index == 0 && viewModel.approvalHasOriginWarning
                            ? Color.dash.primaryText : Color.dash.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var termsCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            termRow(
                title: NSLocalizedString("Identity funding limit", comment: "DashConnect approve sheet"),
                value: viewModel.approvalFundingText ?? "",
                showsInfo: true,
                changeLabel: NSLocalizedString(
                    "Change the identity funding limit", comment: "DashConnect approve sheet: accessibility"),
                onChange: { termsSheet = .funding })
            termRow(
                title: NSLocalizedString("Connection will expire", comment: "DashConnect approve sheet"),
                value: viewModel.approvalExpiryText ?? "",
                showsInfo: false,
                changeLabel: NSLocalizedString("Change when the connection expires", comment: "DashConnect approve sheet: accessibility"),
                onChange: { termsSheet = .expiry })
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.dash.gray300Alpha20, lineWidth: 2))
    }

    private func termRow(
        title: String,
        value: String,
        showsInfo: Bool,
        changeLabel: String,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .dashFont(.footnote)
                        .foregroundColor(Color.dash.tertiaryText)
                    if showsInfo {
                        Button(action: { termsSheet = .fundingInfo }) {
                            InfoRoundIcon(size: 13, color: Color.dash.gray300Alpha90)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .frame(width: 18, height: 18)
                        .accessibilityLabel(Text(NSLocalizedString(
                            "What are identity funding limits?", comment: "DashConnect connection sheet")))
                    }
                }
                Text(value)
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DashUIKit.DashButton(
                text: NSLocalizedString("Change", comment: "DashConnect approve sheet"),
                isEnabled: !viewModel.isApproving && !viewModel.approvalTermsLocked,
                size: .small, style: .plainBlue, action: onChange)
                .accessibilityLabel(Text(changeLabel))
        }
        .padding(.leading, 14)
        .padding(.vertical, 8)
    }

    private var spendableRow: some View {
        HStack(alignment: .top, spacing: 6) {
            PermissionRow(
                icon: .custom("dashconnect.xmark.circle", maxHeight: 18),
                text: NSLocalizedString("Your spendable Dash balance", comment: "DashConnect approve sheet"))
            Spacer(minLength: 0)
            Button(action: { termsSheet = .spendableInfo }) {
                InfoRoundIcon(size: 16, color: Color.dash.gray300Alpha90)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .frame(width: 20, height: 20)
            .accessibilityLabel(Text(NSLocalizedString("What is spendable Dash?", comment: "DashConnect approve sheet")))
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = viewModel.approveError {
                Text(error)
                    .dashFont(.footnote)
                    .foregroundColor(Color.dash.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if viewModel.approveNeedsTopUp {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Top up identity", comment: "DashConnect approve sheet"),
                    fillsWidth: true, size: .large, style: .tintedBlue, action: onTopUp)
            }
            DashUIKit.DashButton(
                text: NSLocalizedString("Approve", comment: "DashConnect"),
                isEnabled: !viewModel.isApproving && viewModel.termsAppliedPlan != nil,
                isLoading: viewModel.isApproving,
                fillsWidth: true, size: .large, style: .filledBlue,
                action: viewModel.approvePendingRequest)
            DashUIKit.DashButton(
                text: NSLocalizedString("Deny", comment: "DashConnect"),
                isEnabled: !viewModel.isApproving,
                fillsWidth: true, size: .large, style: .tintedGray,
                action: viewModel.denyPendingRequest)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
}

/// The funding limit for the whole connection: a preset, or an amount typed
/// on the keypad, up to the wallet's cap.
struct FundingLimitSheet: View {
    @ObservedObject var viewModel: ConnectionsViewModel
    let onClose: () -> Void

    @State private var isTyping = false
    @State private var typed = ""

    var body: some View {
        BottomSheet(
            title: isTyping
                ? NSLocalizedString("Funding limit", comment: "DashConnect funding limit keypad")
                : NSLocalizedString("Identity funding limits", comment: "DashConnect funding limit presets"),
            showBackButton: .constant(isTyping),
            onBackButtonPressed: { isTyping = false },
            onClose: onClose,
            background: Color.dash.secondaryBackground
        ) {
            if isTyping { keypad } else { presets }
        }
    }

    private var presets: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                ForEach(viewModel.fundingPresets, id: \.credits) { preset in
                    RadioButtonRow(
                        title: PlatformCreditsFormatter.dashString(preset.credits),
                        isSelected: preset.isSelected,
                        action: {
                            viewModel.setFundingLimit(preset.credits)
                            onClose()
                        })
                }
            }
            .modifier(MenuViewModifier())
            Button(action: { isTyping = true }) {
                Text(NSLocalizedString("Set limit", comment: "DashConnect funding limit presets"))
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(MenuViewModifier())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var keypad: some View {
        let error = viewModel.fundingLimitError(forDash: typed)
        let credits = viewModel.credits(fromDash: typed)
        return VStack(spacing: 8) {
            Spacer(minLength: 0)
            Text(String(
                format: NSLocalizedString("%@ DASH", comment: "DashConnect funding limit keypad: a typed amount"),
                typed.isEmpty ? "0" : typed))
                .dashFont(.title1)
                .foregroundColor(error == nil ? Color.dash.primaryText : Color.dash.red)
            Text(error ?? " ")
                .dashFont(.footnote)
                .foregroundColor(Color.dash.red)
                .accessibilityHidden(error == nil)
            Spacer(minLength: 0)
            NumericKeyboardView(
                value: $typed,
                showDecimalSeparator: true,
                actionButtonText: NSLocalizedString("Submit", comment: "DashConnect funding limit keypad"),
                actionEnabled: error == nil && (credits ?? 0) > 0,
                inProgress: false,
                actionHandler: {
                    if let credits, viewModel.setFundingLimit(credits) { onClose() }
                })
        }
    }
}

/// When every key of the connection expires: a preset, or a date up to the
/// wallet's cap.
struct ExpirySheet: View {
    @ObservedObject var viewModel: ConnectionsViewModel
    let onClose: () -> Void

    @State private var isPickingDate = false
    @State private var date = Date()

    var body: some View {
        BottomSheet(
            title: isPickingDate
                ? NSLocalizedString("Set date", comment: "DashConnect expiry date picker")
                : NSLocalizedString("Connection expiration period", comment: "DashConnect expiry presets"),
            showBackButton: .constant(isPickingDate),
            onBackButtonPressed: { isPickingDate = false },
            onClose: onClose,
            background: Color.dash.secondaryBackground
        ) {
            if isPickingDate { picker } else { presets }
        }
    }

    private var presets: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                ForEach(viewModel.expiryPresets, id: \.days) { preset in
                    RadioButtonRow(
                        title: String(
                            format: NSLocalizedString("%d days", comment: "DashConnect expiry presets: a number of days"),
                            preset.days),
                        isSelected: preset.isSelected,
                        action: {
                            viewModel.setExpiry(days: preset.days)
                            onClose()
                        })
                }
            }
            .modifier(MenuViewModifier())
            Button(action: { isPickingDate = true }) {
                Text(NSLocalizedString("Set date", comment: "DashConnect expiry presets"))
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(MenuViewModifier())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var picker: some View {
        VStack(spacing: 20) {
            DatePicker(
                NSLocalizedString("Connection will expire", comment: "DashConnect approve sheet"),
                selection: $date,
                in: Date()...viewModel.latestExpiry,
                displayedComponents: .date)
                .datePickerStyle(.graphical)
            DashUIKit.DashButton(
                text: NSLocalizedString("Submit", comment: "DashConnect funding limit keypad"),
                fillsWidth: true, size: .large, style: .filledBlue,
                action: { if viewModel.setExpiry(date: date) { onClose() } })
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

/// What spendable Dash is: the wallet's own balance, which an app connection
/// never touches.
struct SpendableDashInfoSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scrolls at large text sizes, so "Got it" stays in reach.
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("What is spendable Dash?", comment: "DashConnect approve sheet"))
                        .dashFont(.title2)
                        .foregroundColor(Color.dash.primaryText)
                    Text(NSLocalizedString(
                        "This is the Dash on your wallet's home screen – the balance you can send to anyone.",
                        comment: "DashConnect: what spendable Dash is"))
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.primaryText)
                    Text(NSLocalizedString(
                        "It's separate from your identity's balance, which only pays for network actions.",
                        comment: "DashConnect: what spendable Dash is"))
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.primaryText)
                        .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 40)
            }

            DashUIKit.DashButton(
                text: NSLocalizedString("Got it", comment: "DashConnect"),
                fillsWidth: true, size: .large, style: .tintedGray, action: onClose)
                .padding(.horizontal, 40)
                .padding(.vertical, 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.secondaryBackground)
    }
}
