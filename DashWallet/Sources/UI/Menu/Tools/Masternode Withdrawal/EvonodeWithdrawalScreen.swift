//
//  EvonodeWithdrawalScreen.swift
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
import SwiftDashSDK
import SwiftUI
import UIKit

// MARK: - EvonodeWithdrawalScreen

/// Withdraw (claim) an evonode's Platform credits: amount keypad, the
/// destination — the registered payout address, editable only when this
/// wallet holds the payout key — and a confirmation sheet that runs the
/// claim. Pushed from `MasternodeDetailScreen` inside its `NavigationStack`.
struct EvonodeWithdrawalScreen: View {
    @StateObject private var viewModel: EvonodeWithdrawalViewModel
    @Environment(\.dismiss) private var dismiss

    /// Fired after a successful claim with the identity's remaining
    /// claimable balance, so the detail screen can update without refetching.
    private let onWithdrawn: (UInt64) -> Void
    /// Fired when the claim was submitted but its result could not be
    /// confirmed — the detail screen must re-read the balance (the claim may
    /// have executed) before any further attempt.
    private let onOutcomeUnconfirmed: () -> Void

    @State private var showConfirmation = false
    @State private var showScanner = false

    init(
        masternode: PlatformMasternode,
        keys: MasternodeWithdrawalKeys,
        claimableCredits: UInt64,
        ownerKeyIndexHint: UInt32? = nil,
        onWithdrawn: @escaping (UInt64) -> Void,
        onOutcomeUnconfirmed: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: EvonodeWithdrawalViewModel(
            masternode: masternode,
            keys: keys,
            claimableCredits: claimableCredits,
            ownerKeyIndexHint: ownerKeyIndexHint))
        self.onWithdrawn = onWithdrawn
        self.onOutcomeUnconfirmed = onOutcomeUnconfirmed
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    amountRow
                    availableRow
                    destinationCard
                    howItWorksCard
                    if let message = viewModel.amountValidationMessage {
                        ValidationNote(message: message)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            keyboardSection
        }
        .background(Color.dash.primaryBackground)
        .navigationTitle(NSLocalizedString("Withdraw", comment: "Evonode withdrawal"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showConfirmation) {
            EvonodeWithdrawalConfirmSheet(
                viewModel: viewModel,
                onCancel: { showConfirmation = false },
                onCompleted: { remaining in
                    showConfirmation = false
                    onWithdrawn(remaining)
                    dismiss()
                },
                onUnconfirmedAcknowledged: {
                    showConfirmation = false
                    onOutcomeUnconfirmed()
                    dismiss()
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerRepresentable(
                onScanned: { value in
                    showScanner = false
                    viewModel.setDestination(value)
                },
                onCancel: { showScanner = false })
                .ignoresSafeArea()
        }
    }

    // MARK: Amount

    private var amountRow: some View {
        EnterAmountView(
            primaryAmount: dashAmountText,
            secondaryAmount: fiatAmountText,
            primaryCurrency: .dash,
            secondaryCurrency: .fiat(viewModel.fiatCurrencyCode),
            isPrimarySelected: viewModel.unit == .dash,
            currencyCodes: ["DASH", viewModel.fiatCurrencyCode],
            selectedCurrencyCode: viewModel.unit == .dash ? "DASH" : viewModel.fiatCurrencyCode,
            onMax: { viewModel.fillMax() },
            onSwap: toggleUnit,
            onCurrencyTap: toggleUnit,
            onSelectInputType: { code in
                viewModel.setUnit(code.caseInsensitiveCompare("DASH") == .orderedSame ? .dash : .fiat)
            }
        )
    }

    private var availableRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.system(size: 13))
                .foregroundColor(Color.dash.secondaryText)
            Text(String(
                format: NSLocalizedString("%@ · Claimable %@ DASH", comment: "Evonode withdrawal: node title, balance"),
                viewModel.masternode.displayTitle,
                viewModel.claimableDashFormatted))
                .font(.system(size: 13))
                .foregroundColor(Color.dash.secondaryText)
            Spacer()
        }
    }

    private var dashAmountText: String {
        switch viewModel.unit {
        case .dash:
            return keypadBinding.wrappedValue
        case .fiat:
            guard viewModel.parsedDashAmount > 0 else { return "" }
            return EvonodeWithdrawalViewModel.formatTyped(viewModel.parsedDashAmount, fractionDigits: 8)
        }
    }

    private var fiatAmountText: String {
        switch viewModel.unit {
        case .dash:
            guard viewModel.parsedDashAmount > 0,
                  let fiat = try? CurrencyExchanger.shared.convertDash(
                      amount: viewModel.parsedDashAmount,
                      to: viewModel.fiatCurrencyCode)
            else { return "" }
            return EvonodeWithdrawalViewModel.formatTyped(fiat, fractionDigits: 2)
        case .fiat:
            return keypadBinding.wrappedValue
        }
    }

    private func toggleUnit() {
        viewModel.setUnit(viewModel.unit == .dash ? .fiat : .dash)
    }

    private var keypadBinding: Binding<String> {
        Binding(
            get: { viewModel.amountText == "0" ? "" : viewModel.amountText },
            set: { newValue in
                viewModel.amountText = newValue.isEmpty ? "0" : newValue
            })
    }

    // MARK: Destination

    @ViewBuilder
    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("Withdraw to", comment: "Evonode withdrawal"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.dash.primaryText)

            if viewModel.canChooseDestination {
                AddressFieldView(
                    text: $viewModel.destinationText,
                    label: NSLocalizedString("Dash address", comment: "Evonode withdrawal"),
                    placeholder: NSLocalizedString("Enter a Dash address", comment: "Evonode withdrawal"),
                    hasError: viewModel.destinationErrorMessage != nil,
                    errorText: viewModel.destinationErrorMessage,
                    onScanQR: { showScanner = true },
                    onPaste: { viewModel.pasteDestination() })

                if viewModel.payoutAddress != nil, !viewModel.destinationIsPayoutAddress {
                    Button {
                        viewModel.resetDestinationToPayoutAddress()
                    } label: {
                        Label(
                            NSLocalizedString("Use the payout address", comment: "Evonode withdrawal"),
                            systemImage: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color.dash.blue)
                } else if viewModel.payoutAddress != nil {
                    Label(
                        NSLocalizedString("This is the evonode's registered payout address.", comment: "Evonode withdrawal"),
                        systemImage: "checkmark.circle")
                        .font(.system(size: 13))
                        .foregroundColor(Color.dash.secondaryText)
                }

                Text(NSLocalizedString(
                    "This wallet holds the evonode's payout address key, so the balance can be withdrawn to any Dash address.",
                    comment: "Evonode withdrawal"))
                    .font(.system(size: 13))
                    .foregroundColor(Color.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.dash.secondaryText)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Registered payout address", comment: "Evonode withdrawal"))
                            .font(.system(size: 12))
                            .foregroundColor(Color.dash.secondaryText)
                        Text(viewModel.payoutAddress ?? NSLocalizedString("Not available", comment: ""))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(Color.dash.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.dash.secondaryBackground)
                .cornerRadius(10)

                Text(NSLocalizedString(
                    "This withdrawal is signed with the evonode's owner key. Dash Platform only lets the owner key withdraw to the registered payout address, so the destination can't be changed here. To withdraw to another address, use the wallet that holds the payout address key.",
                    comment: "Evonode withdrawal"))
                    .font(.system(size: 13))
                    .foregroundColor(Color.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.dash.secondaryBackground.opacity(0.6))
        .cornerRadius(12)
    }

    // MARK: How it works

    private var howItWorksCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 30, height: 30)
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("How it works", comment: "Evonode withdrawal"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.primaryText)
                Text(String(
                    format: NSLocalizedString(
                        "Dash Platform pays the withdrawal out on the Dash chain — usually within a few minutes. A Platform fee of about %@ DASH is taken from the evonode's balance on top of the amount, so Max leaves a little behind to cover it.",
                        comment: "Evonode withdrawal"),
                    viewModel.estimatedFeeDashFormatted))
                    .font(.system(size: 13))
                    .foregroundColor(Color.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    // MARK: Keyboard

    private var keyboardSection: some View {
        NumericKeyboardView(
            value: keypadBinding,
            showDecimalSeparator: true,
            actionButtonText: NSLocalizedString("Continue", comment: ""),
            actionEnabled: viewModel.canContinue,
            inProgress: false,
            actionHandler: { showConfirmation = true }
        )
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.dash.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
        .background(Color.dash.secondaryBackground, ignoresSafeAreaEdges: .bottom)
    }
}

