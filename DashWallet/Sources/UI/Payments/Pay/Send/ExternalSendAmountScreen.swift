//
//  ExternalSendAmountScreen.swift
//  DashWallet
//
//  Step three: the amount keypad, and the route it commits to.
//

import SwiftUI
import DashUIKit
import SwiftDashSDK
import UIKit

// MARK: - Step 3: amount

/// The final step of the split external-send flow: the address and source are
/// already chosen (both shown read-only), leaving only the amount keypad and
/// the balance/affordability validation. Continue routes exactly as the old
/// single-screen form did — Core → Core into the L1 payment processor,
/// everything else into `SendConfirmSheet`.
struct ExternalSendAmountScreen: View {
    @ObservedObject var viewModel: SendViewModel
    /// Pop back to the source step.
    var onBack: () -> Void
    /// Core → Core: hand (address, amount in duffs) to the hosting
    /// controller, which routes through the L1 payment processor.
    var onContinueCore: (String, UInt64) -> Void
    /// A non-core route finished successfully (confirm sheet's Done).
    var onSendCompleted: () -> Void

    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            SendStepHeader(onBack: onBack)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            ScrollView {
                VStack(spacing: 14) {
                    SendAddressSummary(viewModel: viewModel, onEdit: onBack)
                        .padding(.top, 12)

                    fromSummary

                    amountRow
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                    if let message = viewModel.amountValidationMessage {
                        TransferAmountValidationNote(message: message)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            keyboardSection
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .sheet(isPresented: $showConfirm) {
            if let route = viewModel.route, route != .coreToCore {
                SendConfirmSheet(
                    route: route,
                    destinationAddress: viewModel.trimmedAddress,
                    destinationRaw43: shieldedRecipientRaw43,
                    dashDuffs: viewModel.dashDuffs,
                    creditsAmount: viewModel.creditsPreview,
                    fiatText: viewModel.fiatAmountString,
                    withdrawalFeeCredits: viewModel.withdrawalPreflight?.estimatedFee,
                    isFullPlatformWithdrawal: viewModel.isFullPlatformWithdrawal,
                    isFullShieldedSweep: viewModel.isFullShieldedSweep,
                    onCancel: { showConfirm = false },
                    onCompleted: {
                        showConfirm = false
                        onSendCompleted()
                    })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    private var shieldedRecipientRaw43: Data? {
        if case .shielded(let raw43) = viewModel.destination { return raw43 }
        return nil
    }

    // MARK: - Amount

    private var amountRow: some View {
        EnterAmountView(
            primaryAmount: dashAmountText,
            secondaryAmount: fiatAmountText,
            primaryCurrency: .dash,
            secondaryCurrency: .fiat(viewModel.fiatCurrencyCode),
            isPrimarySelected: isDashInputSelected,
            currencyCodes: amountCurrencyCodes,
            selectedCurrencyCode: selectedAmountCurrencyCode,
            onMax: { viewModel.fillMaxFromWallet() },
            onSwap: toggleAmountUnit,
            onCurrencyTap: toggleAmountUnit,
            onSelectInputType: selectAmountCurrency
        )
    }

    // MARK: - Keyboard

    private var keyboardSection: some View {
        NumericKeyboardView(
            value: keypadBinding,
            showDecimalSeparator: true,
            actionButtonText: NSLocalizedString("Continue", comment: ""),
            actionEnabled: viewModel.canContinue,
            inProgress: false,
            actionHandler: continueAction
        )
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.dash.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
        .background(Color.dash.secondaryBackground, ignoresSafeAreaEdges: .bottom)
    }

    private func continueAction() {
        guard let route = viewModel.route else { return }
        if route == .coreToCore {
            onContinueCore(viewModel.trimmedAddress, viewModel.dashDuffsUnsigned)
        } else {
            showConfirm = true
        }
    }

    /// The source picked on the previous step, read-only. Tapping goes back.
    private var fromSummary: some View {
        Button(action: onBack) {
            HStack(spacing: 10) {
                Image(systemName: sourceIconName(viewModel.source))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.dashBlue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("From", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(sourceTitle(viewModel.source))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.secondaryBackground)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Amount helpers

    private var isDashInputSelected: Bool {
        viewModel.unit == .dash
    }

    private var dashAmountText: String {
        switch viewModel.unit {
        case .dash:
            return keypadBinding.wrappedValue
        case .fiat:
            guard viewModel.parsedDashAmount > 0 else { return "" }
            return InternalTransferViewModel.formatTyped(
                viewModel.parsedDashAmount,
                fractionDigits: 8)
        }
    }

    private var fiatAmountText: String {
        switch viewModel.unit {
        case .dash:
            guard viewModel.parsedDashAmount > 0,
                  let fiatAmount = try? CurrencyExchanger.shared.convertDash(
                    amount: viewModel.parsedDashAmount,
                    to: viewModel.fiatCurrencyCode)
            else { return "" }
            return InternalTransferViewModel.formatTyped(
                fiatAmount,
                fractionDigits: 2)
        case .fiat:
            return keypadBinding.wrappedValue
        }
    }

    private var amountCurrencyCodes: [String] {
        ["DASH", viewModel.fiatCurrencyCode]
    }

    private var selectedAmountCurrencyCode: String {
        isDashInputSelected ? "DASH" : viewModel.fiatCurrencyCode
    }

    private func toggleAmountUnit() {
        viewModel.unit = isDashInputSelected ? .fiat : .dash
    }

    private func selectAmountCurrency(_ currencyCode: String) {
        viewModel.unit =
            currencyCode.caseInsensitiveCompare("DASH") == .orderedSame
            ? .dash
            : .fiat
    }

    private var keypadBinding: Binding<String> {
        Binding(
            get: { viewModel.amountText == "0" ? "" : viewModel.amountText },
            set: { newValue in
                if newValue.isEmpty {
                    viewModel.amountText = "0"
                } else {
                    viewModel.amountText = newValue
                }
            })
    }
}
