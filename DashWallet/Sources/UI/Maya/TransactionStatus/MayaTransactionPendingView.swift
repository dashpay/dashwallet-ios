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

struct MayaTransactionPendingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            LoadingIllustration()
                .padding(.bottom, 30)


            VStack(spacing: 6) {
                Text(NSLocalizedString("Conversion in progress", comment: "Maya"))
                    .font(.title1)
                    .foregroundColor(.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subhead)
                    .foregroundColor(.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 60)

            Spacer()
        }
    }
}

#if DEBUG
#Preview {
    MayaTransactionPendingView(
        message: NSLocalizedString(
            "Waiting for block confirmation. Maya swaps require one Dash block (~2–5 min) before the swap begins.",
            comment: "Maya"
        )
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.primaryBackground)
}
#endif
