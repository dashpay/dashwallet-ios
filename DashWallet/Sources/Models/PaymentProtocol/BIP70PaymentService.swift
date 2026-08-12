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
//  and broadcasting happen ONLY inside `confirmAndSend`. No consumer can move money before it
//  explicitly calls `confirmAndSend`.
//
//  Ordering: build+sign → broadcast → POST Payment (best-effort, soft-fail because the coins
//  have already moved by POST time). The SDK build/broadcast split is real (`buildSignedTransaction`
//  returns a held tx; `broadcast(_:)` submits it), so the BIP70-correct build → POST → broadcast
//  reorder is now unblocked — a localized reorder inside `confirmAndSend` plus promoting POST
//  failures to a hard throw (see the TODO there). The `WalletSending` seam is shaped for that flip.
//

import Foundation

// MARK: - Injected dependencies (implemented in L6 over the real SDK/app surfaces)

/// Build/sign/broadcast over the funded SwiftDashSDK wallet.
protocol WalletSending {
    /// Build + sign a multi-recipient tx. Does NOT broadcast — the returned `PreparedSend`
    /// carries the built transaction handle for a later `broadcast(_:)`.
    func buildSignedTransaction(recipients: [(address: String, amountDuffs: UInt64)]) async throws -> PreparedSend
    /// Broadcast a previously-prepared tx; returns the display-order txid hex.
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

// MARK: - Single-use guard

/// One-shot send claim shared across copies of a `Confirmation`. `Confirmation` is a value type,
/// but this guard is a reference, so every copy (e.g. the reused `BIP70ConfirmationBox` on an
/// interactive retry) shares one claim — letting `confirmAndSend` reject a second send (a
/// concurrent double-tap, or a re-tap after a successful spend) while a fresh (headless)
/// `Confirmation` always starts unclaimed. Foundation-only; iOS-14-safe (manual `NSLock`).
final class BIP70SendGuard {
    private let lock = NSLock()
    private var claimed = false

    /// Atomically claims the single send slot. Throws `.alreadySent` if it is already claimed.
    func begin() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { throw BIP70Error.alreadySent }
        claimed = true
    }

    /// Releases the claim so a pre-spend failure can be retried on the same `Confirmation`.
    func reset() {
        lock.lock()
        claimed = false
        lock.unlock()
    }
}

// MARK: - Value types

/// Opaque built-and-signed transaction handle.
struct PreparedSend: Equatable {
    /// Serialized signed tx bytes — become `Payment.transactions[0]` and feed the L6 `DSTransaction` shim.
    let txData: Data
    /// Exact fee in duffs, settled by the SDK's coin selection when the tx was built.
    let fee: UInt64
    /// 32-byte txid in **display order** (double-SHA256, byte-reversed). Logging / callback only.
    let txHashDisplay: Data
    /// Opaque SDK transaction handle (the built `FinalizedCoreTransaction`), carried so the
    /// L6 adapter can broadcast the exact built tx. Kept as `AnyObject` so this module stays
    /// Foundation-only. nil in test fakes. Excluded from equality.
    let sdkTransaction: AnyObject?

    init(txData: Data, fee: UInt64, txHashDisplay: Data, sdkTransaction: AnyObject? = nil) {
        self.txData = txData
        self.fee = fee
        self.txHashDisplay = txHashDisplay
        self.sdkTransaction = sdkTransaction
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.txData == rhs.txData && lhs.fee == rhs.fee && lhs.txHashDisplay == rhs.txHashDisplay
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
    /// Single-use claim so the same prepared confirmation can't be sent twice (see `confirmAndSend`).
    /// Default-initialized: a reference shared by every value copy of this `Confirmation`.
    let sendGuard = BIP70SendGuard()

    var primaryAddress: String? { recipients.first?.address }
}

/// Outcome of a completed send: the tx was broadcast; the merchant round-trip was attempted.
struct SendResult {
    /// Display-order txid hex — logging / UI / callback only (NOT the CTX authoritative txid).
    let txidHexDisplay: String
    /// Display-order txid bytes (the same value as `txidHexDisplay`, binary) —
    /// L6 reverses these to wire order for the recent-sends registry key.
    let txHashDisplay: Data
    /// The actual built fee in duffs.
    let fee: UInt64
    /// Σ recipient amounts (duffs) — what the merchant receives, fee excluded.
    let amount: UInt64
    /// First recipient address, for the send-success screen's "Sent to" line.
    let primaryAddress: String?
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
    /// App-layer policy check. Kept injectable so this protocol core remains
    /// independent of the wallet runtime and can prove pre-auth ordering.
    private let coreSpendPreflight: () async throws -> Void
    /// When true, allow unsigned (`pki_type == "none"`) requests. Invalid SIGNED requests are
    /// always blocked regardless of this flag.
    private let allowUntrustedUnsigned: Bool

