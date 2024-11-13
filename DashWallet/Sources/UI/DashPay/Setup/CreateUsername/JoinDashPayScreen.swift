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

public struct JoinDashPayScreen: View {
    @StateObject private var viewModel = CreateUsernameViewModel.shared
    @State private var navigateToVotingInfo = false
    var action: () -> Void
    
    public var body: some View {
        ZStack {
            TextIntro(
                buttonLabel: NSLocalizedString("Continue", comment: ""),
                action: { navigateToVotingInfo = true },
                isActionEnabled: viewModel.hasMinimumRequiredBalance,
                inProgress: .constant(false),
                topText: {
                    FeatureTopText(
                        title: NSLocalizedString("Join DashPay", comment: ""),
                        text: NSLocalizedString("Forget about long crypto addresses, create the username, find friends and add them to your contacts", comment: "")
                    )
                },
                features: {[
                    FeatureSingleItem(iconName: .custom("username.letter"), title: NSLocalizedString("Create a username", comment: ""), description: NSLocalizedString("Pay to usernames. No more alphanumeric addresses.", comment: "")),
                    FeatureSingleItem(iconName: .custom("friends.add"), title: NSLocalizedString("Add your friends & family", comment: ""), description: NSLocalizedString("Invite your family, find your friends by searching their usernames.", comment: "")),
                    FeatureSingleItem(iconName: .custom("profile.personalized"), title: NSLocalizedString("Personalise profile", comment: ""), description: NSLocalizedString("Upload your picture, personalize your identity.", comment: ""))
                ]},
                info: getInfo()
            )

            NavigationLink(
                destination: VotingInfoScreen(action: action).navigationBarHidden(true),
                isActive: $navigateToVotingInfo
            ) {
                EmptyView()
            }
        }
    }
    
    private func getInfo() -> String? {
        if viewModel.hasRecommendedBalance {
            return nil
        }
        
        if viewModel.hasMinimumRequiredBalance {
            return String.localizedStringWithFormat(NSLocalizedString("You have %@ Dash.\nSome usernames cost up to %@ Dash.", comment: "Usernames"), viewModel.balance, viewModel.recommendedBalance)
        }
        
        return String.localizedStringWithFormat(NSLocalizedString("You need to have more than %@ Dash to create a username", comment: "Usernames"), viewModel.minimumRequiredBalance)
    }
}
