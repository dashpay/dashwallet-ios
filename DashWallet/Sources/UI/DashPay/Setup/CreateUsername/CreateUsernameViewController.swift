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
    @objc var completionHandler: ((Bool) -> ())?
    
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

        let content = CreateUsernameView(dashPayModel: dashPayModel) {
            self.navigationController?.popViewController(animated: true)
            self.completionHandler?(true)
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
    @FocusState private var isTextInputFocused: Bool
    @State private var inProgress: Bool = false
    var finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("Create your username", comment: "Usernames"))
                .foregroundColor(.primaryText)
                .font(.title1)
                .padding(.top, 12)
            Text(NSLocalizedString("Please note that you will not be able to change it in future", comment: "Usernames"))
                .foregroundColor(.primaryText)
                .font(.system(size: 14))
            TextInput(label: "Username", text: $viewModel.username)
                .padding(.top, 20)
                .focused($isTextInputFocused)
                
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
            
            Spacer()
            
            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                isEnabled: viewModel.uiState.canContinue,
                isLoading: inProgress
            ) {
                // `viewModel.uiState.canContinue` is only true after
                // `checkIfBlocked` flips `usernameBlockedRule` to
                // `.valid`, so the button is gated on the same condition
                // — no `if .valid` check needed here.
                Task {
                    inProgress = true
                    let result = await viewModel.submitUsernameRequest(withProve: nil, dashPayModel: dashPayModel)
                    inProgress = false

                    if result {
                        finish()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            isTextInputFocused = true
        }
    }

    private func getMessageForBlockedRule() -> String {
        // After PR 2.5 the only rule state the user ever sees here is
        // `.valid` (set by `CreateUsernameViewModel.checkIfBlocked`);
        // `.loading` shows briefly before that. The `.warning`,
        // `.invalid`, `.invalidCritical` rule states no longer fire
        // because the SDK v1 doesn't surface contested-username or
        // already-taken checks in the SwiftUI form's pipeline.
        switch viewModel.uiState.usernameBlockedRule {
        case .loading:
            return ""
        default:
            return NSLocalizedString("Username is available", comment: "Usernames")
        }
    }
}
