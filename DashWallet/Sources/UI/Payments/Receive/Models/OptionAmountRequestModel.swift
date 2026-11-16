//
//  OptionAmountRequestModel.swift
//  DashWallet
//
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

import UIKit

/// A request for an amount on Shielded, Platform or Identity:
/// `dash:<address-or-ID>?amount=<DASH>`, built by `PaymentURIBuilder` so the
/// amount reads exactly as Core's. Nothing else rides along — no fiat, no
/// username — the same payload Android's Receive builds for these options.
///
/// Core keeps `DWReceiveModel`, which follows the next unused address and adds
/// the fiat and username parameters. The address here is fixed: it is the one
/// the Receive card showed when the amount was entered.
final class OptionAmountRequestModel: NSObject, DWReceiveModelProtocol {
    let amount: UInt64
    let paymentAddress: String?
    let qrCodeImage: UIImage?
    /// The caption over the value on the sheet, the same one the option's card uses.
    let addressCaption: String
    #if DASHPAY
    /// No username row: the request names only the address or ID.
    let username: String? = nil
    #endif
    /// The side of the QR in points, as the request-amount sheet draws it.
    let qrCodeSize = CGSize(width: 200, height: 200)
    weak var delegate: DWReceiveModelDelegate?

    private let request: String

    init(address: String, amount: UInt64, option: ReceiveOption) {
        self.amount = amount
        paymentAddress = address
        request = PaymentURIBuilder(address: address, amount: amount).string
        qrCodeImage = QRCodeGenerator.image(for: request)
        addressCaption = option == .identity
            ? NSLocalizedString("Identity ID", comment: "")
            : NSLocalizedString("Your DASH address", comment: "Payments")
        super.init()
    }

    func paymentAddressOrRequestToShare() -> String {
        request
    }

    func copyAddressToPasteboard() {
        UIPasteboard.general.string = request
    }

    func copyQRImageToPasteboard() {
        guard let qrCodeImage else { return }
        UIPasteboard.general.image = qrCodeImage
    }

    #if DASHPAY
    /// Unreachable: with no username the sheet draws no username row to copy from.
    func copyUsernameToPasteboard() {}
    #endif

    /// Always nil. The check behind this on Core reads Core addresses only;
    /// on these options the Receive session's receipt is what closes the sheet.
    func requestAmountReceivedInfoIfReceived() -> String? {
        nil
    }

    /// Nothing to refresh: the address and the amount are fixed for this request.
    func updateReceivingInfo() {}
}
