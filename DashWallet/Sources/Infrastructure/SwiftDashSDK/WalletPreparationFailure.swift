import Foundation
import SQLite3

/// Display and support evidence for a failed wallet open. Never retains an
/// Error or its userInfo: Core Data errors can contain paths and stored values.
struct WalletPreparationFailure: Equatable, Identifiable {
    enum Kind: String { case database, storage }

    let id: UUID
    let kind: Kind
    let occurredAt: Date
    let codes: [String]

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

    var title: String {
        NSLocalizedString("Couldn't open your wallet data",
                          comment: "Wallet preparation failure")
    }

    var message: String {
        if kind == .storage {
            return NSLocalizedString(
                "There isn't enough free space to prepare your wallet. Free up storage in iPhone Settings, then try again. Do not delete this app.",
                comment: "Wallet preparation failure")
        }
        return NSLocalizedString(
            "Your wallet could not be opened. Do not delete this app. Try again or contact support for help.",
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
