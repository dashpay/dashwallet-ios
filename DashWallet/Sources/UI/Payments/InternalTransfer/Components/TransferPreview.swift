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
import DashUIKit

/// "You will transfer ~ N" under the form, shown once the amount is valid.
///
/// Takes the formatted string rather than an amount: the view model owns the
/// formatting, and this draws what it is given.
struct TransferPreview: View {
    let amountFormatted: String

    var body: some View {
        VStack(spacing: 2) {
            Text(NSLocalizedString("You will transfer", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(Color.dash.secondaryText)
            HStack(spacing: 4) {
                Text("~ \(amountFormatted)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Image("icon_dash_currency")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 13, height: 13)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG

private func transferPreviewSample(_ amount: String) -> some View {
    TransferPreview(amountFormatted: amount)
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview {
    transferPreviewSample("0.0125")
}

/// Full 8-digit precision — the amount and the Dash glyph stay centred as one
/// unit rather than the glyph being pushed off the trailing edge.
@available(iOS 17, *)
#Preview("Full precision") {
    transferPreviewSample("123.45678901")
}

@available(iOS 17, *)
#Preview("Dark") {
    transferPreviewSample("0.0125")
        .preferredColorScheme(.dark)
}

@available(iOS 17, *)
#Preview("Large type") {
    transferPreviewSample("0.0125")
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
