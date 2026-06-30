//
//  BIP70PaymentOutputFactory.swift
//  DashWallet
//
//  BIP70 Layer 6 — builds the confirm-screen `DWPaymentOutput` from a verified `Confirmation`
//  box, so the existing `ConfirmPaymentViewController` renders the merchant name + 🔒 lock +
//  amount/estimated-fee with no UI change. The box rides along so the broadcast step can call
//  `confirmAndSend` on the same prepared confirmation.
//

import Foundation

@objc(DWBIP70PaymentOutputFactory)
final class BIP70PaymentOutputFactory: NSObject {

    @objc(paymentOutputFromBox:userItem:)
    static func paymentOutput(from box: BIP70ConfirmationBox,
                              userItem: DWDPBasicUserItem?) -> DWPaymentOutput {
        DWPaymentOutput(merchantName: box.merchantName,
                        isSecure: box.isSecure,
                        amount: box.amount,
                        fee: box.estimatedFee,
                        address: box.primaryAddress ?? "",
                        memo: box.memo,
                        bip70Confirmation: box,
                        userItem: userItem)
    }
}
