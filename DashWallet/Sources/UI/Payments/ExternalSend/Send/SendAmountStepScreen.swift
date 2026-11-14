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

import Combine
import DashUIKit
import SwiftUI

/// SCR-04 Send. Draws the ViewModel's state; opening Select source and going back are the flow's callbacks,
/// and Continue reports through the ViewModel's `onContinue`.
struct SendAmountScreen: View {
    @ObservedObject var viewModel: SendAmountViewModel

    var onBack: () -> Void
    var onSelectSource: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: { DashUIKit.NavigationBarElement.back.button(action: onBack) })

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DashUIKit.TopIntroView(title: NSLocalizedString("Send", comment: "External send"))
                    amountField
                    endpoints
                    notices
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(Color.dash.primaryBackground)
        .task { await viewModel.load() }
    }

    // MARK: - From and To

    private var endpoints: some View {
        DashUIKit.ConverterCard(
            fromItem: DashUIKit.ConverterCardItem(
                id: "from",
                icon: viewModel.source.icon,
                title: viewModel.sourceTitle,
                dashBalance: Int64(viewModel.sourceBalanceDuffs ?? 0),
                fiat: viewModel.sourceBalanceFiatText,
                trailingView: viewModel.sourceBalanceDuffs == nil ? AnyView(Text("—")) : nil,
                onTap: onSelectSource),
            toItem: DashUIKit.ConverterCardItem(
                id: "to",
                icon: viewModel.destinationIcon,
                title: viewModel.recipientName ?? viewModel.destinationLabel ?? viewModel.destinationTypeText,
                trailingView: AnyView(Text(viewModel.shortAddress)
                    .dashFont(.subhead)
                    .foregroundStyle(Color.dash.primaryText)),
                showsBalance: false),
            // No swap here: the card draws its static arrow, hidden from VoiceOver.
            onSwap: nil)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("send_source_and_destination")
    }

    // MARK: - Amount

    private var amountField: some View {
        DashUIKit.EnterAmountView(
            primaryAmount: viewModel.dashAmountDisplay,
            secondaryAmount: viewModel.fiatAmountDisplay,
            primaryCurrency: .dash,
            secondaryCurrency: .fiat(viewModel.fiatCurrencyCode),
            isPrimarySelected: viewModel.unit == .dash,
            isCurrencySelectorHidden: true,
            currencyCodes: showsUnitPicker ? ["DASH", viewModel.fiatCurrencyCode] : nil,
            selectedCurrencyCode: viewModel.unit == .dash ? "DASH" : viewModel.fiatCurrencyCode,
            // Max stays in place while it is disabled; `tapMax` does nothing then. DashUIKit has no disabled Max.
            onMax: viewModel.isMaxVisible ? { Task { await viewModel.tapMax() } } : nil,
            onSwap: showsUnitPicker ? toggleUnit : nil,
            onSelectInputType: showsUnitPicker ? { viewModel.setUnit($0 == "DASH" ? .dash : .fiat) } : nil,
            errorMessage: viewModel.amountErrorMessage)
            .accessibilityIdentifier("send_amount_field")
    }

    private var showsUnitPicker: Bool {
        viewModel.isFiatAvailable && !viewModel.isAmountLocked
    }

    private func toggleUnit() {
        viewModel.setUnit(viewModel.unit == .dash ? .fiat : .dash)
    }

    // MARK: - Notices

    private func infoMessage(_ text: String) -> some View {
        DashUIKit.SystemMessageView(
            title: text,
            icon: DashIcon.SystemMessage.infoRectSmall.source,
            backgroundColor: Color.dash.blueAlpha5)
    }

    @ViewBuilder private var notices: some View {
        if let text = viewModel.destinationNote { infoMessage(text) }
        if let text = viewModel.sourceChangedNotice { infoMessage(text) }
        if let text = viewModel.recipientNotice { infoMessage(text) }
        if let text = viewModel.reserveNote { infoMessage(text) }
        if let text = viewModel.reserveWarning {
            DashUIKit.SystemMessageView(title: text, backgroundColor: Color.dash.orangeAlpha10)
        }
        if viewModel.isBlockedBySync { SyncGateNote() }
        if let message = viewModel.feeFailureMessage {
            DashUIKit.SystemMessageView(
                title: message,
                backgroundColor: Color.dash.redAlpha5,
                buttonName: NSLocalizedString("Try again", comment: "External send"),
                onAction: { Task { await viewModel.retryFee() } })
        }
        if let caption = viewModel.lockedCaption {
            Text(caption)
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.secondaryText)
        }
    }

    // MARK: - Continue

    /// The keypad carries Continue; a payment request has no keypad, so Continue stands alone.
    @ViewBuilder private var footer: some View {
        if viewModel.isKeypadVisible {
            DashUIKit.NumericKeyboardView(
                value: Binding(get: { viewModel.amountText },
                               set: { text in Task { await viewModel.keypadInput(text) } }),
                showDecimalSeparator: true,
                actionButtonText: NSLocalizedString("Continue", comment: "External send"),
                actionEnabled: viewModel.isContinueEnabled,
                inProgress: viewModel.isContinueLoading,
                actionHandler: { Task { await viewModel.proceed() } })
                .accessibilityIdentifier("send_amount_keypad")
        } else {
            DashUIKit.DashButton(
                text: NSLocalizedString("Continue", comment: "External send"),
                isEnabled: viewModel.isContinueEnabled,
                isLoading: viewModel.isContinueLoading,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: { Task { await viewModel.proceed() } })
                .accessibilityIdentifier("send_amount_continue")
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
    }
}

