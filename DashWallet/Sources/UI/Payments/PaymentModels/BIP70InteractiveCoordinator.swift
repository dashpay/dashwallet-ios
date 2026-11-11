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
    /// How many outputs the request pays. The confirm screen shows one address.
    @objc var recipientCount: Int { confirmation.recipients.count }
}

/// What the interactive (scan / link / paste / NFC) flow refuses on top of the protocol rules
/// in `BIP70PaymentService`. Kept out of the service on purpose: the headless gift-card
/// purchase shares that service and shows no confirm screen, so these rules do not apply to it.
enum BIP70InteractivePolicy {
    enum Violation: LocalizedError, Equatable {
        /// The request URL is not `https`.
        case insecureTransport
        /// An unsigned request paying more than one output.
        case unsignedMultipleRecipients

        var errorDescription: String? {
            switch self {
            case .insecureTransport:
                return NSLocalizedString("This payment request does not use a secure connection.",
                                         comment: "Payment request refused")
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

    /// Checked before the fetch.
    static func check(requestURL: URL, allowsInsecureTransport: Bool) throws {
        guard allowsInsecureTransport || requestURL.scheme?.lowercased() == "https" else {
            throw Violation.insecureTransport
        }
    }

    /// Whether sending must ask for the PIN / biometric first. A signed request keeps the two
    /// existing exemptions; an unsigned one has neither.
    static func requiresAuthentication(isSecure: Bool,
                                       spendingConfirmationDisabled: Bool,
                                       alreadyAuthorized: Bool) -> Bool {
        !(isSecure && (spendingConfirmationDisabled || alreadyAuthorized))
    }

    /// Checked on the fetched and verified request. The confirm screen shows one address, and
    /// an unsigned request has no signer answering for the others.
    static func check(_ confirmation: Confirmation) throws {
        if !confirmation.isSecure, confirmation.recipients.count > 1 {
            throw Violation.unsignedMultipleRecipients
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

    private let service: BIP70PaymentService

    @objc override init() {
        service = BIP70PaymentService.makeForCurrentWallet(
            requiresHTTPSFetch: !BIP70InteractivePolicy.allowsInsecureTransport)
        super.init()
    }

    /// `BIP70InteractivePolicy.requiresAuthentication` for the ObjC payment processor.
    @objc(requiresAuthenticationForSecureRequest:spendingConfirmationDisabled:alreadyAuthorized:)
    static func requiresAuthentication(isSecure: Bool,
                                       spendingConfirmationDisabled: Bool,
                                       alreadyAuthorized: Bool) -> Bool {
        BIP70InteractivePolicy.requiresAuthentication(isSecure: isSecure,
                                                      spendingConfirmationDisabled: spendingConfirmationDisabled,
                                                      alreadyAuthorized: alreadyAuthorized)
    }

    /// Fetch + verify a BIP70 request (no build, no spend). Completion fires on the main thread.
    @objc(fetchAndVerifyWithRequestURL:scheme:callbackScheme:completion:)
    func fetchAndVerify(requestURL: URL,
                        scheme: String,
                        callbackScheme: String?,
                        completion: @escaping (BIP70ConfirmationBox?, NSError?) -> Void) {
        let normalizedScheme = Self.normalize(scheme)
        Task {
            do {
                try BIP70InteractivePolicy.check(
                    requestURL: requestURL,
                    allowsInsecureTransport: BIP70InteractivePolicy.allowsInsecureTransport)
                let network = try PaymentNetworkResolver.current()
                let confirmation = try await service.prepareForConfirmation(
                    from: requestURL, scheme: normalizedScheme, network: network, callbackScheme: callbackScheme)
                try BIP70InteractivePolicy.check(confirmation)
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

    private static func nsError(_ error: Error) -> NSError {
        if let bip = error as? BIP70Error {
            return NSError(domain: "org.dashfoundation.dash.bip70",
                           code: 1,
                           userInfo: [NSLocalizedDescriptionKey: bip.errorDescription ?? "Payment failed"])
        }
        if let violation = error as? BIP70InteractivePolicy.Violation {
            return NSError(domain: "org.dashfoundation.dash.bip70",
                           code: 3,
                           userInfo: [NSLocalizedDescriptionKey: violation.errorDescription ?? "Payment failed"])
        }
        return error as NSError
    }
}