// MARK: - ValidationNote

private struct ValidationNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Color.dash.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
    }
}

// MARK: - EvonodeWithdrawalConfirmSheet

/// Review → Confirm → (auth) → submitting → success / failure.
struct EvonodeWithdrawalConfirmSheet: View {
    @ObservedObject var viewModel: EvonodeWithdrawalViewModel
    let onCancel: () -> Void
    let onCompleted: (UInt64) -> Void
    /// Close after an ambiguous outcome — leaves the flow so the balance can
    /// be re-read; no retry is offered from that state.
    let onUnconfirmedAcknowledged: () -> Void

    var body: some View {
        DashUIKit.BottomSheet(
            title: NSLocalizedString("Confirm withdrawal", comment: "Evonode withdrawal"),
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!(isInFlight || isUnconfirmed)),
            onClose: onCancel
        ) {
            switch viewModel.phase {
            case let .success(remaining):
                successBody(remainingCredits: remaining)
            case let .submittedUnconfirmed(detail):
                unconfirmedBody(detail: detail)
            default:
                detailsBody
            }
        }
    }

    private var isUnconfirmed: Bool {
        if case .submittedUnconfirmed = viewModel.phase { return true }
        return false
    }

    private var isInFlight: Bool {
        switch viewModel.phase {
        case .authorizing, .submitting: return true
        default: return false
        }
    }

    private var detailsBody: some View {
        VStack(spacing: 0) {
            DashAmount(
                amount: Int64(clamping: viewModel.amountDuffs),
                font: .largeTitle,
                dashSymbolFactor: 0.7,
                showDirection: false)
                .padding(.top, 14)

            Text(viewModel.fiatAmountString)
                .font(.subheadline)
                .foregroundColor(.dash.secondaryText)
                .padding(.top, 6)

            summaryCard
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if case let .failed(message) = viewModel.phase {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else if !viewModel.canChooseDestination {
                Text(NSLocalizedString(
                    "Owner-key withdrawals are always paid to the registered payout address.",
                    comment: "Evonode withdrawal"))
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            switch viewModel.phase {
            case .idle:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Confirm", comment: ""),
                    positiveButtonAction: { Task { await viewModel.submit() } },
                    negativeButtonText: NSLocalizedString("Cancel", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .failed:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Try again", comment: ""),
                    positiveButtonAction: { viewModel.resetAfterFailure() },
                    negativeButtonText: NSLocalizedString("Close", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .authorizing, .submitting:
                HStack(spacing: 10) {
                    SwiftUI.ProgressView()
                    Text(viewModel.phase == .authorizing
                        ? NSLocalizedString("Waiting for authorization…", comment: "Evonode withdrawal")
                        : NSLocalizedString("Submitting to Dash Platform…", comment: "Evonode withdrawal"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.secondaryText)
                }
                .padding(.bottom, 28)

            case .success, .submittedUnconfirmed:
                EmptyView()
            }
        }
    }

    /// Ambiguous outcome: broadcast accepted, result unconfirmed. The claim
    /// may have gone through and the identity nonce was consumed, so no
    /// "Try again" here — only Close, which makes the detail screen re-read
    /// the balance.
    private func unconfirmedBody(detail: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.exclamationmark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.orange)
                .padding(.top, 24)

            Text(NSLocalizedString("Result not confirmed", comment: "Evonode withdrawal"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)

            Text(NSLocalizedString(
                "The withdrawal was sent to Dash Platform, but its result couldn't be confirmed. It may have gone through. Don't submit it again — check the claimable balance and the payout address first.",
                comment: "Evonode withdrawal"))
                .font(.system(size: 13))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(.dash.tertiaryText)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 24)

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Close", comment: ""),
                style: .filled,
                stretch: true,
                action: onUnconfirmedAcknowledged)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private func successBody(remainingCredits: UInt64) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.green)
                .padding(.top, 24)

            Text(NSLocalizedString("Withdrawal submitted", comment: "Evonode withdrawal"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)

            DashAmount(
                amount: Int64(clamping: viewModel.amountDuffs),
                font: .title,
                dashSymbolFactor: 0.7,
                showDirection: false)

            Text(NSLocalizedString(
                "Dash Platform will pay it out on the Dash chain shortly — it usually arrives within a few minutes.",
                comment: "Evonode withdrawal"))
                .font(.system(size: 13))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(String(
                format: NSLocalizedString("Remaining claimable balance: %@ DASH", comment: "Evonode withdrawal"),
                (remainingCredits / EvonodeWithdrawalViewModel.creditsPerDuff).formattedDashAmountWithoutCurrencySymbol))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.dash.primaryText)

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Done", comment: ""),
                style: .filled,
                stretch: true,
                action: { onCompleted(remainingCredits) })
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(
                label: NSLocalizedString("From", comment: ""),
                value: String(
                    format: NSLocalizedString("%@ · Platform balance", comment: "Evonode withdrawal"),
                    viewModel.masternode.displayTitle))
            divider
            summaryRow(
                label: NSLocalizedString("To", comment: ""),
                value: destinationValue,
                monospaced: true)
            divider
            summaryRow(
                label: NSLocalizedString("Signed with", comment: "Evonode withdrawal"),
                value: viewModel.signingKeyLabel)
            divider
            summaryRow(
                label: NSLocalizedString("Platform fee", comment: "Evonode withdrawal"),
                value: "≈ " + viewModel.estimatedFeeDashFormatted + " DASH")
        }
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var destinationValue: String {
        if viewModel.canChooseDestination {
            let address = viewModel.destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
            return viewModel.destinationIsPayoutAddress
                ? String(format: NSLocalizedString("%@ (payout address)", comment: "Evonode withdrawal"), address)
                : address
        }
        return viewModel.payoutAddress
            ?? NSLocalizedString("Registered payout address", comment: "Evonode withdrawal")
    }

    private func summaryRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
            Spacer(minLength: 16)
            Text(value)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 14, weight: .medium))
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.dash.gray300.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
}

// MARK: - QRScannerRepresentable

/// SwiftUI wrapper for the UIKit `GenericQRScannerController`. Internal: the
/// add-masternode locator field reuses it.
struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> GenericQRScannerController {
        let scanner = GenericQRScannerController()
        scanner.onQRCodeScanned = onScanned
        scanner.onCancel = onCancel
        return scanner
    }

    func updateUIViewController(_ uiViewController: GenericQRScannerController, context: Context) {
        uiViewController.onQRCodeScanned = onScanned
        uiViewController.onCancel = onCancel
    }
}
