//
//  WalletLocalStoreResetter.swift
//  DashWallet
//

import Foundation

/// The three per-scope store roots under the app's Documents directory. Every
/// store path the host, the SPV coordinator and the devnet scope enumeration
/// build starts from one of these; the local-store reset deletes their
/// children. Foundation-only so the wallet-preparation harness can compile it.
struct WalletLocalStoreRoots: Equatable, Sendable {
    /// `Documents/SwiftDashSDK/Platform/<scope>/DashModel.sqlite` (+ `-wal`,
    /// `-shm`, and the SDK's `DashModel.sqlite.legacy-v2-backups/` directory).
    let platform: URL
    /// `Documents/SwiftDashSDK/Shielded/<scope>/commitment-tree.sqlite`.
    let shielded: URL
    /// `Documents/SPV/<scope>/` — dash-spv headers, filters and chain state.
    let spv: URL

    init(documents: URL) {
        let sdk = documents.appendingPathComponent("SwiftDashSDK", isDirectory: true)
        platform = sdk.appendingPathComponent("Platform", isDirectory: true)
        shielded = sdk.appendingPathComponent("Shielded", isDirectory: true)
        spv = documents.appendingPathComponent("SPV", isDirectory: true)
    }

    /// The roots under the user's Documents directory (created if missing,
    /// like every store path builder did before; the roots themselves are
    /// not created here).
    static func inDocuments(fileManager: FileManager = .default) throws -> WalletLocalStoreRoots {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        return WalletLocalStoreRoots(documents: documents)
    }

    /// Deletion order within one scope. The SPV store goes first: wallet rows
    /// without a chain store are always safe (SPV re-anchors at the rows'
    /// birth height), while fresh rows over an old header store are the one
    /// combination dash-spv never repairs (it does not re-anchor an existing
    /// header store), so no interruption may leave the Platform store deleted
    /// ahead of the SPV store.
    var orderedForDeletion: [(label: String, url: URL)] {
        [("SPV", spv), ("Shielded", shielded), ("Platform", platform)]
    }
}

/// What a local-store reset removed, for logging and tests.
struct WalletLocalStoreResetReport: Equatable, Sendable {
    struct Removed: Equatable, Sendable {
        /// `SPV`, `Shielded` or `Platform`.
        let root: String
        /// The scope directory name, e.g. `mainnet` or `devnet-moutai`.
        let scope: String
    }

    let removed: [Removed]

    /// Distinct scopes touched, sorted.
    var scopes: [String] {
        Array(Set(removed.map(\.scope))).sorted()
    }
}

enum WalletLocalStoreResetError: Error, Equatable {
    /// `removeItem` failed at `root/scope`. Entries removed before it are
    /// gone; nothing after it was touched. `code` is `domain:code` only —
    /// Cocoa file errors carry paths in their userInfo, and those never reach
    /// the diagnostic logs.
    case removalFailed(root: String, scope: String, code: String)
}

/// Seam for the runtime's reset-and-rescan operation: production deletes the
/// real roots, tests substitute a recorder.
protocol WalletLocalStoreResetting: Sendable {
    /// Delete every per-scope store directory under the three roots, off the
    /// main thread. Stops at the first failure and throws
    /// `WalletLocalStoreResetError`; a re-run after a failure continues where
    /// it stopped because removed entries no longer exist.
    func resetAllScopes() async throws -> WalletLocalStoreResetReport
}

/// Deletes the children of the three store roots — every network and devnet
/// scope present on disk — leaving the roots in place. The next wallet start
/// recreates whichever scope directories it needs. Keychain mnemonics and
/// UserDefaults are not touched here; the runtime operation owns the state
/// that must go with the stores.
struct WalletLocalStoreResetter: WalletLocalStoreResetting {
    let roots: WalletLocalStoreRoots
    /// Built inside the detached task because `FileManager` is not Sendable;
    /// tests inject a subclass whose `removeItem(at:)` fails for one scope.
    let makeFileManager: @Sendable () -> FileManager

    init(roots: WalletLocalStoreRoots,
         makeFileManager: @escaping @Sendable () -> FileManager = { FileManager() }) {
        self.roots = roots
        self.makeFileManager = makeFileManager
    }

    func resetAllScopes() async throws -> WalletLocalStoreResetReport {
        let roots = self.roots
        let makeFileManager = self.makeFileManager
        return try await Task.detached(priority: .userInitiated) {
            try Self.removeEveryScope(under: roots, fileManager: makeFileManager())
        }.value
    }

    /// Synchronous body of `resetAllScopes`, separated so the ordering rules
    /// are testable without the detached task.
    static func removeEveryScope(
        under roots: WalletLocalStoreRoots,
        fileManager: FileManager
    ) throws -> WalletLocalStoreResetReport {
        let ordered = roots.orderedForDeletion
        var scopes = Set<String>()
        for (_, root) in ordered {
            scopes.formUnion(childNames(of: root, fileManager: fileManager))
        }

        var removed: [WalletLocalStoreResetReport.Removed] = []
        for scope in scopes.sorted() {
            for (label, root) in ordered {
                let url = root.appendingPathComponent(scope)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    let nsError = error as NSError
                    let code = "\(nsError.domain):\(nsError.code)"
                    DWLogger.log("🧹 STORE-RESET FAILED at \(label)/\(scope) code=\(code) removedBefore=\(removed.count)")
                    throw WalletLocalStoreResetError.removalFailed(root: label, scope: scope, code: code)
                }
                removed.append(.init(root: label, scope: scope))
                DWLogger.log("🧹 STORE-RESET removed \(label)/\(scope)")
            }
        }

        let report = WalletLocalStoreResetReport(removed: removed)
        DWLogger.log("🧹 STORE-RESET done scopes=\(report.scopes.joined(separator: ",")) removed=\(removed.count)")
        return report
    }

    /// Every entry directly under `root`, hidden ones included; a missing or
    /// unreadable root reads as empty.
    private static func childNames(of root: URL, fileManager: FileManager) -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: []) else { return [] }
        return contents.map(\.lastPathComponent)
    }
}
