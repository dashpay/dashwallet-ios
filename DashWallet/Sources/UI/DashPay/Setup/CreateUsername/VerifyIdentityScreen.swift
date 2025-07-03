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

public struct VerifyIdentityScreen: View {
    @State private var link: String = ""
    @State private var showCopiedToast: Bool = false
    @State private var isInputError: Bool = false
    @State private var errorText: String = ""
    @State private var canContinue: Bool = false
    @State private var confirmUsernameRequest: Bool = false
    
    @StateObject var viewModel: CreateUsernameViewModel
    var onConfirmed: (URL?) -> Void
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("Verify your identity", comment: "Usernames"))
                    .font(.h5Bold)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .foregroundColor(.primaryText)
              
                Text(NSLocalizedString("The link you send will be visible only to the network owners", comment: "Usernames"))
                    .font(.body2)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .foregroundColor(.secondaryText)

                HStack(spacing: 0) {
                    let text = String.localizedStringWithFormat(NSLocalizedString("Please vote to approve my requested Dash username - %@", comment: "Usernames"), viewModel.username)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(NSLocalizedString("Copy text", comment: ""))
                            .font(.footnote)
                            .foregroundStyle(Color.secondaryText)
                        
                        Text(text)
                            .font(.body2)
                            .padding(.top, 2)
                    }
                    .padding(14)
                    
                    Spacer()
                    
                    Button(action: {
                        UIPasteboard.general.string = text
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showCopiedToast = false
                        }
                    }) {
                        Image("icon_copy_outline")
                            .foregroundStyle(Color.primaryText)
                            .frame(width: 40, height: 40)
                            .scaledToFit()
                    }
                    .padding(.trailing, 10)
                }
                .frame(maxWidth: .infinity)
                .background(Color.gray400.opacity(0.13))
                .cornerRadius(10)
                .padding(.vertical, 20)
                
                Text(NSLocalizedString("Prove your identity", comment: "Usernames"))
                    .font(.subtitle1)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .foregroundColor(.primaryText)
                    .padding(.top, 8)
              
                Text(NSLocalizedString("Make a post with the text above on a well known social media or messaging platform to verify that you are the original owner of the requested username and paste the link bellow", comment: "Usernames"))
                    .font(.body2)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .foregroundColor(.secondaryText)
                    .padding(.top, 1)
                
                TextInput(
                    label: NSLocalizedString("Paste link here", comment: "Usernames"),
                    text: $link,
                    isError: isInputError
                ).padding(.top, 7)
                
                if isInputError {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundColor(.systemRed)
                        .padding(.leading, 4)
                }
                
                Spacer()
                
                DashButton(
                    text: NSLocalizedString("Verify", comment: ""),
                    isEnabled: canContinue
                ) {
                    let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let url = URL(string: trimmed), url.scheme != nil {
                        onConfirmed(url)
                    } else {
                        isInputError = true
                        errorText = NSLocalizedString("Not a valid URL", comment: "Usernames")
                    }
                }
            }
            
            if showCopiedToast {
                ToastView(text: NSLocalizedString("Copied", comment: ""))
                    .padding(.bottom, 50)
            }
        }
        .padding()
        .onChange(of: link) { link in
            let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.count > 75 {
                isInputError = true
                errorText = NSLocalizedString("Maximum 75 characters", comment: "Usernames")
                canContinue = false
                return
            }
            
            isInputError = false
            errorText = ""
            canContinue = !trimmed.isEmpty
        }
    }
}
