//
//  BIP70InteractiveCoordinator.swift
//  DashWallet
//
//  BIP70 Layer 6 — the @objc bridge between the ObjC `DWPaymentProcessor` (interactive QR /
//  deep-link / clipboard flow) and the pure-Swift `BIP70PaymentService`. ObjC can't `await`, so
//  the surface is completion-based; the opaque boxes carry the Swift `Confirmation`/`SendResult`
//  across the language boundary without exposing their (tuple-bearing) shapes to ObjC.
//

import Foundation

/// Opaque carrier for a prepared `Confirmation` handed to / from ObjC. ObjC reads the @objc
/// accessors to build the confirm-screen `DWPaymentOutput`; it hands the same box back to
/// `confirmAndSend`.
@objc(DWBIP70ConfirmationBox)
final class BIP70ConfirmationBox: NSObject {
    let confirmation: Confirmation
    init(_ confirmation: Confirmation) { self.confirmation = confirmation }

    @objc var merchantName: String? { confirmation.merchantName }
    @objc var isSecure: Bool { confirmation.isSecure }
    @objc var amount: UInt64 { confirmation.amount }
    @objc var estimatedFee: UInt64 { confirmation.estimatedFee }
    @objc var primaryAddress: String? { confirmation.primaryAddress }
    @objc var memo: String? { confirmation.memo }
    /// How many different addresses the request pays. The confirm screen shows one address.
    @objc var recipientCount: Int { BIP70InteractivePolicy.addressCount(of: confirmation) }
}

/// What the interactive (scan / link / paste / NFC) flow refuses on top of the protocol rules
/// in `BIP70PaymentService`. Kept out of the service on purpose: the headless gift-card
/// purchase shares that service and shows no confirm screen, so these rules do not apply to it.
enum BIP70InteractivePolicy {
    enum Violation: LocalizedError, Equatable {
        /// An unsigned request paying more than one address.
        case unsignedMultipleRecipients

        var errorDescription: String? {
            switch self {
            case .unsignedMultipleRecipients:
                return NSLocalizedString("This payment request is unsigned and pays more than one address.",
                                         comment: "Payment request refused")
            }
        }
    }

    /// Debug builds may fetch over plain http, which the local test server in
    /// `BIP70_TESTING.md` uses.
    static var allowsInsecureTransport: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Whether sending must ask for the PIN / biometric first. A signed request follows the
    /// "spending confirmation" setting; an unsigned one always asks.
    static func requiresAuthentication(isSecure: Bool, spendingConfirmationDisabled: Bool) -> Bool {
        !(isSecure && spendingConfirmationDisabled)
    }

    /// Different addresses among the request's outputs.
    static func addressCount(of confirmation: Confirmation) -> Int {
        Set(confirmation.recipients.map(\.address)).count
    }

    /// Checked on the fetched and verified request, before the confirm screen. The screen shows
    /// one address, and an unsigned request has no signer answering for the others. The
    /// `payment_url` is checked here so an http one is refused before anything is built; the
    /// request URL and its hops are the transport's (`requiresHTTPS`).
    static func check(_ confirmation: Confirmation, allowsInsecureTransport: Bool) throws {
        if !confirmation.isSecure, addressCount(of: confirmation) > 1 {
            throw Violation.unsignedMultipleRecipients
        }
        if !allowsInsecureTransport, let paymentURL = confirmation.paymentURL,
           !PaymentProtocolTransport.isHTTPS(paymentURL) {
            throw BIP70Error.insecureTransport
        }
    }
}

/// Opaque carrier for a completed `SendResult`.
@objc(DWBIP70SendResultBox)
final class BIP70SendResultBox: NSObject {
    let result: SendResult
    init(_ result: SendResult) { self.result = result }

    @objc var txidHexDisplay: String { result.txidHexDisplay }
    /// Wire-order txid (`Transaction.txHashData` convention) for the retyped
    /// send-success delegate; `result.txHashDisplay` reversed.
    @objc var txidWire: Data { Data(result.txHashDisplay.reversed()) }
    @objc var callbackURL: URL? { result.callbackURL }
    @objc var ackMemo: String? { result.ackMemo }
}

@objc(DWBIP70InteractiveCoordinator)
final class BIP70InteractiveCoordinator: NSObject {

    /// NSError code of a request the app refused by rule (not https, or unsigned and paying
    /// more than one address), as opposed to one that failed to load or verify.
    static let refusalErrorCode = 3
    private static let errorDomain = "org.dashfoundation.dash.bip70"

