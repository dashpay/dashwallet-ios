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
        static let hSpacing: CGFloat = 10
        static let lPadding: CGFloat = 16
        static let tPadding: CGFloat = 12
        static let vPadding: CGFloat = 12
        static let iconSize: CGFloat = 30
        static let minTapSize: CGFloat = 44
        static let cornerRadius: CGFloat = 16
        static let fontSize: CGFloat = 14
        static let errorBackgroundOpacity: Double = 0.05
        static let borderWidth: CGFloat = 1
    }

    @Binding var text: String
    let placeholder: String
    let hasError: Bool
    var onScanQR: (() -> Void)?

    var body: some View {
        HStack(spacing: Layout.hSpacing) {
            textField
            scanButton
        }
        .padding(.leading, Layout.lPadding)
        .padding(.trailing, Layout.tPadding)
        .padding(.vertical, Layout.vPadding)
        .background(backgroundColor)
        .clipShape(.rect(cornerRadius: Layout.cornerRadius))
    }

    // MARK: - Subviews

    @ViewBuilder private var textField: some View {
        if #available(iOS 17.0, *) {
            TextField(
                text: $text,
                prompt: Text(NSLocalizedString(placeholder, comment: "")).foregroundStyle(Color.black1000Alpha30)
            ) {
                EmptyView()
            }
            .autocapitalization(.none)
            .disableAutocorrection(true)
//            .focused($isFocused)
            .tint(.primaryText)
        } else {
            // Fallback on earlier versions
            TextField(NSLocalizedString(placeholder, comment: ""), text: $text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .foregroundColor(.primaryText)
//                .focused($isFocused)
                .tint(.primaryText)
        }
    }

    private var scanButton: some View {
        Button(action: { onScanQR?() }) {
            scanIcon
        }
        .accessibilityLabel(NSLocalizedString("Scan QR code", comment: "Maya"))
    }

    private var scanIcon: some View {
        Icon(name: .custom("scan-qr.accessory.icon", maxHeight: 15))
            .frame(width: Layout.iconSize, height: Layout.iconSize)
            .contentShape(.rect)
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        hasError
            ? Color.systemRed.opacity(Layout.errorBackgroundOpacity)
            : Color.gray400Alpha10
    }
}

#if DEBUG
#Preview("Empty") {
    AddressFieldView(
        text: .constant(""),
        placeholder: "BTC address",
        hasError: false,
        onScanQR: {}
    )
    .padding()
}

#Preview("With Text") {
    AddressFieldView(
        text: .constant("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"),
        placeholder: "BTC address",
        hasError: false,
        onScanQR: {}
    )
    .padding()
}

#Preview("Error") {
    AddressFieldView(
        text: .constant("invalid-address"),
        placeholder: "BTC address",
        hasError: true,
        onScanQR: {}
    )
    .padding()
}
#endif
