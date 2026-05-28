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
        VStack(spacing: 20) {
            HStack {
                infoIcon

                Text(NSLocalizedString("Fees in crypto purchases", comment: "Maya"))
                    .font(.calloutMedium)
                    .foregroundColor(.primaryText)
                    .multilineTextAlignment(.center)
            }

            Text(NSLocalizedString(
                "Maya charges a fee to facilitate cross-chain swaps. It covers rewards to liquidity providers and estimated outbound network costs. The displayed amount is an estimate and may vary slightly at execution time.",
                comment: "Maya"
            ))
            .font(.subhead)
            .foregroundColor(.secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(3)

            Button {
                openURL(kMayaFeeDocsURL)
            } label: {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("Learn more", comment: "Maya"))
                        .font(.footnote)
                        .foregroundColor(.dashBlue)

                    Icon(name: .system("arrow.up.right"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.dashBlue)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var infoIcon: some View {
        ZStack {
            Circle()
                .fill(Color.dashBlue)
                .frame(width: 46, height: 46)

            Icon(name: .system("info"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
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
                let sheet = BottomSheet(showBackButton: .constant(false)) {
                        MayaFeeInfoSheet(onDismiss: {})
                    }

                if #available(iOS 16.0, *) {
                    sheet.presentationDetents([.height(300)])
                } else {
                    sheet
                }
            }
    }
}

#Preview("Bottom sheet") {
    MayaFeeInfoSheetPreviewHost()
}
#endif
