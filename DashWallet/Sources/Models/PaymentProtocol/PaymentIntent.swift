//
//  PaymentIntent.swift
//  DashWallet
//
//  App-side send carrier — the value object `DWPaymentProcessor` consumes for a plain-`dash:`
//  send, replacing the synthetic `DSPaymentProtocolRequest` that `protocolRequestFromPaymentRequest:`
//  used to mint from a `DSPaymentRequest` courier (C8 step 4). The send-side mirror of the parse
//  box (`DWParsedPaymentURI`): a faithful projection of its fields, plus a settable send `amount`
//  (the parse box's `amount` is an immutable parse fact, but `payToAddress:amount:` overrides it as
//  a send parameter).
//
//  Foundation only (no SDK / no network). The `DWParsedPaymentURI` → intent projection is done at
//  the ObjC input boundary (`DWPaymentInput.attachParsedURI:`) so this type stays pure and carries
//  no `DSChain` / CoreData / wallet-identity dependency — that drag was the whole point of killing
//  the DashSync conversion.
//

import Foundation

@objc(DWPaymentIntent)
final class PaymentIntent: NSObject {
    /// The send destination (percent-decoded). nil for inputs with no address (e.g. `dash:?r=…`,
    /// unparseable) — the processor only reaches the send path once address validity is confirmed
    /// on the parse box.
    @objc let address: String?
    /// Amount in duffs; 0 ⇒ ask (amount screen). Settable: `payToAddress:amount:` supplies a fixed
    /// send amount that is not a parse fact.
    @objc var amount: UInt64
    /// `label=` — carried as the confirm-screen name (parity with the old synthetic `commonName`).
    @objc let label: String?
    /// `message=` — carried as the confirm-screen memo and `userDetails` reconstruction.
    @objc let message: String?
    /// `sender=` x-callback-url scheme; fired after a successful broadcast.
    @objc let callbackScheme: String?
    /// `currency=` requested fiat code (confirm-screen local-currency display).
    @objc let fiatCurrencyCode: String?
    /// `local=` requested fiat amount; 0 when absent.
    @objc let fiatAmount: Float
    /// `user=` DashPay username (value carry only; DashPay routing deferred to C10).
    @objc let dashpayUsername: String?

    @objc init(address: String?,
               amount: UInt64,
               label: String?,
               message: String?,
               callbackScheme: String?,
               fiatCurrencyCode: String?,
               fiatAmount: Float,
               dashpayUsername: String?) {
        self.address = address
        self.amount = amount
        self.label = label
        self.message = message
        self.callbackScheme = callbackScheme
        self.fiatCurrencyCode = fiatCurrencyCode
        self.fiatAmount = fiatAmount
        self.dashpayUsername = dashpayUsername
        super.init()
    }
}
