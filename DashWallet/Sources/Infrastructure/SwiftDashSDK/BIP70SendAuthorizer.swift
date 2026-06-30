//
//  BIP70SendAuthorizer.swift
//  DashWallet
//
//  BIP70 Layer 6 adapter — implements the protocol-core `SendAuthorizing` over the app's
//  PIN/biometric gate (`DSAuthenticationManager`), mapping user-cancel to
//  `BIP70Error.authCancelled`. Used by the headless (CTX) path; the interactive path
//  authenticates inside `DWPaymentProcessor` before calling the coordinator.
//
//  Mirrors the private `SendAuthorizer` in WalletSendService.swift (which isn't visible here).
//

import Foundation

final class BIP70SendAuthorizer: SendAuthorizing {
    func authorize() async throws {
        // Routes through the shared timeout-guarded gate (in WalletSendService.swift) so a
        // silently-non-presenting PIN prompt can never hang the headless flow forever.
        let outcome = await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled)

        switch outcome {
        case .ok:
            return
        case .cancelled:
            throw BIP70Error.authCancelled
        case .failed, .timedOut:
            throw NSError(domain: "org.dashfoundation.dash.bip70",
                          code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])
        }
    }
}
