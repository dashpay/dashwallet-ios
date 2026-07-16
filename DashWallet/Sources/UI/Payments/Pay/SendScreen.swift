//
//  SendScreen.swift
//  DashWallet
//
//  External-send form: recipient address (typed / pasted / scanned) decides
//  the destination type (Transparent L1 / Platform / Shielded); the From
//  picker chooses which balance funds it; the amount is entered inline on
//  the numeric keypad. Core → Core continues into the classic payment
//  processor (real fee math + its own confirm); every other route confirms
//  in `SendConfirmSheet` and executes via `ShieldedTransferCoordinator`.
//

import SwiftUI
import DashUIKit
import SwiftDashSDK
import UIKit

struct SendScreen: View {
    @ObservedObject var viewModel: SendViewModel
    var onClose: () -> Void
    var onScanQR: () -> Void
    /// Core → Core: hand (address, amount in duffs) to the hosting
    /// controller, which routes through the L1 payment processor.
    var onContinueCore: (String, UInt64) -> Void
    /// A non-core route finished successfully (confirm sheet's Done).
    var onSendCompleted: () -> Void

    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 10)

            ScrollView {
                VStack(spacing: 14) {
                    addressField
                        .padding(.top, 12)

                    if let suggestion = viewModel.clipboardSuggestion,
                       suggestion.address != viewModel.trimmedAddress {
                        clipboardChip(for: suggestion)
                    }

                    scanRow

                    if viewModel.destination != nil {
                        sourceCards

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
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

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

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
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

    // MARK: - Address

    private var addressField: some View {
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
            TextField(
                NSLocalizedString("Dash address", comment: "Send screen address placeholder"),
                text: $viewModel.addressText,
                axis: .vertical)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.primaryText)
                .padding(12)
                .background(Color.secondaryBackground)
                .cornerRadius(10)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                .lineLimit(2...4)

            if viewModel.showsInvalidAddress {
                Text(NSLocalizedString("This is not a valid Dash address for this network", comment: "Send screen"))
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 20)
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

    private func clipboardChip(for suggestion: SendViewModel.ClipboardSuggestion) -> some View {
        Button(action: { viewModel.useClipboardSuggestion() }) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Send to copied address", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(truncateMiddle(suggestion.address))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(destinationTitle(suggestion.kind))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray300.opacity(0.3))
                    .cornerRadius(8)
            }
            .padding(12)
            .background(Color.blue.opacity(0.08))
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
            .background(Color.blue.opacity(0.12))
            .cornerRadius(10)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - From picker

    private var sourceCards: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.validSources, id: \.self) { network in
                sourceRow(network)
            }
        }
        .padding(.horizontal, 20)
    }

    private func sourceRow(_ network: ChainNetwork) -> some View {
        let icon: String
        let title: String
        let balance: String
        switch network {
        case .core:
            icon = "d.circle.fill"
            title = NSLocalizedString("Transparent", comment: "Balance breakdown")
            balance = viewModel.coreBalanceFormatted
        case .platform:
            icon = "creditcard.fill"
            title = NSLocalizedString("Platform", comment: "Dash Platform chain")
            balance = viewModel.platformCreditsFormatted
        case .shielded:
            icon = "shield.fill"
            title = NSLocalizedString("Shielded", comment: "")
            balance = viewModel.shieldedBalanceFormatted
        }
        return TransferSourceRow(
            iconSystemName: icon,
            caption: NSLocalizedString("From", comment: ""),
            title: title,
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(balance),
            selected: viewModel.source == network,
            action: { viewModel.source = network })
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
                .foregroundColor(.primaryText)
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
        .background(Color.primaryBackground)
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
                .foregroundColor(.secondaryText)
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
                .foregroundColor(.primaryText)

            DashAmount(
                amount: dashDuffs,
                font: .title,
                dashSymbolFactor: 0.7,
                showDirection: false)

            Text(fiatText)
                .font(.subheadline)
                .foregroundColor(.secondaryText)

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
            .fill(Color(red: 0.83, green: 0.83, blue: 0.85))
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
                    .foregroundColor(.secondaryText)
                Spacer()
                Text(truncateMiddle(destinationAddress))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.primaryText)
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
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private var fromLabel: String {
        switch route {
        case .platformToPlatform, .platformToCore:
            return NSLocalizedString("Platform balance", comment: "The Dash Platform credits balance")
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
            return NSLocalizedString("Shielded balance", comment: "")
        case .coreToCore:
            return NSLocalizedString("Transparent balance", comment: "The transparent (Core) balance of the Dash Wallet")
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray300.opacity(0.3))
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
                    .fill(Color.dashBlue)
                    .frame(width: 30, height: 30)
                Image(systemName: infoIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(infoTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text(infoBody)
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.secondaryBackground)
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
        // Only shielded legs build an Orchard proof.
        switch route {
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
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
        coordinator.reset()
        confirm()
    }
}