    private let service: BIP70PaymentService
    private let allowsInsecureTransport: Bool

    @objc override convenience init() {
        let allowsInsecureTransport = BIP70InteractivePolicy.allowsInsecureTransport
        self.init(service: BIP70PaymentService.makeForCurrentWallet(requiresHTTPS: !allowsInsecureTransport),
                  allowsInsecureTransport: allowsInsecureTransport)
    }

    init(service: BIP70PaymentService, allowsInsecureTransport: Bool) {
        self.service = service
        self.allowsInsecureTransport = allowsInsecureTransport
        super.init()
    }

    /// `BIP70InteractivePolicy.requiresAuthentication` for the ObjC payment processor, read
    /// off the output it is about to send.
    @objc(requiresAuthenticationForPaymentOutput:spendingConfirmationDisabled:)
    static func requiresAuthentication(for output: DWPaymentOutput, spendingConfirmationDisabled: Bool) -> Bool {
        BIP70InteractivePolicy.requiresAuthentication(isSecure: output.isSecure,
                                                      spendingConfirmationDisabled: spendingConfirmationDisabled)
    }

    /// Whether `error` (as delivered by `fetchAndVerify`) is a refusal by rule.
    @objc(isRefusalError:)
    static func isRefusal(_ error: NSError) -> Bool {
        error.domain == errorDomain && error.code == refusalErrorCode
    }

    /// Fetch + verify, then apply the interactive rules. No build, no spend.
    func prepare(requestURL: URL, scheme: String, callbackScheme: String?,
                 network: PaymentNetwork) async throws -> Confirmation {
        let confirmation = try await service.prepareForConfirmation(
            from: requestURL, scheme: Self.normalize(scheme), network: network, callbackScheme: callbackScheme)
        try BIP70InteractivePolicy.check(confirmation, allowsInsecureTransport: allowsInsecureTransport)
        return confirmation
    }

    /// Fetch + verify a BIP70 request (no build, no spend). Completion fires on the main thread.
    @objc(fetchAndVerifyWithRequestURL:scheme:callbackScheme:completion:)
    func fetchAndVerify(requestURL: URL,
                        scheme: String,
                        callbackScheme: String?,
                        completion: @escaping (BIP70ConfirmationBox?, NSError?) -> Void) {
        Task {
            do {
                let network = try PaymentNetworkResolver.current()
                let confirmation = try await prepare(requestURL: requestURL, scheme: scheme,
                                                     callbackScheme: callbackScheme, network: network)
                await MainActor.run { completion(BIP70ConfirmationBox(confirmation), nil) }
            } catch {
                await MainActor.run { completion(nil, Self.nsError(error)) }
            }
        }
    }

    /// Build → broadcast → POST the Payment. The caller must have authenticated already (the
    /// interactive path PIN-gates before calling this). Completion fires on the main thread.
    @objc(confirmAndSend:completion:)
    func confirmAndSend(_ box: BIP70ConfirmationBox,
                        completion: @escaping (BIP70SendResultBox?, NSError?) -> Void) {
        Task {
            do {
                let result = try await service.confirmAndSend(box.confirmation)
                // Record BEFORE the ObjC completion fires the send-success
                // delegate, so the success screen's registry fallback is
                // already populated. The pure BIP70 layer can't write the
                // registry itself (it is deliberately SDK/DW-free).
                WalletSendService.shared.recentSends.record(
                    txidWire: Data(result.txHashDisplay.reversed()),
                    address: result.primaryAddress,
                    amount: result.amount,
                    fee: result.fee)
                await MainActor.run { completion(BIP70SendResultBox(result), nil) }
            } catch {
                await MainActor.run { completion(nil, Self.nsError(error)) }
            }
        }
    }

    // MARK: - Helpers

    private static func normalize(_ scheme: String) -> String {
        switch scheme.lowercased() {
        case "pay", "dashwallet": return "dash"
        default: return scheme.lowercased()
        }
    }

    static func nsError(_ error: Error) -> NSError {
        if let bip = error as? BIP70Error {
            return NSError(domain: errorDomain,
                           code: bip == .insecureTransport ? refusalErrorCode : 1,
                           userInfo: [NSLocalizedDescriptionKey: bip.errorDescription ?? "Payment failed"])
        }
        if let violation = error as? BIP70InteractivePolicy.Violation {
            return NSError(domain: errorDomain,
                           code: refusalErrorCode,
                           userInfo: [NSLocalizedDescriptionKey: violation.errorDescription ?? "Payment failed"])
        }
        return error as NSError
    }
}
