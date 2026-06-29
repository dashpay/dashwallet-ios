//
//  BIP70PaymentService.swift
//  DashWallet
//
//  BIP70 payment-protocol — orchestrator (Layer 5).
//
//  The only layer that knows the *whole* flow: fetch → verify → network-match → expiry →
//  resolve outputs → confirm → build/sign → broadcast → POST Payment → ACK. It drives L1–L4
//  and the injected wallet/receive/auth dependencies, replacing DashSync's
//  `DSTransactionManager confirmProtocolRequest:` orchestration and routing the spend through
//  the funded SwiftDashSDK wallet.
//
//  Pure: Foundation only. No UIKit / SwiftDashSDK / DS*/DW* / DWEnvironment. The wallet,
//  receive-address, and PIN/biometric auth arrive via the three protocols below; the active
//  network arrives as a `PaymentNetwork` token resolved at the L5/L6 boundary.
//
//  Spend-safety invariant: `prepareForConfirmation` NEVER builds and NEVER spends — building
//  (which, in the interim build-bundles-broadcast world, also broadcasts) happens ONLY inside
//  `confirmAndSend`. No consumer can move money before it explicitly calls `confirmAndSend`.
//
//  Ordering (interim): build+sign → broadcast → POST Payment (best-effort, soft-fail because
//  the coins have already moved). When the additive build-without-broadcast FFI lands, flip to
//  the BIP70-correct build → POST → broadcast — a localized reorder inside `confirmAndSend`
//  (see the TODO there). The `WalletSending` seam is shaped for that flip.
//

import Foundation

// MARK: - Injected dependencies (implemented in L6 over the real SDK/app surfaces)

/// Build/sign/broadcast over the funded SwiftDashSDK wallet.
protocol WalletSending {
    /// Build + sign a multi-recipient tx. (Interim L6 impl also broadcasts — see file header.)
    func buildSignedTransaction(recipients: [(address: String, amountDuffs: UInt64)]) async throws -> PreparedSend
    /// Broadcast a previously-prepared tx; returns the display-order txid hex.
    /// (Interim L6 impl is a no-op returning the prepared txid — the tx is already live.)
    func broadcast(_ prepared: PreparedSend) async throws -> String
}

/// The wallet's own next receive address, for `Payment.refund_to`. nil ⇒ send empty refund_to.
protocol ReceiveAddressProviding {
    func receiveAddress() -> String?
}

/// PIN / biometric gate. Returns on success; throws `BIP70Error.authCancelled` on user cancel.
protocol SendAuthorizing {
    func authorize() async throws
}

// MARK: - Value types

/// Opaque built-and-signed transaction handle. Mirrors the SDK tuple `(txData, fee, txHash)`.
struct PreparedSend: Equatable {
    /// Serialized signed tx bytes — become `Payment.transactions[0]` and feed the L6 `DSTransaction` shim.
    let txData: Data
    /// Fee in duffs (preview-grade: the SDK approximates it as the tx byte count).
    let fee: UInt64
    /// 32-byte txid in **display order** (double-SHA256, byte-reversed). Logging / callback only.
    let txHashDisplay: Data

    init(txData: Data, fee: UInt64, txHashDisplay: Data) {
        self.txData = txData
        self.fee = fee
        self.txHashDisplay = txHashDisplay
    }
}

/// The fully-prepared, ready-to-send result of `prepareForConfirmation`. Carries no
/// `PreparedSend` — nothing is built yet (spend-safety invariant).
struct Confirmation {
    let merchantName: String?
    /// true only for a trusted x509 request; false for `pki_type == "none"`.
    let isSecure: Bool
    /// Resolved outputs in request order (multi-recipient merchants supported).
    let recipients: [(address: String, amount: UInt64)]
    /// Σ recipient amounts (what the merchant receives).
    let amount: UInt64
    /// Preview-grade size estimate; the real built fee comes back in `SendResult`.
    let estimatedFee: UInt64
    var estimatedTotal: UInt64 { amount + estimatedFee } // fee charged ON TOP
    let network: PaymentNetwork
    /// POST target for the Payment. nil ⇒ no merchant round-trip (plain address-style request).
    let paymentURL: URL?
    /// "dash"/"bitcoin" — drives the L3 content-type headers.
    let scheme: String
    /// Echoed verbatim into `Payment.merchantData` (BIP70 round-trips it).
    let merchantData: Data?
    /// Merchant memo from `PaymentDetails` (UI subtitle).
    let memo: String?
    /// From `?sender=` — the scheme L6 opens for the x-callback-url after a good send.
    let callbackScheme: String?
    /// The original request, for the send-time expiry re-check and audit.
    let request: PaymentRequest

    var primaryAddress: String? { recipients.first?.address }
}

