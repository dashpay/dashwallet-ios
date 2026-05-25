//
//  DWIdentityAuthorizer.swift
//  DashWallet
//
//  Async wrapper around DSAuthenticationManager for the identity
//  registration flow.
//
//  Modeled on the private `SendAuthorizer` in `WalletSendService.swift`
//  (lines 129-172). Kept as a separate class rather than reusing the
//  send-side one because:
//    1. `SendAuthorizer` is fileprivate to `WalletSendService.swift`.
//    2. Identity registration deserves its own error namespace so
//       the registration UI can distinguish authentication failures
//       from FFI failures without scanning `WalletSendService`
//       error codes.
//
//  If both surfaces grow further, a future cleanup could hoist a
//  shared internal `KeychainAuthGate` and have both wrappers thin-
//  forward to it. For now, copy-then-adapt keeps the migration
//  contained.
//

import Foundation
import OSLog

/// Async PIN/biometric gate for identity registration. Wraps
/// `DSAuthenticationManager.sharedInstance().authenticate(...)` in an
/// `async throws` API so the coordinator can `await` user
/// authorization before pre-deriving identity keys.
final class DWIdentityAuthorizer {

    fileprivate static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.identity-authorizer")

    enum AuthError: LocalizedError {
        case cancelled
        case failed

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return NSLocalizedString("Authentication cancelled", comment: "DashPay identity registration")
            case .failed:
                return NSLocalizedString("Authentication failed", comment: "DashPay identity registration")
            }
        }
    }

    @MainActor
    func authorize() async throws {
        let biometricEnabled = DWGlobalOptions.sharedInstance().biometricAuthEnabled
        Self.logger.info("🪪 IDENTITY-AUTH :: calling DSAuthenticationManager.authenticate(biometric=\(biometricEnabled, privacy: .public))")
        let result = await withCheckedContinuation { continuation in
            DSAuthenticationManager.sharedInstance().authenticate(
                withPrompt: nil,
                usingBiometricAuthentication: biometricEnabled,
                alertIfLockout: true
            ) { authenticatedOrSuccess, _, cancelled in
                Self.logger.info("🪪 IDENTITY-AUTH :: authenticate callback authenticated=\(authenticatedOrSuccess, privacy: .public) cancelled=\(cancelled, privacy: .public)")
                if cancelled {
                    continuation.resume(returning: AuthorizationResult.cancelled)
                } else if authenticatedOrSuccess {
                    continuation.resume(returning: AuthorizationResult.authorized)
                } else {
                    continuation.resume(returning: AuthorizationResult.failed)
                }
            }
        }

        switch result {
        case .authorized:
            Self.logger.info("🪪 IDENTITY-AUTH :: user authorized identity registration")
            return
        case .cancelled:
            Self.logger.info("🪪 IDENTITY-AUTH :: user cancelled authentication")
            throw AuthError.cancelled
        case .failed:
            Self.logger.error("🪪 IDENTITY-AUTH :: authentication failed")
            throw AuthError.failed
        }
    }

    private enum AuthorizationResult {
        case authorized
        case cancelled
        case failed
    }
}
