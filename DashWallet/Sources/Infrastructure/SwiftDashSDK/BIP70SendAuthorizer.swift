//
//  BIP70SendAuthorizer.swift
//  DashWallet
//
//  BIP70 Layer 6 adapter — implements the protocol-core `SendAuthorizing` as a thin
//  BIP70-error-namespace adapter over the shared internal `AuthenticationGate`
//  (WalletSendService.swift), mapping user-cancel to `BIP70Error.authCancelled`.
//  Used by the headless (CTX) path; the interactive path authenticates inside
//  `DWPaymentProcessor` (via the same gate) before calling the coordinator.
//

import Foundation

final class BIP70SendAuthorizer: SendAuthorizing {
    func authorize(spendAmount: UInt64) async throws {
        // Routes through the shared timeout-guarded gate (in WalletSendService.swift) so a
        // silently-non-presenting PIN prompt can never hang the headless flow forever.
        // The amount engages the biometric spending limit, as for any other send.
        let outcome = await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            spendAmount: spendAmount)

        switch outcome {
        case .ok:
            return
        case .cancelled:
            throw BIP70Error.authCancelled
        case .failed, .timedOut:
            throw NSError(domain: "org.dashfoundation.dash.bip70",
                          code: 2,
                          userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Authentication failed", comment: "BIP70 payment error")])
        }
    }
}
