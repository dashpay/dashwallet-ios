//
//  InternalTransferScreen.swift
//  DashWallet
//

import SwiftUI
import DashUIKit

struct InternalTransferScreen: View {
    @ObservedObject var viewModel: InternalTransferViewModel

    /// Invoked when the user finishes a successful transfer via the
    /// confirm sheet's `Done` button. The hosting controller wires it
    /// to `navigationController?.popViewController`.
    var onCompleted: () -> Void = {}

    /// False when embedded under a host that renders its own title
    /// (the balance-row receive sheet) — hides the built-in header.
    var showsHeader: Bool = true

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

    @State private var showConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
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

                    directionCards
                        .padding(.horizontal, 20)

                    if viewModel.isBlockedBySync {
                        SyncGateNote()
                            .padding(.horizontal, 20)
                    }

                    if let message = viewModel.amountValidationMessage {
                        TransferAmountValidationNote(message: message)
                            .padding(.horizontal, 20)
                    }

                    if viewModel.canContinue {
                        transferPreview
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            keyboardSection
        }
        .background(Color.dash.primaryBackground)
        .sheet(isPresented: $showConfirm) {
            InternalTransferConfirmSheet(
                route: viewModel.route,
                dashDuffs: viewModel.dashDuffs,
                amountDuffsUnsigned: viewModel.dashDuffsUnsigned,
                creditsAmount: viewModel.creditsPreview,
                fiatText: viewModel.fiatAmountString,
                withdrawalFeeCredits: viewModel.withdrawalPreflight?.estimatedFee,
                isFullPlatformWithdrawal: viewModel.isFullPlatformWithdrawal,
                onCancel: { showConfirm = false },
                onCompleted: {
                    showConfirm = false
                    onCompleted()
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
            actionHandler: { showConfirm = true }
        )
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.dash.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
        .background(Color.dash.secondaryBackground, ignoresSafeAreaEdges: .bottom)
    }

    // MARK: - From / To cards

    @ViewBuilder
    private var directionCards: some View {
        if let source = sendFrom {
            sendCards(source: source)
        } else if let target = receiveInto {
            receiveCards(target: target)
        } else {
            swappableCards
        }
    }

    /// Send-sheet layout: the source stays pinned as the top card; the rows
    /// below pick the destination among the other two balances. No swap
    /// badge — the source is fixed by the tapped balance row.
    @ViewBuilder
    private func sendCards(source: ChainNetwork) -> some View {
        VStack(spacing: 12) {
            pinnedCard(source, caption: NSLocalizedString("From", comment: ""))
            selectionGroup(
                caption: NSLocalizedString("To", comment: ""),
                networks: availableTargets(for: source),
                selected: sanitizedTarget(for: source, proposed: viewModel.sendTarget),
                onSelect: viewModel.selectSendTarget)
        }
    }

    /// Non-tappable pinned endpoint card (the fixed From of the send sheet).
    private func pinnedCard(_ network: ChainNetwork, caption: String) -> some View {
        let display = networkDisplay(network)
        return sourceRow(
            iconSystemName: display.icon,
            caption: caption,
            title: display.title,
            balanceTrailing: dashBalanceTrailing(display.balance),
            selected: false,
            showsRadio: false,
            action: {})
    }

    /// Icon / title / formatted balance for a balance row, one source of
    /// truth for the pinned cards and picker rows.
    private func networkDisplay(_ network: ChainNetwork) -> (icon: String, title: String, balance: String) {
        switch network {
        case .core:
            return ("d.circle.fill",
                    NSLocalizedString("Transparent", comment: "Balance breakdown"),
                    viewModel.coreBalanceFormatted)
        case .platform:
            return ("creditcard.fill",
                    NSLocalizedString("Platform", comment: "Dash Platform chain"),
                    viewModel.platformCreditsFormatted)
        case .shielded:
            return ("shield.fill",
                    NSLocalizedString("Shielded", comment: ""),
                    viewModel.shieldedBalanceFormatted)
        }
    }

    private var swappableCards: some View {
        VStack(spacing: 12) {
            selectionGroup(
                caption: NSLocalizedString("From", comment: ""),
                networks: ChainNetwork.allCases,
                selected: viewModel.source,
                onSelect: viewModel.selectStandaloneSource)

            selectionGroup(
                caption: NSLocalizedString("To", comment: ""),
                networks: availableTargets(for: viewModel.source),
                selected: sanitizedTarget(for: viewModel.source, proposed: viewModel.sendTarget),
                onSelect: viewModel.selectStandaloneTarget)
        }
    }

    /// Receive-sheet layout: the destination stays pinned as the bottom
    /// card; the rows above pick the source among the other two balances.
    /// No swap badge — the destination is fixed by the tapped balance row.
    @ViewBuilder
    private func receiveCards(target: ChainNetwork) -> some View {
        VStack(spacing: 12) {
            selectionGroup(
                caption: NSLocalizedString("From", comment: ""),
                networks: availableSources(for: target),
                selected: sanitizedSource(into: target, proposed: viewModel.receiveSource),
                onSelect: viewModel.selectReceiveSource)

            pinnedCard(target, caption: NSLocalizedString("To", comment: ""))
        }
    }

    /// Trailing balance amount + Dash currency glyph, shared by every card.
    private func dashBalanceTrailing(_ formatted: String) -> AnyView {
        TransferSourceRow.dashBalanceTrailing(formatted)
    }

    private func selectionGroup(
        caption: String,
        networks: [ChainNetwork],
        selected: ChainNetwork,
        onSelect: @escaping (ChainNetwork) -> Void
    ) -> some View {
        VStack(spacing: 8) {
            ForEach(networks, id: \.self) { network in
                let display = networkDisplay(network)
                sourceRow(
                    iconSystemName: display.icon,
                    caption: caption,
                    title: display.title,
                    balanceTrailing: dashBalanceTrailing(display.balance),
                    selected: selected == network,
                    action: { onSelect(network) })
            }
        }
    }

    /// Tappable source row with a trailing radio indicator — rendered by the
    /// shared `TransferSourceRow` (also used by the Send screen's From picker).
    private func sourceRow(
        iconSystemName: String,
        caption: String,
        title: String,
        balanceTrailing: AnyView,
        selected: Bool,
        showsRadio: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        TransferSourceRow(
            iconSystemName: iconSystemName,
            caption: caption,
            title: title,
            balanceTrailing: balanceTrailing,
            selected: selected,
            showsRadio: showsRadio,
            action: action)
    }

    private func availableTargets(for source: ChainNetwork) -> [ChainNetwork] {
        ChainNetwork.allCases.filter { $0 != source }
    }

    private func availableSources(for target: ChainNetwork) -> [ChainNetwork] {
        ChainNetwork.allCases.filter { $0 != target }
    }

    private func sanitizedTarget(for source: ChainNetwork, proposed target: ChainNetwork) -> ChainNetwork {
        source == target ? defaultTarget(for: source) : target
    }

    private func sanitizedSource(into target: ChainNetwork, proposed source: ChainNetwork) -> ChainNetwork {
        source == target ? defaultSource(for: target) : source
    }

    private func defaultTarget(for source: ChainNetwork) -> ChainNetwork {
        switch source {
        case .core, .platform:
            return .shielded
        case .shielded:
            return .core
        }
    }

    private func defaultSource(for target: ChainNetwork) -> ChainNetwork {
        switch target {
        case .shielded:
            return .core
        case .core, .platform:
            return .shielded
        }
    }

    // MARK: - Transfer preview

    private var transferPreview: some View {
        VStack(spacing: 2) {
            Text(NSLocalizedString("You will transfer", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(Color.dash.secondaryText)
            HStack(spacing: 4) {
                Text("~ \(viewModel.dashAmountFormatted)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Image("icon_dash_currency")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 13, height: 13)
            }
        }
        .frame(maxWidth: .infinity)
    }

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

// MARK: - TransferAmountValidationNote

/// Inline explanation for a route-specific amount that cannot be submitted.
/// Keeping this next to the amount/source controls prevents a protective SDK
/// build-time refusal from becoming the user's first feedback.
struct TransferAmountValidationNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - TransferSourceRow

/// Tappable balance row with icon, caption ("From"/"To"), title, trailing
/// balance, and a radio indicator — shared by the internal transfer screen's
/// source picker and the Send screen's From picker.
struct TransferSourceRow: View {
    let iconSystemName: String
    let caption: String
    let title: String
    let balanceTrailing: AnyView
    let selected: Bool
    /// False renders a fixed (non-picker) endpoint card: no radio circle
    /// and no selection border.
    var showsRadio: Bool = true
    var action: () -> Void

    /// Trailing balance amount + Dash currency glyph, the standard trailing
    /// content for these rows.
    static func dashBalanceTrailing(_ formatted: String) -> AnyView {
        AnyView(
            HStack(spacing: 2) {
                Text(formatted)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Image("icon_dash_currency")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            })
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: iconSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color.dash.blue.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundColor(Color.dash.secondaryText)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                }

                Spacer()

                balanceTrailing

                if showsRadio {
                    radioIndicator
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.dash.secondaryBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(showsRadio && selected ? Color.dash.blue : Color.clear,
                            lineWidth: showsRadio && selected ? 1.5 : 0))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(!showsRadio)
    }

    private var radioIndicator: some View {
        ZStack {
            Circle()
                .stroke(selected ? Color.dash.blue : Color.dash.gray300.opacity(0.6), lineWidth: 1.5)
                .frame(width: 18, height: 18)
            if selected {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 10, height: 10)
            }
        }
    }
}
