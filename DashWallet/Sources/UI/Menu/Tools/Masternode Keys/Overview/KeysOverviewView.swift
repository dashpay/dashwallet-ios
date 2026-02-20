//
//  KeysOverviewView.swift
//  DashWallet
//
//  SwiftUI version of the Masternode Keys overview page
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
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
import UIKit

struct KeysOverviewView: View {
    @StateObject private var viewModel = KeysOverviewViewModel()
    @Environment(\.presentationMode) var presentationMode
    private let navigationController: UINavigationController?

    init(navigationController: UINavigationController? = nil) {
        self.navigationController = navigationController
    }

    var body: some View {
        ZStack {
            Color.secondaryBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                // Navigation bar with back button
                NavBarBack {
                    presentationMode.wrappedValue.dismiss()
                }

                // Title
                Text("Masternode Keys")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // Keys list
                VStack(spacing: kMenuVGap) {
                    ForEach(viewModel.items, id: \.self) { item in
                        KeyItemButton(
                            item: item,
                            count: viewModel.keyCount(for: item),
                            used: viewModel.usedCount(for: item)
                        ) {
                            handleItemTap(item)
                        }
                    }
                }
                .padding(kMenuPadding)
                .background {
                    Color.background
                }
                .cornerRadius(kMenuRadius)
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }

    private func handleItemTap(_ item: MNKey) {
        // Authenticate before showing keys
        DSAuthenticationManager.sharedInstance().authenticate(
            withPrompt: nil,
            usingBiometricAuthentication: false,
            alertIfLockout: true
        ) { [weak navigationController] authenticated, _, _ in
            guard authenticated else { return }

            DispatchQueue.main.async {
                let derivationPath = viewModel.derivationPath(for: item)
                let vc = DerivationPathKeysViewController(with: item, derivationPath: derivationPath)
                vc.hidesBottomBarWhenPushed = true
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
}

// MARK: - KeyItemButton

struct KeyItemButton: View {
    let item: MNKey
    let count: Int
    let used: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Left side - key name and count
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundColor(.primaryText)

                    Text(keyCountText)
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }

                Spacer()

                // Right side - used count
                Text(usedCountText)
                    .font(.footnote)
                    .foregroundColor(.tertiaryText)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(height: 62)
            .background {
                Color.background
            }
            .cornerRadius(14)
        }
    }

    private var keyCountText: String {
        String(format: NSLocalizedString("%d key(s)", comment: "#bc-ignore!"), count)
    }

    private var usedCountText: String {
        String(format: NSLocalizedString("%ld used(s)", comment: "#bc-ignore!"), used)
    }
}

// MARK: - KeysOverviewViewModel

class KeysOverviewViewModel: ObservableObject {
    @Published var items: [MNKey] = MNKey.allCases

    private let model: WalletKeysOverviewModel

    init() {
        model = WalletKeysOverviewModel()
    }

    func keyCount(for type: MNKey) -> Int {
        model.keyCount(for: type)
    }

    func usedCount(for type: MNKey) -> Int {
        model.usedCount(for: type)
    }

    func derivationPath(for type: MNKey) -> DSAuthenticationKeysDerivationPath {
        model.derivationPath(for: type)
    }
}

// MARK: - MNKey Identifiable

extension MNKey: Identifiable {
    var id: Self { self }
}

// MARK: - Preview

#Preview {
    KeysOverviewView()
}
