//
//  Created by Dash Core Group
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

/// The first screen without a wallet: the Dash logo over the photo, then
/// Create a New Wallet and Recover Wallet.
///
/// The logo starts in the middle of the screen, where the launch screen has
/// it, and rises to the middle of the space above the buttons.
struct SetupView: View {
    /// Rise without animating: setup follows onboarding, not the launch screen.
    let skipsLogoAnimation: Bool
    let onCreate: () -> Void
    let onRecover: () -> Void

    @State private var isLogoSettled = false

    private static let buttonsHeight: CGFloat = 54 + 8 + 54 + 4

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let buttonsTop = height - proxy.safeAreaInsets.bottom - Self.buttonsHeight

            ZStack(alignment: .bottom) {
                Image("logo_with_tag")
                    .accessibilityLabel(String(localized: "Dash. Your money, your way.", comment: "Setup logo, VoiceOver"))
                    .position(x: proxy.size.width / 2,
                              y: (isLogoSettled ? buttonsTop / 2 : height / 2) - proxy.safeAreaInsets.top)

                VStack(spacing: 8) {
                    Button(String(localized: "Create a New Wallet", comment: ""), action: onCreate)
                        .buttonStyle(SetupActionButtonStyle())
                    Button(String(localized: "Recover Wallet", comment: ""), action: onRecover)
                        .buttonStyle(SetupTextButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
        .background {
            Color.clear
                .overlay {
                    Image("image_bg")
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .onAppear {
            guard !isLogoSettled else { return }
            withAnimation(skipsLogoAnimation ? nil : .easeInOut(duration: 0.25)) {
                isLogoSettled = true
            }
        }
    }
}
