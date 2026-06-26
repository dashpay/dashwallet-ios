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

struct CrowdNodeBalanceReminderBanner: View {
    var onWithdraw: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(dash: .custom("warning_triangle", bundle: .dashUIKit))
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("You have a balance on CrowdNode", comment: "CrowdNode"))
                        .font(Font.dash.subheadMedium)
                        .foregroundColor(Color.dash.primaryText)

                    Text(NSLocalizedString("These funds should be withdrawn from CrowdNode. You can transfer these funds to this wallet or via your online account on some other device.", comment: "CrowdNode"))
                        .font(Font.dash.subhead)
                        .foregroundColor(Color.dash.secondaryText)
                        .multilineTextAlignment(.leading)
                }

                DashUIKit.DashButton(
                    text: NSLocalizedString("Withdraw funds", comment: "CrowdNode"),
                    size: .small,
                    style: .filledBlue,
                    action: onWithdraw
                )
            }
            .padding(.trailing, 20)
            .padding(.top, 5)
        }
        .padding(16)
        .background(Color.dash.gray300Alpha10)
        .clipShape(.rect(cornerRadius: 20))
    }
}

#Preview {
    CrowdNodeBalanceReminderBanner(onWithdraw: {})
        .padding(20)
        .background(Color.dash.primaryBackground)
}
