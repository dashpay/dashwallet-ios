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
    /// Presents the identity top-up; `nil` where this build cannot, and
    /// the sheet then offers none.
    let onTopUp: (() -> Void)?

    @State private var showsGranted = true
    @State private var showsWithheld = false
    @State private var termsSheet: TermsSheet?

    private enum TermsSheet: String, Identifiable {
        case funding, expiry, fundingInfo, spendableInfo
        var id: String { rawValue }
    }

    var body: some View {
        // No title in the bar: the intro block below names the request. The
        // close button denies, as a swipe-down does through the presenter's
        // binding; both are blocked while an approval is in flight.
        DashUIKit.BottomSheet(
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!viewModel.isApproving),
            isCloseButtonEnabled: !viewModel.isApproving,
            onClose: { viewModel.denyPendingRequest(asksToReturn: true) },
            background: Color.dash.secondaryBackground
        ) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        // One box for what to check before approving
                        // (`approvalCaution`). A re-login, which replaces the
                        // app's row and turns off keys an earlier sign-in holds
                        // on the same connection (`AppConnect.supersededKeyIds`),
                        // leads with that, then since when and that the wallet
                        // does not know the app; otherwise the wallet does not
                        // know the app (and where it returns), then a first
                        // connection.
                        if let caution = viewModel.approvalCaution {
                            SystemMessageView(
                                title: caution.title,
                                subtitle: caution.subtitle,
                                backgroundColor: Color.dash.yellowAlpha10)
                        }
                        detailsCard
                        // A plan of encryption keys only has no limit or expiry
                        // to set.
                        if viewModel.approvalHasTerms {
                            termsCard
                        }
                        if let granted = viewModel.approvalGrantedLines {
                            DashConnectCollapsibleCard(
                                title: String(
                                    format: NSLocalizedString(
                                        "See what %@ will be able to do", comment: "DashConnect: the app's name"),
                                    request.resolvedAppLabel),
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
                                request.resolvedAppLabel),
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
                // Room under the content for the toast, so nothing stays under it.
                .contentMargins(
                    .bottom, (viewModel.approveError ?? viewModel.approveDisabledReason) == nil ? 0 : 72,
                    for: .scrollContent)
                // Over the end of the scrolling content, above the buttons.
                .dashConnectErrorToast(viewModel.approveError ?? viewModel.approveDisabledReason)

                footer
            }
        }
        // Every terms sheet is as tall as what it shows. The info sheets
        // start at the tallest they may be, so the first measurement is of
        // all of it; the funding and expiry sheets switch between presets and
        // a keypad or a calendar, so their height follows in an animation.
        .sheet(item: $termsSheet) { sheet in
            switch sheet {
            case .funding:
                FundingLimitSheet(viewModel: viewModel, onClose: { termsSheet = nil })
                    .animatedSelfSizingSheet(background: Color.dash.secondaryBackground)
            case .expiry:
                ExpirySheet(viewModel: viewModel, onClose: { termsSheet = nil })
                    .animatedSelfSizingSheet(background: Color.dash.secondaryBackground)
            case .fundingInfo:
                FundingLimitsInfoSheet(onClose: { termsSheet = nil })
                    .selfSizingSheet(fallback: .greatestFiniteMagnitude, background: Color.dash.secondaryBackground)
                    .presentationDragIndicator(.visible)
            case .spendableInfo:
                SpendableDashInfoSheet(onClose: { termsSheet = nil })
                    .selfSizingSheet(fallback: .greatestFiniteMagnitude, background: Color.dash.secondaryBackground)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.approvalTitle)
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

    /// The funding limit and the expiry with their Change buttons.
    private var termsCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            termRow(
                title: NSLocalizedString("Identity funding limit", comment: "DashConnect approve sheet"),
                value: viewModel.approvalFundingText ?? "",
                showsInfo: true,
                changeLabel: NSLocalizedString(
                    "Change the identity funding limit", comment: "DashConnect approve sheet: accessibility"),
                canChange: viewModel.canChangeFundingLimit,
                onChange: { termsSheet = .funding })
            termRow(
                title: NSLocalizedString("Connection will expire", comment: "DashConnect approve sheet"),
                value: viewModel.approvalExpiryText ?? "",
                showsInfo: false,
                changeLabel: NSLocalizedString("Change when the connection expires", comment: "DashConnect approve sheet: accessibility"),
                canChange: true,
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
        canChange: Bool,
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
            if canChange {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Change", comment: "DashConnect approve sheet"),
                    isEnabled: !viewModel.isApproving,
                    size: .small, style: .plainBlue, action: onChange)
                    .accessibilityLabel(Text(changeLabel))
            }
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
            if viewModel.approveNeedsTopUp, let onTopUp {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Top up identity", comment: "DashConnect approve sheet"),
                    fillsWidth: true, size: .large, style: .tintedBlue, action: onTopUp)
            }
            DashUIKit.DashButton(
                text: NSLocalizedString("Approve", comment: "DashConnect"),
                isEnabled: !viewModel.isApproving && !viewModel.approveNeedsTopUp && viewModel.termsAppliedPlan != nil,
                isLoading: viewModel.isApproving,
                fillsWidth: true, size: .large, style: .filledBlue,
                action: viewModel.approvePendingRequest)
            DashUIKit.DashButton(
                text: NSLocalizedString("Deny", comment: "DashConnect"),
                isEnabled: !viewModel.isApproving,
                fillsWidth: true, size: .large, style: .tintedGray,
                action: { viewModel.denyPendingRequest(asksToReturn: true) })
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
}

