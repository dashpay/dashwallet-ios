//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import DashUIKit
import SwiftUI

/// SwiftUI port of `DWRequestAmountContentView`: the requested amount over the
/// QR that encodes it, the address under that, and Share.
///
/// Same contents and same copy-on-tap behaviour as the original, dressed in the
/// redesign: the amount is `SwapAmountView`, the same component the amount step
/// enters it with, and the card below is `PaymentsReceiveContent`'s — same QR
/// size, same address row, same pill actions — so the sheet reads as the
/// Receive tab with an amount on it. The original is still in the tree; nothing
/// routes here yet.
///
/// Values in, closures out: the model stays with the host, because
/// `DWReceiveModelProtocol` is an ObjC protocol with a delegate that pushes
/// updates rather than publishing them.
struct RequestAmountScreen: View {
    let amountDuffs: UInt64
    let fiatAmount: String
    let qrCodeImage: UIImage?
    let paymentAddress: String?
    /// DashPay only; `nil` everywhere else, and the row is dropped.
    var username: String? = nil

    var onCopyAddress: () -> Void
    var onCopyQRCode: () -> Void
    var onCopyUsername: () -> Void = {}
    var onShare: () -> Void

    /// Taken from `PaymentsReceiveContent`, the Receive tab this sheet is the
    /// amount-carrying twin of: the same 200pt QR in the same 10pt well, the
    /// same address row, the same pill actions, the same `MenuViewModifier`
    /// card around all of it.
    private enum Layout {
        static let contentInset: CGFloat = 20
        /// A fixed square, not a fraction of the width — the Receive tab sizes
        /// its QR this way so the rows under it never shift.
        static let qrSide: CGFloat = 200
        static let qrPadding: CGFloat = 10
        /// The DashPay avatar, or the Dash "D", at the centre of the code.
        static let qrBadgeFraction: CGFloat = 0.18
    }

    private var hasAddress: Bool { paymentAddress != nil }

    var body: some View {
        VStack(spacing: 20) {
            amount
            card
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Amount

    /// The same component the amount step draws with, so the number keeps its
    /// size and weight as the user crosses from "Specify amount" into this
    /// sheet. It renders the Dash glyph itself, and scales the whole group down
    /// to fit rather than truncating the digits — which the fixed-size
    /// `DWAmountPreviewView` this replaces could not do.
    ///
    /// Interaction is all opt-in and stays off here: no paste, no currency
    /// chevron, no swap. This amount is a result, not an input.
    private var amount: some View {
        DashUIKit.SwapAmountView(
            amount: amountDuffs.formattedDashAmountWithoutCurrencySymbol,
            // An empty secondary renders as "0" inside the component, so the
            // "rates have not arrived" case has to pass nil to drop the line.
            secondaryText: fiatAmount.isEmpty ? nil : fiatAmount,
            showDashLogo: true
        )
        .padding(.horizontal, Layout.contentInset)
    }

    // MARK: - Card

    /// The Receive tab's card, rebuilt around this screen's contents: the QR
    /// and its rows share one block of padding, and the action sits below them
    /// with its own, so the button keeps the tab's 20pt frame instead of
    /// inheriting the rows' spacing.
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .center, spacing: 20) {
                Text(NSLocalizedString("This QR contains the specified amount", comment: "Receive screen"))
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.primaryText)

                qrCode

                if let paymentAddress {
                    addressRow(
                        caption: NSLocalizedString("Your DASH address", comment: "Receive screen"),
                        value: paymentAddress,
                        action: onCopyAddress)
                }

                if let username {
                    addressRow(
                        caption: NSLocalizedString("Username", comment: "Receive screen"),
                        value: username,
                        action: onCopyUsername)
                }
            }
            .padding(.horizontal, Layout.contentInset)
            .padding(.top, 40)
            .padding(.bottom, 10)
        }
        .modifier(MenuViewModifier(innerPadding: 0))
    }

    // MARK: - QR

    /// The Receive tab's QR: a fixed 200pt square in a 10pt well, drawn
    /// straight onto the card rather than into a container of its own.
    ///
    /// Tapping copies the image, as the original's QR button did. The badge in
    /// the middle is the DashPay avatar when there is one, and the Dash "D"
    /// otherwise — the tab has no badge because it has no DashPay identity to
    /// show, this screen does.
    @ViewBuilder
    private var qrCode: some View {
        if let qrCodeImage {
            Button(action: onCopyQRCode) {
                Image(uiImage: qrCodeImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Layout.qrSide, height: Layout.qrSide)
                    .padding(Layout.qrPadding)
                    .overlay(qrBadge(side: Layout.qrSide * Layout.qrBadgeFraction))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            // The same 220pt square the QR occupies, so the rows below do not
            // jump once the address resolves.
            SwiftUI.ProgressView()
                .frame(width: Layout.qrSide + Layout.qrPadding * 2,
                       height: Layout.qrSide + Layout.qrPadding * 2)
        }
    }

    @ViewBuilder
    private func qrBadge(side: CGFloat) -> some View {
        if let avatarInitial {
            Text(avatarInitial)
                .dashFont(.subheadMedium)
                .foregroundColor(Color.dash.white)
                .frame(width: side, height: side)
                .background(Circle().fill(Color.dash.blue))
                .overlay(Circle().stroke(Color.dash.white, lineWidth: 3))
        } else {
            DashIcon.Menu.dashLogoSquare.image
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        }
    }

    /// Stand-in for Android's avatar image: the profile picture is not on this
    /// screen's model, so the username's first letter carries it.
    private var avatarInitial: String? {
        guard let first = username?.first else { return nil }
        return String(first).uppercased()
    }

    // MARK: - Copyable rows

    /// The Receive tab's address row: caption over a wrapping value, with a
    /// `tintedGray` copy pill on the trailing edge.
    ///
    /// One deviation from the tab — the text takes the full width. The tab has
    /// a single row and can let the pair sit centred; this screen can show two
    /// (address and username), and centred rows of different lengths would put
    /// their copy pills at different x.
    private func addressRow(caption: String, value: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)

                Text(value)
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.primaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DashUIKit.DashButton(
                leadingIcon: .custom(DashIcon.Icons.copyOutline.rawValue, bundle: .dashUIKit),
                size: .medium,
                style: .tintedGray,
                action: action
            )
        }
        .padding(.vertical, 6)
    }
}