#if DEBUG

private let previewAddress = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN"
private let previewIdentityID = "4EfA9Jrvv7vTuTWfQsoCgQ9nQJi1JkZDzrmAu5AY4DpZ"

private struct PreviewBalances: ExternalSendBalanceReading {
    func spendableBalance(of source: SendSource) async -> UInt64? { nil }
}

private struct PreviewIdentity: CurrentIdentityReading {
    func currentIdentity() async -> SelectSourceIdentity? { nil }
}

private struct PreviewEstimator: SendFeeEstimating {
    func estimate(route: SendRoute, amount: UInt64) async -> SendFeeEstimate { .unavailable }
}

private struct PreviewPlanner: SendMaxPlanning {
    func maxPlan(route: SendRoute) async -> SendMaxPlan? { nil }
    func canFund(route: SendRoute, amount: UInt64) async -> SendFundingCheck { .notChecked }
}

/// 1 DASH = 50 units of the local currency.
private struct PreviewConverter: SendAmountConverting {
    func fiat(forDuffs duffs: UInt64) -> Decimal? { Decimal(duffs) / 100_000_000 * 50 }
    func duffs(forFiat fiat: Decimal) -> UInt64? { nil }
    func fiatText(forDuffs duffs: UInt64) -> String? { "$\(fiat(forDuffs: duffs) ?? 0)" }
}

/// The screen without `load()`, which would overwrite the fixed preview state.
private struct PreviewHost: View {
    @ObservedObject var viewModel: SendAmountViewModel

    var body: some View {
        SendAmountScreen(viewModel: viewModel, onBack: {}, onSelectSource: {})
    }
}

@MainActor
private func previewScreen(
    _ destination: Destination = Destination(type: .coreAddress, text: previewAddress),
    source: SendSource = .core, balance: UInt64? = 300_000_000, unit: InternalTransferUnit = .dash,
    text: String = "", duffs: UInt64 = 0, fee: UInt64? = 1_000, isMax: Bool = false,
    estimating: Bool = false, failed: Bool = false, recipient: IdentityRecipient? = nil,
    changedNotice: String? = nil, restoreSyncRunning: Bool = false, ownIdentityID: String? = nil
) -> some View {
    let vm = SendAmountViewModel(destination: destination, pinnedSource: nil, recipient: recipient,
                                 balances: PreviewBalances(),
                                 feeEstimator: PreviewEstimator(), maxPlanner: PreviewPlanner(),
                                 converter: PreviewConverter(), currentIdentity: PreviewIdentity(),
                                 initialRestoreSync: Just(false).eraseToAnyPublisher())
    vm.setPreview(source: source, balanceDuffs: balance, unit: unit, amountText: text, amountDuffs: duffs,
                  fee: fee, isMax: isMax, isEstimating: estimating, estimateFailed: failed,
                  sourceChangedNotice: changedNotice, initialRestoreSyncRunning: restoreSyncRunning,
                  ownIdentityID: ownIdentityID)
    return PreviewHost(viewModel: vm)
}

#Preview("Amount empty") { previewScreen() }

#Preview("Ready") { previewScreen(text: "1.5", duffs: 150_000_000) }

#Preview("Estimating") { previewScreen(text: "1.5", duffs: 150_000_000, estimating: true) }

#Preview("Fee failed") { previewScreen(text: "1.5", duffs: 150_000_000, fee: nil, failed: true) }

