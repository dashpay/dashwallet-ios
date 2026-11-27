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
import UniformTypeIdentifiers
import DashUIKit

struct GiftCardDetailsView: View {
    @StateObject private var viewModel: GiftCardDetailsViewModel
    @State private var showHowToUse = false
    @State private var originalBrightness: CGFloat = -1
    @State private var redeemRoute: RedeemLinkRoute?
    @State private var isOnScreen = false
    @Binding var backNavigationRequested: Bool
    var onShowBackButton: (Bool) -> Void
    var onOpenTransaction: ((Transaction) -> Void)?
    private let selectedCardIndex: Int
    private let isPreview: Bool
    private let shouldObserve: Bool
    
    init(
        txId: Data,
        selectedCardIndex: Int = 0,
        backNavigationRequested: Binding<Bool>,
        onShowBackButton: @escaping (Bool) -> Void,
        onOpenTransaction: ((Transaction) -> Void)? = nil
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
        onOpenTransaction: ((Transaction) -> Void)? = nil
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
        .background(Color.dash.primaryBackground)
        .onAppear {
            guard !isPreview else { return }
            isOnScreen = true
            if shouldObserve {
                viewModel.startObserving()
            }
            setMaxBrightness(true)
        }
        .onDisappear {
            guard !isPreview else { return }
            isOnScreen = false
            if shouldObserve {
                viewModel.stopObserving()
            }
            setMaxBrightness(false)
        }
        .fullScreenCover(item: $redeemRoute, onDismiss: {
            // If the sheet went away together with the browser, nothing would lower the brightness again.
            guard isOnScreen else { return }
            setMaxBrightness(true)
        }) { route in
            GiftCardRedeemWebScreen(
                link: route.link,
                merchantName: viewModel.uiState.merchantName,
                challenge: route.challenge,
                onCopyChallenge: { GiftCardSheetFeedback.copySensitive($0) }
            )
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
            onRetryLoading: viewModel.uiState.canRetryLoading ? { viewModel.retryLoadingCardDetails() } : nil,
            onRedeemLink: redeem,
            onCopy: { GiftCardSheetFeedback.copySensitive($0) }
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
                Text(String(localized: "View transaction details", comment: "DashSpend"))
                    .font(.subheadMedium)
                    .foregroundColor(.dash.primaryText)

                Spacer()

                Image("greyarrow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            }
            .frame(height: 46)
            .padding(6)
            .padding(.horizontal, 14)
            .background(Color.dash.secondaryBackground)
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
                    Text(String(localized: "See how to use this gift card", comment: "DashSpend"))
                        .font(.subheadMedium)
                        .foregroundColor(.dash.blue)
                }
                .padding(.horizontal, 16)
            } else {
                GiftCardDetailsHowToUseSection(
                    isLinkCard: selectedCard?.redeemLink != nil,
                    hasChallenge: selectedCard?.challengeCode != nil
                )
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

    private func redeem(_ link: String) {
        let ctxBaseURL = CTXConstants.baseURI

        if RedeemLinkPolicy.canOpenInApp(link, ctxBaseURL: ctxBaseURL) {
            setMaxBrightness(false)
            redeemRoute = RedeemLinkRoute(link: link, challenge: selectedCard?.challengeCode)
        } else if let url = RedeemLinkPolicy.externalURL(link, ctxBaseURL: ctxBaseURL) {
            UIApplication.shared.open(url)
        } else {
            GiftCardSheetFeedback.showBlockedLinkNotice()
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
        // en_US stays "MMMM dd, yyyy 'at' h:mm a"; other locales get their own order, words and clock (`j`).
        formatter.setLocalizedDateFormatFromTemplate("MMMMddyyyyjmm")
        return formatter
    }
}

private struct RedeemLinkRoute: Identifiable {
    let id = UUID()
    let link: String
    let challenge: String?
}

@MainActor
enum GiftCardSheetFeedback {
    private static let clipboardLifetime: TimeInterval = 120
    private static weak var noticeView: UIView?

    /// Copies a card secret so that it stays on this device and leaves the pasteboard after two minutes.
    static func copySensitive(_ value: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: value]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(clipboardLifetime),
            ]
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showNotice(String(localized: "Copied", comment: ""))
    }

    static func showBlockedLinkNotice() {
        showNotice(String(localized: "This link can't be opened here.", comment: "DashSpend"))
    }

    static func hideNotice() {
        noticeView?.dw_hideInfoHUD()
    }

    // Shown over the topmost controller so it appears above the gift card sheet and the redeem screen.
    private static func showNotice(_ text: String) {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let keyWindow = windowScene?.windows.first(where: { $0.isKeyWindow }) ?? windowScene?.windows.first
        noticeView = keyWindow?.rootViewController?.topController().view
        noticeView?.dw_showInfoHUD(withText: text)
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
