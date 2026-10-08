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
        [(Self.spvLabel, spv), (Self.platformLabel, platform), (Self.shieldedLabel, shielded)]
    }

    /// Root labels as `WalletLocalStoreResetReport.Removed.root` reports them.
    static let spvLabel = "SPV"
    static let platformLabel = "Platform"
    static let shieldedLabel = "Shielded"
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
    /// Native storage workers can outlive shutdown, including workers that
    /// do not retain a SwiftData container. A fresh process is required.
    case restartRequired
    /// A stopped SDK worker or another reader still owns a store. Nothing
    /// may be unlinked until those owners release their containers.
    case storesStillInUse
    /// Listing a root failed before any directory was removed.
    case enumerationFailed(root: String, code: String)
    /// `removeItem` failed at `root/scope`. Entries before it are gone;
    /// nothing after it was touched. The failed entry itself may be partly
    /// removed — directory removal is not atomic — which is why
    /// `willRemove` runs before the attempt. `code` is `domain:code` only —
    /// Cocoa file errors carry paths in their userInfo, and those never reach
    /// the diagnostic logs.
    case removalFailed(root: String, scope: String, code: String)
}

/// Rust retains its Swift persistence callback context until its last worker
/// exits, even when `shutdown()` has already returned success. That context
/// strongly owns the ModelContainer. Track every container weakly, including
/// opens later rejected by cache invalidation, so reset can prove those
/// owners are gone without extending their lifetime itself.
@MainActor
final class WalletLocalStoreLifetimeBarrier {
    private final class Entry {
        weak var value: AnyObject?
        init(_ value: AnyObject) { self.value = value }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func track(_ container: AnyObject) {
        entries = entries.filter { $0.value.value != nil }
        entries[ObjectIdentifier(container)] = Entry(container)
    }

    /// Admission must remain suspended for the entire wait and deletion.
    /// If a worker cannot stop, keep the files and let the user relaunch.
    func waitForRelease(timeout: Duration = .seconds(5)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while entries.values.contains(where: { $0.value != nil }) {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw WalletLocalStoreResetError.storesStillInUse }
            try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(50))))
        }
        entries.removeAll()
    }
}

/// A partially recreated store already contains wallet rows, so the ordinary
/// "no wallets" fallback alone cannot resume recovery. Keep a per-store
/// marker until every eligible keychain wallet has been recreated. This also
/// covers an app termination between creating the first and last wallet.
/// The atomic marker lives beside the SQLite store; unlike UserDefaults it
/// is written before the first wallet creation rather than flushed later.
struct WalletLocalStoreRecovery {
    let directory: URL
    private var marker: URL { directory.appendingPathComponent("wallet-recovery.pending") }

    func isPending() throws -> Bool {
        do {
            _ = try Data(contentsOf: marker)
            return true
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError {
            return false
        }
    }

    func begin() throws { try Data().write(to: marker, options: .atomic) }

    func finish() throws {
        do {
            try FileManager.default.removeItem(at: marker)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            return
        }
    }
}

/// Seam for the runtime's reset-and-rescan operation: production deletes the
/// real roots, tests substitute a recorder.
protocol WalletLocalStoreResetting: Sendable {
    /// Delete every per-scope store directory under the three roots, off the
    /// main thread. Stops at the first failure and throws
    /// `WalletLocalStoreResetError`; a re-run after a failure continues where
    /// it stopped because removed entries no longer exist.
    ///
    /// `willRemove` runs on the deleting thread right before each entry's
    /// removal is attempted. A directory removal is not atomic and the process
    /// can die at any point, so state that must not outlive the entry's files
    /// (a "scan already done" flag) is dropped there: whichever way the
    /// attempt ends, the files never exist without that state already gone.
    func resetAllScopes(
        willRemove: @escaping @Sendable (WalletLocalStoreResetReport.Removed) -> Void
    ) async throws -> WalletLocalStoreResetReport
}

extension WalletLocalStoreResetting {
    func resetAllScopes() async throws -> WalletLocalStoreResetReport {
        try await resetAllScopes(willRemove: { _ in })
    }
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

    func resetAllScopes(
        willRemove: @escaping @Sendable (WalletLocalStoreResetReport.Removed) -> Void
    ) async throws -> WalletLocalStoreResetReport {
        let roots = self.roots
        let makeFileManager = self.makeFileManager
        return try await Task.detached(priority: .userInitiated) {
            try Self.removeEveryScope(
                under: roots, fileManager: makeFileManager(), willRemove: willRemove)
        }.value
    }

    /// Synchronous body of `resetAllScopes`, separated so the ordering rules
    /// are testable without the detached task.
    static func removeEveryScope(
        under roots: WalletLocalStoreRoots,
        fileManager: FileManager,
        willRemove: (WalletLocalStoreResetReport.Removed) -> Void = { _ in }
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
                let entry = WalletLocalStoreResetReport.Removed(root: label, scope: scope)
                willRemove(entry)
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
                removed.append(entry)
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
