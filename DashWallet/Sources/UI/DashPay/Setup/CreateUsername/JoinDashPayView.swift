//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

enum JoinDashPayState {
    case none
    case callToAction
    case voting
    case approved
    case failed
    case blocked
    case contested
    case registered
}

extension JoinDashPayState {
    func hasAction() -> Bool {
        return self == .callToAction || self == .approved || self == .failed || self == .blocked || self == .contested
    }
}

struct JoinDashPayView: View {
    @StateObject var viewModel: JoinDashPayViewModel
    var onTap: (JoinDashPayState) -> Void
    var onActionButton: ((JoinDashPayState) -> Void)? = nil
    var onDismissButton: ((JoinDashPayState) -> Void)? = nil
    var onSizeChange: ((CGSize) -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(leadingIconName)
                    .padding(.horizontal, 10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.primaryText)
                        .multilineTextAlignment(.leading)
                    
                    if viewModel.state != .registered {
                        Text(subtitleText)
                            .font(.footnote)
                            .foregroundColor(.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if viewModel.state.hasAction() {
                ButtonsGroup(
                    orientation: .horizontal,
                    size: .small,
                    positiveButtonText: actionButtonText,
                    positiveButtonIcon: actionButtonIcon,
                    positiveButtonAction: {
                        onActionButton?(viewModel.state)
                    },
                    negativeButtonText: NSLocalizedString("Hide", comment: ""),
                    negativeButtonAction: {
                        onDismissButton?(viewModel.state)
                    }
                ).padding(.top, 15)
                 .padding(.trailing, 10)
            }
        }
        .padding(.vertical, 15)
        .padding(.leading, 15)
        .padding(.trailing, 5)
        .background(
            GeometryReader { geometry in
                onSizeChange?(geometry.size)
                return Color.secondaryBackground
            }
        )
        .cornerRadius(8)
        .shadow(color: .shadow, radius: 10, x: 0, y: 5)
        .onTapGesture {
            onTap(viewModel.state)
        }
        .onAppear {
            viewModel.checkUsername()
        }
    }
    
    private var leadingIconName: String {
        switch viewModel.state {
        case .none, .callToAction, .registered:
            return "dp_user_generic"
        case .voting:
            return "username_requested"
        case .approved:
            return "username_approved"
        default:
            return "username_rejected"
        }
    }
    
    private var titleText: String {
        switch viewModel.state {
        case .none:
            return NSLocalizedString("Join DashPay", comment: "")
        case .callToAction:
            return NSLocalizedString("Upgrade to DashPay", comment: "")
        case .voting, .registered:
            return viewModel.username
        case .approved:
            return NSLocalizedString("Your username has been successfully created", comment: "Usernames")
        case .failed:
            return NSLocalizedString("Username request failed", comment: "Usernames")
        case .blocked:
            return NSLocalizedString("Requested username has been blocked", comment: "Usernames")
        case .contested:
            return NSLocalizedString("Requested username has been given to someone else", comment: "Usernames")
        }
    }
    
    private var subtitleText: String {
        switch viewModel.state {
        case .none:
            return NSLocalizedString("Request your username", comment: "")
        case .callToAction:
            return NSLocalizedString("Request a username and say goodbye to numerical addresses", comment: "")
        case .voting:
            let endDate = Date(timeIntervalSince1970: VotingConstants.votingEndTime)
            let endDateStr = DWDateFormatter.sharedInstance.dateOnly(from: endDate)
            return String.localizedStringWithFormat(NSLocalizedString("Username %@ has been requested on the Dash network. After the voting ends (%@) we will notify you about its results", comment: "Usernames"), viewModel.username, endDateStr)
        case .approved:
            return NSLocalizedString("Get started by setting up your profile picture and other information.", comment: "Usernames")
        case .failed:
            return String.localizedStringWithFormat(NSLocalizedString("For some reason, the request for the username '%@' has failed.", comment: "Usernames"), viewModel.username)
        case .blocked:
            return String.localizedStringWithFormat(NSLocalizedString("The username '%@' was blocked by the Dash Network. Please try again by requesting another username.", comment: "Usernames"), viewModel.username)
        case .contested:
            return String.localizedStringWithFormat(NSLocalizedString("Due to the voting process, the Dash Network has decided to assign the username '%@' to someone else. Please try again by requesting another username.", comment: "Usernames"), viewModel.username)
        case .registered:
            return ""
        }
    }
    
    private var actionButtonText: String {
        switch viewModel.state {
        case .callToAction:
            return NSLocalizedString("Upgrade", comment: "")
        case .approved:
            return NSLocalizedString("Edit profile", comment: "")
        default:
            return NSLocalizedString("Retry", comment: "")
        }
    }
    
    private var actionButtonIcon: IconName? {
        switch viewModel.state {
        case .failed, .blocked, .contested:
            return .system("arrow.counterclockwise")
        default:
            return nil
        }
    }
}