/// The approve sheet's last step for a request already answered, when it
/// returns to an app the wallet does not know: whether to open that
/// address.
struct DashConnectReturnStep: View {
    /// Where the return leads, e.g. "yap.pr".
    let host: String
    /// Why a request that came meanwhile was not taken.
    var note: String?
    let onOpen: () -> Void
    let onStay: () -> Void

    var body: some View {
        // The close button stays in the wallet, as a swipe-down does
        // through the presenter's binding.
        DashUIKit.BottomSheet(
            showBackButton: .constant(false),
            onClose: onStay,
            background: Color.dash.secondaryBackground
        ) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(
                            format: NSLocalizedString(
                                "Return to %@?",
                                comment: "DashConnect: asks before returning to an app the wallet does not know; the placeholder is a website, e.g. yap.pr"),
                            host))
                            .dashFont(.title1)
                            .foregroundColor(Color.dash.primaryText)
                        Text(NSLocalizedString(
                            "This wallet does not know this app, so it cannot confirm where this address leads. Open it only if you started this on that website.",
                            comment: "DashConnect: asks before returning to an app the wallet does not know"))
                            .dashFont(.subhead)
                            .foregroundColor(Color.dash.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                }

                VStack(spacing: 10) {
                    DashConnectInlineErrorToast(message: note)
                    DashUIKit.DashButton(
                        text: String(
                            format: NSLocalizedString(
                                "Open %@",
                                comment: "DashConnect: return to an app the wallet does not know; the placeholder is a website, e.g. yap.pr"),
                            host),
                        fillsWidth: true, size: .large, style: .filledBlue, action: onOpen)
                    DashUIKit.DashButton(
                        text: NSLocalizedString(
                            "Stay in the wallet", comment: "DashConnect: do not return to an app the wallet does not know"),
                        fillsWidth: true, size: .large, style: .tintedGray, action: onStay)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
    }
}

/// The funding limit for the whole connection: a preset, or an amount typed
/// on the keypad, up to the wallet's cap.
struct FundingLimitSheet: View {
    @ObservedObject var viewModel: ConnectionsViewModel
    let onClose: () -> Void

    @State private var isTyping = false
    @State private var typed = ""
    /// The typed amount's size, scaled with the user's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 32

