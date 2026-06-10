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

struct GiftCardDetailsInfoCard: View {
    let formattedPrice: String
    let card: GiftCardDetailsCardItem?
    let isLoadingCardDetails: Bool
    let hasBeenPollingForLongTime: Bool
    let loadingError: Error?
    let onOpenClaimLink: (String) -> Void
    let onCopy: (String) -> Void

    private var isClaimLink: Bool { card?.isClaimLink ?? false }

    var body: some View {
        VStack(spacing: 2) {
            barcodeSection
            detailsRowsSection
        }
        .background(Color.secondaryBackground)
        .cornerRadius(20)
    }

    @ViewBuilder
    private var barcodeSection: some View {
        if isClaimLink {
            EmptyView()
        } else if let barcodeImage = card?.barcodeImage {
            Image(uiImage: barcodeImage)
                .resizable()
                .frame(width: 200, height: 80)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.systemGray6))
                    .frame(height: 72)

                if isLoadingCardDetails {
                    if hasBeenPollingForLongTime {
                        Text(NSLocalizedString("As soon as your code is generated, it will be displayed here", comment: "DashSpend"))
                            .font(.footnote)
                            .foregroundColor(.tertiaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 50)
                    } else {
                        SwiftUI.ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    }
                } else if loadingError != nil {
                    Text(NSLocalizedString("Failed to load barcode", comment: "DashSpend"))
                        .font(.footnote)
                        .foregroundColor(.systemRed)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var detailsRowsSection: some View {
        if isClaimLink {
            VStack(spacing: 20) {
                textValueRow(
                    title: NSLocalizedString("Original Price", comment: "DashSpend"),
                    value: formattedPrice
                )

                if let claimLink = card?.cardNumber {
                    Button(action: {
                        onOpenClaimLink(claimLink)
                    }) {
                        Text(NSLocalizedString("See card details", comment: "DashSpend"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.dashBlue)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 20)
        } else {
            VStack(spacing: 2) {
                textValueRow(
                    title: NSLocalizedString("Original Price", comment: "DashSpend"),
                    value: formattedPrice
                )

                if let cardNumber = card?.cardNumber {
                    cardValueRow(
                        title: NSLocalizedString("Card number", comment: "DashSpend"),
                        value: cardNumber,
                        onCopy: {
                            onCopy(cardNumber)
                        }
                    )
                }

                if let cardPin = card?.cardPin {
                    cardValueRow(
                        title: NSLocalizedString("Card PIN", comment: "DashSpend"),
                        value: cardPin,
                        onCopy: {
                            onCopy(cardPin)
                        }
                    )
                }

                multilineValueRow(
                    title: NSLocalizedString("Cashier instructions", comment: "DashSpend"),
                    value: NSLocalizedString("Tell the cashier that you'd like to pay with a gift card and share the card number and pin.", comment: "DashSpend")
                )
            }
            .padding(.horizontal, 14)
        }
    }

    private func textValueRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(title)
                .font(.subheadMedium)
                .foregroundColor(.tertiaryText)

            Spacer()

            Text(value)
                .font(.subhead)
                .foregroundColor(.primaryText)
        }
        .padding(.vertical, 12)
    }

    private func cardValueRow(title: String, value: String, onCopy: @escaping () -> Void) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.subheadMedium)
                .foregroundColor(.tertiaryText)

            Spacer()

            HStack(spacing: 6) {
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.primaryText)

                Button(action: onCopy) {
                    Icon(name: .custom("icon_copy_outline", maxHeight: 14))
                        .tint(.primaryText)
                }
            }
        }
        .frame(height: 42, alignment: .center)
    }

    private func multilineValueRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.tertiaryText)

            Text(value)
                .font(.subheadline)
                .foregroundColor(.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Barcode + PIN") {
    GiftCardDetailsInfoCard(
        formattedPrice: "$75.00",
        card: GiftCardDetailsCardItem(
            id: "preview-barcode",
            formattedPrice: "$75.00",
            cardNumber: "1234 5678 9012",
            cardPin: "7890",
            barcodeImage: UIImage(systemName: "barcode.viewfinder"),
            isClaimLink: false
        ),
        isLoadingCardDetails: false,
        hasBeenPollingForLongTime: false,
        loadingError: nil,
        onOpenClaimLink: { _ in },
        onCopy: { _ in }
    )
    .padding()
    .background(Color.primaryBackground)
}

#Preview("Claim Link") {
    GiftCardDetailsInfoCard(
        formattedPrice: "$50.00",
        card: GiftCardDetailsCardItem(
            id: "preview-claim",
            formattedPrice: "$50.00",
            cardNumber: "https://giftcards.example.com/claim/ABC123",
            cardPin: nil,
            barcodeImage: nil,
            isClaimLink: true
        ),
        isLoadingCardDetails: false,
        hasBeenPollingForLongTime: false,
        loadingError: nil,
        onOpenClaimLink: { _ in },
        onCopy: { _ in }
    )
    .padding()
    .background(Color.primaryBackground)
}

#Preview("Loading") {
    GiftCardDetailsInfoCard(
        formattedPrice: "$100.00",
        card: nil,
        isLoadingCardDetails: true,
        hasBeenPollingForLongTime: true,
        loadingError: nil,
        onOpenClaimLink: { _ in },
        onCopy: { _ in }
    )
    .padding()
    .background(Color.primaryBackground)
}
