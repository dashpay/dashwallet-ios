//
//  AddressFieldView.swift
//  DashWallet
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

import SwiftUI

struct AddressFieldView: View {

    private enum Layout {
        static let hSpacing: CGFloat = 20
        static let lPadding: CGFloat = 20
        static let tPadding: CGFloat = 10
        static let iconSize: CGFloat = 17
        static let cornerRadius: CGFloat = 16
        static let actionTapArea: CGFloat = 40
    }

    @Binding var text: String
    let label: String
    let placeholder: String
    let hasError: Bool
    let errorText: String?
    var isDisabled: Bool = false
    var onScanQR: (() -> Void)?

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.gray500)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: Layout.hSpacing) {
                textField
                    .padding(.vertical, 15)

                if !isDisabled {
                    // In the blurred-filled state (text present, unfocused, no error) the trailing
                    // icon stays in the layout so the field width — and the address text wrapping —
                    // doesn't shift between focused and unfocused. Per design it's just hidden:
                    // opacity 0 and non-interactive, but the space is reserved.
                    actionButton
                        .opacity(isBlurredFilledState ? 0 : 1)
                        .allowsHitTesting(!isBlurredFilledState)
                }
            }
            .padding(.leading, Layout.lPadding)
            .padding(.trailing, Layout.tPadding)
            .background(backgroundColor)
            .clipShape(.rect(cornerRadius: Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Color(UIColor(red: 0.92, green: 0.22, blue: 0.26, alpha: 1)))
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder private var textField: some View {
        if #available(iOS 17.0, *) {
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).font(.subhead).foregroundStyle(Color.black1000Alpha30),
                axis: .vertical
            )
            .lineLimit(1...3) // cap growth at 3 lines; longer addresses scroll inside the field
            .font(.subhead)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .foregroundStyle(Color.primaryText)
            .tint(.primaryText)
            .focused($isTextFieldFocused)
            .disabled(isDisabled)
        } else {
            TextField(placeholder, text: $text)
                .font(.subhead)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .foregroundStyle(Color.primaryText)
                .tint(.primaryText)
                .focused($isTextFieldFocused)
                .disabled(isDisabled)
        }
    }

    private var actionButton: some View {
        Group {
            if text.isEmpty {
                Button(action: { onScanQR?() }) {
                    Icon(name: .custom("qr", maxHeight: Layout.iconSize))
                        .frame(width: Layout.iconSize, height: Layout.iconSize)
                }
                .accessibilityLabel(NSLocalizedString("Scan QR code", comment: "Maya"))
            } else {
                Button(action: { text = "" }) {
                    Image("text-field-clear")
                        .renderingMode(.template)
                        .foregroundStyle(Color(uiColor: UIColor(red: 0.14, green: 0.12, blue: 0.13, alpha: 1)))
                        .frame(width: 11, height: 11)
                }
                .accessibilityLabel(NSLocalizedString("Clear address", comment: "Maya"))
            }
        }
        .frame(width: Layout.actionTapArea, height: Layout.actionTapArea)
        .contentShape(.rect)
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        if isFocusedState {
            return .clear
        }

        if hasError {
            return Color(UIColor(red: 0.92, green: 0.22, blue: 0.26, alpha: 0.05))
        }

        if isFilledState {
            return Color.gray300Alpha10
        }

        return Color.gray300Alpha10
    }

    private var borderColor: Color {
        isFocusedState ? .gray300Alpha40 : .clear
    }

    private var borderWidth: CGFloat {
        isFocusedState ? 1 : 0
    }

    private var isFocusedState: Bool {
        isTextFieldFocused && !isDisabled
    }

    private var isFilledState: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFocusedState
    }

    /// Field is unfocused ("tapped outside"), has text, and has no error — a clean read-out state
    /// with no editing affordance (the trailing action button is suppressed).
    /// `isFilledState` already implies `!isFocusedState` and non-empty text.
    private var isBlurredFilledState: Bool {
        isFilledState && !hasError && !isDisabled
    }
}

#if DEBUG
#Preview("Empty") {
    AddressFieldView(
        text: .constant(""),
        label: "Destination address",
        placeholder: "BTC address",
        hasError: false, errorText: nil,
        onScanQR: {}
    )
    .padding()
}

#Preview("With Text") {
    AddressFieldView(
        text: .constant("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"),
        label: "Destination address",
        placeholder: "BTC address",
        hasError: false, errorText: nil,
        onScanQR: {}
    )
    .padding()
}

#Preview("Multiline") {
    AddressFieldView(
        text: .constant("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh\nbc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"),
        label: "Destination address",
        placeholder: "BTC address",
        hasError: false, errorText: nil,
        onScanQR: {}
    )
    .padding()
}

#Preview("Error") {
    AddressFieldView(
        text: .constant("invalid-address"),
        label: "Destination address",
        placeholder: "BTC address",
        hasError: true, errorText: "Error text",
        onScanQR: {}
    )
    .padding()
}

#Preview("Filled") {
    AddressFieldView(
        text: .constant("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"),
        label: "Destination address",
        placeholder: "BTC address",
        hasError: false, errorText: nil,
        onScanQR: {}
    )
    .padding()
}

// Blurred + filled (no error): unfocused with text → clean read-out on gray300Alpha10 in
// primaryText, with NO trailing QR/clear button.
#Preview("Blurred + filled (no action button)") {
    AddressFieldView(
        text: .constant("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"),
        label: "Destination address",
        placeholder: "BTC address",
        hasError: false, errorText: nil,
        onScanQR: {}
    )
    .padding()
}
#endif