#Preview("Not enough") { previewScreen(text: "5", duffs: 500_000_000) }

#Preview("Initial restore sync") { previewScreen(text: "1.5", duffs: 150_000_000, restoreSyncRunning: true) }

#Preview("No source funds") {
    previewScreen(Destination(type: .identityID, text: previewIdentityID), source: .shielded, balance: 0)
}

#Preview("Fiat unit") { previewScreen(unit: .fiat, text: "75", duffs: 150_000_000) }

#Preview("Max") { previewScreen(text: "2.99999", duffs: 299_999_000, isMax: true) }

#Preview("Locked payment request") {
    previewScreen(Destination(type: .paymentRequest, text: "", amountDuffs: 100_000_000,
                              paymentRequestURL: URL(string: "https://merchant.example/pay/1")),
                  text: "1", duffs: 100_000_000)
}

#Preview("Verified merchant with memo") {
    previewScreen(Destination(type: .coreAddress, text: previewAddress, amountDuffs: 100_000_000, label: "Merchant",
                              message: "Order 7", paymentRequestURL: URL(string: "https://merchant.example/pay/1"),
                              isVerifiedMerchant: true),
                  text: "1", duffs: 100_000_000)
}

#Preview("Labelled link with message") {
    previewScreen(Destination(type: .coreAddress, text: previewAddress, label: "Coffee Shop", message: "Table 4"),
                  text: "0.1", duffs: 10_000_000)
}

#Preview("Long label and message") {
    previewScreen(Destination(type: .coreAddress, text: previewAddress,
                              label: "A merchant with a very long trading name that will not fit on one line",
                              message: "Order 123456 · two coffees, one croissant, delivery to the third floor"),
                  text: "0.1", duffs: 10_000_000)
}

/// Credits of an identity in the previews.
private let previewCredits: UInt64 = 5_000_000_000

#Preview("Identity source") {
    previewScreen(source: .identity, balance: AmountRules.dashValue(of: previewCredits), fee: 1_000_000)
}

#Preview("Identity source, Max") {
    previewScreen(source: .identity, balance: AmountRules.dashValue(of: previewCredits), text: "0.03999",
                  duffs: 3_999_000, fee: 1_000_000, isMax: true)
}

#Preview("Identity, reserve spent, Max off") {
    previewScreen(source: .identity, balance: AmountRules.dashValue(of: IdentityCreditBalance.lowBalance),
                  fee: 1_000_000)
}

#Preview("Identity, reserve warning") {
    previewScreen(source: .identity, balance: AmountRules.dashValue(of: previewCredits), text: "0.0399",
                  duffs: 3_990_000, fee: 1_000_000)
}

private let previewOwnRecipient = IdentityRecipient(id: previewIdentityID, username: "alice",
                                                    isOwnCurrentIdentity: true)

#Preview("Recipient, own identity") {
    previewScreen(Destination(type: .identityID, text: previewIdentityID), recipient: previewOwnRecipient)
}

#Preview("Own identity from Core, below the top-up minimum") {
    previewScreen(Destination(type: .identityID, text: previewIdentityID), text: "0.0005", duffs: 50_000,
                  recipient: previewOwnRecipient, ownIdentityID: previewIdentityID)
}

#Preview("Recipient with username") {
    previewScreen(Destination(type: .identityID, text: previewIdentityID),
                  recipient: IdentityRecipient(id: previewIdentityID, username: "bob", isOwnCurrentIdentity: false))
}

#Preview("Recipient without username") {
    previewScreen(Destination(type: .identityID, text: previewIdentityID),
                  recipient: IdentityRecipient(id: previewIdentityID, username: nil, isOwnCurrentIdentity: false))
}

#Preview("Source changed notice") {
    previewScreen(Destination(type: .identityID, text: previewIdentityID), source: .shielded,
                  recipient: IdentityRecipient(id: previewIdentityID, username: "bob", isOwnCurrentIdentity: false),
                  changedNotice: "Core can't pay someone else's identity, so the source was changed to Shielded.")
}

#Preview("Long text, large Dynamic Type") {
    previewScreen(Destination(type: .platformAddress,
                              text: "dash1kxqyzzjn8cl0sgr5vmw4pe3tq7h2fuaxd9yc6gs0lnrzv5w8j4ek3m2pt7qhxy9"),
                  source: .platform, balance: 123_456_789_012_345, text: "1234.56789", duffs: 123_456_789_000)
        .dynamicTypeSize(.accessibility3)
}

#endif
