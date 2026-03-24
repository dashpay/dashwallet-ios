//
//  Created by Claude
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
import UIKit

struct ExtendedPublicKeysView: View {
    @StateObject private var viewModel = ExtendedPublicKeysViewModel()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            Color.secondaryBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                // Navigation bar
                NavBarBack {
                    presentationMode.wrappedValue.dismiss()
                }

                // Title
                Text("Extended Public Keys")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // Keys container with VStack
                VStack(spacing: kMenuVGap) {
                    ForEach(Array(viewModel.derivationPaths.enumerated()), id: \.offset) { index, item in
                        KeyItemView(item: item)
                    }
                }
                .padding(kMenuPadding)
                .background(Color.background)
                .cornerRadius(kMenuRadius)
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

struct KeyItemView: View {
    let item: DerivationPathKeysItem
    @State private var showCopiedMessage = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.footnote)
                    .foregroundColor(.tertiaryText)

                Text(item.value)
                    .font(.subheadline)
                    .foregroundColor(.primaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: {
                UIPasteboard.general.string = item.value
                showCopiedMessage = true

                // Hide message after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopiedMessage = false
                }
            }) {
                Image("icon_copy_outline")
                    .resizable()
                    .frame(width: 30, height: 30)
                    .foregroundColor(.primaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.background)
        .cornerRadius(14)
        .overlay(
            Group {
                if showCopiedMessage {
                    Text("Copied")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        )
    }
}

class ExtendedPublicKeysViewModel: ObservableObject {
    @Published var derivationPaths: [DerivationPathKeysItem] = []

    init() {
        loadKeys()
    }

    private func loadKeys() {
        let model = ExtendedPublicKeysModel()
        derivationPaths = model.derivationPaths.map { $0.item }
    }
}

#Preview {
    ExtendedPublicKeysView()
}
