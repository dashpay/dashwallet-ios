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
import DashUIKit
import SDWebImageSwiftUI

struct DashSpendPayScreen: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel: DashSpendPayViewModel
    let merchant: ExplorePointOfUse
    let provider: GiftCardProvider
    @State var justAuthenticated: Bool
    @State var showConfirmToast: Bool
    @State private var showErrorDialog = false
    @State private var showCustomErrorDialog = false
    @State private var errorMessage = ""
    @State private var errorTitle = ""
    @State private var quantities: [Decimal: Int] = [:]
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
                DashUIKit.NavigationBar(leading: {
                    DashUIKit.NavigationBarElement.back.button {
                        presentationMode.wrappedValue.dismiss()
                    }
                })

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
        .background(Color.dash.primaryBackground)
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
        .sheet(isPresented: isPurchaseSheetPresented, onDismiss: { viewModel.purchaseSheetDidDismiss() }) {
            DashSpendPurchaseSheet(viewModel: viewModel, onConfirm: purchaseGiftCard)
        }
    }

    /// The sheet follows the view model's state. A swipe down reaches the view model as a
    /// dismissal: it closes the Confirm sheet and declines a price change.
    private var isPurchaseSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.purchaseSheet != nil },
            set: { isPresented in
                if !isPresented { viewModel.dismissPurchaseSheet() }
            })
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
            LegacyModalDialog(
                style: .error,
                icon: .system("exclamationmark.triangle.fill"),
                heading: errorTitle,
                textBlock1: errorMessage,
                positiveButtonText: NSLocalizedString("OK", comment: ""),
                positiveButtonAction: { showErrorDialog = false }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dash.backgroundOverlay)
            .edgesIgnoringSafeArea(.all)
        }

        if showCustomErrorDialog {
            LegacyModalDialog(
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
            .background(Color.dash.backgroundOverlay)
            .edgesIgnoringSafeArea(.all)
        }
    }

    private func handlePayAction() {
        if !viewModel.isUserSignedIn { showSignInError(); return }
        let snapshotQuantities = quantities.filter { $0.value > 0 }
        let snapshotTotal = snapshotQuantities.reduce(Decimal(0)) { $0 + $1.key * Decimal($1.value) }
        // `input.decimal()` is `Decimal(string:locale:)` with a nil locale, which only
        // understands "." as the decimal mark — on a comma-decimal locale it truncates
        // "5,5" to 5, silently dropping the fraction. Use the same region-agnostic parser
        // the view model already feeds `amount` from so both agree.
        let snapshotSingleAmount = PastedAmountParser.parse(viewModel.input, locale: .current)?.decimalValue ?? viewModel.amount

        // Keep viewModel amount in sync before presenting the dialog to avoid delayed UI updates.
        if snapshotQuantities.isEmpty {
            viewModel.updateTotalAmount(snapshotSingleAmount)
        } else {
            viewModel.updateTotalAmount(snapshotTotal, quantities: snapshotQuantities)
        }

        // The price, discount and Dash amount are captured here, so the sheet shows the same
        // values that Confirm passes on, whatever the view model changes to meanwhile.
        do {
            try viewModel.beginPurchase(
                price: snapshotQuantities.isEmpty ? snapshotSingleAmount : snapshotTotal,
                quantities: snapshotQuantities)
        } catch {
            showPurchaseError(error)
        }
    }

    private func purchaseGiftCard(_ snapshot: GiftCardPurchaseSnapshot) {
        Task {
            do {
                let txId = try await viewModel.purchaseGiftCardAndPay(snapshot)
                presentationMode.wrappedValue.dismiss()
                onPurchaseSuccess?(txId)
            } catch DashSpendError.purchaseCancelled {
                // A higher price was declined or could not be shown, or this was a second
                // tap on Confirm. Nothing was sent and there is nothing to report; the view
                // model logged which.
            } catch DashSpendError.paymentStatusUnknown(let txId, let reason) {
                // Paid, order placed, acceptance verdict missing. The purchase is already
                // recorded, so route to the card details exactly like a confirmed purchase —
                // its poller is what turns the pending order into a card. Reporting "Purchase
                // Failed" here is what previously left customers paying for an invisible card.
                DWLogger.log("Gift card purchase pending network confirmation: \(reason)")
                presentationMode.wrappedValue.dismiss()
                onPurchaseSuccess?(txId)
            } catch DashSpendError.paymentNotAcknowledged(let txId, let reason) {
                // Posted to CTX, acknowledgement not read. CTX may be fulfilling the order
                // already and the purchase is recorded, so this is not a failed purchase:
                // route to the card details, whose poller shows the card once CTX issues it.
                DWLogger.log("Gift card payment not acknowledged by the provider: \(reason)")
                presentationMode.wrappedValue.dismiss()
                onPurchaseSuccess?(txId)
            } catch {
                showPurchaseError(error)
            }
        }
    }

    private func showPurchaseError(_ error: Error) {
        if let error = error as? DashSpendError {
            errorTitle = NSLocalizedString("Purchase Failed", comment: "DashSpend")
            errorMessage = error.errorDescription ?? NSLocalizedString("Error", comment: "")

            if case .customError = error {
                showCustomErrorDialog = true
            } else {
                showErrorDialog = true
            }
        } else {
            errorTitle = !error.localizedDescription.isEmpty ? error.localizedDescription : NSLocalizedString("Error", comment: "")
            errorMessage = error.localizedDescription
            showErrorDialog = true

            DWLogger.log("Gift card purchase failed with error: \(error)")
        }
    }

    private func showSignInError() {
        errorTitle = NSLocalizedString("Sign in required", comment: "Alert title")
        errorMessage = NSLocalizedString("You need to sign in to DashSpend to purchase gift cards.", comment: "DashSpend")
        showErrorDialog = true
    }
}

