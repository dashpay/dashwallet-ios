//
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

/// "What is username voting?" — the last page of the Join DashPay sheet, and
/// the destination of the info button on the Home row while a contested name
/// is being requested or voted on.
///
/// Same page template as `JoinDashPayScreen`: heading, a short lead, a column
/// of `SheetFeature` rows and one button. Nothing here is a navigation
/// destination — the sheet pages itself.
public struct VotingInfoScreen: View {
    /// The button. In the registration flow it moves on to the form; opened
    /// from the Home row as an explainer, it just closes the sheet.
    var action: () -> Void
    /// Button label, so the explainer can say "Close" where the flow says
    /// "Continue".
    var buttonLabel: String = NSLocalizedString("Continue", comment: "")

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(maxHeight: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("What is username voting?", comment: "Usernames"))
                    .dashFont(.title1)
                    .foregroundStyle(Color.dash.primaryText)
                    // The sheet cross-fades its pages inside a ZStack, which
                    // offers an ideal width first — without this the heading
                    // truncates instead of wrapping.
                    .fixedSize(horizontal: false, vertical: true)

                Text(NSLocalizedString("The Dash network has to vote to approve some usernames before they are created", comment: "Usernames"))
                    .dashFont(.body)
                    .foregroundStyle(Color.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 16) {
                SheetFeature(
                    title: NSLocalizedString("Voting is only required in some cases", comment: "Usernames"),
                    description: NSLocalizedString("Any username that has a number 2–9 or 20 or more characters will be automatically approved", comment: "Usernames"),
                    icon: DashIcon.Features.selectedList.source
                )
                SheetFeature(
                    title: NSLocalizedString("Some usernames can be blocked", comment: "Usernames"),
                    description: NSLocalizedString("If enough of the network determines that a username is inappropriate, they can block it", comment: "Usernames"),
                    icon: DashIcon.Features.usernameBlock.source
                )
                SheetFeature(
                    title: NSLocalizedString("Keep your passphrase safe", comment: "Usernames"),
                    description: NSLocalizedString("In case you lose your passphrase you will lose your right to your requested username", comment: "Usernames"),
                    icon: DashIcon.Features.recovery.source
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
            .padding(.bottom, 20)

            Spacer()
                .frame(maxHeight: 20)

            DashUIKit.DashButton(
                text: buttonLabel,
                fillsWidth: true,
                size: .large,
                style: .filledBlue,
                action: action
            )
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Previews

#if DEBUG

/// In the registration flow: the button carries the user on to the form.
#Preview("Voting info — in the flow") {
    VotingInfoScreen(action: {})
        .background(Color.dash.primaryBackground)
}

/// Opened as an explainer from the Home row, where there is nothing to
/// continue to.
#Preview("Voting info — explainer") {
    VotingInfoScreen(
        action: {},
        buttonLabel: NSLocalizedString("Close", comment: ""))
        .background(Color.dash.primaryBackground)
}

#endif
