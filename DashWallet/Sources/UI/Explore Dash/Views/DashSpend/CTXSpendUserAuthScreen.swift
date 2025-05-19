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
import Combine

enum CTXSpendUserAuthType {
    case createAccount
    case signIn
    case otp
    
    var screenTitle: String {
        switch self {
        case .createAccount:
            return NSLocalizedString("Create account", comment: "DashSpend")
        case .signIn:
            return NSLocalizedString("Log in to your account", comment: "DashSpend")
        case .otp:
            return NSLocalizedString("Enter verification code", comment: "DashSpend")
        }
    }
    
    var screenSubtitle: String {
        switch self {
        case .createAccount:
            return NSLocalizedString("Your email is only used to send a one-time password.", comment: "DashSpend")
        case .signIn:
            return NSLocalizedString("Your email is only used to send a one-time password.", comment: "DashSpend")
        case .otp:
            return NSLocalizedString("Check your email and enter the verification code.", comment: "DashSpend")
        }
    }
    
    var textInputHint: String {
        switch self {
        case .createAccount, .signIn:
            return NSLocalizedString("Email", comment: "DashSpend")
        case .otp:
            return NSLocalizedString("Password", comment: "DashSpend")
        }
    }
}

struct CTXSpendUserAuthScreen: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel = CTXSpendUserAuthViewModel()
    @FocusState private var isTextFieldFocused: Bool
    @State private var navigateToOtp: Bool = false
    
    let authType: CTXSpendUserAuthType
    let onAuthSuccess: () -> Void
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primaryText)
                                .padding(10)
                        }
                        
                        Spacer()
                        
                        Text("DashSpend")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primaryText)
                            .frame(maxWidth: .infinity)
                        
                        Spacer()
                        
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.top, 5)
                    .padding(.horizontal, 10)
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authType.screenTitle)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primaryText)
                            
                            Text(authType.screenSubtitle)
                                .font(.system(size: 13))
                                .foregroundColor(.primaryText)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 20)
                        
                        VStack(spacing: 4) {
                            TextInput(
                                label: authType.textInputHint,
                                text: $viewModel.input,
                                keyboardType: .emailAddress,
                                autocapitalization: .never,
                                isEnabled: authType != .otp,
                                onSubmit: {
                                    viewModel.onContinue()
                                }
                            ).focused($isTextFieldFocused)
                            
                            if viewModel.showError {
                                Text(viewModel.errorMessage)
                                    .font(.footnote)
                                    .foregroundColor(.systemRed)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 10)
                }
                
                Spacer()
                
                VStack {
                    if authType == .otp {
                        NumericKeyboardView(
                            value: $viewModel.input,
                            showDecimalSeparator: false,
                            actionButtonText: NSLocalizedString("Continue", comment: ""),
                            actionEnabled: true,
                            actionHandler: {
                                viewModel.onContinue()
                            }
                        ).frame(maxWidth: .infinity)
                         .frame(height: 320)
                         .padding(.horizontal, 20)
                         .padding(.bottom, 20)
                    } else {
                        ZStack(alignment: .center) {
                            DashButton(
                                text: viewModel.isLoading ? "" : NSLocalizedString("Continue", comment: "Continue"),
                                isEnabled: viewModel.isInputValid(authType: authType)
                            ) {
                                if !viewModel.isLoading {
                                    viewModel.onContinue()
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            if viewModel.isLoading {
                                SwiftUI.ProgressView()
                                    .tint(.white)
                            }
                        }
                    }
                }
                .padding(.bottom, authType == .otp ? 0 : 20)
            }
            
            NavigationLink(
                destination: CTXSpendUserAuthScreen(
                    authType: .otp,
                    onAuthSuccess: onAuthSuccess
                ).navigationBarHidden(true),
                isActive: $navigateToOtp
            ) {
                EmptyView()
            }
        }
        .background(Color.secondaryBackground)
        .onAppear {
            viewModel.setup(screenType: authType)
            
            if authType != .otp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            } else {
                isTextFieldFocused = false
            }
        }
        .onChange(of: viewModel.screenType) { newValue in
            if newValue != authType && newValue == .otp {
                navigateToOtp = true
            }
        }
        .onChange(of: viewModel.isUserSignedIn) { isSignedIn in
            if (isSignedIn && authType == .otp) {
                presentationMode.wrappedValue.dismiss()
                onAuthSuccess()
            }
        }
    }
}

// TODO: toast should be on the buy screen
