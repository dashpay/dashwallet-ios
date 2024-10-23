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

public struct VotingInfoScreen: View {
    var action: () -> Void
    
    public var body: some View {
        ZStack {
            TextIntro(
                buttonLabel: NSLocalizedString("Continue", comment: ""),
                action: action,
                inProgress: .constant(false),
                topText: {
                    FeatureTopText(
                        title: NSLocalizedString("What is username voting?", comment: "Usernames"),
                        text: NSLocalizedString("The Dash network has to vote to approve some usernames before they are created", comment: "Usernames")
                    )
                },
                features: {[
                    FeatureSingleItem(iconName: .custom("voting.list"), title: NSLocalizedString("Voting is only required in some cases", comment: "Usernames"), description: NSLocalizedString("Any username that has a number 2-9, is more than 20 characters or that has a hyphen will be automatically approved", comment: "Usernames")),
                    FeatureSingleItem(iconName: .custom("voting.blocked"), title: NSLocalizedString("Some usernames can be blocked", comment: "Usernames"), description: NSLocalizedString("If enough of the network feels that a username is inappropriate, they can block it", comment: "Usernames")),
                    FeatureSingleItem(iconName: .custom("icon.passphrase"), title: NSLocalizedString("Keep your passphrase safe", comment: "Usernames"), description: NSLocalizedString("In case you lose your passphrase you will lose your right to your requested username.", comment: "Usernames"))
                ]}
            )
        }
    }
}
