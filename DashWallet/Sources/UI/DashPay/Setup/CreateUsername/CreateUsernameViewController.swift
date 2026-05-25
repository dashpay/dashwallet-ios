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
    /// Funding source for the SwiftDashSDK identity registration. Defaults
    /// to Core; auto-pinned to Platform when only PP credits are available;
    /// user-selectable via the segmented picker when both sources have enough.
    /// Written into `DWIdentityRegistrationBridge.shared.preferredFundingSource`
    /// in the Continue handler right before the submit call.
    @State private var fundingSource: DWIdentityFundingSource = .core
    /// Tracks the contested-name confirmation alert. Continue routes
    /// through this alert (instead of submitting directly) when the
    /// typed name is contested-eligible — `viewModel.isContestedCandidate`.
    @State private var showContestedConfirmation: Bool = false
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

            // Contested-name warning. Shown when the typed label is
            // ≤19 chars + only [a-zA-Z0-9-] AND otherwise passes the
            // local validators. Submitting a contested name triggers
            // masternode voting (~45 min testnet, ~2 weeks mainnet)
            // before the name is actually claimed — the user gets a
            // separate confirmation alert on Continue. Mirrors the
            // example app's `RegisterNameView.swift:277-293` styling.
            if viewModel.isContestedCandidate {
                contestedNameWarning
                    .padding(.top, 20)
            }

            // Funding source picker. Visible only when both Core and
            // Platform Payment have enough balance to cover the
            // identity-registration cost. When only one source is
            // viable, the picker stays hidden and `fundingSource` is
            // auto-pinned by `.onChange` so the Continue handler
            // routes correctly without UI clutter.
            if viewModel.hasMinimumRequiredCoreBalance && viewModel.hasMinimumRequiredPlatformBalance {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Pay with", comment: "Usernames"))
                        .foregroundColor(.secondaryText)
                        .font(.caption)
                    Picker("", selection: $fundingSource) {
                        Text("Core (\(viewModel.balance) Dash)").tag(DWIdentityFundingSource.core)
                        Text("Platform (\(viewModel.platformPaymentBalance) Dash)").tag(DWIdentityFundingSource.platformPayment)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.top, 20)
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
                //
                // Contested-name submissions go through a confirmation
                // alert first so the user explicitly acknowledges the
                // ~45 min testnet / ~2 weeks mainnet voting wait and
                // the locked Dash. Non-contested names submit directly.
                if viewModel.isContestedCandidate {
                    showContestedConfirmation = true
                } else {
                    performSubmit()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            isTextInputFocused = true
            // Seed the picker selection so a wallet with only one
            // viable source (typical case) doesn't default to a
            // non-viable Core path.
            syncFundingSourceToViableSource()
        }
        .onChange(of: viewModel.hasMinimumRequiredCoreBalance) { _ in
            syncFundingSourceToViableSource()
        }
        .onChange(of: viewModel.hasMinimumRequiredPlatformBalance) { _ in
            syncFundingSourceToViableSource()
        }
        .alert(
            NSLocalizedString("Contested name", comment: "Usernames"),
            isPresented: $showContestedConfirmation
        ) {
            Button(NSLocalizedString("Submit anyway", comment: "Usernames"), role: .destructive) {
                performSubmit()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString(
                "This name requires voting. Your Dash will be locked until voting completes.",
                comment: "Usernames"))
        }
    }

    /// Orange warning callout shown above the Continue button when
    /// the typed name is contested-eligible. Styled to match the
    /// example app's `RegisterNameView.swift:277-293`.
    private var contestedNameWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Contested name", comment: "Usernames"))
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                Text(NSLocalizedString(
                    "This name requires a masternode vote.",
                    comment: "Usernames"))
                    .font(.caption)
                    .foregroundColor(.secondaryText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Encapsulates the submit-to-bridge dance so both the direct
    /// Continue path and the contested-name alert's "Submit anyway"
    /// button can share the code. Writes the funding-source pick
    /// into the bridge right before submit. The bridge resets to
    /// `.core` on every terminal phase, so a stale picker value
    /// can't leak into a future attempt; this single write is the
    /// only synchronization needed.
    private func performSubmit() {
        DWIdentityRegistrationBridge.shared.preferredFundingSource = fundingSource
        Task {
            inProgress = true
            let result = await viewModel.submitUsernameRequest(withProve: nil, dashPayModel: dashPayModel)
            inProgress = false

            if result {
                finish()
            }
        }
    }

    /// Keep `fundingSource` pointing at a viable source when only one
    /// of {Core, Platform} qualifies. When both qualify we leave the
    /// selection alone so the picker preserves the user's pick.
    private func syncFundingSourceToViableSource() {
        let coreOk = viewModel.hasMinimumRequiredCoreBalance
        let platformOk = viewModel.hasMinimumRequiredPlatformBalance
        if coreOk && !platformOk {
            fundingSource = .core
        } else if platformOk && !coreOk {
            fundingSource = .platformPayment
        }
        // Otherwise (both viable, or neither): leave `fundingSource`
        // alone. With neither viable, the Continue button is disabled
        // anyway; with both viable, the picker is shown and the user
        // makes the call.
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
