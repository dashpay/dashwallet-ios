//
//  Created by Codex
//

import SwiftUI

struct GiftCardPurchaseSelectionSheet: View {
    let merchantIcon: UIImage?
    let merchantName: String
    let provider: String?
    let cards: [GiftCardDetailsCardItem]
    let isLoadingCardDetails: Bool
    let hasBeenPollingForLongTime: Bool

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
        .background(Color.primaryBackground)
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
            } else if hasBeenPollingForLongTime {
                Text(NSLocalizedString("As soon as your code is generated, it will be displayed here", comment: "DashSpend"))
                    .font(.footnote)
                    .foregroundColor(.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text(NSLocalizedString("Gift card is being prepared", comment: "DashSpend"))
                    .font(.subheadline)
                    .foregroundColor(.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(Color.secondaryBackground)
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
                                    .background(Color.gray50)
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
                                .foregroundColor(.primaryText)
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
        .background(Color.secondaryBackground)
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
                barcodeImage: UIImage(systemName: "barcode.viewfinder"),
                isClaimLink: false
            ),
            GiftCardDetailsCardItem(
                id: "preview-multi-2",
                formattedPrice: "$50.00",
                cardNumber: "4444 5555 6666",
                cardPin: "9876",
                barcodeImage: UIImage(systemName: "barcode.viewfinder"),
                isClaimLink: false
            )
        ],
        isLoadingCardDetails: false,
        hasBeenPollingForLongTime: false,
        onSelectCard: { _ in }
    )
}
