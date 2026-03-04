//
//  Created by Assistant
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

struct ImportPrivateKeySheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    let onScanPrivateKey: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Grabber
            Capsule()
                .fill(colorScheme == .dark ? Color.whiteAlpha20 : Color.gray300Alpha50)
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 6)

            // Close button
            HStack {
                Spacer()

                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(colorScheme == .dark ? "icon-close-sheet-white" : "icon-close-sheet")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 9, height: 9)
                        .foregroundColor(Color.primaryText)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(Color.gray300.opacity(0.3), lineWidth: 1.5)
                        )
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 64)
            .background(Color.secondaryBackground)

            // Content
            VStack(spacing: 0) {
                // Icon
                Image("image.import.private.key.large")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 94, height: 100)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                // Text content
                VStack(spacing: 6) {
                    Text(NSLocalizedString("Import private key", comment: ""))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(NSLocalizedString("This action will move all coins from the Dash paper wallet to your DashPay app on this device.", comment: ""))
                        .font(.system(size: 15))
                        .foregroundColor(Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }

            Spacer()

            // Button wrap with fixed padding
            VStack(spacing: 0) {
                DashButton(
                    text: NSLocalizedString("Scan private key", comment: ""),
                    style: .filledBlue,
                    size: .large,
                    stretch: true,
                    isEnabled: true,
                    action: {
                        presentationMode.wrappedValue.dismiss()
                        onScanPrivateKey()
                    }
                )
                .padding(.horizontal, 60)
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .background(Color.secondaryBackground)
    }
}

struct ImportPrivateKeySheet_Previews: PreviewProvider {
    static var previews: some View {
        ImportPrivateKeySheet(onScanPrivateKey: {})
    }
}
