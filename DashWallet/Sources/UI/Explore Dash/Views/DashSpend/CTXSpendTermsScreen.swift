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

struct CTXSpendTermsScreen: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var isTermsAccepted: Bool = false
    @State private var hasViewedTerms: Bool = false
    @State private var shouldShakeLink: Bool = false
    @State private var navigateToCreateAccount: Bool = false
    
    let onAuthSuccess: () -> Void
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primaryText)
                            .padding(10)
                    }
                }
                .padding(.top, 5)
                .padding(.horizontal, 10)
                
                TextIntro(
                    icon: .custom("dashspend.logo", maxHeight: 32),
                    inProgress: Binding.constant(false)
                ) {
                    FeatureTopText(
                        title: NSLocalizedString("Accept terms and\nconditions", comment: "DashSpend"),
                        label: NSLocalizedString("Terms & conditions", comment: "Terms & conditions"),
                        labelIcon: .custom("external.link"),
                        linkAction: {
                            UIApplication.shared.open(URL(string: CTXConstants.ctxGiftCardAgreementUrl)!, options: [:], completionHandler: nil)
                            hasViewedTerms = true
                            shouldShakeLink = false
                        },
                        shakeLabel: shouldShakeLink
                    )
                }
                .padding(.top, 20)
                
                Spacer()
                
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ZStack {
                            if isTermsAccepted {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.dashBlue)
                                    .frame(width: 22, height: 22)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.gray300, lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        
                        Text(NSLocalizedString("I accept DashSpend terms and conditions", comment: "Accept terms checkbox"))
                            .font(.system(size: 14))
                            .foregroundColor(.primaryText)
                            
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .onTapGesture {
                        if !hasViewedTerms {
                            shouldShakeLink = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                shouldShakeLink = true
                            }
                        } else {
                            isTermsAccepted.toggle()
                        }
                    }
                    
                    DashButton(
                        text: NSLocalizedString("Create account", comment: "Create account"),
                        isEnabled: isTermsAccepted,
                        action: {
                            navigateToCreateAccount = true
                        }
                    )
                }
                .padding(20)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .edgesIgnoringSafeArea(.top)
        
        NavigationLink(
            destination: CTXSpendUserAuthScreen(
                authType: .createAccount,
                onAuthSuccess: onAuthSuccess
            ).navigationBarHidden(true),
            isActive: $navigateToCreateAccount
        ) {
            EmptyView()
        }
    }
}
