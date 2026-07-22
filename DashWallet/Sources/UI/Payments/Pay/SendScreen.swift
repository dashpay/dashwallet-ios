//
//  SendScreen.swift
//  DashWallet
//
//  External-send flow, split across two steps. Step one (`SendScreen`) is
//  address only: the recipient address (typed / pasted / scanned) decides the
//  destination type (Transparent L1 / Platform / Shielded); Continue advances
//  to step two. Step two (`ExternalSendAmountScreen`) is the From picker plus
//  the amount keypad — Core → Core continues into the classic payment
//  processor (real fee math + its own confirm); every other route confirms in
//  `SendConfirmSheet` and executes via `ShieldedTransferCoordinator`.
//

import SwiftUI
import DashUIKit
import SwiftDashSDK
import UIKit

// MARK: - Step 1: address

struct SendScreen: View {
    @ObservedObject var viewModel: SendViewModel
    var onClose: () -> Void
    var onScanQR: () -> Void
    /// The entered address is valid → advance to the amount step. The host
    /// pushes `ExternalSendAmountScreen` onto the same navigation stack.
    var onContinue: () -> Void
    /// False when embedded under a host that renders its own chrome
    /// (the balance-row send sheet) — hides the X + title header.
    var showsHeader: Bool = true

    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            ScrollView {
                VStack(spacing: 14) {
                    addressField
                        .padding(.top, 12)

                    if let suggestion = viewModel.clipboardSuggestion,
                       suggestion.address != viewModel.trimmedAddress {
                        clipboardChip(for: suggestion)
                    }

                    scanRow
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                style: .filled,
                stretch: true,
                isEnabled: viewModel.canAdvanceToAmount,
                action: {
                    addressFieldFocused = false
                    onContinue()
                })
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.dash.primaryText)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
            }
            Spacer()
            Text(NSLocalizedString("Send", comment: ""))
                .font(.headline)
                .foregroundColor(.dash.primaryText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
    }

    // MARK: - Address

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString("Address", comment: ""))
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
                Spacer()
                if let destination = viewModel.destination {
                    destinationBadge(destination)
                }
            }
            if isAddressLocked {
                lockedAddressCard
            } else {
                TextField(
                    NSLocalizedString("Dash address", comment: "Send screen address placeholder"),
                    text: $viewModel.addressText,
                    axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.dash.primaryText)
                    .padding(12)
                    .background(Color.dash.secondaryBackground)
                    .cornerRadius(10)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .lineLimit(2...4)
                    .focused($addressFieldFocused)
                    .onAppear {
                        // Rendered after tapping the locked card → put the
                        // cursor straight back into the field.
                        if isEditingAddress {
                            addressFieldFocused = true
                        }
                    }
                    .onChange(of: addressFieldFocused) { _, focused in
                        // Focus left the field → re-lock (when valid).
                        if !focused {
                            isEditingAddress = false
                        }
                    }
                    .onChange(of: viewModel.destination) { _, destination in
                        // The address just became valid (a paste, or the
                        // final typed character) → lock in right away.
                        // Software-keyboard-less setups (simulator with a
                        // hardware keyboard) never drop focus on their own,
                        // so don't wait for that.
                        if destination != nil {
                            addressFieldFocused = false
                            isEditingAddress = false
                        }
                    }
            }

            if viewModel.showsInvalidAddress {
                Text(NSLocalizedString("This is not a valid Dash address for this network", comment: "Send screen"))
                    .font(.caption)
                    .foregroundColor(.red)
            } else if viewModel.pinnedSourceMismatch {
                Text(String(
                    format: NSLocalizedString("This address can't be paid from your %@ balance", comment: "Send sheet source/destination mismatch"),
                    viewModel.pinnedSourceTitle))
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 20)
    }

    /// The locked-in address: middle-truncated single line + pencil.
    /// Tapping reopens the editable field with the cursor in place.
    private var lockedAddressCard: some View {
        Button(action: { isEditingAddress = true }) {
            HStack(spacing: 8) {
                Text(truncateMiddle(viewModel.trimmedAddress, visible: 10))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.dash.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.dash.secondaryBackground)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func destinationBadge(_ destination: SendViewModel.DestinationKind) -> some View {
        HStack(spacing: 4) {
            Image(systemName: destinationIconName(destination))
                .font(.system(size: 10, weight: .semibold))
            Text(destinationTitle(destination))
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(.dash.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.dash.blue.opacity(0.1))
        .clipShape(Capsule())
    }

    private func destinationIconName(_ destination: SendViewModel.DestinationKind) -> String {
        switch destination {
        case .core: return "d.circle.fill"
        case .platform: return "creditcard.fill"
        case .shielded: return "shield.fill"
        }
    }

    private func destinationTitle(_ destination: SendViewModel.DestinationKind) -> String {
        switch destination {
        case .core: return NSLocalizedString("Transparent address", comment: "Send screen destination type")
        case .platform: return NSLocalizedString("Platform address", comment: "Send screen destination type")
        case .shielded: return NSLocalizedString("Shielded address", comment: "Send screen destination type")
        }
    }

    private func clipboardChip(for suggestion: SendViewModel.ClipboardSuggestion) -> some View {
        Button(action: { viewModel.useClipboardSuggestion() }) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Send to copied address", comment: ""))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                    Text(truncateMiddle(suggestion.address))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.dash.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(destinationTitle(suggestion.kind))
                    .font(.caption2)
                    .foregroundColor(Color.dash.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.dash.gray300.opacity(0.3))
                    .cornerRadius(8)
            }
            .padding(12)
            .background(Color.dash.blue.opacity(0.08))
            .cornerRadius(10)
        }
        .padding(.horizontal, 20)
    }

    private var scanRow: some View {
        Button(action: onScanQR) {
            HStack(spacing: 6) {
                Image(systemName: "qrcode.viewfinder")
                Text(NSLocalizedString("Scan QR", comment: ""))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.dash.blue.opacity(0.12))
            .cornerRadius(10)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Step 2: amount

/// The amount step for the split external-send flow. The address is already
/// chosen (locked, read-only) — this screen carries the From picker, the
/// sync gate, and the amount keypad, plus the balance/affordability
/// validations. Continue routes exactly as the old single-screen form did:
/// Core → Core into the L1 payment processor, everything else into
/// `SendConfirmSheet`.
struct SendSourceScreen: View {
    @ObservedObject var viewModel: SendViewModel
    /// Pop back to the address step.
    var onBack: () -> Void
    /// A valid source is chosen → advance to the amount step.
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SendStepHeader(onBack: onBack)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            ScrollView {
                VStack(spacing: 14) {
                    SendAddressSummary(viewModel: viewModel, onEdit: onBack)
                        .padding(.top, 12)

                    sourceCards

                    if viewModel.isBlockedBySync {
                        SyncGateNote()
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                style: .filled,
                stretch: true,
                isEnabled: viewModel.route != nil && !viewModel.isBlockedBySync,
                action: onContinue)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - From picker

    @ViewBuilder
    private var sourceCards: some View {
        if let pinned = viewModel.pinnedSource {
            // Balance-row send sheet: the source is the tapped balance,
            // rendered as a fixed card (no radio, not tappable).
            sourceRow(pinned, showsRadio: false)
                .padding(.horizontal, 20)
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.validSources, id: \.self) { network in
                    sourceRow(network)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func sourceRow(_ network: ChainNetwork, showsRadio: Bool = true) -> some View {
        let balance: String
        switch network {
        case .core: balance = viewModel.coreBalanceFormatted
        case .platform: balance = viewModel.platformCreditsFormatted
        case .shielded: balance = viewModel.shieldedBalanceFormatted
        }
        return TransferSourceRow(
            iconSystemName: sourceIconName(network),
            caption: NSLocalizedString("From", comment: ""),
            title: sourceTitle(network),
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(balance),
            selected: viewModel.source == network,
            showsRadio: showsRadio,
            action: { viewModel.source = network })
    }
}

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

                    TransferAmountRow(
                        unit: $viewModel.unit,
                        amountText: viewModel.amountText,
                        secondaryText: viewModel.secondaryDisplayString,
                        currencySymbol: viewModel.primaryCurrencySymbol,
                        fiatCurrencyCode: viewModel.fiatCurrencyCode,
                        onMax: { viewModel.fillMaxFromWallet() })
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
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
                actionHandler: continueAction)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color.primaryBackground)
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

    // MARK: - Keypad

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

// MARK: - Shared step chrome

/// Back-chevron + "Send" title, shared by the source and amount steps.
private struct SendStepHeader: View {
    var onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
            }
            Spacer()
            Text(NSLocalizedString("Send", comment: ""))
                .font(.headline)
                .foregroundColor(.primaryText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
    }
}

/// The chosen destination address, read-only. Tapping (`onEdit`) pops back to
/// the address step. Shared by the source and amount steps.
private struct SendAddressSummary: View {
    @ObservedObject var viewModel: SendViewModel
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(NSLocalizedString("Address", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let destination = viewModel.destination {
                        destinationBadge(destination)
                    }
                }
                HStack(spacing: 8) {
                    Text(truncateMiddle(viewModel.trimmedAddress, visible: 10))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.secondaryBackground)
                .cornerRadius(10)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

// MARK: - Shared helpers

private func sourceIconName(_ network: ChainNetwork) -> String {
    switch network {
    case .core: return "d.circle.fill"
    case .platform: return "creditcard.fill"
    case .shielded: return "shield.fill"
    }
}

private func sourceTitle(_ network: ChainNetwork) -> String {
    switch network {
    case .core: return NSLocalizedString("Transparent", comment: "Balance breakdown")
    case .platform: return NSLocalizedString("Platform", comment: "Dash Platform chain")
    case .shielded: return NSLocalizedString("Shielded", comment: "")
    }
}

private func destinationBadge(_ destination: SendViewModel.DestinationKind) -> some View {
    HStack(spacing: 4) {
        Image(systemName: destinationIconName(destination))
            .font(.system(size: 10, weight: .semibold))
        Text(destinationTitle(destination))
            .font(.caption2.weight(.semibold))
    }
    .foregroundColor(.dashBlue)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Color.dashBlue.opacity(0.1))
    .clipShape(Capsule())
}

private func destinationIconName(_ destination: SendViewModel.DestinationKind) -> String {
    switch destination {
    case .core: return "d.circle.fill"
    case .platform: return "creditcard.fill"
    case .shielded: return "shield.fill"
    }
}

private func destinationTitle(_ destination: SendViewModel.DestinationKind) -> String {
    switch destination {
    case .core: return NSLocalizedString("Transparent address", comment: "Send screen destination type")
    case .platform: return NSLocalizedString("Platform address", comment: "Send screen destination type")
    case .shielded: return NSLocalizedString("Shielded address", comment: "Send screen destination type")
    }
}

/// Middle-truncated address display shared by the screen's clipboard chip
/// and the confirm sheet's To row.
private func truncateMiddle(_ s: String, visible: Int = 8) -> String {
    guard s.count > visible * 2 + 3 else { return s }
    let head = s.prefix(visible)
    let tail = s.suffix(visible)
    return "\(head)…\(tail)"
}

// MARK: - SendConfirmSheet

/// Confirmation half-sheet for the non-core external send routes. Same
/// skeleton as `InternalTransferConfirmSheet` (summary → progress checklist →
/// success), but the To row is the recipient's address and execution runs the
/// coordinator's external-destination legs. Core → Core never reaches this
/// sheet — it rides the classic payment processor.
struct SendConfirmSheet: View {

    let route: SendViewModel.Route
    let destinationAddress: String
    /// The recipient's raw 43-byte Orchard payload — required for
    /// `.shieldedToShielded`, nil otherwise.
    let destinationRaw43: Data?
    let dashDuffs: Int64
    let creditsAmount: UInt64
    let fiatText: String
    /// Preflighted withdrawal fee — only meaningful for `.platformToCore`.
    var withdrawalFeeCredits: UInt64? = nil
    var isFullPlatformWithdrawal: Bool = false
    var onCancel: () -> Void
    var onCompleted: () -> Void

    @StateObject private var coordinator = ShieldedTransferCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 8)

            Text(NSLocalizedString("Confirm", comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 20)

            switch coordinator.phase {
            case .success:
                successBody
            case .submittedUnconfirmed:
                ShieldedSubmittedUnconfirmedView(onDone: onCompleted)
            default:
                detailsBody
            }
        }
        .background(Color.dash.primaryBackground)
        .interactiveDismissDisabled(isInFlight)
    }

    private var isInFlight: Bool {
        switch coordinator.phase {
        case .signing, .locking, .proving, .broadcasting:
            return true
        default:
            return false
        }
    }

    // MARK: - Idle / in-flight / failed body

    private var detailsBody: some View {
        VStack(spacing: 0) {
            DashAmount(
                amount: dashDuffs,
                font: .largeTitle,
                dashSymbolFactor: 0.7,
                showDirection: false)
                .padding(.top, 14)

            Text(fiatText)
                .font(.subheadline)
                .foregroundColor(.dash.secondaryText)
                .padding(.top, 6)

            summaryCard
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if case let .failed(message) = coordinator.phase {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else {
                infoCard
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            switch coordinator.phase {
            case .idle:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Confirm", comment: ""),
                    positiveButtonAction: confirm,
                    negativeButtonText: NSLocalizedString("Cancel", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .failed:
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Try again", comment: ""),
                    positiveButtonAction: tryAgain,
                    negativeButtonText: NSLocalizedString("Close", comment: ""),
                    negativeButtonAction: onCancel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

            case .signing, .locking, .proving, .broadcasting:
                ShieldedTransferStepList(currentPhase: coordinator.phase, steps: progressSteps)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

            case .success, .submittedUnconfirmed:
                EmptyView()
            }
        }
    }

    // MARK: - Success body

    private var successBody: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.green)
                .padding(.top, 24)

            Text(NSLocalizedString("Sent", comment: "Send confirm sheet"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)

            DashAmount(
                amount: dashDuffs,
                font: .title,
                dashSymbolFactor: 0.7,
                showDirection: false)

            Text(fiatText)
                .font(.subheadline)
                .foregroundColor(.dash.secondaryText)

            Spacer(minLength: 12)

            DashButton(
                text: NSLocalizedString("Done", comment: ""),
                style: .filled,
                stretch: true,
                action: onCompleted)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Pieces

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.dash.grabberFill)
            .frame(width: 36, height: 5)
            .cornerRadius(2.5)
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow(
                label: NSLocalizedString("From", comment: ""),
                value: fromLabel)
            divider
            HStack {
                Text(NSLocalizedString("To", comment: ""))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                Spacer()
                Text(truncateMiddle(destinationAddress))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            divider
            summaryRow(
                label: NSLocalizedString("Network fee", comment: ""),
                value: networkFeeString)
            divider
            summaryRow(
                label: NSLocalizedString("Total", comment: ""),
                value: dashDuffs.formattedDashAmount)
        }
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var fromLabel: String {
        switch route {
        case .platformToPlatform, .platformToCore:
            return NSLocalizedString("Platform balance", comment: "The Dash Platform credits balance")
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
            return NSLocalizedString("Shielded balance", comment: "")
        case .coreToCore, .coreToShielded:
            return NSLocalizedString("Transparent balance", comment: "The transparent (Core) balance of the Dash Wallet")
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.dash.primaryText)
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

    // MARK: - Network fee estimate

    /// Platform credits per DASH (1e11).
    private static let creditsPerDash: Decimal = 100_000_000_000

    /// Flat fee estimate (credits) for the active route — same estimators as
    /// the internal transfer's confirm sheet. `nil` → the row shows "—".
    private var networkFeeCredits: UInt64? {
        switch route {
        case .coreToShielded:
            // ShieldFromAssetLock: base shielded fee + asset-lock base cost
            // (same estimate as the internal Core → Shielded transfer).
            guard let base = try? PlatformWalletManager.estimateShieldedFee(kind: .transfer, numActions: 2)
            else { return nil }
            return base + InternalTransferConfirmSheet.assetLockBaseCostCredits
        case .platformToPlatform:
            // Credit transfer: the metered transition fee. The executor
            // states ~0.001 DASH as the conservative max.
            return 100_000_000
        case .platformToCore:
            return withdrawalFeeCredits
        case .shieldedToCore:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .withdrawal, numActions: 2)
        case .shieldedToPlatform:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .unshield, numActions: 2)
        case .shieldedToShielded:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .transfer, numActions: 2)
        case .coreToCore:
            // Never presented here — the L1 processor shows the real fee.
            return nil
        }
    }

    private var networkFeeString: String {
        guard let credits = networkFeeCredits else { return "—" }
        let dash = Decimal(credits) / Self.creditsPerDash
        return "~ " + CurrencyExchanger.shared.fiatAmountString(for: dash)
    }

    // MARK: - Info card

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 30, height: 30)
                Image(systemName: infoIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(infoTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Text(infoBody)
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    private var infoIcon: String {
        switch route {
        case .platformToCore, .shieldedToCore: return "clock.fill"
        default: return "exclamationmark.shield.fill"
        }
    }

    private var infoTitle: String {
        switch route {
        case .platformToCore, .shieldedToCore:
            return NSLocalizedString("Processing time", comment: "")
        default:
            return NSLocalizedString("Double-check the address", comment: "Send confirm sheet")
        }
    }

    private var infoBody: String {
        switch route {
        case .shieldedToCore:
            return NSLocalizedString(
                "The Dash arrives at the recipient's address after the network processes the withdrawal — this can take up to 10 minutes.",
                comment: "Send confirm sheet")
        case .platformToCore:
            return isFullPlatformWithdrawal
                ? NSLocalizedString(
                    "This withdraws your entire Platform balance in one transfer. The Dash arrives at the recipient's address once the network processes the withdrawal.",
                    comment: "Send confirm sheet")
                : NSLocalizedString(
                    "The Dash arrives at the recipient's address once the network processes the withdrawal.",
                    comment: "Send confirm sheet")
        default:
            return NSLocalizedString(
                "Dash sent to a wrong address can't be recovered. Make sure the address is exactly the one you intend to pay.",
                comment: "Send confirm sheet")
        }
    }

    // MARK: - Progress checklist

    private var progressSteps: [ShieldedTransferStepList.Step] {
        var steps: [ShieldedTransferStepList.Step] = [
            .init(label: NSLocalizedString("Authorizing", comment: ""), phase: .signing)
        ]
        // Only the asset-lock route has the on-chain locking stage.
        if route == .coreToShielded {
            steps.append(.init(label: NSLocalizedString("Locking funds", comment: ""), phase: .locking))
        }
        // Only shielded legs build an Orchard proof.
        switch route {
        case .coreToShielded, .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
            steps.append(.init(label: NSLocalizedString("Generating proof", comment: ""), phase: .proving))
        case .platformToPlatform, .platformToCore, .coreToCore:
            break
        }
        steps.append(.init(label: NSLocalizedString("Broadcasting", comment: ""), phase: .broadcasting))
        return steps
    }

    // MARK: - Actions

    private func confirm() {
        Task {
            switch route {
            case .coreToShielded:
                guard let destinationRaw43 else {
                    coordinator.reset()
                    return
                }
                await coordinator.performAssetLock(
                    amountDuffs: UInt64(dashDuffs),
                    recipientRaw43: destinationRaw43)
            case .platformToPlatform:
                await coordinator.performPlatformSend(
                    destination: destinationAddress,
                    amountCredits: creditsAmount)
            case .platformToCore:
                await coordinator.performPlatformWithdraw(
                    amountCredits: creditsAmount,
                    fullBalance: isFullPlatformWithdrawal,
                    feeHeadroomCredits: withdrawalFeeCredits,
                    toCoreAddress: destinationAddress)
            case .shieldedToCore:
                await coordinator.performWithdraw(
                    amountCredits: creditsAmount,
                    toCoreAddress: destinationAddress)
            case .shieldedToPlatform:
                await coordinator.performUnshield(
                    amountCredits: creditsAmount,
                    toPlatformAddress: destinationAddress)
            case .shieldedToShielded:
                guard let destinationRaw43 else {
                    coordinator.reset()
                    return
                }
                await coordinator.performShieldedTransfer(
                    amountCredits: creditsAmount,
                    recipientRaw43: destinationRaw43)
            case .coreToCore:
                // Unreachable: the screen routes Core → Core through the L1
                // payment processor and never presents this sheet.
                break
            }
        }
    }

    private func tryAgain() {
        // If the just-failed Core → Shielded attempt already committed its
        // asset lock, RESUME that exact outpoint with the same recipient
        // instead of building a second lock (which strands the first) —
        // mirrors the internal transfer's retry.
        if route == .coreToShielded,
           let op = coordinator.lastAssetLockOutPoint,
           let destinationRaw43 {
            coordinator.reset()
            Task {
                await coordinator.resumeAssetLock(
                    outPointTxidWire: op.txidWire,
                    outPointVout: op.vout,
                    recipientRaw43: destinationRaw43)
            }
            return
        }
        coordinator.reset()
        confirm()
    }
}


/// Inline explanation for a Continue disabled by the chain-sync gate:
/// Core-funded sends stay off until `SyncingActivityMonitor` reports
/// `.syncDone` (a stale UTXO set can't safely fund a spend). Shared by
/// the Send and Internal transfer screens.
struct SyncGateNote: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13))
                .foregroundColor(.orange)
            Text(NSLocalizedString(
                "Your wallet is still syncing. Sending from your Transparent balance will be available once syncing completes.",
                comment: "Core send blocked until chain sync completes"))
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }
}
