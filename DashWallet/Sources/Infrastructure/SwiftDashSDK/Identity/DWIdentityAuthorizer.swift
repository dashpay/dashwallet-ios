//
//  DWIdentityAuthorizer.swift
//  DashWallet
//
//  Thin adapter over the shared `AuthenticationGate` (WalletSendService.swift)
//  that keeps a dedicated error namespace for the identity/shielded flows, so
//  their coordinators can distinguish authentication failures from FFI
//  failures without scanning `WalletSendService` error codes. The gate owns
//  the actual DSAuthenticationManager call and its 120 s watchdog (a
//  silently-non-presenting PIN prompt resumes as `.timedOut` instead of
//  hanging the awaiting coordinator forever).
//

import Foundation
import OSLog

/// Async PIN/biometric gate for identity registration, profile updates, and
/// shielded transfers. `await`-able so coordinators can gate work on user
/// authorization before pre-deriving identity keys or moving funds.
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
        Self.logger.info("🪪 IDENTITY-AUTH :: authenticating via AuthenticationGate (biometric=\(biometricEnabled, privacy: .public))")
        let outcome = await AuthenticationGate.authenticate(biometric: biometricEnabled)

        switch outcome {
        case .ok:
            Self.logger.info("🪪 IDENTITY-AUTH :: user authorized")
            return
        case .cancelled:
            Self.logger.info("🪪 IDENTITY-AUTH :: user cancelled authentication")
            throw AuthError.cancelled
        case .failed:
            Self.logger.error("🪪 IDENTITY-AUTH :: authentication failed")
            throw AuthError.failed
        case .timedOut:
            Self.logger.error("🪪 IDENTITY-AUTH :: authentication timed out (prompt never presented)")
            throw AuthError.failed
        }
    }
}
