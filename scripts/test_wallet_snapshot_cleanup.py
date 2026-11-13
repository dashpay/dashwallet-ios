#!/usr/bin/env python3
"""Exercise the actual wiper preparation code without opening SDK wallets or Keychain."""
from pathlib import Path
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
source = (repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKWalletWiper.swift").read_text()


def section(start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


# The factory and cleanup/shutdown dispatch are production code. Only the SDK
# opening boundary is replaced by fixtures: cleanup really removes a temp file,
# and failures are injected before that removal. No app/SDK source is modified.
factory = section("    @MainActor\n    private static func deletionBackend", "    /// Run synchronous full deletion")
factory = factory.replace("private static func deletionBackend", "static func deletionBackend", 1)
cleanup = section("        @MainActor\n        func deleteCompletedMigrationSnapshots", "        /// Remove one wallet")
shutdown = section("        func shutDownIfOwned()", "\n    }\n")

harness = r'''
import Foundation
import OSLog

enum Network { case mainnet, testnet, devnet }
enum ProbeError: Error { case open, cleanup, assertion(String) }
enum SwiftDashSDKWalletDeletionError: Error { case managerUnavailable }

@MainActor final class PlatformWalletPersistenceHandler {
    let snapshot: URL
    var failCleanup = false
    var cleanupCalls = 0
    init(snapshot: URL) throws {
        self.snapshot = snapshot
        try Data("synthetic snapshot".utf8).write(to: snapshot)
    }
    func deleteCompletedMigrationSnapshots() throws {
        cleanupCalls += 1
        if failCleanup { throw ProbeError.cleanup }
        if FileManager.default.fileExists(atPath: snapshot.path) {
            try FileManager.default.removeItem(at: snapshot)
        }
    }
}
@MainActor final class PlatformWalletManager {
    let persistence: PlatformWalletPersistenceHandler?
    var shutdownCalls = 0
    init(_ handler: PlatformWalletPersistenceHandler) { persistence = handler }
    func shutdown() async { shutdownCalls += 1 }
}
@MainActor final class SwiftDashSDKHost {
    static let shared = SwiftDashSDKHost()
    var manager: PlatformWalletManager!
    var failManager = false
    var temporary = true
    func managerForWipe(network: Network) async throws -> (PlatformWalletManager, Bool) {
        if failManager { throw ProbeError.open }
        return (manager, temporary)
    }
    func storeOnlyPersistenceHandler(for network: Network) async throws -> PlatformWalletPersistenceHandler {
        guard let persistence = manager.persistence else { throw ProbeError.open }
        return persistence
    }
}
@MainActor enum Wiper {
    static let logger = Logger(subsystem: "wallet-wiper-test", category: "test")
    enum DeletionBackend {
        case manager(PlatformWalletManager, isTemporary: Bool)
        case offline(PlatformWalletPersistenceHandler)
        CLEANUP
        SHUTDOWN
    }
    FACTORY
}
@main struct Tests {
    @MainActor static func main() async throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw ProbeError.assertion(message) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = SwiftDashSDKHost.shared
        var cases = 0
        // For both native-manager and offline-devnet paths, an unrelated
        // store's failing purge must not run while preparing a single removal.
        for offline in [false, true] {
            let network: Network = offline ? .devnet : .testnet
            let handler = try PlatformWalletPersistenceHandler(snapshot: root.appendingPathComponent(UUID().uuidString))
            host.manager = PlatformWalletManager(handler)
            host.failManager = offline
            handler.failCleanup = true
            let backend = try await Wiper.deletionBackend(for: network)
            try check(handler.cleanupCalls == 0, "Single-wallet preparation touched snapshots")
            try check(FileManager.default.fileExists(atPath: handler.snapshot.path), "Unrelated snapshot was removed")
            await backend.shutDownIfOwned()
            cases += 1
        }
        // Delete All must purge even an empty live store, and propagate a purge
        // failure while releasing exactly the temporary manager it owns.
        for offline in [false, true] {
            for failure in [false, true] {
                let handler = try PlatformWalletPersistenceHandler(snapshot: root.appendingPathComponent(UUID().uuidString))
                host.manager = PlatformWalletManager(handler)
                host.failManager = offline
                handler.failCleanup = failure
                do {
                    let backend = try await Wiper.deletionBackend(for: offline ? .devnet : .testnet, forFullWipe: true)
                    try check(!failure, "Purge failure was swallowed")
                    try check(!FileManager.default.fileExists(atPath: handler.snapshot.path), "Full wipe left snapshot")
                    await backend.shutDownIfOwned()
                } catch ProbeError.cleanup {
                    try check(failure, "Unexpected purge failure")
                    try check(FileManager.default.fileExists(atPath: handler.snapshot.path), "Failed purge removed snapshot")
                }
                try check(handler.cleanupCalls == 1, "Full wipe did not attempt cleanup")
                try check(host.manager.shutdownCalls == (offline ? 0 : 1), "Wrong manager shutdown count")
                cases += 1
            }
        }
        print("Passed \(cases) wallet snapshot preparation cases")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="wallet-snapshot-cleanup-") as directory:
    root = Path(directory)
    swift = root / "main.swift"
    swift.write_text(harness.replace("CLEANUP", cleanup).replace("SHUTDOWN", shutdown).replace("FACTORY", factory))
    executable = root / "tests"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(root / "modules"),
                    str(swift), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
