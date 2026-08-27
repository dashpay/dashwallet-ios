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

public struct JoinDashPayScreen: View {
    @StateObject private var viewModel = CreateUsernameViewModel.shared
    @State private var navigateToVotingInfo = false
    var action: () -> Void
    /// Non-nil renders the "Have an invitation?" entry — the
    /// install-then-paste redeem path for invited users (DIP-13).
    var onClaimInvitation: (() -> Void)? = nil

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TextIntro(
                    buttonLabel: NSLocalizedString("Continue", comment: ""),
                    action: { navigateToVotingInfo = true },
                    // A transparent balance is no longer a hard precondition:
                    // the shielded route starts with ADDING funds (via the
                    // get-ready checklist after Continue), so the button only
                    // stays disabled while the wallet hasn't hydrated yet.
                    isActionEnabled: viewModel.hasMinimumRequiredBalance || viewModel.shieldedReadiness != nil,
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
                        FeatureSingleItem(iconName: .custom("profile.personalized"), title: NSLocalizedString("Personalise profile", comment: ""), description: NSLocalizedString("Upload your picture, personalize your identity.", comment: "")),
                        FeatureSingleItem(iconName: .system("shield.lefthalf.filled"), title: NSLocalizedString("Private by design", comment: "Usernames"), description: NSLocalizedString("Fund your username from your Shielded balance. Add funds a few hours ahead — the short rest keeps your username unlinkable to your other Dash.", comment: "Usernames"))
                    ]},
                    info: getInfo()
                )

                if let onClaimInvitation {
                    Button(action: onClaimInvitation) {
                        Text(NSLocalizedString("Have an invitation?", comment: "DashPay Invitations"))
                            .font(.subheadline)
                            .foregroundColor(.dash.blue)
                    }
                    .padding(.bottom, 12)
                }
            }

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

        if viewModel.hasReadyShieldedFunding {
            // No transparent balance, but the shielded route is fully
            // ready — nothing to warn about.
            return nil
        }

        let shieldedMinimum = (ShieldedIdentityFundingReadiness.standardDenominationCredits / 1_000)
            .dashAmount.formattedDashAmountWithoutCurrencySymbol
        return String.localizedStringWithFormat(
            NSLocalizedString("Registering privately takes at least %@ Dash in your Shielded balance plus a few hours of rest time — the next screens walk you through it.", comment: "Usernames"),
            shieldedMinimum)
    }
}
