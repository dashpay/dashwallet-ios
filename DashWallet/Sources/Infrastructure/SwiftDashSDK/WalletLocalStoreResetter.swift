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

    /// SPV must disappear before wallet rows so the next open re-anchors at
    /// their birth height. Platform must disappear before Shielded so no
    /// saved scan watermark can outlive its commitment tree. An interruption
    /// leaves either the old rows and tree together, or no rows: the latter
    /// rescans from index zero, also supported with an existing shared tree
    /// (the SDK's `clearShielded` contract).
    var orderedForDeletion: [(label: String, url: URL)] {
        [("SPV", spv), ("Platform", platform), ("Shielded", shielded)]
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
    /// Listing a root failed before any directory was removed.
    case enumerationFailed(root: String, code: String)
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
        for (label, root) in ordered {
            do {
                scopes.formUnion(try childNames(of: root, fileManager: fileManager))
            } catch {
                throw WalletLocalStoreResetError.enumerationFailed(
                    root: label,
                    code: WalletPreparationFailure(error: error).codes.joined(separator: ","))
            }
        }

        var removed: [WalletLocalStoreResetReport.Removed] = []
        for scope in scopes.sorted() {
            for (label, root) in ordered {
                let url = root.appendingPathComponent(scope)
                do {
                    try fileManager.removeItem(at: url)
                } catch let error as NSError where error.domain == NSCocoaErrorDomain
                    && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                    continue
                } catch {
                    let code = WalletPreparationFailure(error: error).codes.joined(separator: ",")
                    DWLogger.log("🧹 STORE-RESET FAILED at \(label)/\(scope) code=\(code) removedBefore=\(removed.count)")
                    throw WalletLocalStoreResetError.removalFailed(root: label, scope: scope, code: code)
                }
                removed.append(.init(root: label, scope: scope))
                DWLogger.log("🧹 STORE-RESET removed \(label)/\(scope)")
            }
        }

        let report = WalletLocalStoreResetReport(removed: removed)
        DWLogger.log("🧹 STORE-RESET files removed scopes=\(report.scopes.joined(separator: ",")) removed=\(removed.count)")
        return report
    }

    /// Every entry directly under `root`, hidden ones included. Only a missing
    /// root is empty; permission and I/O errors must stop the reset.
    private static func childNames(of root: URL, fileManager: FileManager) throws -> [String] {
        do {
            return try fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: []).map(\.lastPathComponent)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        }
    }
}