/// Outcome of a completed send: the tx was broadcast; the merchant round-trip was attempted.
struct SendResult {
    /// Signed tx bytes, so L6 can build `DSTransaction(message:on:)` for `payWithDashUrl`'s return.
    let signedTxData: Data
    /// Display-order txid hex — logging / UI / callback only (NOT the CTX authoritative txid).
    let txidHexDisplay: String
    /// The actual built fee in duffs.
    let fee: UInt64
    /// Merchant ACK memo, if any. nil when there was no POST or the POST/ACK soft-failed.
    let ackMemo: String?
    /// Ready-to-open x-callback-url, or nil. L6 performs `UIApplication.open`.
    let callbackURL: URL?
}

// MARK: - Service

final class BIP70PaymentService {

    private let transport: PaymentProtocolTransporting
    private let verifier: PaymentRequestVerifier
    private let wallet: WalletSending
    private let receiveAddress: ReceiveAddressProviding
    private let auth: SendAuthorizing
    /// When true, allow unsigned (`pki_type == "none"`) requests. Invalid SIGNED requests are
    /// always blocked regardless of this flag.
    private let allowUntrustedUnsigned: Bool

    init(transport: PaymentProtocolTransporting = PaymentProtocolTransport(),
         verifier: PaymentRequestVerifier = PaymentRequestVerifier(),
         wallet: WalletSending,
         receiveAddress: ReceiveAddressProviding,
         auth: SendAuthorizing,
         allowUntrustedUnsigned: Bool = true) {
        self.transport = transport
        self.verifier = verifier
        self.wallet = wallet
        self.receiveAddress = receiveAddress
        self.auth = auth
        self.allowUntrustedUnsigned = allowUntrustedUnsigned
    }

    // MARK: Prepare (no build, no spend)

    /// Fetch → verify → policy → network-match → expiry → resolve outputs. Builds nothing and
    /// spends nothing; the returned `Confirmation` is what the confirm UI / headless path acts on.
    func prepareForConfirmation(from requestURL: URL,
                                scheme: String,
                                network: PaymentNetwork,
                                callbackScheme: String? = nil,
                                now: Date = Date()) async throws -> Confirmation {

        // 1. Fetch (L3).
        let request = try await transport.fetchRequest(from: requestURL, scheme: scheme)

        // 2. Verify (L2): X.509 chain + signature + (when valid) expiry.
        let verdict = verifier.verify(request, now: now)

        // 3. Untrusted-cert policy.
        if request.pkiType != "none" {
            // Signed: must be valid. Always blocked otherwise, regardless of the flag.
            guard verdict.isValid else {
                throw BIP70Error.untrustedCertificate(detail: verdict.errorMessage)
            }
        } else {
            // Unsigned: allowed iff the flag permits. Expiry still applies.
            guard allowUntrustedUnsigned else {
                throw BIP70Error.untrustedCertificate(detail: "Unsigned request")
            }
            if !verdict.isValid { throw BIP70Error.expired }
        }

        let details = request.details

        // 4. Network match. nil ⇒ no check (use active network); recognized ⇒ must equal it;
        //    present-but-unrecognized ⇒ mismatch.
        if let netString = details.network {
            if let requested = Self.paymentNetwork(fromString: netString) {
                guard requested == network else {
                    throw BIP70Error.networkMismatch(requested: netString)
                }
            } else {
                throw BIP70Error.networkMismatch(requested: netString)
            }
        }

        // 5. Expiry re-check (cheap defense-in-depth so prepare never returns an expired
        //    Confirmation). The authoritative re-check is at send time in confirmAndSend, since
        //    the user may linger on the confirm screen between prepare and send.
        try Self.assertNotExpired(details.expires, now: now)

        // 6. Resolve outputs (L4): scriptPubKey → address. Throws .nonStandardScript /
        //    .malformedRequest. Order preserved, all-or-nothing.
        let recipients = try ScriptAddressCodec.resolveOutputs(details.outputs, network: network)
        guard !recipients.isEmpty else { throw BIP70Error.malformedRequest }

        let amount = recipients.reduce(UInt64(0)) { $0 + $1.amount }
        return Confirmation(
            merchantName: verdict.commonName,
            isSecure: verdict.isSecure,
            recipients: recipients,
            amount: amount,
            estimatedFee: Self.estimatedFee(recipientCount: recipients.count),
            network: network,
            paymentURL: details.paymentURL.flatMap { URL(string: $0) },
            scheme: scheme,
            merchantData: details.merchantData,
            memo: details.memo,
            callbackScheme: callbackScheme,
            request: request)
    }

    // MARK: Send (the only spend point)

