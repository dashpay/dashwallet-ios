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

struct MayaTransactionSuccessView: View {
    let message: String

    var body: some View {
        VStack(spacing: 24) {

            HStack {
                successIcon

                Text(NSLocalizedString("Conversion Submitted", comment: "Maya"))
                    .font(.title1)
                    .foregroundColor(.primaryText)
                    .multilineTextAlignment(.center)
            }

            Text(message)
                .font(.subhead)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

        }
    }

    private var successIcon: some View {
        ZStack {
            Circle()
                .fill(Color.dashBlue.opacity(0.1))
                .frame(width: 100, height: 100)

            Icon(name: .system("checkmark.circle.fill"))
                .frame(width: 56, height: 56)
                .foregroundColor(.dashBlue)
        }
    }
}

#if DEBUG
#Preview {
    MayaTransactionSuccessView(
        message: NSLocalizedString(
            "Your swap has been submitted to Maya Protocol. It may take a few minutes to complete.",
            comment: "Maya"
        )
    )
}

private struct MayaTransactionSuccessSheetPreviewHost: View {
    @State private var isPresented = true

    var body: some View {
        Color.primaryBackground
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                let sheet = BottomSheet(showBackButton: .constant(false)) {
                    MayaTransactionSuccessView(
                        message: NSLocalizedString(
                            "Your swap has been submitted to Maya Protocol. It may take a few minutes to complete.",
                            comment: "Maya"
                        )
                    )
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
    MayaTransactionSuccessSheetPreviewHost()
}
#endif
