//
//  InternalTransferScreen.swift
//  DashWallet
//

import SwiftUI
import DashUIKit

/// Immutable values the user saw when tapping Continue. Async balance/preflight
/// refreshes may keep updating the form underneath the sheet, but they must not
/// rewrite the amount already presented for confirmation.
private struct InternalTransferConfirmation: Identifiable {
    let id = UUID()
    let route: InternalTransferRoute
    let dashDuffs: Int64
    let amountDuffsUnsigned: UInt64
    let creditsAmount: UInt64
    let fiatText: String
    let withdrawalFeeCredits: UInt64?
    let isFullPlatformWithdrawal: Bool
    let isFullShieldedSweep: Bool
    let platformShieldAmountWasMax: Bool
}

struct InternalTransferScreen: View {
    @ObservedObject var viewModel: InternalTransferViewModel

    /// Invoked when the user finishes a successful transfer via the
    /// confirm sheet's `Done` button. The hosting controller wires it
    /// to `navigationController?.popViewController`.
    var onCompleted: () -> Void = {}

    /// False when embedded under a host that renders its own title
    /// (the balance-row receive sheet) — hides the built-in header.
    var showsHeader: Bool = true

    /// Draws the design system's navigation bar with a back button above the
    /// title. `nil` for the embedded variants, which sit under the host's own
    /// chrome. The host hides the UIKit bar and passes the pop through here,
    /// so the back button is `DashUIKit`'s rather than the system's.
    var onBack: (() -> Void)? = nil

    /// Receive-sheet variant: fixes the destination card (the balance being
    /// received into) at the bottom, turns the rows above it into the
    /// source picker, and hides the swap badge. `nil` = the standard
    /// swappable transfer screen.
    var receiveInto: ChainNetwork? = nil

    /// Send-sheet variant (the balance-row out arrows): fixes the source
    /// card (the balance being sent from) at the top, turns the rows below
    /// it into the destination picker, and hides the swap badge. Takes
    /// precedence over `receiveInto`.
    var sendFrom: ChainNetwork? = nil

    @State private var confirmation: InternalTransferConfirmation?

