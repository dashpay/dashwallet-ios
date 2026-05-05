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
    let provider: GiftCardProvider
    @State var justAuthenticated: Bool
    @State var showConfirmToast: Bool
    @State private var showConfirmationDialog = false
    @State private var showErrorDialog = false
    @State private var showCustomErrorDialog = false
    @State private var errorMessage = ""
    @State private var errorTitle = ""
    @State private var quantities: [Decimal: Int] = [:]
    @State private var confirmationQuantities: [Decimal: Int] = [:]
    @State private var confirmationOriginalPrice: Decimal = 0
    let onPurchaseSuccess: ((Data) -> Void)?

    init(
        merchant: ExplorePointOfUse,
        provider: GiftCardProvider = .ctx,
        justAuthenticated: Bool = false,
        onPurchaseSuccess: ((Data) -> Void)? = nil
    ) {
        self.merchant = merchant
        self.provider = provider
        self._viewModel = .init(wrappedValue: DashSpendPayViewModel(merchant: merchant, provider: provider))
        self.justAuthenticated = justAuthenticated
        self.showConfirmToast = false
        self.onPurchaseSuccess = onPurchaseSuccess
    }

    fileprivate init(previewViewModel: DashSpendPayViewModel) {
        self.merchant = ExplorePointOfUse(
            id: 0,
            name: "",
            category: .unknown,
            active: true,
            city: nil,
            territory: nil,
            address1: nil,
            address2: nil,
            address3: nil,
            address4: nil,
            latitude: nil,
            longitude: nil,
            website: nil,
            phone: nil,
            logoLocation: nil,
            coverImage: nil,
            source: nil
        )
        self.provider = .ctx
        self._viewModel = .init(wrappedValue: previewViewModel)
        self.justAuthenticated = false
        self.showConfirmToast = false
        self.onPurchaseSuccess = nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                NavBarBack {
                    presentationMode.wrappedValue.dismiss()
                }

                if viewModel.isFixedDenomination {
                    DashSpendFixedContent(
                        viewModel: viewModel,
                        quantities: $quantities,
                        onAction: handlePayAction
                    )
                } else {
                    DashSpendFlexibleContent(
                        viewModel: viewModel,
                        quantities: $quantities,
                        onAction: handlePayAction
                    )
                }
            }
            overlays
        }
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
        .onChange(of: viewModel.isUserSignedIn) { isSignedIn in
            if !isSignedIn {
                presentationMode.wrappedValue.dismiss()
            }
        }
        .sheet(isPresented: $showConfirmationDialog) {
            DashSpendPayConfirmationSheet(
                merchantName: viewModel.merchantTitle,
                merchantIconUrl: viewModel.merchantIconUrl,
                originalPrice: confirmationOriginalPrice,
                discount: viewModel.savingsFraction,
                quantities: confirmationQuantities.isEmpty ? nil : confirmationQuantities,
                onConfirm: {
                    showConfirmationDialog = false
                    purchaseGiftCard()
                },
                onCancel: {
                    showConfirmationDialog = false
                }
            )
        }
    }

    @ViewBuilder
    private var overlays: some View {
        if justAuthenticated {
            ToastView(
                text: NSLocalizedString("Logged in to DashSpend account", comment: "DashSpend"),
                icon: .system("checkmark.circle")
            )
            .frame(height: 20)
            .padding(.bottom, 30)
        }

        if showConfirmToast {
            ToastView(text: NSLocalizedString("Gift card purchase successful", comment: "DashSpend"))
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
                positiveButtonAction: { showErrorDialog = false }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.7))
            .edgesIgnoringSafeArea(.all)
        }

        if showCustomErrorDialog {
            ModalDialog(
                style: .error,
                icon: .system("exclamationmark.triangle.fill"),
                heading: errorTitle,
                textBlock1: errorMessage,
                positiveButtonText: NSLocalizedString("Close", comment: ""),
                positiveButtonAction: { showCustomErrorDialog = false },
                negativeButtonText: viewModel.contactSupportButtonText,
                negativeButtonAction: {
                    showCustomErrorDialog = false
                    viewModel.contactSupport()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.7))
            .edgesIgnoringSafeArea(.all)
        }
    }

    private func handlePayAction() {
        if !viewModel.isUserSignedIn { showSignInError(); return }
        let snapshotQuantities = quantities.filter { $0.value > 0 }
        let snapshotTotal = snapshotQuantities.reduce(Decimal(0)) { $0 + $1.key * Decimal($1.value) }
        let snapshotSingleAmount = viewModel.input.decimal() ?? viewModel.amount

        confirmationQuantities = snapshotQuantities
        confirmationOriginalPrice = snapshotQuantities.isEmpty ? snapshotSingleAmount : snapshotTotal

        // Keep viewModel amount in sync before presenting the dialog to avoid delayed UI updates.
        if snapshotQuantities.isEmpty {
            viewModel.updateTotalAmount(snapshotSingleAmount)
        } else {
            viewModel.updateTotalAmount(snapshotTotal)
        }

        DispatchQueue.main.async {
            showConfirmationDialog = true
        }
    }

    private func purchaseGiftCard() {
        Task {
            do {
                let txId = try await viewModel.purchaseGiftCardAndPay(selectedQuantities: confirmationQuantities)
                showConfirmationDialog = false
                presentationMode.wrappedValue.dismiss()
                onPurchaseSuccess?(txId)
            } catch let error as DashSpendError {
                showConfirmationDialog = false
                errorTitle = NSLocalizedString("Purchase Failed", comment: "DashSpend")
                errorMessage = error.errorDescription ?? NSLocalizedString("Error", comment: "")

                if case .customError = error {
                    showCustomErrorDialog = true
                } else {
                    showErrorDialog = true
                }

            } catch {
                showConfirmationDialog = false
                errorTitle = !error.localizedDescription.isEmpty ? error.localizedDescription : NSLocalizedString("Error", comment: "")
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

private struct DashSpendPayConfirmationSheet: View {
    let merchantName: String
    let merchantIconUrl: String
    let originalPrice: Decimal
    let discount: Decimal
    let quantities: [Decimal: Int]?
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var contentHeight: CGFloat = 0
    
    @ViewBuilder
    var body: some View {
        let dialog = DashSpendConfirmationDialog(
            merchantName: merchantName,
            merchantIconUrl: merchantIconUrl,
            originalPrice: originalPrice,
            discount: discount,
            quantities: quantities,
            onConfirm: onConfirm,
            onCancel: onCancel,
            contentHeight: $contentHeight
        )

        if #available(iOS 16.4, *) {
            dialog
                .presentationBackground(Color.primaryBackground)
                .presentationDetents([.height(550)])
                .presentationCornerRadius(32)
                .presentationDragIndicator(.hidden)
        } else {
            dialog
        }
    }
}

#Preview("Flexible amount") {
    DashSpendPayScreen(previewViewModel: DashSpendPayPreviewViewModel())
}

#Preview("Fixed amount") {
    DashSpendPayScreen(previewViewModel: DashSpendPayFixedPreviewViewModel())
}

