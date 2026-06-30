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

private enum BIP70AuthResult { case ok, cancelled, failed }

final class BIP70SendAuthorizer: SendAuthorizing {
    func authorize() async throws {
        let result: BIP70AuthResult = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                DSAuthenticationManager.sharedInstance().authenticate(
                    withPrompt: nil,
                    usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
                    alertIfLockout: true
                ) { authenticatedOrSuccess, _, cancelled in
                    if cancelled {
                        continuation.resume(returning: .cancelled)
                    } else if authenticatedOrSuccess {
                        continuation.resume(returning: .ok)
                    } else {
                        continuation.resume(returning: .failed)
                    }
                }
            }
        }

        switch result {
        case .ok:
            return
        case .cancelled:
            throw BIP70Error.authCancelled
        case .failed:
            throw NSError(domain: "org.dashfoundation.dash.bip70",
                          code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])
        }
    }
}
