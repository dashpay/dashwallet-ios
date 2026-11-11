//
//  Created by Roman Chornyi
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

/// SCR-06 Confirm and SCR-08 Sending. Draws the ViewModel's state; Cancel and the close button both call `cancel()`,
/// which does nothing while sending, and the sheet's swipe-down is locked until the outcome.
struct ConfirmSheet: View {
    @ObservedObject var viewModel: ConfirmViewModel

    var body: some View {
        ConfirmSheetContent(viewModel: viewModel)
            .task { await viewModel.start() }
    }
}

/// The sheet without the `start()` that prepares the send, which a preview must not run.
struct ConfirmSheetContent: View {
    @ObservedObject var viewModel: ConfirmViewModel

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: NSLocalizedString("Confirm", comment: "External send"),
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!viewModel.isDismissLocked),
            showsCloseButton: viewModel.isCancelVisible,
            onClose: viewModel.cancel,
            content: {
                ViewThatFits(in: .vertical) {
                    sheetBody
                    ScrollView { sheetBody }
                }
            })
    }

    private var sheetBody: some View {
        VStack(spacing: 16) {
            amount
            rows
            messages
            buttons
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Amount, From, To, fee and total

    private var amount: some View {
        VStack(spacing: 4) {
            DashUIKit.DashAmount(amount: viewModel.amountDuffs, fontSize: 34, weight: .bold, sign: .none)
            if let fiat = viewModel.amountFiatText {
                Text(fiat)
                    .dashFont(.subhead)
                    .foregroundStyle(Color.dash.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            DashUIKit.List1View(label: NSLocalizedString("From", comment: "External send"),
                                value: viewModel.fromText)
            DashUIKit.List1View(label: NSLocalizedString("To", comment: "External send"), value: viewModel.toText)
            DashUIKit.List1View(label: NSLocalizedString("Network fee", comment: "External send"),
                                value: viewModel.feeRowText)
                .accessibilityElement(children: .combine)
                .accessibilityValue(viewModel.feeAccessibilityValue)
            if let note = viewModel.feeEstimateNote {
                Text(note)
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
            DashUIKit.List1View(label: NSLocalizedString("Total", comment: "External send"),
                                value: viewModel.totalRowText)
                .accessibilityElement(children: .combine)
                .accessibilityValue(viewModel.totalAccessibilityValue)
        }
        .modifier(DashUIKit.MenuViewModifier())
        .accessibilityElement(children: .contain)
    }

    // MARK: - Warnings and the blocked message

    @ViewBuilder private var messages: some View {
        if let message = viewModel.blockedMessage {
            DashUIKit.SystemMessageView(
                title: message,
                backgroundColor: Color.dash.redAlpha5,
                buttonName: NSLocalizedString("Try again", comment: "External send"),
                onAction: { Task { await viewModel.tryAgain() } })
        }
        ForEach(viewModel.warningItems) { warning in
            DashUIKit.SystemMessageView(
                title: warning.title,
                subtitle: warning.subtitle,
                icon: Self.icon(of: warning.style),
                backgroundColor: warning.style == .caution ? Color.dash.orangeAlpha10 : Color.dash.blueAlpha5)
        }
    }

    private static func icon(of style: ConfirmViewModel.Warning.Style) -> DashUIKit.DashIconSource {
        switch style {
        case .info: return DashIcon.SystemMessage.infoRectSmall.source
        case .delay: return DashIcon.SystemMessage.timerSmall.source
        case .publicExposure: return .system("eye")
        case .caution: return DashIcon.SystemMessage.warningTriangle.source
        }
    }

    // MARK: - Cancel and Confirm, or Sending

    @ViewBuilder private var buttons: some View {
        if viewModel.isCancelVisible {
            HStack(spacing: 8) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Cancel", comment: "External send"),
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: viewModel.cancel)
                    .accessibilityIdentifier("send_confirm_cancel")
                DashUIKit.DashButton(
                    text: NSLocalizedString("Confirm", comment: "External send"),
                    isEnabled: viewModel.isConfirmEnabled,
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: { Task { await viewModel.confirm() } })
                    .accessibilityIdentifier("send_confirm_button")
            }
        } else {
            DashUIKit.DashButton(
                text: NSLocalizedString("Sending…", comment: "External send"),
                isLoading: true,
                fillsWidth: true,
                size: .large,
                style: .filledBlue)
        }
    }
}

#if DEBUG

private let previewAddress = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN"
private let previewIdentityID = "7Zp3MqIdentityIDxxxxxxxxxxxxxxxxxxxxxxoVyBn"

@MainActor
private final class PreviewExecutor: ExternalSendExecuting {
    func prepare(route: SendRoute, destination: Destination, amount: UInt64,
                 isMax: Bool, sweepCredits: UInt64?) async throws -> PreparedExternalSend {
        throw ExternalSendError.feeUnavailable
    }

    func send(_ prepared: PreparedExternalSend) async -> SendOutcome { .sent }
    func discard(_ prepared: PreparedExternalSend) {}
}

private struct PreviewBalances: ExternalSendBalanceReading {
    func spendableBalance(of source: SendSource) async -> UInt64? { nil }
}

/// 1 DASH = 50 units of the local currency.
private struct PreviewConverter: SendAmountConverting {
    func fiat(forDuffs duffs: UInt64) -> Decimal? { Decimal(duffs) / 100_000_000 * 50 }
    func duffs(forFiat fiat: Decimal) -> UInt64? { nil }
    func fiatText(forDuffs duffs: UInt64) -> String? { "$\(fiat(forDuffs: duffs) ?? 0)" }
}

private func previewWarning(_ id: Int, _ style: ConfirmViewModel.Warning.Style, _ title: String,
                            _ subtitle: String? = nil) -> ConfirmViewModel.Warning {
    ConfirmViewModel.Warning(id: id, style: style, title: title, subtitle: subtitle)
}

private let delayWarning = previewWarning(
    0, .delay, "This is a withdrawal. It arrives on Core after a delay.")
private let publicWarning = previewWarning(
    1, .publicExposure,
    "Sending from Shielded to an address that is not Shielded makes the amount and the destination public.")
private let processingWarning = previewWarning(
    2, .delay, SendWarningText.processingTimeTitle, SendWarningText.shieldedWithdrawalBody)
private let reserveWarning = previewWarning(0, .caution, SendAmountViewModel.reserveWarningText)

@MainActor
private func previewSheet(
    route: SendRoute = .coreToCore, destination: Destination? = nil, recipient: IdentityRecipient? = nil,
    amount: UInt64 = 150_000_000, state: ConfirmViewModel.State = .ready, fee: UInt64? = 1_000,
    warnings: [ConfirmViewModel.Warning] = [], blocked: Bool = false, balanceUnreadable: Bool = false
) -> some View {
    let target = destination ?? Destination(type: .coreAddress, text: previewAddress)
    let vm = ConfirmViewModel(
        request: SendAmountRequest(route: route, destination: target, amount: amount, isMax: false),
        recipient: recipient, executor: PreviewExecutor(), balances: PreviewBalances(),
        converter: PreviewConverter())
    vm.setPreview(state: state, feeDuffs: fee, warnings: warnings, blocked: blocked,
                  balanceUnreadable: balanceUnreadable)
    return Color.dash.primaryBackground.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) { ConfirmSheetContent(viewModel: vm) }
}

private let identityDestination = Destination(type: .identityID, text: previewIdentityID)

#Preview("Preparing") { previewSheet(state: .preparing, fee: nil) }

#Preview("Ready, exact fee") { previewSheet() }

#Preview("Ready, estimated fee") { previewSheet(route: .platformToCore) }

#Preview("Ready, stacked warnings") {
    previewSheet(route: .shieldedToCore, warnings: [
        delayWarning, publicWarning, processingWarning,
        previewWarning(3, .info, SendWarningText.doubleCheckTitle, SendWarningText.doubleCheckBody)
    ])
}

