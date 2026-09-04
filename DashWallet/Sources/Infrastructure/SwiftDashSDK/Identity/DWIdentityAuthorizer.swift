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

    /// `sessionAuthSufficient` lets a caller that has ALREADY gated the whole
    /// operation once skip the per-item prompt — a bulk asset-lock recovery
    /// authenticates for the batch, not for each of its (possibly dozens of)
    /// resumes. Default `false`, so every interactive caller keeps prompting.
    @MainActor
    func authorize(sessionAuthSufficient: Bool = false) async throws {
        let biometricEnabled = DWGlobalOptions.sharedInstance().biometricAuthEnabled
        Self.logger.info("🪪 IDENTITY-AUTH :: authenticating via AuthenticationGate (biometric=\(biometricEnabled, privacy: .public) sessionAuthSufficient=\(sessionAuthSufficient, privacy: .public))")
        let outcome = await AuthenticationGate.authenticate(
            biometric: biometricEnabled,
            sessionAuthSufficient: sessionAuthSufficient)

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