private class DashSpendPayFixedPreviewViewModel: DashSpendPayViewModel {
    override var isMixing: Bool { false }
    override func subscribeToUpdates() {}
    override func unsubscribeFromAll() {}

    init() {
        let merchant = ExplorePointOfUse(
            id: 2,
            name: "Domino's",
            category: .merchant(
                ExplorePointOfUse.Merchant(
                    merchantId: "dominos-123",
                    paymentMethod: .giftCard,
                    type: .online,
                    deeplink: nil,
                    savingsBasisPoints: 500,
                    denominationsType: "fixed",
                    denominations: [],
                    redeemType: "online",
                    giftCardProviders: [
                        ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                            providerId: "ctx", savingsPercentage: 500,
                            denominationsType: "fixed", sourceId: nil
                        )
                    ]
                )
            ),
            active: true,
            city: nil,
            territory: nil,
            address1: nil,
            address2: nil,
            address3: nil,
            address4: nil,
            latitude: nil,
            longitude: nil,
            website: nil,
            phone: nil,
            logoLocation: nil,
            coverImage: nil,
            source: "ctx"
        )
        super.init(merchant: merchant, provider: .ctx)
        merchantTitle = "Domino's"
        isFixedDenomination = true
        denominations = [5, 25, 50, 100]
    }
}

private class DashSpendPayPreviewViewModel: DashSpendPayViewModel {
    override var isMixing: Bool { false }
    override func subscribeToUpdates() {}
    override func unsubscribeFromAll() {}

    init() {
        let merchant = ExplorePointOfUse(
            id: 1,
            name: "Amazon",
            category: .merchant(
                ExplorePointOfUse.Merchant(
                    merchantId: "amazon-123",
                    paymentMethod: .giftCard,
                    type: .online,
                    deeplink: nil,
                    savingsBasisPoints: 1000,
                    denominationsType: "range",
                    denominations: [],
                    redeemType: "online",
                    giftCardProviders: [
                        ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                            providerId: "ctx", savingsPercentage: 1000,
                            denominationsType: "range", sourceId: nil
                        )
                    ]
                )
            ),
            active: true,
            city: nil,
            territory: nil,
            address1: nil,
            address2: nil,
            address3: nil,
            address4: nil,
            latitude: nil,
            longitude: nil,
            website: nil,
            phone: nil,
            logoLocation: nil,
            coverImage: nil,
            source: "ctx"
        )
        super.init(merchant: merchant, provider: .ctx)
        merchantTitle = "Amazon"
        minimumAmount = 5
        maximumAmount = 100
    }
}
