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
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            NumericKeyboardView(
                value: keypadBinding,
                showDecimalSeparator: true,
                actionButtonText: NSLocalizedString("Continue", comment: ""),
                actionEnabled: viewModel.canContinue,
                inProgress: false,
                actionHandler: { showConfirm = true })
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
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
        TransferAmountRow(
            unit: $viewModel.unit,
            amountText: viewModel.amountText,
            secondaryText: viewModel.secondaryDisplayString,
            currencySymbol: viewModel.primaryCurrencySymbol,
            fiatCurrencyCode: viewModel.fiatCurrencyCode,
            onMax: { viewModel.fillMaxFromWallet() })
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
        VStack(spacing: 8) {
            pinnedCard(source, caption: NSLocalizedString("From", comment: ""))
            switch source {
            case .core:
                sendTargetRow(.shielded)
                sendTargetRow(.platform)
            case .platform:
                sendTargetRow(.shielded)
                sendTargetRow(.core)
            case .shielded:
                sendTargetRow(.core)
                sendTargetRow(.platform)
            }
        }
    }

    /// Selectable To row of the send sheet, bound to `viewModel.sendTarget`.
    private func sendTargetRow(_ network: ChainNetwork) -> some View {
        let display = networkDisplay(network)
        return sourceRow(
            iconSystemName: display.icon,
            caption: NSLocalizedString("To", comment: ""),
            title: display.title,
            balanceTrailing: dashBalanceTrailing(display.balance),
            selected: viewModel.sendTarget == network,
            action: { viewModel.sendTarget = network })
    }

    /// Non-tappable pinned endpoint card (the fixed From of the send sheet).
    private func pinnedCard(_ network: ChainNetwork, caption: String) -> some View {
        let display = networkDisplay(network)
        return directionCard(
            iconSystemName: display.icon,
            iconColor: .blue,
            caption: caption,
            title: display.title,
            balanceTrailing: dashBalanceTrailing(display.balance))
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
        ZStack {
            VStack(spacing: 8) {
                switch viewModel.direction {
                case .toShielded:
                    coreSourceCard
                    platformSourceCard
                    toCard
                case .fromShielded:
                    fromShieldedCard
                    coreSourceCard
                    platformSourceCard
                }
            }

            // Tappable swap badge — toggles the transfer direction. Sits over
            // the boundary between the From and To sides. Forward (2 source rows
            // above the To card) nudges it down (y:32); reverse (1 From card
            // above 2 destination rows) nudges it up (y:-32).
            swapBadge
                .offset(y: viewModel.direction == .toShielded ? 32 : -32)
        }
    }

    /// Receive-sheet layout: the destination stays pinned as the bottom
    /// card; the rows above pick the source among the other two balances.
    /// No swap badge — the destination is fixed by the tapped balance row.
    @ViewBuilder
    private func receiveCards(target: ChainNetwork) -> some View {
        VStack(spacing: 8) {
            switch target {
            case .shielded:
                coreSourceCard
                platformSourceCard
                toCard
            case .core:
                receiveSourceRow(.shielded)
                receiveSourceRow(.platform)
                toTransparentCard
            case .platform:
                receiveSourceRow(.shielded)
                receiveSourceRow(.core)
                toPlatformCard
            }
        }
    }

    /// Selectable From row of the receive sheet, bound to
    /// `viewModel.receiveSource` (the .shielded target reuses the legacy
    /// `source`-bound cards instead).
    private func receiveSourceRow(_ network: ChainNetwork) -> some View {
        let display = networkDisplay(network)
        return sourceRow(
            iconSystemName: display.icon,
            caption: NSLocalizedString("From", comment: ""),
            title: display.title,
            balanceTrailing: dashBalanceTrailing(display.balance),
            selected: viewModel.receiveSource == network,
            action: { viewModel.receiveSource = network })
    }

    private var toTransparentCard: some View {
        directionCard(
            iconSystemName: "d.circle.fill",
            iconColor: .blue,
            caption: NSLocalizedString("To", comment: ""),
            title: NSLocalizedString("Transparent", comment: "Balance breakdown"),
            balanceTrailing: dashBalanceTrailing(viewModel.coreBalanceFormatted))
    }

    private var toPlatformCard: some View {
        directionCard(
            iconSystemName: "creditcard.fill",
            iconColor: .blue,
            caption: NSLocalizedString("To", comment: ""),
            title: NSLocalizedString("Platform", comment: "Dash Platform chain"),
            balanceTrailing: dashBalanceTrailing(viewModel.platformCreditsFormatted))
    }

    /// Trailing balance amount + Dash currency glyph, shared by every card.
    private func dashBalanceTrailing(_ formatted: String) -> AnyView {
        TransferSourceRow.dashBalanceTrailing(formatted)
    }

    private var coreSourceCard: some View {
        sourceRow(
            iconSystemName: "d.circle.fill",
            caption: sourceCaption,
            title: NSLocalizedString("Transparent", comment: "Balance breakdown"),
            balanceTrailing: dashBalanceTrailing(viewModel.coreBalanceFormatted),
            selected: viewModel.source == .core,
            action: { viewModel.source = .core })
    }

    private var platformSourceCard: some View {
        sourceRow(
            iconSystemName: "creditcard.fill",
            caption: sourceCaption,
            title: NSLocalizedString("Platform", comment: "Dash Platform chain"),
            balanceTrailing: dashBalanceTrailing(viewModel.platformCreditsFormatted),
            selected: viewModel.source == .platform,
            action: { viewModel.source = .platform })
    }

    private var toCard: some View {
        directionCard(
            iconSystemName: "shield.fill",
            iconColor: .blue,
            caption: NSLocalizedString("To", comment: ""),
            title: NSLocalizedString("Shielded", comment: ""),
            balanceTrailing: AnyView(
                Text(viewModel.shieldedBalanceFormatted)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)))
    }

    // MARK: - Reverse-direction From card

    /// "From" card in reverse mode — the shielded balance (non-tappable). The
    /// reverse *destination* is chosen via the reused `coreSourceCard` /
    /// `platformSourceCard` radio rows rendered below it.
    private var fromShieldedCard: some View {
        directionCard(
            iconSystemName: "shield.fill",
            iconColor: .blue,
            caption: NSLocalizedString("From", comment: ""),
            title: NSLocalizedString("Shielded", comment: ""),
            balanceTrailing: AnyView(
                Text(viewModel.shieldedBalanceFormatted)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)))
    }

    /// Caption for the reusable source rows: "From" in the forward direction,
    /// "To" in reverse (where they act as the destination picker).
    private var sourceCaption: String {
        viewModel.direction == .toShielded
            ? NSLocalizedString("From", comment: "")
            : NSLocalizedString("To", comment: "")
    }

    /// Tappable source row with a trailing radio indicator — rendered by the
    /// shared `TransferSourceRow` (also used by the Send screen's From picker).
    private func sourceRow(
        iconSystemName: String,
        caption: String,
        title: String,
        balanceTrailing: AnyView,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        TransferSourceRow(
            iconSystemName: iconSystemName,
            caption: caption,
            title: title,
            balanceTrailing: balanceTrailing,
            selected: selected,
            action: action)
    }

    private func directionCard(
        iconSystemName: String,
        iconColor: Color,
        caption: String,
        title: String,
        balanceTrailing: AnyView
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: iconSystemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var swapBadge: some View {
        Button(action: toggleDirection) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.dash.primaryText)
                .frame(width: 28, height: 28)
                .background(Color.dash.primaryBackground)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func toggleDirection() {
        viewModel.direction = viewModel.direction == .toShielded ? .fromShielded : .toShielded
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

// MARK: - TransferAmountRow

/// The Max-pill / big-number / DASH-fiat unit-pill amount entry row, shared
/// by the internal transfer screen and the Send screen so the two amount
/// entries can't drift apart visually.
struct TransferAmountRow: View {
    @Binding var unit: InternalTransferUnit
    let amountText: String
    /// The small grey line under the big number (the non-input unit).
    let secondaryText: String
    /// Fiat currency symbol prefixed to the big number in `.fiat` mode.
    let currencySymbol: String
    /// Active fiat code (e.g. "THB") — the second unit pill's label.
    let fiatCurrencyCode: String
    var onMax: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onMax) {
                Text(NSLocalizedString("Max", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.dash.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.dash.secondaryBackground)
                    .clipShape(Capsule())
            }

            VStack(spacing: 4) {
                primaryAmountDisplay

                Text(secondaryText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.dash.secondaryText)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                unitPill(label: "DASH", selected: unit == .dash) {
                    unit = .dash
                }
                unitPill(label: fiatCurrencyCode, selected: unit == .fiat) {
                    unit = .fiat
                }
            }
        }
    }

    @ViewBuilder
    private var primaryAmountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            switch unit {
            case .dash:
                Text(amountText)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Image("icon_dash_currency")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            case .fiat:
                Text(currencySymbol)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                Text(amountText)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private func unitPill(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(selected ? .dash.primaryText : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? Color.dash.secondaryBackground : Color.clear)
                .clipShape(Capsule())
        }
    }
}
