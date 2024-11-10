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

import UIKit
import SwiftUI

class CreateUsernameViewController: UIViewController {
    private let dashPayModel: DWDashPayProtocol
    
    @objc
    init(dashPayModel: DWDashPayProtocol, invitationURL: URL?, definedUsername: String?) {
        // TODO: invites
        self.dashPayModel = dashPayModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.dw_secondaryBackground()

        let content = CreateUsernameView(dashPayModel: dashPayModel) { dialog in
            self.showModalDialog(dialog: dialog)
        } dismissDialog: {
            self.dismiss(animated: true)
        }
        let swiftUIController = UIHostingController(rootView: content)
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        self.dw_embedChild(swiftUIController)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.applyOpaqueAppearance(with: UIColor.dw_secondaryBackground(), shadowColor: .clear)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

struct CreateUsernameView: View {
    @State var dashPayModel: DWDashPayProtocol
    @StateObject private var viewModel = CreateUsernameViewModel()
    @State private var showVotingInfo: Bool = false
    var showVerifyDialog: (any View) -> Void
    var dismissDialog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("Create your username", comment: "Usernames"))
                .foregroundColor(.primaryText)
                .font(.h5Bold)
                .padding(.top, 12)
            Text(NSLocalizedString("Please note that you will not be able to change it in future", comment: "Usernames"))
                .foregroundColor(.primaryText)
                .font(.system(size: 14))
            TextInput(label: "Username", text: $viewModel.username)
                .padding(.top, 20)
                
            if viewModel.uiState.lengthRule != .hidden {
                ValidationCheck(
                    validationResult: viewModel.uiState.lengthRule,
                    text: NSLocalizedString("Between 3 and 23 characters", comment: "Usernames")
                ).padding(.top, 20)
            }
            
            if viewModel.uiState.allowedCharactersRule != .hidden {
                ValidationCheck(
                    validationResult: viewModel.uiState.allowedCharactersRule,
                    text: NSLocalizedString("Letter, numbers and hyphens only", comment: "Usernames")
                ).padding(.top, 20)
            }
            
            if viewModel.uiState.costRule != .hidden {
                ValidationCheck(
                    validationResult: viewModel.uiState.costRule,
                    text: String.localizedStringWithFormat(NSLocalizedString("You need to have more %@ Dash to create this username", comment: "Usernames"), viewModel.uiState.requiredDash.dashAmount.formattedDashAmountWithoutCurrencySymbol)
                ).padding(.top, 20)
            }
            
            if viewModel.uiState.usernameBlockedRule != .hidden {
                ValidationCheck(
                    validationResult: viewModel.uiState.usernameBlockedRule,
                    text: getMessageForBlockedRule()
                ).padding(.top, 20)
            }
            
            if viewModel.uiState.usernameBlockedRule == .warning {
                DashButton(
                    text: NSLocalizedString("What is username voting?", comment: "Usernames"),
                    leadingIcon: .system("plus"),
                    style: .plain,
                    size: .small,
                    stretch: false
                ) {
                    showVotingInfo = true
                }
                .overrideForegroundColor(.dashBlue)
                .padding(.leading, 12)
                .padding(.top, 4)
            }
            
            Spacer()
            
            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                isEnabled: viewModel.uiState.canContinue
            ) {
                if viewModel.uiState.usernameBlockedRule == .valid {
//                    dashPayModel.createUsername(username, invitation: invitationURL) TODO
                } else {
                    showVerifyDialog(getVerifyDialog())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showVotingInfo) {
            let dialog = BottomSheet(showBackButton: Binding<Bool>.constant(false)) {
                VotingInfoScreen {
                    showVotingInfo = false
                }
            }
            
            if #available(iOS 16.0, *) {
                dialog.presentationDetents([.height(600)])
            } else {
                dialog
            }
        }
    }
    
    @ViewBuilder
    private func getVerifyDialog() -> some View {
        ModalDialog(
            heading: NSLocalizedString("Verify your identity to enhance your chances of getting your requested username", comment: "Usernames"),
            textBlock1: NSLocalizedString("If somebody else requests the same username as you, we will let the network decide whom to give this username", comment: "Usernames"),
            positiveButtonText: NSLocalizedString("Verify", comment: ""),
            positiveButtonAction: {
                dismissDialog()
            },
            negativeButtonText: NSLocalizedString("Skip", comment: ""),
            negativeButtonAction: {
                dismissDialog()
//                    dashPayModel.createUsername(username, invitation: invitationURL) TODO
            },
            buttonsOrientation: .horizontal
        )
    }
    
    private func getMessageForBlockedRule() -> String {
        switch viewModel.uiState.usernameBlockedRule {
        case .invalid:
            return NSLocalizedString("This username is blocked by the Dash Network", comment: "Usernames")
        case .invalidCritical:
            return NSLocalizedString("This username is already created by someone else", comment: "Usernames")
        case .warning:
            return NSLocalizedString("The Dash network will vote on this username. We will notify you of the results on March 14, 2024.", comment: "Usernames") // TODO: date
        case .loading:
            return ""
        default:
            return NSLocalizedString("Username is available", comment: "Usernames")
        }
    }
}