/// The purchase sheet: the Confirm sheet, which stays up with a spinner while the provider
/// answers, and the "Price updated" sheet that replaces it in place when the provider asks
/// for more than the buyer confirmed.
private struct DashSpendPurchaseSheet: View {
    @ObservedObject var viewModel: DashSpendPayViewModel
    let onConfirm: (GiftCardPurchaseSnapshot) -> Void
    /// The last content the view model asked for. Kept so the sheet does not go blank while
    /// it animates away after the view model cleared its state.
    @State private var sheet: GiftCardPurchaseSheet?

    init(viewModel: DashSpendPayViewModel, onConfirm: @escaping (GiftCardPurchaseSnapshot) -> Void) {
        self.viewModel = viewModel
        self.onConfirm = onConfirm
        _sheet = State(initialValue: viewModel.purchaseSheet)
    }

    private var title: String {
        switch sheet {
        case .confirm, .waitingForProvider:
            return NSLocalizedString("Confirm", comment: "DashSpend")
        case .priceUpdated:
            return NSLocalizedString("Price updated", comment: "DashSpend")
        case nil:
            return ""
        }
    }

    private var isWaiting: Bool {
        if case .waitingForProvider = sheet { return true }
        return false
    }

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: title,
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(!isWaiting),
            isCloseButtonEnabled: !isWaiting,
            onClose: { viewModel.dismissPurchaseSheet() },
            fallback: DashSpendConfirmationDialog.sheetFallbackHeight,
            cornerRadius: 32,
            animatesHeightChanges: true
        ) {
            // The content stays drawn while the sheet animates away; it takes no taps then.
            content
                .allowsHitTesting(viewModel.purchaseSheet != nil)
        }
        .onChange(of: viewModel.purchaseSheet) { newSheet in
            if let newSheet { sheet = newSheet }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case .confirm(let snapshot), .waitingForProvider(let snapshot):
            DashSpendConfirmationDialog(
                merchantName: viewModel.merchantTitle,
                merchantIconUrl: viewModel.merchantIconUrl,
                originalPrice: snapshot.price,
                discount: snapshot.discount,
                dashAmount: snapshot.approval.amount,
                quantities: snapshot.quantities.isEmpty ? nil : snapshot.quantities,
                isWaiting: isWaiting,
                onConfirm: { onConfirm(snapshot) },
                onCancel: { viewModel.dismissPurchaseSheet() }
            )
        case .priceUpdated(let change):
            DashSpendPriceUpdatedDialog(
                change: change,
                onPay: { viewModel.resolvePriceChange(pay: true) },
                onCancel: { viewModel.resolvePriceChange(pay: false) }
            )
        case nil:
            EmptyView()
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
