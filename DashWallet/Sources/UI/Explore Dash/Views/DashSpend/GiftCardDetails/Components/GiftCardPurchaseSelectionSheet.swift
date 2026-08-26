//
//  Created by Codex
//

import SwiftUI
import DashUIKit

struct GiftCardPurchaseSelectionSheet: View {
    let merchantIcon: UIImage?
    let merchantName: String
    let provider: String?
    let cards: [GiftCardDetailsCardItem]
    let isLoadingCardDetails: Bool
    let hasBeenPollingForLongTime: Bool
    /// Set once the poller gave up on a run of failures — without it this sheet keeps promising
    /// a card that nothing is fetching any more.
    var loadingError: Error? = nil
    /// Offered alongside `loadingError`; nil hides the affordance.
    var onRetryLoading: (() -> Void)? = nil

    let onSelectCard: (Int) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                GiftCardDetailsMerchantHeader(
                    merchantIcon: merchantIcon,
                    merchantName: merchantName,
                    purchaseDateText: nil
                )

                contentSection

                GiftCardDetailsPoweredBySection(provider: provider)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(Color.dash.primaryBackground)
    }

    @ViewBuilder
    private var contentSection: some View {
        if cards.isEmpty {
            loadingCard
        } else {
            cardsList
        }
    }

    private var loadingCard: some View {
        VStack {
            if isLoadingCardDetails {
                SwiftUI.ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.9)
            } else if loadingError != nil {
                VStack(spacing: 6) {
                    Text(NSLocalizedString("Could not load your gift card", comment: "DashSpend"))
                        .font(.footnote)
                        .foregroundColor(.dash.red)
                        .multilineTextAlignment(.center)

                    if let onRetryLoading {
                        Button(action: onRetryLoading) {
                            Text(NSLocalizedString("Retry", comment: "DashSpend"))
                                .font(.footnote.weight(.medium))
                                .foregroundColor(.dash.blue)
                        }
                    }
                }
                .padding(.horizontal, 24)
            } else if hasBeenPollingForLongTime {
                Text(NSLocalizedString("As soon as your code is generated, it will be displayed here", comment: "DashSpend"))
                    .font(.footnote)
                    .foregroundColor(.dash.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text(NSLocalizedString("Gift card is being prepared", comment: "DashSpend"))
                    .font(.subheadline)
                    .foregroundColor(.dash.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(20)
    }

    private var cardsList: some View {
        VStack(spacing: 10) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                Button(action: {
                    onSelectCard(index)
                }) {
                    HStack(spacing: 20) {
                        HStack(spacing: 12) {
                            if cards.count > 2 {
                                Text("\(index + 1)")
                                    .font(.caption1.weight(.medium))
                                    .padding(.horizontal, 4)
                                    .background(Color.dash.gray50)
                                    .clipShape(.rect(cornerRadius: 5))
                            }

                            Icon(
                                name: .custom(
                                    provider == "PiggyCards" ? "icon-gift_card-piggy_cards" : "ctx.logo",
                                    maxHeight: 23
                                )
                            )

                            Text(card.formattedPrice)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.dash.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Icon(name: .custom("list-chevron-right", maxHeight: 10))
                            .padding(.trailing, 14)
                    }
                    .frame(height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(20)
    }
}

#Preview("Multiple") {
    GiftCardPurchaseSelectionSheet(
        merchantIcon: UIImage(systemName: "cart.fill"),
        merchantName: "Amazon",
        provider: "PiggyCards",
        cards: [
            GiftCardDetailsCardItem(
                id: "preview-multi-1",
                formattedPrice: "$50.00",
                cardNumber: "1111 2222 3333",
                cardPin: "1234",
                redeemUrlChallenge: nil,
                barcodeImage: UIImage(systemName: "barcode.viewfinder"),
                isClaimLink: false
            ),
            GiftCardDetailsCardItem(
                id: "preview-multi-2",
                formattedPrice: "$50.00",
                cardNumber: "4444 5555 6666",
                cardPin: "9876",
                redeemUrlChallenge: nil,
                barcodeImage: UIImage(systemName: "barcode.viewfinder"),
                isClaimLink: false
            )
        ],
        isLoadingCardDetails: false,
        hasBeenPollingForLongTime: false,
        onSelectCard: { _ in }
    )
}