    /// Build/sign → broadcast → (if a payment_url) POST the Payment + read the ACK. The merchant
    /// round-trip is best-effort: once broadcast has happened, a POST/ACK failure is a soft-fail
    /// (the coins have moved) — we return success with `ackMemo == nil` rather than throwing.
    func confirmAndSend(_ confirmation: Confirmation, now: Date = Date()) async throws -> SendResult {

        // 1. Expiry re-check at send time (the user may have lingered on the confirm screen).
        try Self.assertNotExpired(confirmation.request.details.expires, now: now)

        // 2. A signed merchant request with nowhere to POST is invalid.
        if confirmation.isSecure, confirmation.paymentURL == nil {
            throw BIP70Error.missingPaymentURL
        }

        // 3. Build + sign. (Interim: this also broadcasts.)
        let sdkRecipients = confirmation.recipients.map { (address: $0.address, amountDuffs: $0.amount) }
        let prepared = try await wallet.buildSignedTransaction(recipients: sdkRecipients)

        // 4. Broadcast. (Interim: no-op returning the prepared txid.)
        // TODO(P0 flip): once the build-without-broadcast FFI lands, move this step AFTER a
        // successful POST below and promote POST transport failures to a hard throw
        // (.ackRejected / .unexpectedResponse) so a rejecting merchant aborts before any spend.
        let txidHexDisplay = try await wallet.broadcast(prepared)

        // 5. Merchant round-trip, if there's a payment_url.
        var ackMemo: String?
        if let url = confirmation.paymentURL {
            let refundTo = makeRefundOutputs(amount: confirmation.amount, network: confirmation.network)
            let payment = Payment(merchantData: confirmation.merchantData,
                                  transactions: [prepared.txData],
                                  refundTo: refundTo,
                                  memo: nil)
            do {
                let ack = try await transport.postPayment(payment, to: url, scheme: confirmation.scheme)
                ackMemo = ack.memo
            } catch {
                // Soft-fail: the tx is already on the network; do NOT roll back. The merchant
                // can reconcile from chain. (Becomes a hard failure in the post-P0 flip above.)
                ackMemo = nil
            }
        }

        let callbackURL = Self.makeCallbackURL(scheme: confirmation.callbackScheme,
                                               address: confirmation.primaryAddress,
                                               txidHexDisplay: txidHexDisplay)
        return SendResult(signedTxData: prepared.txData,
                          txidHexDisplay: txidHexDisplay,
                          fee: prepared.fee,
                          ackMemo: ackMemo,
                          callbackURL: callbackURL)
    }

    /// One-shot entry for headless flows (CTX gift cards): authorize, then prepare + send.
    func confirmAndSendHeadless(from requestURL: URL,
                                scheme: String,
                                network: PaymentNetwork,
                                callbackScheme: String? = nil,
                                now: Date = Date()) async throws -> SendResult {
        try await auth.authorize()
        let confirmation = try await prepareForConfirmation(from: requestURL, scheme: scheme,
                                                            network: network, callbackScheme: callbackScheme, now: now)
        return try await confirmAndSend(confirmation, now: now)
    }

    // MARK: Helpers

    /// `Payment.refund_to` = our own receive address as a single P2PKH output for the full amount.
    /// A nil/undecodable receive address yields an empty refund_to (valid BIP70), not a failure.
    private func makeRefundOutputs(amount: UInt64, network: PaymentNetwork) -> [PaymentOutput] {
        guard let mine = receiveAddress.receiveAddress(),
              let script = ScriptAddressCodec.scriptPubKey(forAddress: mine, network: network) else {
            return []
        }
        return [PaymentOutput(amount: amount, script: script)]
    }

    private static func assertNotExpired(_ expires: UInt64, now: Date) throws {
        if expires >= 1, now.timeIntervalSince1970 > Double(expires) {
            throw BIP70Error.expired
        }
    }

    /// Maps a BIP70 `details.network` string to a `PaymentNetwork`. nil ⇒ unknown/absent.
    /// Reproduces DashSync's `chainForNetworkName:` value set.
    static func paymentNetwork(fromString string: String?) -> PaymentNetwork? {
        switch string?.lowercased() {
        case "main", "live", "livenet", "mainnet": return .mainnet
        case "test", "testnet": return .testnet
        default: return nil
        }
    }

    /// Preview-grade fee estimate (duffs ≈ bytes): version/locktime overhead + one input + one
    /// output per recipient + a change output. The authoritative fee is the built one.
    static func estimatedFee(recipientCount: Int) -> UInt64 {
        let overhead = 10, perInput = 148, perOutput = 34
        return UInt64(overhead + perInput + perOutput * (recipientCount + 1))
    }

    /// Builds the x-callback-url string L6 opens after a good send. Matches the legacy
    /// `DWPaymentProcessor` format. nil unless both a callback scheme and a primary address exist.
    static func makeCallbackURL(scheme: String?, address: String?, txidHexDisplay: String) -> URL? {
        guard let scheme, let address else { return nil }
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
        return URL(string: "\(scheme)://callback=payack&address=\(encoded)&txid=\(txidHexDisplay)")
    }
}
