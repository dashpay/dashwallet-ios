//
//  SwiftDashSDKPinChanger.swift
//  DashWallet
//
//  Re-encrypts the SwiftDashSDK encrypted seed when the user changes
//  their PIN through Settings → Security → Change PIN. Without this
//  mirror, the SwiftDashSDK seed (created at onboarding/import time
//  by SwiftDashSDKWalletCreator) stays encrypted with the OLD PIN
//  forever, leaving it unreadable after every PIN change.
//
//  Called from `DWSetPinModel.setPin:` AFTER DashSync's setupNewPin
//  succeeds. Self-discriminates: skips first-time PIN setup (no old
//  seed to re-encrypt) and skips no-op "changes" where old == new.
//
//  This file is intentionally decoupled from DashSync — it does not
//  import DashSync, does not know DashSync's keychain layout. All
//  inputs come from the caller. Sister files in the same group:
//    - SwiftDashSDKWalletCreator.swift  (create + import)
//    - SwiftDashSDKWalletWiper.swift    (wipe)
//    - SwiftDashSDKKeyMigrator.swift    (one-shot upgrade-time mirror)
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKPinChanger)
final class SwiftDashSDKPinChanger: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.pin-changer")

    // MARK: - Public entry point

    /// Re-encrypt the SwiftDashSDK seed with a new PIN.
    ///
    /// Dispatched to a background queue, returns immediately. The total
    /// cost is two PBKDF2 derivations (~10–20 ms each on modern hardware),
    /// completed well before the user navigates away from the success
    /// screen.
    ///
    /// Idempotent at the API boundary — calling with the same (old, new)
    /// twice is safe; the second call's `retrieveSeed(oldPin)` will fail
    /// with `invalidPIN` (because the first call already swapped the
    /// stored PIN hash to the new PIN), and we no-op with a warning.
    ///
    /// Never throws, never crashes; all errors logged to os.log.
    ///
    /// - Parameters:
    ///   - oldPin: User's previous PIN. Used to decrypt the existing
    ///     SwiftDashSDK seed. Caller must guarantee non-empty.
    ///   - newPin: User's new PIN. Used to re-encrypt the seed.
    @objc(changePinFrom:to:)
    static func changePin(from oldPin: String, to newPin: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            performChange(oldPin: oldPin, newPin: newPin)
        }
    }

    // MARK: - Background body

    /// Self-contained re-encryption body. Three keychain operations:
    /// retrieve(oldPin) → store(newPin) → retrieve(newPin) round-trip.
    /// Each runs in tens of milliseconds on the background queue.
    ///
    /// On any failure, leaves the SwiftDashSDK seed in a clean state
    /// (either fully re-encrypted with the new PIN, or fully deleted).
    /// Never leaves a half-written entry that would cause hard failures
    /// for downstream readers.
    private static func performChange(oldPin: String, newPin: String) {
        // SwiftDashSDK no longer stores PIN-encrypted seeds — the
        // entire encryptedSeed/PIN keychain layer was removed. PIN
        // changes are now a DashSync-only concern; nothing to mirror.
        _ = oldPin
        _ = newPin
        logger.info("PIN change is a no-op; SwiftDashSDK seed encryption removed")
    }
}