    var body: some View {
        BottomSheet(
            title: isTyping
                ? NSLocalizedString("Funding limit", comment: "DashConnect funding limit keypad")
                : NSLocalizedString("Identity funding limits", comment: "DashConnect funding limit presets"),
            showBackButton: .constant(isTyping),
            onBackButtonPressed: { withAnimation(.smooth(duration: 0.3)) { isTyping = false } },
            onClose: onClose,
            fillsHeight: false,
            background: Color.dash.secondaryBackground
        ) {
            // One slot: during the cross-fade only the incoming view sets
            // the height the sheet animates to.
            ZStack(alignment: .top) {
                if isTyping { keypad.transition(.opacity) } else { presets.transition(.opacity) }
            }
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
                            if viewModel.setFundingLimit(preset.credits) { onClose() }
                        })
                }
            }
            .modifier(MenuViewModifier())
            // A limit that is none of the presets (the app's own ask, or a
            // typed amount) is this row's, selected with its amount.
            RadioButtonRow(
                title: NSLocalizedString("Set limit", comment: "DashConnect funding limit presets"),
                trailingText: viewModel.customFundingLimitText,
                isSelected: viewModel.customFundingLimitText != nil,
                action: {
                    // Opens on the limit in effect when it is this row's.
                    typed = viewModel.customFundingLimitTyped ?? ""
                    withAnimation(.smooth(duration: 0.3)) { isTyping = true }
                })
                .modifier(MenuViewModifier())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var keypad: some View {
        let error = viewModel.fundingLimitError(forDash: typed)
        let credits = viewModel.credits(fromDash: typed)
        let color = error == nil ? Color.dash.primaryText : Color.dash.red
        return VStack(spacing: 0) {
            // The typed amount with the Dash sign over the keypad (Figma
            // "Custom funding limit"); what is wrong with it shows as a toast
            // under the amount.
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(typed.isEmpty ? "0" : typed)
                        .font(.system(size: amountSize, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    DashIcon.Common.iconDashCurrency.image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
                .foregroundColor(color)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(String(
                    format: NSLocalizedString("%@ DASH", comment: "DashConnect funding limit keypad: a typed amount"),
                    typed.isEmpty ? "0" : typed)))
                DashConnectInlineErrorToast(message: error)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 40)
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
    /// Why the picked date was not taken.
    @State private var dateError: String?

    var body: some View {
        BottomSheet(
            title: isPickingDate
                ? NSLocalizedString("Set date", comment: "DashConnect expiry date picker")
                : NSLocalizedString("Connection expiration period", comment: "DashConnect expiry presets"),
            showBackButton: .constant(isPickingDate),
            onBackButtonPressed: { withAnimation(.smooth(duration: 0.3)) { isPickingDate = false } },
            onClose: onClose,
            fillsHeight: false,
            background: Color.dash.secondaryBackground
        ) {
            ZStack(alignment: .top) {
                if isPickingDate { picker.transition(.opacity) } else { presets.transition(.opacity) }
            }
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
            // An expiry that is none of the presets (the app's own ask, or a
            // picked date) is this row's, selected with its date.
            RadioButtonRow(
                title: NSLocalizedString("Set date", comment: "DashConnect expiry presets"),
                trailingText: viewModel.customExpiryText,
                isSelected: viewModel.customExpiryText != nil,
                action: {
                    // Opens on the expiry in effect, not on today.
                    date = viewModel.approvalExpiryDate ?? viewModel.earliestExpiry
                    dateError = nil
                    withAnimation(.smooth(duration: 0.3)) { isPickingDate = true }
                })
                .modifier(MenuViewModifier())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var picker: some View {
        VStack(spacing: 20) {
            DatePicker(
                NSLocalizedString("Connection will expire", comment: "DashConnect approve sheet"),
                selection: $date,
                in: viewModel.earliestExpiry...viewModel.latestExpiry,
                displayedComponents: .date)
                .datePickerStyle(.graphical)
            DashConnectInlineErrorToast(message: dateError)
            DashUIKit.DashButton(
                text: NSLocalizedString("Submit", comment: "DashConnect funding limit keypad"),
                fillsWidth: true, size: .large, style: .filledBlue,
                action: {
                    if viewModel.setExpiry(date: date) {
                        onClose()
                    } else {
                        dateError = NSLocalizedString(
                            "This date has passed or is too far away. Pick another one.",
                            comment: "DashConnect expiry date picker: the picked date was refused")
                    }
                })
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .onChange(of: date) { _, _ in dateError = nil }
    }
}

/// What spendable Dash is: the wallet's own balance, which an app connection
/// never touches.
struct SpendableDashInfoSheet: View {
    let onClose: () -> Void

    /// The text's natural height: the scroll view takes no more than this,
    /// so the sheet sizes to its content (`selfSizingSheet`) and scrolls only
    /// when the text is taller than the sheet can be.
    @State private var textHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: textHeight)

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

private enum AppConnectApproveSheetPreview {
    /// A request for one HIGH key on Yappr's "post" documents, with a
    /// budget and an expiry, and an encryption key.
    static var request: ConnectionRequest {
        var request = MockDashConnectDataSource.sampleRequest
        let contract = MockDashConnectDataSource.sampleLoginRequest.contractId
        let binding = AppConnectRequest.AuthBinding(
            kind: .documentType, securityLevel: .high, id: contract, totalBudget: 1_000_000_000,
            expiresAt: 1_800_000_000_000, documentTypeName: "post")
        request.login = .appConnect(AppConnect.GrantPlan(
            appId: contract, appEphemeralPubKeyHash: Data(repeating: 1, count: 20),
            auth: [.init(bindingIndex: 0, binding: binding, totalBudget: 1_000_000_000, expiresAt: 1_800_000_000_000)],
            encryption: [], connectionId: nil, identityHint: nil, createdAt: 1_793_000_000_000))
        return request
    }

    @MainActor
    static func viewModel(isApproving: Bool = false, error: String? = nil) -> ConnectionsViewModel {
        let viewModel = ConnectionsViewModel(dataSource: MockDashConnectDataSource(), featureUnavailable: false)
        viewModel.pendingRequest = request
        viewModel.isApproving = isApproving
        viewModel.approveError = error
        return viewModel
    }
}

#Preview("Approve") {
    AppConnectApproveSheet(viewModel: AppConnectApproveSheetPreview.viewModel(), request: AppConnectApproveSheetPreview.request, onTopUp: {})
}

#Preview("Approving") {
    AppConnectApproveSheet(
        viewModel: AppConnectApproveSheetPreview.viewModel(isApproving: true),
        request: AppConnectApproveSheetPreview.request, onTopUp: nil)
}

#Preview("Failed") {
    AppConnectApproveSheet(
        viewModel: AppConnectApproveSheetPreview.viewModel(error: "Could not complete the DashConnect request: the network did not answer."),
        request: AppConnectApproveSheetPreview.request, onTopUp: {})
}

#Preview("Return step") {
    DashConnectReturnStep(host: "yap.pr", onOpen: {}, onStay: {})
}

#Preview("Return step, with a note") {
    DashConnectReturnStep(
        host: "a-very-long-host-name.example.org",
        note: "Another request arrived while this one was on screen; ask the app again.",
        onOpen: {}, onStay: {})
}

#Preview("Funding limit") {
    FundingLimitSheet(viewModel: AppConnectApproveSheetPreview.viewModel(), onClose: {})
}
