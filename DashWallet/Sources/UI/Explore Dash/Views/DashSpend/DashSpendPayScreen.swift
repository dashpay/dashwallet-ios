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
                    actionEnabled: viewModel.error == nil && !viewModel.showLimits && !viewModel.isLoading,
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
                title: NSLocalizedString("Confirm", comment: "DashSpend confirmation dialog title"),
                showBackButton: Binding<Bool>.constant(false)
            ) {
                ConfirmationDialog(
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
                // Show spinner/activity indicator could be added here
                
                let response = try await viewModel.purchaseGiftCard()
                
                // Success! Show success message and log to console
                print("============ GIFT CARD PURCHASE SUCCESSFUL ============")
                print("Merchant: \(response.merchantName)")
                print("Amount: \(response.fiatCurrency) \(response.fiatAmount)")
                print("Dash Amount: \(response.dashAmount)")
                print("Dash Payment URL: \(response.dashPaymentUrl)")
                
                if let claimCode = response.claimCode {
                    print("Claim Code: \(claimCode)")
                }
                
                if let barcode = response.barcode {
                    print("Barcode: \(barcode)")
                    if let barcodeType = response.barcodeType {
                        print("Barcode Type: \(barcodeType)")
                    }
                }
                
                if let txid = response.txid {
                    print("Transaction ID: \(txid)")
                }
                
                print("Created At: \(response.createdAt)")
                print("Status: \(response.status)")
                print("====================================================")
                
                showConfirmToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showConfirmToast = false
                    // In a real implementation, we would navigate to a gift card details screen
                }
            } catch let error as CTXSpendError {
                errorTitle = NSLocalizedString("Purchase Failed", comment: "Alert title")
                errorMessage = error.localizedDescription
                showErrorDialog = true
                
                print("Gift card purchase failed with CTXSpendError: \(error)")
            } catch {
                errorTitle = NSLocalizedString("Error", comment: "Alert title")
                errorMessage = error.localizedDescription
                showErrorDialog = true
                
                print("Gift card purchase failed with error: \(error)")
            }
        }
    }
    
    private func showSignInError() {
        errorTitle = NSLocalizedString("Sign in required", comment: "Alert title")
        errorMessage = NSLocalizedString("You need to sign in to DashSpend to purchase gift cards.", comment: "DashSpend")
        showErrorDialog = true
    }
}

struct ConfirmationDialog: View {
    let amount: String
    let merchantName: String
    let merchantIconUrl: String
    let originalPrice: Decimal
    let discount: Decimal
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.presentationMode) private var presentationMode
    
    private let fiatFormatter = NumberFormatter.fiatFormatter(currencyCode: kDefaultCurrencyCode)
    
    var body: some View {
        VStack(spacing: 40) {
            HStack {
                Text(fiatFormatter.currencySymbol + amount)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.primaryText)
            }
                
            // Details
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(NSLocalizedString("From", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                        
                    Image("image.explore.dash.wts.dash")
                        .resizable()
                        .frame(width: 24, height: 24)
                            
                    Text(NSLocalizedString("Dash Wallet", comment: "DashSpend"))
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                    
                HStack(spacing: 8) {
                    Text(NSLocalizedString("To", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                        
                    WebImage(url: URL(string: merchantIconUrl))
                        .resizable()
                        .indicator(.activity)
                        .transition(.fade(duration: 0.3))
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                            
                    Text(merchantName)
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                    
                HStack {
                    Text(NSLocalizedString("Gift card total", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                        
                    Text(fiatFormatter.string(from: NSDecimalNumber(decimal: originalPrice)) ?? "")
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                    
                HStack {
                    Text(NSLocalizedString("Discount", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                        
                    Text("\(NSDecimalNumber(decimal: discount * 100).intValue)%")
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                    
                HStack {
                    Text(NSLocalizedString("You pay", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                        
                    Text(fiatFormatter.string(from: NSDecimalNumber(decimal: originalPrice * (1 - discount))) ?? "")
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
            }
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.shadow, radius: 10, x: 0, y: 5)
            
            HStack(spacing: 20) {
                Button(action: onCancel) {
                    Text(NSLocalizedString("Cancel", comment: "DashSpend"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .background(Color(UIColor.systemGray5))
                .cornerRadius(12)
                    
                Button(action: onConfirm) {
                    Text(NSLocalizedString("Confirm", comment: "DashSpend"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .background(Color.dashBlue)
                .cornerRadius(12)
            }
        }
        .padding(.top, 15)
        .padding(.horizontal, 20)
        .edgesIgnoringSafeArea(.bottom)
    }
}
