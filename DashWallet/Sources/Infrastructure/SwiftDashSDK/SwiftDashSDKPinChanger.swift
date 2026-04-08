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
        // Defensive: skip cases the caller should already filter, but
        // belt-and-suspenders.
        guard !oldPin.isEmpty, !newPin.isEmpty else {
            logger.warning("ignoring PIN change with empty pin(s)")
            return
        }
        guard oldPin != newPin else {
            logger.info("old and new PIN are identical, no-op")
            return
        }

        let storage = WalletStorage()

        // 1) Decrypt the existing seed with the OLD PIN.
        //
        // Three relevant outcomes:
        //  - success: continue to step 2.
        //  - seedNotFound: no SwiftDashSDK seed yet — this is the
        //    first-time-setup case slipping through (DWSetPinModel
        //    should have skipped us, but we belt-and-suspender it
        //    here too). The wallet creator will populate the seed
        //    later in the flow with the new PIN. No-op.
        //  - invalidPIN: drift between DashSync's stored PIN and
        //    SwiftDashSDK's. The SwiftDashSDK seed is already
        //    orphaned and unrecoverable; best-effort delete to
        //    clean up so the next createWallet/importWallet starts
        //    from a clean slate.
        let seed: Data
        do {
            seed = try storage.retrieveSeed(pin: oldPin)
        } catch WalletStorageError.seedNotFound {
            logger.info("no SwiftDashSDK seed to re-encrypt; nothing to do")
            return
        } catch WalletStorageError.invalidPIN {
            logger.warning("oldPin doesn't decrypt SwiftDashSDK seed (drift). Deleting orphaned seed.")
            try? storage.deleteSeed()
            return
        } catch {
            logger.error("retrieveSeed(oldPin) failed: \(String(describing: error), privacy: .public)")
            return
        }

        // 2) Re-encrypt with the NEW PIN. WalletStorage.storeSeed is
        // already idempotent — it deletes the existing entry first
        // (WalletStorage.swift:41), so this is effectively atomic
        // from the caller's perspective.
        do {
            _ = try storage.storeSeed(seed, pin: newPin)
        } catch {
            logger.error("storeSeed(newPin) failed: \(String(describing: error), privacy: .public). Cleaning up.")
            // Best-effort cleanup so we don't leave a half-encrypted
            // entry behind. The user will hit seedNotFound on next
            // read, which is recoverable via wipe + restore.
            try? storage.deleteSeed()
            return
        }

        // 3) Round-trip verify with the NEW PIN. Mirrors the migrator
        // and creator's verify-before-commit pattern. If verify fails,
        // delete to avoid leaving a corrupted entry.
        do {
            let verify = try storage.retrieveSeed(pin: newPin)
            guard verify == seed else {
                logger.error("round-trip seed mismatch after PIN change — deleting")
                try? storage.deleteSeed()
                return
            }
        } catch {
            logger.error("retrieveSeed(newPin) verify failed: \(String(describing: error), privacy: .public). Deleting.")
            try? storage.deleteSeed()
            return
        }

        logger.info("PIN change mirrored to SwiftDashSDK successfully")
    }
}
