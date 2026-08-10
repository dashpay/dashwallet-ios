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

/// The final step: the address and source are settled and shown read-only,
/// leaving the amount keypad and the balance/affordability validation.
///
/// Every route, Transparent → Transparent included, confirms in
/// `SendConfirmSheet` — Core → Core prepares (auth + build/sign, showing the
/// real fee) and broadcasts through `WalletSendService` there instead of
/// `ShieldedTransferCoordinator`.
struct ExternalSendAmountScreen: View {
    @ObservedObject var viewModel: SendViewModel
    /// Pop back to the source step.
    var onBack: () -> Void
    /// A route finished successfully (confirm sheet's Done).
    var onSendCompleted: () -> Void

    @State private var showConfirm = false
    /// Core route: built and signed here, before the sheet is presented. The
    /// auth gate inside it puts up the PIN, and UIKit refuses to present that
    /// over a sheet that is still animating in — doing it from the sheet's own
    /// `.task` failed the send on the first attempt every time.
    @StateObject private var coreSend = CoreSendConfirmController()
    @State private var isPreparingCoreSend = false

    var body: some View {
        VStack(spacing: 0) {
            // DashUIKit's bar carries its own height and horizontal
            // insets, so the manual padding the hand-rolled header needed
            // goes with it.
            DashUIKit.NavigationBar(leading: {
                NavigationBarElement.back.button { onBack() }
            })

            VStack(spacing: 20) {
                SendAddressSummary(viewModel: viewModel, showsSource: true)

                amountRow

                // A signature that could not be produced (offline, chain not
                // synced) keeps the user here — say why, or Continue would
                // just look broken.
                if let message = coreSend.failureMessage {
                    TransferAmountValidationNote(message: message)
                        .padding(.horizontal, 20)
                } else if let message = viewModel.amountValidationMessage {
                    TransferAmountValidationNote(message: message)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Spacer()

            keyboardSection
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .sheet(isPresented: $showConfirm) {
            if let route = viewModel.route {
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
                    coreSend: coreSend,
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
            inProgress: isPreparingCoreSend,
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
        guard route == .coreToCore else {
            showConfirm = true
            return
        }
        // Sign first, then present: the sheet opens already knowing the real
        // fee, and the PIN goes up over this screen rather than over a sheet
        // in mid-presentation. Same order the legacy payment processor uses.
        Task {
            isPreparingCoreSend = true
            defer { isPreparingCoreSend = false }
            await coreSend.prepare(
                address: viewModel.trimmedAddress,
                amountDuffs: viewModel.dashDuffsUnsigned)
            // A refused or cancelled signature keeps the user here with the
            // reason, rather than opening a confirm sheet that has nothing to
            // confirm.
            guard coreSend.isReady else { return }
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

#if DEBUG

#Preview("Amount") {
    ExternalSendAmountScreen(
        viewModel: .preview(address: "yV1D1ivvSUyKPJnbFmzSTVh1MyZ3JbeVkY", destination: .core),
        onBack: {}, onSendCompleted: {})
        .background(Color.dash.primaryBackground)
}

/// Shielded source: confirms in `SendConfirmSheet`, same as every other route.
#Preview("From Shielded") {
    ExternalSendAmountScreen(
        viewModel: .preview(
            address: "yV1D1ivvSUyKPJnbFmzSTVh1MyZ3JbeVkY",
            destination: .core,
            source: .shielded),
        onBack: {}, onSendCompleted: {})
        .background(Color.dash.primaryBackground)
}

#endif
