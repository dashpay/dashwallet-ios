//
//  Created by Roman Chornyi
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

private let kMayaFeeDocsURL = URL(string: "https://docs.mayaprotocol.com/how-it-works/fees")!

struct MayaFeeInfoSheet: View {
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Fees in crypto purchases", comment: "Maya"))
                    .font(Font.title1)
                    .foregroundColor(.primaryText)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Text(NSLocalizedString(
                    "In addition to the displayed Maya fee, we include a spread in the price. \nCryptocurrency markets are volatile, and this allows us to temporary lock in a price for trade execution.",
                    comment: "Maya"
                ))
                .font(Font.body)
                .foregroundStyle(Color.gray500)
                .multilineTextAlignment(.leading)
            }
            .padding(.top, 20)
            .padding(.bottom, 32)
            .padding(.horizontal, 60)

            VStack(alignment: .leading, spacing: 16) {
                // Opens the Maya fee docs in the system browser via @Environment(\.openURL).
                // Assumption: https://docs.mayaprotocol.com/how-it-works/fees is the correct URL.
                // Using openURL (system Safari) rather than SFSafariViewController because the
                // sheet has no UIViewController context for modal presentation.
                DashButton(text: NSLocalizedString("Learn more", comment: "Maya")) {
                    openURL(kMayaFeeDocsURL)
                }

                DashButton(text: NSLocalizedString("Close", comment: "Maya")) {
                    onDismiss()
                }
                .overrideBackgroundColor(Color.gray300Alpha10)
                .overrideForegroundColor(Color.black)
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 20)
        }
    }
}

#if DEBUG
#Preview("Standalone") {
    MayaFeeInfoSheet(onDismiss: {})
        .background(Color.secondaryBackground)
}

private struct MayaFeeInfoSheetPreviewHost: View {
    @State private var isPresented = true

    var body: some View {
        Color.primaryBackground
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
//                let sheet = BottomSheet(showBackButton: .constant(false)) {
//                        MayaFeeInfoSheet(onDismiss: {})
//                    }
//
//                if #available(iOS 16.0, *) {
//                    sheet.presentationDetents([.height(450)])
//                } else {
//                    sheet
//                }

                BottomSheet(showBackButton: .constant(false), fillsHeight: false) {
                    MayaFeeInfoSheet(onDismiss: {})
                }
                .selfSizingSheet()
            }
    }
}

#Preview("Bottom sheet") {
    MayaFeeInfoSheetPreviewHost()
}
#endif
