//
//  FundingLimitsInfoSheet.swift
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

import DashUIKit
import SwiftUI

/// What an identity funding limit is: the identity's own balance, which
/// connected apps spend from.
struct FundingLimitsInfoSheet: View {
    let onClose: () -> Void

    /// The text's natural height: the scroll view takes no more than this,
    /// so the sheet sizes to its content (`selfSizingSheet`) and scrolls only
    /// when the text is taller than the sheet can be.
    @State private var textHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("What are identity funding limits?", comment: "DashConnect connection sheet"))
                    .dashFont(.title2)
                    .foregroundColor(Color.dash.primaryText)
                Text(NSLocalizedString(
                    "Your identity has its own balance, separate from the Dash on your wallet's home screen.",
                    comment: "DashConnect: what identity funding limits are"))
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.primaryText)
                Text(NSLocalizedString(
                    "It pays for actions on the Dash network, like updating your profile or using connected apps.",
                    comment: "DashConnect: what identity funding limits are"))
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.primaryText)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: textHeight)

            DashUIKit.DashButton(
                text: NSLocalizedString("Got it", comment: "DashConnect"),
                fillsWidth: true, size: .large, style: .tintedGray, action: onClose)
                .padding(.horizontal, 40)
                .padding(.vertical, 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dash.secondaryBackground)
    }
}

#Preview("Info") {
    FundingLimitsInfoSheet(onClose: {})
        .background(Color.dash.secondaryBackground)
}
