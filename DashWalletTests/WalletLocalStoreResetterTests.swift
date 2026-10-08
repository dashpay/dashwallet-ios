import XCTest
#if canImport(dashpay)
@testable import dashpay
#elseif canImport(dashwallet)
@testable import dashwallet
#else
@testable import WalletPreparationHarness
#endif

final class WalletLocalStoreResetterTests: XCTestCase {
    private var documents: URL!
    private var roots: WalletLocalStoreRoots!

    override func setUpWithError() throws {
        documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: false)
        roots = WalletLocalStoreRoots(documents: documents)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: documents)
    }

    func testRootsDeriveFromDocuments() {
        XCTAssertEqual(roots.platform.path, documents.appendingPathComponent("SwiftDashSDK/Platform").path)
        XCTAssertEqual(roots.shielded.path, documents.appendingPathComponent("SwiftDashSDK/Shielded").path)
        XCTAssertEqual(roots.spv.path, documents.appendingPathComponent("SPV").path)
        XCTAssertEqual(roots.orderedForDeletion.map(\.label), ["SPV", "Platform", "Shielded"])
    }

    func testRemovesEveryScopeUnderAllThreeRoots() async throws {
        let scopes = ["mainnet", "testnet", "devnet", "devnet-moutai"]
        for scope in scopes {
            try plant(roots.platform, scope, files: [
                "DashModel.sqlite", "DashModel.sqlite-wal", "DashModel.sqlite.legacy-v2-backups/x/original.store",
            ])
            try plant(roots.shielded, scope, files: ["commitment-tree.sqlite"])
            try plant(roots.spv, scope, files: ["headers.dat", "filters/0.bin"])
        }

        let report = try await WalletLocalStoreResetter(roots: roots).resetAllScopes()

        XCTAssertEqual(report.scopes, ["devnet", "devnet-moutai", "mainnet", "testnet"])
        XCTAssertEqual(report.removed.count, 12)
        for (_, root) in roots.orderedForDeletion {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.path), "root kept: \(root.lastPathComponent)")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [], root.lastPathComponent)
        }
    }

    func testMissingAndEmptyRootsReportNothing() async throws {
        try FileManager.default.createDirectory(at: roots.platform, withIntermediateDirectories: true)

        let report = try await WalletLocalStoreResetter(roots: roots).resetAllScopes()

        XCTAssertEqual(report.removed, [])
        XCTAssertEqual(report.scopes, [])
    }

    func testFilesOutsideTheRootsArePreserved() async throws {
        try plant(roots.platform, "mainnet", files: ["DashModel.sqlite"])
        let appDatabase = documents.appendingPathComponent("store.db")
        let sdkNote = documents.appendingPathComponent("SwiftDashSDK/notes.txt")
        try Data("db".utf8).write(to: appDatabase)
        try Data("note".utf8).write(to: sdkNote)

        _ = try await WalletLocalStoreResetter(roots: roots).resetAllScopes()

        XCTAssertTrue(FileManager.default.fileExists(atPath: appDatabase.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sdkNote.path))
    }

    func testStopsAtTheFirstFailureInSafeOrder() async throws {
        for scope in ["mainnet", "testnet", "zz-devnet-last"] {
            try plant(roots.platform, scope, files: ["DashModel.sqlite"])
            try plant(roots.shielded, scope, files: ["commitment-tree.sqlite"])
            try plant(roots.spv, scope, files: ["headers.dat"])
        }
        let resetter = WalletLocalStoreResetter(roots: roots) {
            FailingFileManager(failingLastPathComponent: "testnet", underRoot: "Shielded")
        }

        do {
            _ = try await resetter.resetAllScopes()
            XCTFail("Expected the injected removal failure")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, .removalFailed(root: "Shielded", scope: "testnet", code: "NSCocoaErrorDomain:513"))
        }

        // mainnet sorts first: fully removed.
        XCTAssertFalse(exists(roots.platform, "mainnet"))
        XCTAssertFalse(exists(roots.spv, "mainnet"))
        // testnet: SPV and Platform are gone before Shielded removal can fail.
        XCTAssertFalse(exists(roots.spv, "testnet"))
        XCTAssertTrue(exists(roots.shielded, "testnet"))
        XCTAssertFalse(exists(roots.platform, "testnet"))
        // A later scope is untouched.
        XCTAssertTrue(exists(roots.spv, "zz-devnet-last"))
        XCTAssertTrue(exists(roots.platform, "zz-devnet-last"))
    }

    func testRerunAfterPartialFailureCompletes() async throws {
        try plant(roots.platform, "testnet", files: ["DashModel.sqlite"])
        try plant(roots.shielded, "testnet", files: ["commitment-tree.sqlite"])
        try plant(roots.spv, "testnet", files: ["headers.dat"])
        let failing = WalletLocalStoreResetter(roots: roots) {
            FailingFileManager(failingLastPathComponent: "testnet", underRoot: "Shielded")
        }
        _ = try? await failing.resetAllScopes()

        let report = try await WalletLocalStoreResetter(roots: roots).resetAllScopes()

        XCTAssertEqual(report.removed.map(\.root), ["Shielded"])
        XCTAssertFalse(exists(roots.platform, "testnet"))
        XCTAssertFalse(exists(roots.shielded, "testnet"))
    }

    func testEveryInterruptionLeavesSafeStateForOrdinaryReopenWithoutAnotherReset() async throws {
        for failingRoot in ["SPV", "Platform", "Shielded"] {
            for scope in ["mainnet", "testnet"] {
                try plant(roots.platform, scope, files: ["DashModel.sqlite"])
                try plant(roots.shielded, scope, files: ["commitment-tree.sqlite"])
                try plant(roots.spv, scope, files: ["headers.dat"])
            }
            let interrupted = WalletLocalStoreResetter(roots: roots) {
                FailingFileManager(failingLastPathComponent: "testnet", underRoot: failingRoot)
            }
            do {
                _ = try await interrupted.resetAllScopes()
                XCTFail("Expected interruption")
            } catch {}
            // Inspect exactly what an ordinary launch finds, without rerunning
            // reset. Existing watermarks require the original tree; absent
            // wallet rows require absent SPV headers and a scan from zero.
            for scope in ["mainnet", "testnet"] {
                if exists(roots.platform, scope) {
                    XCTAssertTrue(exists(roots.shielded, scope), "Saved watermarks lost their tree")
                } else {
                    XCTAssertFalse(exists(roots.spv, scope), "New rows would reuse old SPV headers")
                }
            }
        }
    }

    func testUnreadableRootFailsBeforeAnyStoreIsRemoved() async throws {
        try plant(roots.platform, "mainnet", files: ["DashModel.sqlite"])
        try plant(roots.shielded, "mainnet", files: ["commitment-tree.sqlite"])
        try plant(roots.spv, "mainnet", files: ["headers.dat"])
        let resetter = WalletLocalStoreResetter(roots: roots) { UnreadableRootFileManager() }
        do {
            _ = try await resetter.resetAllScopes()
            XCTFail("An unreadable root must not be treated as empty")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, .enumerationFailed(root: "Platform", code: "OtherError:257"))
        }
        XCTAssertTrue(exists(roots.spv, "mainnet"))
        XCTAssertTrue(exists(roots.platform, "mainnet"))
        XCTAssertTrue(exists(roots.shielded, "mainnet"))
    }

    // MARK: - Helpers

    private func plant(_ root: URL, _ scope: String, files: [String]) throws {
        for file in files {
            let url = root.appendingPathComponent(scope, isDirectory: true).appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.utf8).write(to: url)
        }
    }

    private func exists(_ root: URL, _ scope: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(scope).path)
    }
}

/// Fails `removeItem(at:)` for one scope directory under one root, with the
/// same error shape Foundation reports for an unremovable item.
private final class FailingFileManager: FileManager {
    private let failingLastPathComponent: String
    private let underRoot: String

    init(failingLastPathComponent: String, underRoot: String) {
        self.failingLastPathComponent = failingLastPathComponent
        self.underRoot = underRoot
        super.init()
    }

    override func removeItem(at url: URL) throws {
        if url.lastPathComponent == failingLastPathComponent,
           url.deletingLastPathComponent().lastPathComponent == underRoot {
            throw NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSFilePathErrorKey: url.path])
        }
        try super.removeItem(at: url)
    }
}

private final class UnreadableRootFileManager: FileManager {
    override func contentsOfDirectory(
        at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if url.lastPathComponent == "Platform" {
            throw NSError(domain: "private-path-or-secret", code: 257)
        }
        return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }
}
