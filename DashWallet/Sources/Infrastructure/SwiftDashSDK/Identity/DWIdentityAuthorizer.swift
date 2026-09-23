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

    /// True while a caller has already run this gate for the work about to
    /// execute, so the executor's own `authorize()` must not ask a second
    /// time.
    ///
    /// Task-local rather than a stored flag: it covers exactly the work run
    /// inside `preauthorized(_:)` and nothing else, so every other entry point
    /// (the recovery sheet, the Send screen, a profile top-up) still prompts
    /// for itself, and it cannot be left set by a transfer that died.
    @TaskLocal static var isPreauthorized = false

    /// Runs `body` with this gate already satisfied. The caller must have
    /// awaited `authorize()` successfully first — this only suppresses the
    /// SECOND prompt, it never skips authentication.
    ///
    /// Why anyone would: the gate has to be settled before the screen that
    /// asked for it goes away, and the executors raise it from deep inside
    /// work that outlives that screen.
    static func preauthorized<T>(_ body: () async -> T) async -> T {
        await $isPreauthorized.withValue(true, operation: body)
    }

    @MainActor
    func authorize() async throws {
        if Self.isPreauthorized {
            Self.logger.info("🪪 IDENTITY-AUTH :: already authorized for this operation — not prompting again")
            return
        }

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
