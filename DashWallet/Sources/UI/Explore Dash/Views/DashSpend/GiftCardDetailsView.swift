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
import CoreImage.CIFilterBuiltins

struct GiftCardDetailsView: View {
    @StateObject private var viewModel: GiftCardDetailsViewModel
    @State private var showHowToUse = false
    @State private var navigationController: UINavigationController? = nil
    
    init(txId: Data) {
        _viewModel = StateObject(wrappedValue: GiftCardDetailsViewModel(txId: txId))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Merchant header
                HStack(spacing: 15) {
                    ZStack(alignment: .bottomTrailing) {
                        if let iconUrl = viewModel.merchantIconUrl {
                            WebImage(url: URL(string: iconUrl))
                                .resizable()
                                .indicator(.activity)
                                .transition(.fade(duration: 0.3))
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "gift.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .foregroundColor(.dashBlue)
                        }
                        
                        // Secondary icon
                        if viewModel.merchantIconUrl != nil {
                            Image(systemName: "gift.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.dashBlue)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.secondaryBackground))
                                .overlay(Circle().stroke(Color.secondaryBackground, lineWidth: 2))
                                .offset(x: 2, y: 2)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.merchantName)
                            .font(.body2)
                            .fontWeight(.medium)
                            .foregroundColor(.primaryText)
                        
                        if let date = viewModel.purchaseDate {
                            Text(date, formatter: dateFormatter)
                                .font(.footnote)
                                .foregroundColor(.tertiaryText)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 25)
                .padding(.top, 20)
                
                // Gift card info container
                VStack(spacing: 0) {
                    // Barcode section
                    if let barcodeImage = viewModel.barcodeImage {
                        Image(uiImage: barcodeImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 108)
                            .padding(.horizontal, 20)
                            .padding(.top, 15)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray)
                                .frame(height: 108)
                            
                            if viewModel.isLoadingCardDetails {
                                SwiftUI.ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else if viewModel.loadingError != nil {
                                Text(NSLocalizedString("Failed to load barcode", comment: ""))
                                    .font(.footnote)
                                    .foregroundColor(.systemRed)
                            } else {
                                Text(NSLocalizedString("Barcode placeholder", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.tertiaryText)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 15)
                    }
                    
                    // Original purchase value
                    HStack {
                        Text(NSLocalizedString("Original Purchase Value", comment: ""))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.tertiaryText)
                        
                        Spacer()
                        
                        Text(viewModel.formattedPrice)
                            .font(.caption)
                            .foregroundColor(.primaryText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Check current balance link
                    if viewModel.merchantUrl != nil {
                        Button(action: {
                            if let url = URL(string: viewModel.merchantUrl!) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text(NSLocalizedString("Check current balance", comment: ""))
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundColor(.dashBlue)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    
                    // Card number and PIN
                    if viewModel.isLoadingCardDetails {
                        SwiftUI.ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding(.vertical, 40)
                    } else if let error = viewModel.loadingError {
                        VStack(spacing: 10) {
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundColor(.systemRed)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 22) {
                            // Card number
                            if let cardNumber = viewModel.cardNumber {
                                HStack {
                                    Text(NSLocalizedString("Card Number", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.tertiaryText)
                                    
                                    Spacer()
                                    
                                    Text(cardNumber)
                                        .font(.caption)
                                        .foregroundColor(.primaryText)
                                    
                                    Button(action: {
                                        UIPasteboard.general.string = cardNumber
                                        // TODO: Show toast
                                    }) {
                                        Image("icon_copy_outline")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                            .foregroundColor(.dashBlue)
                                    }
                                    .frame(width: 32, height: 40)
                                }
                                .padding(.horizontal, 20)
                            }
                            
                            // Card PIN
                            if let cardPin = viewModel.cardPin {
                                HStack {
                                    Text(NSLocalizedString("Card PIN", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.tertiaryText)
                                    
                                    Spacer()
                                    
                                    Text(cardPin)
                                        .font(.caption)
                                        .foregroundColor(.primaryText)
                                    
                                    Button(action: {
                                        UIPasteboard.general.string = cardPin
                                        // TODO: Show toast
                                    }) {
                                        Image("icon_copy_outline")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                            .foregroundColor(.dashBlue)
                                    }
                                    .frame(width: 32, height: 40)
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 22)
                        .padding(.bottom, 15)
                    }
                }
                .background(Color.secondaryBackground)
                .cornerRadius(10)
                .padding(.horizontal, 15)
                .padding(.top, 20)
                
                // View transaction details button
                Button(action: {
                    navigateToTransactionDetails()
                }) {
                    HStack {
                        Text(NSLocalizedString("View transaction details", comment: ""))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primaryText)
                        
                        Spacer()
                        
                        Image("greyarrow")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 17)
                    .background(Color.dashBlue)
                    .cornerRadius(10)
                }
                .padding(.horizontal, 15)
                .padding(.top, 15)
                
                // How to use button
                if !showHowToUse {
                    Button(action: {
                        withAnimation {
                            showHowToUse = true
                        }
                        viewModel.logHowToUse()
                    }) {
                        Text(NSLocalizedString("See how to use this gift card", comment: ""))
                            .font(.body2)
                            .fontWeight(.medium)
                            .foregroundColor(.dashBlue)
                    }
                    .padding(.top, 20)
                } else {
                    // How to use expanded content
                    VStack(alignment: .leading, spacing: 30) {
                        Text(NSLocalizedString("How to use your gift card", comment: ""))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 20)
                        
                        // Self-checkout
                        HStack(alignment: .top, spacing: 25) {
                            Image(systemName: "qrcode")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.dashBlue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Self-checkout", comment: ""))
                                    .font(.subtitle1)
                                    .foregroundColor(.primaryText)
                                
                                Text(NSLocalizedString("Request assistance and show the barcode on your screen for scanning.", comment: ""))
                                    .font(.body2)
                                    .foregroundColor(.tertiaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        // In store
                        HStack(alignment: .top, spacing: 25) {
                            Image(systemName: "storefront")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.dashBlue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("In store", comment: ""))
                                    .font(.subtitle1)
                                    .foregroundColor(.primaryText)
                                
                                Text(NSLocalizedString("Tell the cashier that you'd like to pay with a gift card and share the card number and pin.", comment: ""))
                                    .font(.body2)
                                    .foregroundColor(.tertiaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        // Online
                        HStack(alignment: .top, spacing: 25) {
                            Image(systemName: "globe")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.dashBlue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Online", comment: ""))
                                    .font(.subtitle1)
                                    .foregroundColor(.primaryText)
                                
                                Text(NSLocalizedString("In the payment section of your checkout, select \"gift card\" and enter your card number and pin.", comment: ""))
                                    .font(.body2)
                                    .foregroundColor(.tertiaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.bottom, 35)
                    .background(Color.secondaryBackground)
                    .cornerRadius(10)
                    .padding(.horizontal, 15)
                    .padding(.top, 20)
                }
                
                // Powered by CTX
                VStack(spacing: 8) {
                    Text(NSLocalizedString("Powered by", comment: ""))
                        .font(.callout)
                        .foregroundColor(.tertiaryText)
                    
                    Text("CTX")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.dashBlue)
                }
                .padding(.top, 30)
                .padding(.bottom, 40)
            }
        }
        .background(Color.primaryBackground)
        .onAppear {
            viewModel.startObserving()
        }
        .onDisappear {
            viewModel.stopObserving()
        }
    }
    
    private func navigateToTransactionDetails() {
//        // Navigate to transaction details
//        if let topVC = UIApplication.shared.topViewController() {
//            let tx = DWEnvironment.sharedInstance().currentWallet.allTransactions.first { transaction in
//                guard let tx = transaction as? DSTransaction else { return false }
//                return tx.txHashData == viewModel.txId
//            }
//            
//            if let transaction = tx as? DSTransaction {
//                let controller = TXDetailViewController()
//                controller.transaction = transaction
//                navigationController = UINavigationController(rootViewController: controller)
//                navigationController?.isModalInPresentation = true
//                topVC.present(navigationController!, animated: true)
//            }
//        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd, yyyy 'at' h:mm a"
        return formatter
    }
} 

extension Notification.Name {
    static let showGiftCardDetails = Notification.Name("showGiftCardDetails")
}
