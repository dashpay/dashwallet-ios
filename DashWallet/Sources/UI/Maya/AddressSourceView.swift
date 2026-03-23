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
            HStack(spacing: 16) {
                icon
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(sourceType.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primaryText)

                        Spacer()

                        if isLoggedOut {
                            Text(NSLocalizedString("Log In", comment: "Maya"))
                                .font(.system(size: 14, weight: .medium))
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
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
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
            Image("maya.uphold.logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .coinbase:
            Image("maya.coinbase.logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state {
        case .available(let address):
            Text(address)
                .font(.system(size: 14))
                .foregroundColor(.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        case .notAvailable:
            Text(NSLocalizedString("Not available", comment: "Maya"))
                .font(.system(size: 14))
                .foregroundColor(.tertiaryText)
        case .loading:
            Text(NSLocalizedString("Loading...", comment: "Maya"))
                .font(.system(size: 14))
                .foregroundColor(.tertiaryText)
        case .loggedOut:
            EmptyView()
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

