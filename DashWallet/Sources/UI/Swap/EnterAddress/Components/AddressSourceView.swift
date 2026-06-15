//
//  AddressSourceView.swift
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

// MARK: - AddressSourceType

enum AddressSourceType: Identifiable {
    case uphold
    case coinbase
    case clipboard

    var id: String {
        switch self {
        case .uphold: return "uphold"
        case .coinbase: return "coinbase"
        case .clipboard: return "clipboard"
        }
    }

    var title: String {
        switch self {
        case .uphold: return "Uphold"
        case .coinbase: return "Coinbase"
        case .clipboard: return "Clipboard"
        }
    }
}

// MARK: - AddressSourceState

enum AddressSourceState {
    case loggedOut
    case loading
    case available(String)
    case notAvailable
}

// MARK: - AddressSourceView

/// A row in the "Paste address from" menu showing an exchange service or clipboard
/// with its address or login action.
struct AddressSourceView: View {
    let sourceType: AddressSourceType
    let state: AddressSourceState
    let onTap: () -> Void

    private var isLoggedOut: Bool {
        if case .loggedOut = state { return true }
        return false
    }

    private var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var body: some View {

        Group {
            if let subtitleText {
                MenuItem(
                    title: sourceType.title,
                    subtitleView: AnyView(
                        Text(subtitleText)
                            .font(.footnote)
                            .lineSpacing(4)
                            .foregroundColor(Color.tertiaryText)
                            .lineLimit(sourceType == .clipboard ? 2 : nil)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    ),
                    icon: iconName,
                    trailingView: trailingView,
                    action: onTap)
            } else {
                MenuItem(
                    title: sourceType.title,
                    icon: iconName,
                    trailingView: trailingView,
                    action: onTap)
            }
        }
        .disabled(isDisabled)
    }

    private var iconName: IconName {
        switch sourceType {
        case .uphold:
            .custom("menu-uphold")
        case .coinbase:
            .custom("menu-coinbase")
        case .clipboard:
            .custom("masternode-keys")
        }
    }

    private var subtitleText: String? {
        switch state {
        case .available(let address):
            address
        case .notAvailable:
            NSLocalizedString("Not available", comment: "Maya")
        case .loading:
            NSLocalizedString("Loading...", comment: "Maya")
        case .loggedOut:
            nil
        }
    }

    private var trailingView: AnyView? {
        switch state {
        case .loggedOut:
            AnyView(
                Text(NSLocalizedString("Log In", comment: "Maya"))
                    .font(.subheadMedium)
                    .foregroundColor(.dashBlue)
            )
        case .loading:
            AnyView(SwiftUI.ProgressView())
        case .available, .notAvailable:
            nil
        }
    }

    private var isDisabled: Bool {
        switch state {
        case .notAvailable, .loading:
            return true
        default:
            return false
        }
    }
}

#if DEBUG
#Preview("Logged Out") {
    VStack(spacing: 0) {
        AddressSourceView(sourceType: .uphold, state: .loggedOut, onTap: {})
        AddressSourceView(sourceType: .coinbase, state: .loggedOut, onTap: {})
            .background(.red.opacity(0.5))
    }
    .padding(6)
    .background(Color.red.opacity(0.3))
    .cornerRadius(12)
    .padding()
}

#Preview("Loading") {
    VStack(spacing: 0) {
        AddressSourceView(sourceType: .uphold, state: .loading, onTap: {})
        AddressSourceView(sourceType: .coinbase, state: .loading, onTap: {})
    }
    .padding(6)
    .background(Color.secondaryBackground)
    .cornerRadius(12)
    .padding()
}

#Preview("Available") {
    VStack(spacing: 0) {
        AddressSourceView(sourceType: .uphold, state: .available("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"), onTap: {})
        AddressSourceView(sourceType: .coinbase, state: .notAvailable, onTap: {})
    }
    .padding(6)
    .background(Color.secondaryBackground)
    .cornerRadius(12)
    .padding()
}
#endif
