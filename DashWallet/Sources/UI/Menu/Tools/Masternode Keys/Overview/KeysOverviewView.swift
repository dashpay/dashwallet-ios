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

// MARK: - KeysOverviewContentView

struct KeysOverviewContentView: View {
    @StateObject private var viewModel = KeysOverviewViewModel()
    private let navigationController: UINavigationController?

    init(navigationController: UINavigationController? = nil) {
        self.navigationController = navigationController
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text(NSLocalizedString("Masternode keys", comment: ""))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(uiColor: .dw_label()))
                    .padding(.horizontal, 20)

                // Keys list container
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
                .background(Color(uiColor: .dw_background()))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(uiColor: .dw_secondaryBackground()))
    }

    private func handleItemTap(_ item: MNKey) {
        let derivationPath = viewModel.derivationPath(for: item)
        DSAuthenticationManager.sharedInstance().authenticate(
            withPrompt: nil,
            usingBiometricAuthentication: false,
            alertIfLockout: true
        ) { [weak navigationController] authenticated, _, _ in
            guard authenticated else { return }

            DispatchQueue.main.async {
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
            HStack(spacing: 0) {
                // Left side - key name and count
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundColor(Color(uiColor: .dw_label()))

                    Text(keyCountText)
                        .font(.footnote)
                        .foregroundColor(Color(uiColor: .dw_tertiaryText()))
                }

                Spacer()

                // Right side - used count + chevron
                HStack(spacing: 16) {
                    Text(usedCountText)
                        .font(.footnote)
                        .foregroundColor(Color(uiColor: .dw_label()))

                    Image("list-chevron-right")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 11)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(height: 62)
            .background(Color(uiColor: .dw_background()))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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
    KeysOverviewContentView()
}
