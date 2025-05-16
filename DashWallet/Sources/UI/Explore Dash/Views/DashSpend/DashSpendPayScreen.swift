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
import SDWebImageSwiftUI
import Foundation

struct DashSpendPayScreen: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel: DashSpendPayViewModel
    let merchant: ExplorePointOfUse
    @State var justAuthenticated: Bool
    
    init(merchant: ExplorePointOfUse, justAuthenticated: Bool = false) {
        self.merchant = merchant
        self._viewModel = .init(wrappedValue: DashSpendPayViewModel(merchant: merchant))
        self.justAuthenticated = justAuthenticated
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
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
                }
                .padding(.top, 5)
                .padding(.horizontal, 10)
                
                SendIntro(
                    title: NSLocalizedString("Buy gift card", comment: "DashSpend"),
                    preposition: NSLocalizedString("at", comment: "DashSpend"),
                    destination: viewModel.merchantTitle,
                    dashBalance: viewModel.isMixing ? viewModel.coinJoinBalance : viewModel.walletBalance,
                    balanceLabel: (viewModel.isMixing ? NSLocalizedString("Mixed balance", comment: "") : NSLocalizedString("Balance", comment: "")) + ":",
                    avatarView: {
                        WebImage(url: URL(string: viewModel.merchantIconUrl))
                            .resizable()
                            .indicator(.activity)
                            .transition(.fade(duration: 0.3))
                            .scaledToFit()
                            .clipShape(Circle())
                    }
                ).padding(.horizontal, 20)
                
                Spacer()
                
                Text(viewModel.currencySymbol + viewModel.input)
                    .font(.largeTitle)
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                
                HStack {
                    if viewModel.showLimits {
                        Text(viewModel.minimumLimit)
                            .font(.body2)
                            .foregroundColor(Color.primaryText)
                            .padding(.leading, 20)
                        Spacer()
                    }
                    
                    if let error = viewModel.error {
                        Text(error.localizedDescription)
                            .font(.body2)
                            .foregroundColor(Color.systemRed)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                    } else if viewModel.showCost {
                        Text(viewModel.costMessage)
                            .font(.body2)
                            .foregroundColor(Color.primaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                    }
                    
                    if viewModel.showLimits {
                        Spacer()
                        Text(viewModel.maximumimit)
                            .font(.body2)
                            .foregroundColor(Color.primaryText)
                            .padding(.trailing, 20)
                    }

                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 10)
                
                Spacer()
                
                NumericKeyboardView(
                    value: $viewModel.input,
                    showDecimalSeparator: true,
                    actionButtonText: NSLocalizedString("Preview", comment: ""),
                    actionHandler: {
    //                        viewModel.onContinue()
                    }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .background(Color.secondaryBackground)
                .cornerRadius(20)
            }
            
            if justAuthenticated {
                ToastView(
                    text: NSLocalizedString("Logged in to DashSpend account", comment: "DashSpend"),
                    icon: .system("checkmark.circle")
                )
                .frame(height: 20)
                .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .background(Color.primaryBackground)
        .onAppear {
            if justAuthenticated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    justAuthenticated = false
                }
            }
        }
        .onDisappear {
            viewModel.unsubscribeFromAll()
        }
    }
}
