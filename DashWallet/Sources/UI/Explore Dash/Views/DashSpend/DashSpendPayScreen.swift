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

struct DashSpendPayScreen: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel: DashSpendPayViewModel
    let merchant: ExplorePointOfUse
    @State var justAuthenticated: Bool
    @State var showConfirmToast: Bool
    @State private var showConfirmationDialog = false
    @State private var showErrorDialog = false
    @State private var errorMessage = ""
    @State private var errorTitle = ""
    
    init(merchant: ExplorePointOfUse, justAuthenticated: Bool = false) {
        self.merchant = merchant
        self._viewModel = .init(wrappedValue: DashSpendPayViewModel(merchant: merchant))
        self.justAuthenticated = justAuthenticated
        self.showConfirmToast = false
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
                        Text(viewModel.minimumLimitMessage)
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
                        Text(viewModel.maximumLimitMessage)
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
                    actionEnabled: viewModel.error == nil && !viewModel.showLimits && !viewModel.isLoading,
                    inProgress: viewModel.isProcessingPayment,
                    actionHandler: {
                        if !viewModel.isUserSignedIn() {
                            showSignInError()
                            return
                        }
                        
                        showConfirmationDialog = true
                    }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .background(Color.secondaryBackground)
                .cornerRadius(20)
            }
            
            if justAuthenticated {
                ToastView(
                    text: NSLocalizedString("Logged in to DashSpend account", comment: "DashSpend"),
                    icon: .system("checkmark.circle")
                )
                .frame(height: 20)
                .padding(.bottom, 30)
            }
            
            if showConfirmToast {
                ToastView(
                    text: NSLocalizedString("Gift card purchase successful", comment: "DashSpend")
                )
                .frame(height: 20)
                .padding(.bottom, 30)
            }
            
            if showErrorDialog {
                ModalDialog(
                    style: .error,
                    icon: .system("exclamationmark.triangle.fill"),
                    heading: errorTitle,
                    textBlock1: errorMessage,
                    positiveButtonText: NSLocalizedString("OK", comment: ""),
                    positiveButtonAction: {
                        showErrorDialog = false
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.7))
                .edgesIgnoringSafeArea(.all)
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .background(Color.primaryBackground)
        .onAppear {
            viewModel.subscribeToUpdates()
            
            if justAuthenticated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    justAuthenticated = false
                }
            }
        }
        .onDisappear {
            viewModel.unsubscribeFromAll()
        }
        .sheet(isPresented: $showConfirmationDialog) {
            let dialog = BottomSheet(
                title: NSLocalizedString("Confirm", comment: "DashSpend"),
                showBackButton: Binding<Bool>.constant(false)
            ) {
                DashSpendConfirmationDialog(
                    amount: viewModel.input,
                    merchantName: viewModel.merchantTitle,
                    merchantIconUrl: viewModel.merchantIconUrl,
                    originalPrice: viewModel.amount,
                    discount: viewModel.savingsFraction,
                    onConfirm: {
                        showConfirmationDialog = false
                        purchaseGiftCard()
                    },
                    onCancel: {
                        showConfirmationDialog = false
                    }
                )
            }.background(Color.primaryBackground)
            
            if #available(iOS 16.0, *) {
                dialog.presentationDetents([.height(500)])
            } else {
                dialog
            }
        }
    }
    
    private func purchaseGiftCard() {
        Task {
            do {
                try await viewModel.purchaseGiftCardAndPay()
                
                // Close the confirmation dialog and show success toast
                showConfirmationDialog = false
                showConfirmToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showConfirmToast = false
                    presentationMode.wrappedValue.dismiss()
                }
            } catch let error as CTXSpendError {
                // Close the confirmation dialog and show error
                showConfirmationDialog = false
                errorTitle = NSLocalizedString("Purchase Failed", comment: "DashSpend")
                errorMessage = error.localizedDescription
                showErrorDialog = true
                
                DSLogger.log("Gift card purchase failed with CTXSpendError: \(error)")
            } catch {
                // Close the confirmation dialog and show error
                showConfirmationDialog = false
                errorTitle = NSLocalizedString("Error", comment: "")
                errorMessage = error.localizedDescription
                showErrorDialog = true
                
                DSLogger.log("Gift card purchase failed with error: \(error)")
            }
        }
    }
    
    private func showSignInError() {
        errorTitle = NSLocalizedString("Sign in required", comment: "Alert title")
        errorMessage = NSLocalizedString("You need to sign in to DashSpend to purchase gift cards.", comment: "DashSpend")
        showErrorDialog = true
    }
}
