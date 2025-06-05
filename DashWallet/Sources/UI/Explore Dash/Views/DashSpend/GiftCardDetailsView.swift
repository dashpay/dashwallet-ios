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
    @State private var originalBrightness: CGFloat = -1
    @State private var openTransaction: Bool = false
    @Binding var backNavigationRequested: Bool
    var onShowBackButton: (Bool) -> Void
    
    init(txId: Data, backNavigationRequested: Binding<Bool>, onShowBackButton: @escaping (Bool) -> Void) {
        _viewModel = StateObject(wrappedValue: GiftCardDetailsViewModel(txId: txId))
        _backNavigationRequested = backNavigationRequested
        self.onShowBackButton = onShowBackButton
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Merchant header
                HStack(spacing: 15) {
                    ZStack(alignment: .bottomTrailing) {
                        if let icon = viewModel.uiState.merchantIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .transition(.fade(duration: 0.3))
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        } else {
                            Image("image.explore.dash.wts.payment.gift-card")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                        }
                        
                        // Secondary icon
                        if viewModel.uiState.merchantIcon != nil {
                            Image("image.explore.dash.wts.payment.gift-card")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .frame(width: 23, height: 23)
                                .background(Circle().fill(Color.secondaryBackground))
                                .offset(x: 2, y: 2)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.uiState.merchantName)
                            .font(.body2)
                            .fontWeight(.medium)
                            .foregroundColor(.primaryText)
                        
                        if let date = viewModel.uiState.purchaseDate {
                            Text(date, formatter: dateFormatter)
                                .font(.footnote)
                                .foregroundColor(.tertiaryText)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 25)
                .padding(.top, 15)
                
                // Gift card info container
                VStack(spacing: 0) {
                    // Barcode section
                    if let barcodeImage = viewModel.uiState.barcodeImage {
                        Image(uiImage: barcodeImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray50)
                                .frame(height: 108)
                            
                            if viewModel.uiState.isLoadingCardDetails {
                                SwiftUI.ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            } else if viewModel.uiState.loadingError != nil {
                                Text(NSLocalizedString("Failed to load barcode", comment: "DashSpend"))
                                    .font(.footnote)
                                    .foregroundColor(.systemRed)
                            } else {
                                Text(NSLocalizedString("Barcode placeholder", comment: "DashSpend"))
                                    .font(.caption)
                                    .foregroundColor(.tertiaryText)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 15)
                    }
                    
                    // Original purchase value
                    HStack {
                        Text(NSLocalizedString("Original purchase", comment: "DashSpend"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.tertiaryText)
                        
                        Spacer()
                        
                        Text(viewModel.uiState.formattedPrice)
                            .font(.subheadline)
                            .foregroundColor(.primaryText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Check current balance link
                    if let merchantUrl = viewModel.uiState.merchantUrl {
                        Button(action: {
                            if let url = URL(string: merchantUrl) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text(NSLocalizedString("Check current balance", comment: "DashSpend"))
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundColor(.dashBlue)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    
                    // Card number and PIN
                    if viewModel.uiState.isLoadingCardDetails {
                        SwiftUI.ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding(.vertical, 40)
                    } else if let error = viewModel.uiState.loadingError {
                        VStack(spacing: 10) {
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundColor(.systemRed)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 15) {
                            // Card number
                            if let cardNumber = viewModel.uiState.cardNumber {
                                HStack {
                                    Text(NSLocalizedString("Card number", comment: "DashSpend"))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.tertiaryText)
                                    
                                    Spacer()
                                    
                                    Text(cardNumber)
                                        .font(.subheadline)
                                        .foregroundColor(.primaryText)
                                    
                                    Button(action: {
                                        UIPasteboard.general.string = cardNumber
                                        // TODO: Show toast
                                    }) {
                                        Image("icon_copy_outline")
                                            .resizable()
                                            .scaledToFit()
                                            .tint(.primaryText)
                                            .frame(width: 20, height: 20)
                                    }
                                    .frame(width: 28, height: 40)
                                }
                                .padding(.leading, 20)
                                .padding(.trailing, 10)
                            }
                            
                            // Card PIN
                            if let cardPin = viewModel.uiState.cardPin {
                                HStack {
                                    Text(NSLocalizedString("Card PIN", comment: "DashSpend"))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.tertiaryText)
                                    
                                    Spacer()
                                    
                                    Text(cardPin)
                                        .font(.subheadline)
                                        .foregroundColor(.primaryText)
                                    
                                    Button(action: {
                                        UIPasteboard.general.string = cardPin
                                        // TODO: Show toast
                                    }) {
                                        Image("icon_copy_outline")
                                            .resizable()
                                            .scaledToFit()
                                            .tint(.primaryText)
                                            .frame(width: 20, height: 20)
                                    }
                                    .frame(width: 32, height: 40)
                                }
                                .padding(.leading, 20)
                                .padding(.trailing, 10)
                            }
                        }
                        .padding(.top, 22)
                        .padding(.bottom, 15)
                    }
                }
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Button(action: {
                    openTransaction = true
                    onShowBackButton(true)
                }) {
                    HStack {
                        Text(NSLocalizedString("View transaction details", comment: "DashSpend"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primaryText)
                        
                        Spacer()
                        
                        Image("greyarrow")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 20)
                    .background(Color.secondaryBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // How to use button
                if !showHowToUse {
                    Button(action: {
                        withAnimation {
                            showHowToUse = true
                        }
                    }) {
                        Text(NSLocalizedString("See how to use this gift card", comment: "DashSpend"))
                            .font(.subtitle1)
                            .foregroundColor(.dashBlue)
                    }
                    .padding(.top, 30)
                } else {
                    // How to use expanded content
                    VStack(alignment: .leading, spacing: 30) {
                        Text(NSLocalizedString("How to use your gift card", comment: "DashSpend"))
                            .font(.body2)
                            .fontWeight(.medium)
                            .foregroundColor(.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 20)
                        
                        // Self-checkout
                        FeatureSingleItem(
                            iconName: .custom("dp_user_generic"),
                            title: NSLocalizedString("Self-checkout", comment: "DashSpend"),
                            description: NSLocalizedString("Request assistance and show the barcode on your screen for scanning.", comment: "DashSpend")
                        )
                        
                        // In store
                        FeatureSingleItem(
                            iconName: .custom("image.dashspend.shop"),
                            title: NSLocalizedString("In store", comment: "DashSpend"),
                            description: NSLocalizedString("Tell the cashier that you'd like to pay with a gift card and share the card number and pin.", comment: "DashSpend")
                        )
                        
                        // Online
                        FeatureSingleItem(
                            iconName: .custom("image.dashspend.online"),
                            title: NSLocalizedString("Online", comment: "DashSpend"),
                            description: NSLocalizedString("In the payment section of your checkout, select \"gift card\" and enter your card number and pin.", comment: "DashSpend")
                        )
                    }
                    .padding(.horizontal, 15)
                    .padding(.bottom, 35)
                    .background(Color.secondaryBackground)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                
                // Powered by CTX
                VStack(spacing: 8) {
                    Text(NSLocalizedString("Powered by", comment: "DashSpend"))
                        .font(.callout)
                        .foregroundColor(.tertiaryText)
                    
                    Image("ctx.logo")
                        .resizable()
                        .frame(width: 49, height: 18)
                }
                .padding(.top, 34)
                .padding(.bottom, 40)
            }
            
            if let transaction = viewModel.uiState.transaction {
                NavigationLink(
                    destination:
                        TXDetailVCWrapper(
                            transaction: transaction,
                            navigateBack: $backNavigationRequested,
                            onDismissed: {
                                onShowBackButton(false)
                            }
                        ).navigationBarHidden(true),
                    isActive: $openTransaction
                ) {
                    SwiftUI.EmptyView()
                }.opacity(0)
            }
        }
        .background(Color.primaryBackground)
        .onAppear {
            viewModel.startObserving()
            setMaxBrightness(true)
        }
        .onDisappear {
            viewModel.stopObserving()
            setMaxBrightness(false)
        }
    }
    
    private func setMaxBrightness(_ enable: Bool) {
        if enable {
            // Save original brightness
            if originalBrightness < 0 {
                originalBrightness = UIScreen.main.brightness
            }

            UIScreen.main.brightness = 1.0
        } else {
            // Restore original brightness
            if originalBrightness >= 0 {
                UIScreen.main.brightness = originalBrightness
                originalBrightness = -1
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd, yyyy 'at' h:mm a"
        return formatter
    }
}