    init(transport: PaymentProtocolTransporting = PaymentProtocolTransport(),
         verifier: PaymentRequestVerifier = PaymentRequestVerifier(),
         wallet: WalletSending,
         receiveAddress: ReceiveAddressProviding,
         auth: SendAuthorizing,
         coreSpendPreflight: @escaping () async throws -> Void,
         allowUntrustedUnsigned: Bool = true) {
        self.transport = transport
        self.verifier = verifier
        self.wallet = wallet
        self.receiveAddress = receiveAddress
        self.auth = auth
        self.coreSpendPreflight = coreSpendPreflight
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

    /// Build/sign → (if a payment_url) POST the Payment + read the ACK → broadcast. BIP70-correct
    /// ordering: the merchant sees the signed transaction and acknowledges it BEFORE any coins
    /// move, so a rejecting or unreachable merchant stops the spend with the money unspent.
    ///
    /// Send-guard invariant: the guard resets (retry allowed) only while nothing has been
    /// broadcast — build/sign failures and POST/ACK failures. Once broadcast is attempted the
    /// guard is never reset: the merchant holds the signed bytes and may broadcast them
    /// independently, so a retry would rebuild a conflicting spend of the same inputs.
    func confirmAndSend(_ confirmation: Confirmation, now: Date = Date()) async throws -> SendResult {

        // This is the hard service backstop. Interactive callers also check
        // before PIN, but no caller may reach build/sign while blocked.
        try await coreSpendPreflight()

        // 1. Expiry re-check at send time (the user may have lingered on the confirm screen).
        try Self.assertNotExpired(confirmation.request.details.expires, now: now)

        // 2. A signed merchant request with nowhere to POST is invalid.
        if confirmation.isSecure, confirmation.paymentURL == nil {
            throw BIP70Error.missingPaymentURL
        }

        // 3. Claim the single-use send slot AFTER the pre-spend checks (so an expired/no-URL
        //    request stays freely retryable). A concurrent double-tap or a re-tap after a
        //    successful spend — both share this confirmation's guard — is rejected with .alreadySent.
        try confirmation.sendGuard.begin()

        // 4. Build + sign only — nothing is broadcast yet, so any throw releases the claim.
        let prepared: PreparedSend
        do {
            let sdkRecipients = confirmation.recipients.map { (address: $0.address, amountDuffs: $0.amount) }
            prepared = try await wallet.buildSignedTransaction(recipients: sdkRecipients)
        } catch {
            confirmation.sendGuard.reset()
            throw error
        }

        // 5. Merchant round-trip BEFORE broadcast, if there's a payment_url. A decoded ACK is
        //    the acknowledgement (BIP70 has no reject bit — rejection surfaces as an HTTP or
        //    decode failure). A failure here is a hard throw with the money unspent; the guard
        //    resets so the user can retry. Caveat (accepted): a POST that fails after the
        //    merchant received the bytes leaves them able to broadcast independently while a
        //    retry rebuilds a conflicting tx.
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
                confirmation.sendGuard.reset()
                throw (error as? BIP70Error) ?? BIP70Error.ackRejected
            }
        }

        // 6. Broadcast. From this point the guard is never reset — see the invariant above.
        let txidHexDisplay = try await wallet.broadcast(prepared)

        let callbackURL = Self.makeCallbackURL(scheme: confirmation.callbackScheme,
                                               address: confirmation.primaryAddress,
                                               txidHexDisplay: txidHexDisplay)
        return SendResult(txidHexDisplay: txidHexDisplay,
                          txHashDisplay: prepared.txHashDisplay,
                          fee: prepared.fee,
                          amount: confirmation.amount,
                          primaryAddress: confirmation.primaryAddress,
                          ackMemo: ackMemo,
                          callbackURL: callbackURL)
    }

    /// One-shot entry for headless flows (CTX gift cards): policy, authorize,
    /// then prepare + send. The policy must reject before any PIN prompt.
    func confirmAndSendHeadless(from requestURL: URL,
                                scheme: String,
                                network: PaymentNetwork,
                                callbackScheme: String? = nil,
                                now: Date = Date()) async throws -> SendResult {
        try await coreSpendPreflight()
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
