//
//  Created by OpenAI Codex
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

struct CrowdNodeBalanceReminderSheet: View {
    var onWithdraw: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(dash: .custom("crowdnode.warning", bundle: .dashUIKit))
                .resizable()
                .scaledToFit()
                .frame(width: 90, height: 90)
                .padding(.top, 20)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .center)


            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("You have a balance on CrowdNode", comment: "CrowdNode"))
                    .font(Font.dash.title1)
                    .foregroundStyle(Color.dash.primaryText)
                    .multilineTextAlignment(.leading)

                Text(NSLocalizedString("These funds should be withdrawn from CrowdNode. You can transfer these funds to this wallet or via your online account on some other device.", comment: "CrowdNode"))
                    .font(Font.dash.subhead)
                    .foregroundStyle(Color.dash.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 40 + 20)
            .padding(.top, 20)
            .padding(.bottom, 32)


            VStack(alignment: .center, spacing: 16) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Withdraw funds", comment: "CrowdNode"),
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue,
                    action: onWithdraw
                )

                DashUIKit.DashButton(
                    text: NSLocalizedString("Close", comment: "CrowdNode"),
                    fillsWidth: true,
                    size: .large,
                    style: .tintedGray,
                    action: onDismiss
                )
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 20)
        }
    }
}

#Preview {
    CrowdNodeBalanceReminderSheet(
        onWithdraw: {},
        onDismiss: {}
    )
    .background(Color.dash.primaryBackground)
}

#Preview {
    Color.dash.primaryBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            // Use the lib's qualified factory: it sets `fillsHeight: false`, self-sizes to content,
            // and (via `cornerRadius`) fills the sheet background + rounds the corners. Being fully
            // qualified by type, it also avoids the ambiguity with the project's `selfSizingSheet`.
            // `fallback` avoids the `.medium` flash before the first measurement.
            DashUIKit.BottomSheet.selfSizing(
                showBackButton: .constant(false),
                fallback: 540,
                cornerRadius: 24
            ) {
                CrowdNodeBalanceReminderSheet(
                    onWithdraw: {},
                    onDismiss: {}
                )
            }
        }
}
