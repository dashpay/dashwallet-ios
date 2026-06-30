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

struct GiftCardDetailsView: View {
    @StateObject private var viewModel: GiftCardDetailsViewModel
    @State private var showHowToUse = false
    @State private var originalBrightness: CGFloat = -1
    @Binding var backNavigationRequested: Bool
    var onShowBackButton: (Bool) -> Void
    var onOpenTransaction: ((DSTransaction) -> Void)?
    private let selectedCardIndex: Int
    private let isPreview: Bool
    private let shouldObserve: Bool
    
    init(
        txId: Data,
        selectedCardIndex: Int = 0,
        backNavigationRequested: Binding<Bool>,
        onShowBackButton: @escaping (Bool) -> Void,
        onOpenTransaction: ((DSTransaction) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: GiftCardDetailsViewModel(txId: txId))
        _backNavigationRequested = backNavigationRequested
        self.onShowBackButton = onShowBackButton
        self.onOpenTransaction = onOpenTransaction
        self.selectedCardIndex = selectedCardIndex
        self.isPreview = false
        self.shouldObserve = true
    }

    init(
        viewModel: GiftCardDetailsViewModel,
        selectedCardIndex: Int = 0,
        backNavigationRequested: Binding<Bool>,
        onShowBackButton: @escaping (Bool) -> Void,
        onOpenTransaction: ((DSTransaction) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _backNavigationRequested = backNavigationRequested
        self.onShowBackButton = onShowBackButton
        self.onOpenTransaction = onOpenTransaction
        self.selectedCardIndex = selectedCardIndex
        self.isPreview = false
        self.shouldObserve = false
    }

    fileprivate init(previewViewModel: GiftCardDetailsViewModel) {
        _viewModel = StateObject(wrappedValue: previewViewModel)
        _backNavigationRequested = .constant(false)
        self.onShowBackButton = { _ in }
        self.onOpenTransaction = nil
        self.selectedCardIndex = 0
        self.isPreview = true
        self.shouldObserve = false
    }
    
    var body: some View {
        VStack(spacing: 20) {
            merchantHeaderSection
            giftCardInfoSection
            transactionDetailsSection
            howToUseSection
            poweredBySection
        }
        .padding(.horizontal, 20)
        .background(Color.primaryBackground)
        .onAppear {
            guard !isPreview else { return }
            if shouldObserve {
                viewModel.startObserving()
            }
            setMaxBrightness(true)
        }
        .onDisappear {
            guard !isPreview else { return }
            if shouldObserve {
                viewModel.stopObserving()
            }
            setMaxBrightness(false)
        }
    }

    private var merchantHeaderSection: some View {
        GiftCardDetailsMerchantHeader(
            merchantIcon: viewModel.uiState.merchantIcon,
            merchantName: viewModel.uiState.merchantName,
            purchaseDateText: purchaseDateText
        )
    }

    private var giftCardInfoSection: some View {
        GiftCardDetailsInfoCard(
            formattedPrice: selectedCard?.formattedPrice ?? viewModel.uiState.formattedPrice,
            card: selectedCard,
            isLoadingCardDetails: viewModel.uiState.isLoadingCardDetails,
            hasBeenPollingForLongTime: viewModel.uiState.hasBeenPollingForLongTime,
            loadingError: viewModel.uiState.loadingError,
            onOpenClaimLink: openClaimLink,
            onCopy: copyToPasteboard
        )
    }

    private var selectedCard: GiftCardDetailsCardItem? {
        if viewModel.uiState.cards.indices.contains(selectedCardIndex) {
            return viewModel.uiState.cards[selectedCardIndex]
        }
        return viewModel.uiState.cards.first
    }

    private var transactionDetailsSection: some View {
        Button(action: {
            guard let transaction = viewModel.uiState.transaction else { return }
            onOpenTransaction?(transaction)
        }) {
            HStack {
                Text(NSLocalizedString("View transaction details", comment: "DashSpend"))
                    .font(.subheadMedium)
                    .foregroundColor(.primaryText)

                Spacer()

                Image("greyarrow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            }
            .frame(height: 46)
            .padding(6)
            .padding(.horizontal, 14)
            .background(Color.secondaryBackground)
            .clipShape(.rect(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private var howToUseSection: some View {
        Group {
            if !showHowToUse {
                Button(action: {
                    withAnimation {
                        showHowToUse = true
                    }
                }) {
                    Text(NSLocalizedString("See how to use this gift card", comment: "DashSpend"))
                        .font(.subheadMedium)
                        .foregroundColor(.dashBlue)
                }
                .padding(.horizontal, 16)
            } else {
                GiftCardDetailsHowToUseSection()
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private var poweredBySection: some View {
        GiftCardDetailsPoweredBySection(provider: viewModel.uiState.provider)
    }

    private var purchaseDateText: String? {
        guard let date = viewModel.uiState.purchaseDate else { return nil }
        return dateFormatter.string(from: date)
    }

    private func openClaimLink(_ claimLink: String) {
        guard let url = URL(string: claimLink) else { return }
        UIApplication.shared.open(url)
    }

    private func copyToPasteboard(_ value: String) {
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Show the same "Copied" HUD used elsewhere (Receive, CrowdNode) over the topmost
        // controller so it appears above this gift card sheet.
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let keyWindow = windowScene?.windows.first(where: { $0.isKeyWindow }) ?? windowScene?.windows.first
        keyWindow?.rootViewController?.topController().view
            .dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
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

#Preview("Barcode + PIN") {
    GiftCardDetailsView(previewViewModel: .previewBarcodeCard())
}

#Preview("Claim Link") {
    GiftCardDetailsView(previewViewModel: .previewClaimLinkCard())
}

#Preview("Loading State") {
    GiftCardDetailsView(previewViewModel: .previewLoadingCard())
}