#Preview("Fee failed") { previewSheet(state: .feeFailed, fee: nil, blocked: true) }

#Preview("Balance unreadable") {
    previewSheet(state: .feeFailed, fee: nil, blocked: true, balanceUnreadable: true)
}

#Preview("Sending") { previewSheet(state: .sending) }

#Preview("Identity, reserve warning") {
    previewSheet(route: .identityToCore, warnings: [delayWarning, reserveWarning])
}

#Preview("Recipient, someone else's identity") {
    previewSheet(
        route: .platformToIdentity, destination: identityDestination,
        recipient: IdentityRecipient(id: previewIdentityID, username: "bob", isOwnCurrentIdentity: false),
        warnings: [previewWarning(
            0, .info, "The money goes to bob's identity balance, not their Dash wallet balance.")])
}

#Preview("Recipient, own identity") {
    previewSheet(
        route: .coreToIdentity, destination: identityDestination,
        recipient: IdentityRecipient(id: previewIdentityID, username: "alice", isOwnCurrentIdentity: true),
        warnings: [previewWarning(0, .info, "This tops up your own Identity credits.")])
}

#Preview("Long text, large Dynamic Type") {
    previewSheet(
        route: .shieldedToCore, amount: 123_456_789_012_345, fee: 12_345_678,
        warnings: [delayWarning, publicWarning, processingWarning]
    )
    .dynamicTypeSize(.accessibility3)
}

#endif
