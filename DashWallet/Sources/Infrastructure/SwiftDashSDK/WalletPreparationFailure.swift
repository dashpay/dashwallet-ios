import Foundation
import SQLite3

/// Display and support evidence for a failed wallet open, for a failed
/// import of the previous app generation's wallet, or for wallet keys that
/// could not be read back from the keychain. Never retains an Error or
/// its userInfo: Core Data errors can contain paths and stored values.
struct WalletPreparationFailure: Equatable, Identifiable {
    /// `keychain`: the store is not the problem — the wallet keys could not
    /// be read or replayed from the keychain, and nothing was deleted.
    enum Kind: String { case database, storage, legacyMigration, keychain }

    /// Why the DashSync → SwiftDashSDK key migration did not deliver a wallet.
    /// Only the migrator's terminal flag names leave this boundary.
    enum LegacyMigrationReason: String { case failed, unknownChain, timedOut, unreadableKeychain }

    /// How the keychain replay of the wallet keys failed, as
    /// `SwiftDashSDKHost.keysFailure(in:)` classifies it. Only these names and
    /// the Security framework status of a failed read leave this boundary.
    enum KeysReason: String { case unreadable, notFound, unclassifiable, idMismatch }

    let id: UUID
    let kind: Kind
    let occurredAt: Date
    let codes: [String]
    let canResetLocalData: Bool

    init(legacyMigration reason: LegacyMigrationReason, now: Date = Date()) {
        id = UUID()
        occurredAt = now
        kind = .legacyMigration
        codes = ["KeyMigrator:\(reason.rawValue)"]
        canResetLocalData = false
    }

    /// The store opened, but the wallet keys could not be read or replayed.
    /// Never resettable: deleting the store cannot help, and the card offers
    /// no phrase backup either, since the phrase is what could not be read.
    init(keys reason: KeysReason, status: OSStatus? = nil, now: Date = Date()) {
        id = UUID()
        occurredAt = now
        kind = .keychain
        codes = ["Keychain:\(reason.rawValue)"] + (status.map { ["OSStatus:\($0)"] } ?? [])
        canResetLocalData = false
    }

    init(error: Error, now: Date = Date()) {
        id = UUID()
        occurredAt = now
        let errors = Self.errorChain(error as NSError)
        let diskFull = errors.contains { error in
            (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
                || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC))
                || (error.domain == "NSSQLiteErrorDomain" && error.code == Int(SQLITE_FULL))
                || Self.isLegacySpaceFailure(error)
        }
        kind = diskFull ? .storage : .database
        canResetLocalData = !diskFull && !errors.contains(where: Self.isTransientStoreFailure)
            && errors.contains(where: Self.isResettableStoreFailure)
        codes = errors.map { error in
            // Only known domain names leave this boundary. Neither arbitrary
            // domain names nor localized descriptions are safe log content.
            let allowed = [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain,
                           NSOSStatusErrorDomain, "NSSQLiteErrorDomain", "SwiftData.SwiftDataError",
                           "SwiftDashSDK.DashLegacyStoreSQLite.Failure"]
            let domain = allowed.contains(error.domain) ? error.domain : "OtherError"
            return "\(domain):\(error.code)"
        }
    }

    /// Reset only known corruption/schema failures. A nested permission or
    /// busy-store error vetoes even a generic SwiftData open failure.
    private static func isResettableStoreFailure(_ error: NSError) -> Bool {
        switch error.domain {
        case "SwiftData.SwiftDataError": return error.code == 1
        case NSCocoaErrorDomain: return [134100, 134110, 134130, 134140].contains(error.code)
        case "NSSQLiteErrorDomain": return [Int(SQLITE_CORRUPT), Int(SQLITE_NOTADB)].contains(error.code & 0xff)
        default: return false
        }
    }

    private static func isTransientStoreFailure(_ error: NSError) -> Bool {
        switch error.domain {
        case NSPOSIXErrorDomain:
            return [EACCES, EPERM, EBUSY, EAGAIN, EIO, EROFS].map(Int.init).contains(error.code)
        case NSCocoaErrorDomain:
            return [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code)
        case "NSSQLiteErrorDomain":
            return [SQLITE_BUSY, SQLITE_LOCKED, SQLITE_PERM, SQLITE_READONLY, SQLITE_IOERR, SQLITE_CANTOPEN]
                .map(Int.init).contains(error.code & 0xff)
        default: return false
        }
    }

    var title: String {
        if kind == .legacyMigration {
            return NSLocalizedString("Couldn't move your wallet",
                                     comment: "Wallet preparation failure")
        }
        if kind == .keychain {
            return NSLocalizedString("Couldn't read your wallet keys",
                                     comment: "Wallet preparation failure")
        }
        return NSLocalizedString("Couldn't open your wallet data",
                                 comment: "Wallet preparation failure")
    }

    var message: String {
        if kind == .legacyMigration {
            return NSLocalizedString(
                "The wallet from the previous version of this app is still on this device but could not be prepared. Do not delete this app. Try again or contact support for help.",
                comment: "Wallet preparation failure")
        }
        if kind == .storage {
            return NSLocalizedString(
                "There isn't enough free space to prepare your wallet. Free up storage in iPhone Settings, then try again. Your wallet keys are still stored safely on this device.",
                comment: "Wallet preparation failure")
        }
        if kind == .keychain {
            // Neither "your keys are safe" nor "your keys are lost": a read
            // failed, and the keychain is untouched by the app.
            return NSLocalizedString(
                "Your wallet keys could not be read from this device's secure storage. Nothing was deleted. Do not delete this app. Try again or contact support for help.",
                comment: "Wallet preparation failure")
        }
        return NSLocalizedString(
            "Your wallet could not be opened. Your wallet keys are still stored safely on this device. Try again or contact support for help.",
            comment: "Wallet preparation failure")
    }

    /// A small, opt-in diagnostic attachment. No general app/SDK logs, database
    /// access, Keychain reads, wallet identifiers or free-form error text.
    func diagnosticReport(appVersion: String, systemVersion: String) -> String {
        """
        Dash Wallet — wallet preparation diagnostic
        App: \(appVersion)
        OS: \(systemVersion)
        Time: \(ISO8601DateFormatter().string(from: occurredAt))
        Category: \(kind.rawValue)
        Error codes:
        \(codes.joined(separator: "\n"))

        This report contains no database, wallet identifiers, keys or general application logs.
        """
    }

    private static func errorChain(_ root: NSError) -> [NSError] {
        var result: [NSError] = []
        var pending = [root]
        var visited = Set<ObjectIdentifier>()
        while !pending.isEmpty && result.count < 8 {
            let error = pending.removeFirst()
            guard visited.insert(ObjectIdentifier(error)).inserted else { continue }
            result.append(error)
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                pending.append(underlying)
            }
            if let detailed = error.userInfo["NSDetailedErrors"] as? [NSError] {
                pending.append(contentsOf: detailed.prefix(8))
            }
        }
        return result
    }

    private static func isLegacySpaceFailure(_ error: NSError) -> Bool {
        // The current SDK does not expose its bridge error enum publicly.
        // Recognize only its exact domain and anchored space-preflight message;
        // unknown SDK errors keep the generic recovery UI. Never export the text.
        error.domain == "SwiftDashSDK.DashLegacyStoreSQLite.Failure"
            && error.localizedDescription.hasPrefix("Legacy database migration needs approximately ")
            && error.localizedDescription.hasSuffix(
                "Free device storage and retry. The original database has not been replaced.")
    }
}
