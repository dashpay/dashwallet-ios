//
//  SendScreen.swift
//  DashWallet
//
//  Step one of the external send: the recipient address, whose form decides the destination type.
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
//            if showsHeader {
//                header
//                    .padding(.horizontal, 20)
//                    .padding(.top, 10)
//            }

            ScrollView {
                VStack(spacing: 14) {
                    addressField
                        .padding(.top, 12)

                    if let suggestion = viewModel.clipboardSuggestion,
                       suggestion.address != viewModel.trimmedAddress {
                        clipboardChip(for: suggestion)
                    }

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

//    // MARK: - Header
//
//    private var header: some View {
//        HStack {
//            Button(action: onClose) {
//                Image(systemName: "xmark")
//                    .font(.system(size: 16, weight: .medium))
//                    .foregroundColor(Color.dash.primaryText)
//                    .frame(width: 36, height: 36)
//                    .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
//            }
//            Spacer()
//            Text(NSLocalizedString("Send", comment: ""))
//                .font(.headline)
//                .foregroundColor(.dash.primaryText)
//            Spacer()
//            Color.clear.frame(width: 36, height: 36)
//        }
//    }

    // MARK: - Address

    private var addressField: some View {
        DashUIKit.AddressFieldView(
            text: $viewModel.addressText,
            label: NSLocalizedString("Address", comment: ""),
            placeholder: NSLocalizedString("Dash address", comment: "Send screen address placeholder"),
            hasError: addressErrorText != nil,
            errorText: addressErrorText,
            onScanQR: onScanQR,
            // No `onPaste`: the clipboard chip below already offers this, and
            // it shows WHICH address it would paste and what kind it is — a
            // bare Paste button would be the same action twice, told less
            // well.
        ) {
            if let destination = viewModel.destination {
                destinationBadge(destination)
            }
        }
        .focused($addressFieldFocused)
        .padding(.horizontal, 20)
        .onChange(of: viewModel.destination) { _, destination in
            // The address just became valid (a paste, or the final typed
            // character) → drop the keyboard so Continue is reachable without
            // a second tap. Software-keyboard-less setups (a simulator with a
            // hardware keyboard) never lose focus on their own, so don't wait
            // for that.
            if destination != nil {
                addressFieldFocused = false
            }
        }
    }

    /// Whichever refusal applies, in the one slot the field has for it.
    private var addressErrorText: String? {
        if viewModel.showsInvalidAddress {
            return NSLocalizedString("This is not a valid Dash address for this network", comment: "Send screen")
        }
        if viewModel.pinnedSourceMismatch {
            return String(
                format: NSLocalizedString("This address can't be paid from your %@ balance", comment: "Send sheet source/destination mismatch"),
                viewModel.pinnedSourceTitle)
        }
        return nil
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

}

#if DEBUG

/// Seeded model, nothing wired — see `SendViewModel.preview`. The production
/// initializer subscribes to the sync monitor and two balance publishers, all
/// live singletons a canvas must not start.
#Preview("Empty") {
    SendScreen(viewModel: .preview(), onClose: {}, onScanQR: {}, onContinue: {})
        .background(Color.dash.primaryBackground)
}

/// A decoded address collapses the field into the summary card.
#Preview("Transparent address") {
    SendScreen(
        viewModel: .preview(
            address: "yV1D1ivvSUyKPJnbFmzSTVh1MyZ3JbeVkY",
            destination: .core),
        onClose: {}, onScanQR: {}, onContinue: {})
        .background(Color.dash.primaryBackground)
}

#Preview("Still syncing") {
    SendScreen(
        viewModel: .preview(isChainSynced: false),
        onClose: {}, onScanQR: {}, onContinue: {})
        .background(Color.dash.primaryBackground)
}

/// Embedded under a host that draws its own chrome — the balance-row sheet.
#Preview("No header") {
    SendScreen(
        viewModel: .preview(), onClose: {}, onScanQR: {}, onContinue: {},
        showsHeader: false)
        .background(Color.dash.primaryBackground)
}

#endif
