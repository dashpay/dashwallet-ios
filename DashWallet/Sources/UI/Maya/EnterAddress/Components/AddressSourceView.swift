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

    var id: String {
        switch self {
        case .uphold: return "uphold"
        case .coinbase: return "coinbase"
        }
    }

    var title: String {
        switch self {
        case .uphold: return "Uphold"
        case .coinbase: return "Coinbase"
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
        Button(action: onTap, label: {
            HStack(spacing: 10) {
                icon

                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(sourceType.title)
                            .font(Font.subheadMedium)
                            .foregroundColor(Color.gray500)

                        Spacer()

                        if isLoggedOut {
                            Text(NSLocalizedString("Log In", comment: "Maya"))
                                .font(Font.subheadMedium)
                                .foregroundColor(.dashBlue)
                        }
                    }

                    subtitle
                }

                Spacer()

                if isLoading {
                    loadingIndicator
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        })
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    // MARK: - Subviews

    private var loadingIndicator: some View {
        SwiftUI.ProgressView()
    }

    @ViewBuilder
    private var icon: some View {
        switch sourceType {
        case .uphold:
            Icon(name: .custom("maya.uphold.logo"))
                .frame(width: 30, height: 30)
        case .coinbase:
            Icon(name: .custom("maya.coinbase.logo"))
                .frame(width: 30, height: 30)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        Group {
            switch state {
            case .available(let address):
                Text(address)
            case .notAvailable:
                Text(NSLocalizedString("Not available", comment: "Maya"))
            case .loading:
                Text(NSLocalizedString("Loading...", comment: "Maya"))
            case .loggedOut:
                EmptyView()
            }
        }
        .font(Font.footnote)
        .foregroundColor(.tertiaryText)
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
    }
    .padding(6)
    .background(Color.secondaryBackground)
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

