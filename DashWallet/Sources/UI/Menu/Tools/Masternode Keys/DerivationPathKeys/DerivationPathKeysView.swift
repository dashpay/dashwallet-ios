//
//  DerivationPathKeysView.swift
//  DashWallet
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

// MARK: - DerivationPathKeysViewModel

class DerivationPathKeysViewModel: ObservableObject {
    @Published var visibleIndexes: Int

    private let model: DerivationPathKeysModel

    init(model: DerivationPathKeysModel) {
        self.model = model
        visibleIndexes = model.visibleIndexes
    }

    var title: String { model.title }
    var infoItems: [DerivationPathInfo] { model.infoItems }
    var numberOfSections: Int { visibleIndexes + 1 }

    func showNextKey() {
        model.showNextKey()
        visibleIndexes = model.visibleIndexes
    }

    func usageInfo(at index: Int) -> String {
        model.usageInfoForKey(at: index)
    }

    func item(for info: DerivationPathInfo, at index: Int) -> DerivationPathKeysItem {
        model.itemForInfo(info, atIndex: index)
    }
}

// MARK: - DerivationPathKeysContentView

struct DerivationPathKeysContentView: View {
    @ObservedObject var viewModel: DerivationPathKeysViewModel
    let onBack: () -> Void
    @State private var copiedValue: String? = nil

    var body: some View {
        ZStack {
            Color(uiColor: .dw_secondaryBackground())
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                NavBarBackPlus(onBack: onBack) {
                    viewModel.showNextKey()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title
                        Text(viewModel.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Color(uiColor: .dw_label()))
                            .padding(.horizontal, 20)

                        // Keypair sections
                        ForEach(0..<viewModel.numberOfSections, id: \.self) { sectionIndex in
                            VStack(alignment: .leading, spacing: 16) {
                                // Section header: "Keypair N" + usage info
                                HStack {
                                    Text(NSLocalizedString("Keypair", comment: "") + " \(sectionIndex)")
                                        .font(.callout.weight(.semibold))
                                        .foregroundColor(Color(uiColor: .dw_label()))
                                    Spacer()
                                    Text(viewModel.usageInfo(at: sectionIndex))
                                        .font(.footnote)
                                        .foregroundColor(Color(uiColor: .dw_secondaryText()))
                                }
                                .padding(.horizontal, 20)

                                // Keys card
                                VStack(spacing: kMenuVGap) {
                                    ForEach(viewModel.infoItems, id: \.self) { info in
                                        let keyItem = viewModel.item(for: info, at: sectionIndex)
                                        KeyInfoRow(
                                            item: keyItem,
                                            isCopied: copiedValue == keyItem.value
                                        ) {
                                            guard !keyItem.value.isEmpty else { return }
                                            UIPasteboard.general.string = keyItem.value
                                            copiedValue = keyItem.value
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                                if copiedValue == keyItem.value {
                                                    copiedValue = nil
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(kMenuPadding)
                                .background(Color(uiColor: .dw_background()))
                                .clipShape(RoundedRectangle(cornerRadius: kMenuRadius, style: .continuous))
                                .padding(.horizontal, 20)
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - BackgroundBlurView

private struct BackgroundBlurView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// MARK: - KeyInfoRow

struct KeyInfoRow: View {
    let item: DerivationPathKeysItem
    let isCopied: Bool
    let onCopy: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.footnote)
                        .foregroundColor(Color(uiColor: .dw_secondaryText()))

                    Text(item.value)
                        .font(.subheadline)
                        .foregroundColor(Color(uiColor: .dw_label()))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                ZStack {
                    Color.clear
                        .frame(width: 40, height: 40)

                    Image("icon_copy_outline")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 13.6)
                        .foregroundColor(Color(uiColor: .dw_label()))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .dw_background()))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            Group {
                if isCopied {
                    Text(NSLocalizedString("Copied", comment: ""))
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(copiedBackground)
                        .foregroundColor(.whiteText)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        )
    }

    @ViewBuilder
    private var copiedBackground: some View {
        if colorScheme == .dark {
            ZStack {
                BackgroundBlurView()
                Color.whiteAlpha15
            }
        } else {
            Color.black.opacity(0.8)
        }
    }
}