#if DEBUG

/// The screen as the host actually shows it — inside `DashUIKit.BottomSheet`,
/// over a dimmed backdrop. On its own it has no chrome and no background of its
/// own, so previewing it bare would flatter it.
private func requestAmountSheet(
    amountDuffs: UInt64 = 125_000_000,
    fiatAmount: String = "$32.75",
    address: String? = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN",
    username: String? = nil
) -> some View {
    DashUIKit.BottomSheet(
        showBackButton: .constant(false),
        fillsHeight: false
    ) {
        RequestAmountScreen(
            amountDuffs: amountDuffs,
            fiatAmount: fiatAmount,
            qrCodeImage: address.flatMap { QRCodeGenerator.image(for: $0) },
            paymentAddress: address,
            username: username,
            onCopyAddress: {},
            onCopyQRCode: {},
            onCopyUsername: {},
            onShare: {})
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
}

@available(iOS 17, *)
#Preview("Address") {
    requestAmountSheet()
}

/// DashPay: the username row joins the address, and the badge in the middle of
/// the QR becomes the avatar instead of the Dash logo.
@available(iOS 17, *)
#Preview("With username") {
    requestAmountSheet(username: "Epsilon2")
}

/// Before the address resolves: a spinner in the QR's square so nothing below
/// moves when it arrives, and Share dimmed rather than sharing nothing.
@available(iOS 17, *)
#Preview("No address") {
    requestAmountSheet(address: nil)
}

/// The address must ellipsize in the middle rather than push the copy button
/// off the row — the failure this layout is most likely to have.
@available(iOS 17, *)
#Preview("Long address · username") {
    requestAmountSheet(
        address: "yTBaseS8fJ4vFrmqhUvBaseLongAddressPaddedOutToItsFullWidth1234",
        username: "a-rather-long-dashpay-username")
}

/// Whole units and a fraction read differently at this size; the fiat line
/// disappears when rates have not arrived.
@available(iOS 17, *)
#Preview("Fractional · no rate") {
    requestAmountSheet(amountDuffs: 12_345_678, fiatAmount: "")
}

#endif
