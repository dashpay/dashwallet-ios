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
}

/// Opaque carrier for a completed `SendResult`.
@objc(DWBIP70SendResultBox)
final class BIP70SendResultBox: NSObject {
    let result: SendResult
    init(_ result: SendResult) { self.result = result }

    @objc var signedTxData: Data { result.signedTxData }
    @objc var txidHexDisplay: String { result.txidHexDisplay }
    @objc var callbackURL: URL? { result.callbackURL }
    @objc var ackMemo: String? { result.ackMemo }
}

@objc(DWBIP70InteractiveCoordinator)
final class BIP70InteractiveCoordinator: NSObject {

    private let service: BIP70PaymentService

    @objc override init() {
        service = BIP70PaymentService.makeForCurrentWallet()
        super.init()
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
                let network = try PaymentNetworkResolver.current()
                let confirmation = try await service.prepareForConfirmation(
                    from: requestURL, scheme: normalizedScheme, network: network, callbackScheme: callbackScheme)
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
        return error as NSError
    }
}
