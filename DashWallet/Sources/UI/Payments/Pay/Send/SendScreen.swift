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
    @State private var isEditingAddress = false

    /// The address is "locked" (shown as a truncated card) once a valid
    /// destination is decoded and focus has left the field; tapping it reopens
    /// the editable field.
    private var isAddressLocked: Bool {
        viewModel.destination != nil && !isEditingAddress && !addressFieldFocused
    }

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

    @ViewBuilder
    private var addressField: some View {
        if isAddressLocked {
            // Collapsed: a decoded address takes one line and gives the rest
            // of the screen back. `AddressFieldView` has no such state, so
            // the card stays here, with the label row it needs.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(NSLocalizedString("Address", comment: ""))
                        .dashFont(.footnote)
                        .foregroundStyle(Color.dash.gray500)
                    Spacer()
                    if let destination = viewModel.destination {
                        destinationBadge(destination)
                    }
                }
                lockedAddressCard
            }
            .padding(.horizontal, 20)
        } else {
            DashUIKit.AddressFieldView(
                text: $viewModel.addressText,
                label: NSLocalizedString("Address", comment: ""),
                placeholder: NSLocalizedString("Dash address", comment: "Send screen address placeholder"),
                hasError: addressErrorText != nil,
                errorText: addressErrorText,
                onScanQR: onScanQR,
                // No `onPaste`: the clipboard chip below already offers this,
                // and it shows WHICH address it would paste and what kind it
                // is — a bare Paste button would be the same action twice,
                // told less well.
            ) {
                if let destination = viewModel.destination {
                    destinationBadge(destination)
                }
            }
            .focused($addressFieldFocused)
            .padding(.horizontal, 20)
            .onAppear {
                // Rendered after tapping the locked card → put the cursor
                // straight back into the field.
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
                // The address just became valid (a paste, or the final typed
                // character) → lock in right away. Software-keyboard-less
                // setups (simulator with a hardware keyboard) never drop
                // focus on their own, so don't wait for that.
                if destination != nil {
                    addressFieldFocused = false
                    isEditingAddress = false
                }
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