    var body: some View {
        VStack(spacing: 0) {
            if let onBack {
                DashUIKit.NavigationBar(
                    leading: { DashUIKit.NavigationBarElement.back.button(action: onBack) })
            }

            if showsHeader {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, onBack == nil ? 10 : 0)
            }

            // Scrollable so the keypad and action button stay fully on
            // screen when vertical space is tight — embedded in the
            // balance-row receive sheet the host's header + hero selector
            // eat ~110pt the standalone layout has to spare. When the
            // content fits (standalone), this behaves like the old
            // fixed layout: top-aligned content, keypad pinned below.
            ScrollView {
                VStack(spacing: 16) {
                    amountRow
                        .padding(.horizontal, 20)
                        .padding(.top, showsHeader ? 12 : 0)

                    TransferEndpointCards(
                        viewModel: viewModel,
                        sendFrom: sendFrom,
                        receiveInto: receiveInto)
                        .padding(.horizontal, 20)

                    if viewModel.canContinue {
                        TransferPreview(amountFormatted: viewModel.dashAmountFormatted)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            keyboardSection
        }
        .background(Color.dash.primaryBackground)
        // Over the keypad rather than inline above it: the gate is about the
        // whole screen being unusable, not about the amount that was typed.
        .conditionToast(
            isVisible: viewModel.isBlockedBySync,
            style: .loading,
            message: NSLocalizedString(
                "Wait until the chain is fully synced to make transfers",
                comment: "Transfer blocked during a restored wallet's initial sync"))
        .sheet(item: $confirmation) { submission in
            InternalTransferConfirmSheet(
                route: submission.route,
                dashDuffs: submission.dashDuffs,
                amountDuffsUnsigned: submission.amountDuffsUnsigned,
                creditsAmount: submission.creditsAmount,
                fiatText: submission.fiatText,
                withdrawalFeeCredits: submission.withdrawalFeeCredits,
                isFullPlatformWithdrawal: submission.isFullPlatformWithdrawal,
                isFullShieldedSweep: submission.isFullShieldedSweep,
                platformShieldAmountWasMax: submission.platformShieldAmountWasMax,
                onCancel: { confirmation = nil },
                onCompleted: {
                    confirmation = nil
                    onCompleted()
                },
                onPlatformShieldCapacityChanged: { maxCredits, amountWasMax in
                    confirmation = nil
                    viewModel.handlePlatformShieldCapacityChanged(
                        maxShieldableCredits: maxCredits,
                        submittedAmountWasMax: amountWasMax)
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - Header

    private var header: some View {
        Text(NSLocalizedString("Internal transfer", comment: ""))
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(.dash.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Amount row

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
            onSelectInputType: selectAmountCurrency,
            errorMessage: viewModel.amountValidationMessage
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
            actionHandler: presentConfirmation
        )
    }

    private func presentConfirmation() {
        guard viewModel.canContinue else { return }
        confirmation = InternalTransferConfirmation(
            route: viewModel.route,
            dashDuffs: viewModel.dashDuffs,
            amountDuffsUnsigned: viewModel.dashDuffsUnsigned,
            creditsAmount: viewModel.creditsPreview,
            fiatText: viewModel.fiatAmountString,
            withdrawalFeeCredits: viewModel.withdrawalPreflight?.estimatedFee,
            isFullPlatformWithdrawal: viewModel.isFullPlatformWithdrawal,
            isFullShieldedSweep: viewModel.isFullShieldedSweep,
            platformShieldAmountWasMax: viewModel.platformShieldAmountWasMax)
    }

    // MARK: - From / To cards































    // MARK: - Helpers

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
        viewModel.unit = currencyCode.caseInsensitiveCompare("DASH") == .orderedSame ? .dash : .fiat
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

/// Previews run without a wallet, so anything the SDK has to price is
/// unavailable: the pool-fee routes (`.coreToShielded`) and the shielded
/// reverse routes render their "fee unavailable" validation note instead of an
/// enabled Continue. `.core → .platform` needs no estimate, so that pair is the
/// default here and the one to use when previewing an enabled action button.
@MainActor
private func transferScreenSample(
    source: ChainNetwork = .core,
    target: ChainNetwork = .platform,
    amountText: String = "0",
    sendFrom: ChainNetwork? = nil,
    receiveInto: ChainNetwork? = nil,
    showsHeader: Bool = true,
    isChainSynced: Bool = true,
    isResyncingWallet: Bool = false
) -> some View {
    InternalTransferScreen(
        viewModel: .makeForPreview(
            source: source,
            target: target,
            sendFrom: sendFrom,
            receiveInto: receiveInto,
            amountText: amountText,
            isChainSynced: isChainSynced,
            isResyncingWallet: isResyncingWallet),
        showsHeader: showsHeader,
        receiveInto: receiveInto,
        sendFrom: sendFrom)
}

@available(iOS 17, *)
#Preview("Standalone · empty") {
    transferScreenSample()
}

/// Amount entered and affordable: the "You will transfer" line appears and
/// Continue is enabled.
@available(iOS 17, *)
#Preview("Standalone · valid amount") {
    transferScreenSample(amountText: "0.5")
}

/// Above the 2.45 DASH preview balance — the inline insufficient-balance note
/// replaces the transfer preview and Continue stays disabled.
@available(iOS 17, *)
#Preview("Standalone · over balance") {
    transferScreenSample(amountText: "9.5")
}

/// The gate needs BOTH halves — the restore marker and an unfinished sync.
/// With only one it never appears, which is what this preview used to show.
@available(iOS 17, *)
#Preview("Sync gate") {
    transferScreenSample(
        amountText: "0.5",
        isChainSynced: false,
        isResyncingWallet: true)
}

/// Same unfinished sync, but the wallet was not restored — nothing is blocked,
/// and Continue stays live.
@available(iOS 17, *)
#Preview("Syncing · not restored") {
    transferScreenSample(amountText: "0.5", isChainSynced: false)
}

/// The gate covers the Core-funded routes only: a shielded source transfers
/// during the same sync.
@available(iOS 17, *)
#Preview("Sync gate · shielded source") {
    transferScreenSample(
        source: .shielded,
        target: .core,
        amountText: "0.1",
        isChainSynced: false,
        isResyncingWallet: true)
}

/// Send-sheet embedding: source pinned, host draws its own title.
@available(iOS 17, *)
#Preview("Send sheet · no header") {
    transferScreenSample(
        source: .core,
        amountText: "0.5",
        sendFrom: .core,
        showsHeader: false)
}

/// Receive-sheet embedding: destination pinned at the bottom.
@available(iOS 17, *)
#Preview("Receive sheet · no header") {
    transferScreenSample(
        source: .core,
        target: .platform,
        amountText: "0.5",
        receiveInto: .platform,
        showsHeader: false)
}

@available(iOS 17, *)
#Preview("Dark") {
    transferScreenSample(amountText: "0.5")
        .preferredColorScheme(.dark)
}

/// The form scrolls above the pinned keypad — at accessibility sizes the
/// action button must stay reachable rather than being pushed off screen.
@available(iOS 17, *)
#Preview("Large type") {
    transferScreenSample(amountText: "0.5")
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif




