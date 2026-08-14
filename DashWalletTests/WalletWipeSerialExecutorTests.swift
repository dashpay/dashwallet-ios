//
//  WalletWipeSerialExecutorTests.swift
//  DashWalletTests
//
//  Regression coverage for the reinstall Delete race: the SDK wallet wipe and
//  successful PIN commit are queued together. The transition barrier must
//  never fire before that queued operation finishes.
//

import XCTest
@testable import dashwallet

private enum WalletLifecycleTestError: Error {
    case walletDeletion
    case mnemonicPersistence
    case walletCreation
}

final class WalletWipeSerialExecutorTests: XCTestCase {
    func testIdleNotificationWaitsForPreviouslyQueuedWipe() {
        let executor = WalletWipeSerialExecutor(
            label: "org.dashfoundation.dash.wallet-wiper-tests.\(UUID().uuidString)")
        let wipeStarted = expectation(description: "wipe started")
        let wipeFinished = expectation(description: "wipe finished")
        let completionCalled = expectation(description: "completion called")
        let releaseWipe = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var events: [String] = []

        executor.enqueue {
            lock.lock()
            events.append("wipe-started")
            lock.unlock()
            wipeStarted.fulfill()

            releaseWipe.wait()

            lock.lock()
            events.append("wipe-finished")
            lock.unlock()
            wipeFinished.fulfill()
            return true
        }

        wait(for: [wipeStarted], timeout: 1)

        executor.notifyWhenIdle(on: .global(qos: .userInitiated)) { succeeded in
            lock.lock()
            events.append(succeeded ? "completion-success" : "completion-failure")
            lock.unlock()
            completionCalled.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            releaseWipe.signal()
        }
        wait(for: [wipeFinished, completionCalled], timeout: 1)

        lock.lock()
        let recordedEvents = events
        lock.unlock()
        XCTAssertEqual(recordedEvents, ["wipe-started", "wipe-finished", "completion-success"])
    }

    func testIdleNotificationPropagatesWipeFailure() {
        let executor = WalletWipeSerialExecutor(
            label: "org.dashfoundation.dash.wallet-wiper-tests.\(UUID().uuidString)")
        let completionCalled = expectation(description: "completion called")

        executor.enqueue { false }
        executor.notifyWhenIdle(on: .global(qos: .userInitiated)) { succeeded in
            XCTAssertFalse(succeeded)
            completionCalled.fulfill()
        }

        wait(for: [completionCalled], timeout: 1)
    }

    @MainActor
    func testDeleteFailureDoesNotRunDestructiveAppCleanup() {
        let walletId = Data(repeating: 0x22, count: 32)
        var appStateCleared = false

        XCTAssertThrowsError(try SwiftDashSDKWalletWiper.deleteWalletFromSDK(
            walletId,
            deleteWallet: { _ in
                throw WalletLifecycleTestError.walletDeletion
            },
            clearAppState: { _ in
                appStateCleared = true
            }
        ))

        XCTAssertFalse(appStateCleared)
    }
}

final class StoredWalletInventoryTests: XCTestCase {
    func testDistinctWalletCountDeduplicatesNetworkScopedCopiesOfOneSeed() {
        let seed = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let entries = [
            (walletId: Data([0x01]), mnemonic: seed),
            (walletId: Data([0x02]), mnemonic: seed),
        ]

        XCTAssertEqual(SwiftDashSDKHost.distinctWalletCount(in: entries), 1)
    }

    func testDistinctWalletCountIncludesDifferentSeedsAcrossNetworks() {
        let entries = [
            (
                walletId: Data([0x01]),
                mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"),
            (
                walletId: Data([0x02]),
                mnemonic: "legal winner thank year wave sausage worth useful legal winner thank yellow"),
        ]

        XCTAssertEqual(SwiftDashSDKHost.distinctWalletCount(in: entries), 2)
    }
}

final class RecoveryPhraseRoutingTests: XCTestCase {
    private let seedA = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private let seedB = "legal winner thank year wave sausage worth useful legal winner thank yellow"

    func testSingleWalletRoutesDirectly() throws {
        let walletId = Data(repeating: 0x01, count: 32)
        let descriptors = try RecoveryPhraseInventory.makeDescriptors(
            entries: [entry(walletId: walletId, canonicalId: walletId, mnemonic: seedA, network: .mainnet)],
            currentNetwork: .mainnet,
            activeWalletIds: [.mainnet: walletId],
            displayNames: [walletId: "Primary"])

        guard case .direct(let descriptor) = RecoveryPhraseInventory.route(for: descriptors) else {
            return XCTFail("Expected one logical wallet to route directly")
        }
        XCTAssertEqual(descriptor.sourceWalletId, walletId)
        XCTAssertEqual(descriptor.displayName, "Primary")
    }

    func testMirroredNetworkEntriesForSameSeedRouteDirectly() throws {
        let mainnetId = Data(repeating: 0x11, count: 32)
        let testnetId = Data(repeating: 0x22, count: 32)
        let entries = [
            entry(walletId: mainnetId, canonicalId: mainnetId, mnemonic: seedA, network: .mainnet),
            entry(walletId: testnetId, canonicalId: mainnetId, mnemonic: seedA, network: .testnet),
        ]
        let descriptors = try RecoveryPhraseInventory.makeDescriptors(
            entries: entries,
            currentNetwork: .testnet,
            activeWalletIds: [.testnet: testnetId],
            displayNames: [testnetId: "Mirrored"])

        XCTAssertEqual(descriptors.count, 1)
        XCTAssertEqual(descriptors[0].sourceWalletId, testnetId)
        XCTAssertEqual(descriptors[0].networks, [.mainnet, .testnet])
        guard case .direct = RecoveryPhraseInventory.route(for: descriptors) else {
            return XCTFail("A mirrored seed must not show a chooser")
        }
    }

    func testDistinctSeedsRouteToChooser() throws {
        let walletA = Data(repeating: 0x31, count: 32)
        let walletB = Data(repeating: 0x42, count: 32)
        let descriptors = try RecoveryPhraseInventory.makeDescriptors(
            entries: [
                entry(walletId: walletA, canonicalId: walletA, mnemonic: seedA, network: .mainnet),
                entry(walletId: walletB, canonicalId: walletB, mnemonic: seedB, network: .testnet),
            ],
            currentNetwork: .mainnet,
            activeWalletIds: [.mainnet: walletA],
            displayNames: [walletA: "A", walletB: "B"])

        guard case .choose(let options) = RecoveryPhraseInventory.route(for: descriptors) else {
            return XCTFail("Distinct seeds must show the wallet chooser")
        }
        XCTAssertEqual(options.map(\.displayName), ["A", "B"])
        XCTAssertEqual(options.map(\.sourceWalletId), [walletA, walletB])
    }

    func testEmptyInventoryIsUnavailable() {
        XCTAssertEqual(RecoveryPhraseInventory.route(for: []), .unavailable)
    }

    func testConflictingMnemonicForCanonicalWalletFailsClosed() {
        let canonicalId = Data(repeating: 0x51, count: 32)
        XCTAssertThrowsError(try RecoveryPhraseInventory.makeDescriptors(
            entries: [
                entry(walletId: canonicalId, canonicalId: canonicalId, mnemonic: seedA, network: .mainnet),
                entry(
                    walletId: Data(repeating: 0x52, count: 32),
                    canonicalId: canonicalId,
                    mnemonic: seedB,
                    network: .testnet),
            ],
            currentNetwork: .mainnet,
            activeWalletIds: [:],
            displayNames: [:]))
    }

    private func entry(
        walletId: Data,
        canonicalId: Data,
        mnemonic: String,
        network: RecoveryPhraseWalletNetwork
    ) -> RecoveryPhraseInventoryEntry {
        RecoveryPhraseInventoryEntry(
            walletId: walletId,
            canonicalWalletId: canonicalId,
            normalizedMnemonic: mnemonic,
            network: network)
    }
}

final class MnemonicFirstWalletCreationTests: XCTestCase {
    func testPersistenceFailureDoesNotCreateWallet() {
        var storedMnemonic: String?
        var createCalled = false

        XCTAssertThrowsError(try MnemonicFirstWalletCreation.run(
            mnemonic: "test mnemonic",
            persistMnemonic: {
                storedMnemonic = "partially written"
                throw WalletLifecycleTestError.mnemonicPersistence
            },
            retrieveMnemonic: {
                storedMnemonic ?? ""
            },
            rollbackMnemonic: {
                storedMnemonic = nil
            },
            createWallet: {
                createCalled = true
                return 1
            }
        )) { error in
            guard case MnemonicFirstWalletCreationError.mnemonicPersistence = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        XCTAssertFalse(createCalled)
        XCTAssertNil(storedMnemonic)
    }

    func testMnemonicIsAvailableBeforeWalletCreation() throws {
        let mnemonic = "test mnemonic"
        var storedMnemonic: String?

        let wallet = try MnemonicFirstWalletCreation.run(
            mnemonic: mnemonic,
            persistMnemonic: {
                storedMnemonic = mnemonic
            },
            retrieveMnemonic: {
                storedMnemonic ?? ""
            },
            rollbackMnemonic: {
                storedMnemonic = nil
            },
            createWallet: {
                XCTAssertEqual(storedMnemonic, mnemonic)
                return 7
            })

        XCTAssertEqual(wallet, 7)
        XCTAssertEqual(storedMnemonic, mnemonic)
    }

    func testCreationFailureRemovesProvisionalMnemonicAndPropagatesError() {
        let mnemonic = "test mnemonic"
        var storedMnemonic: String?

        XCTAssertThrowsError(try MnemonicFirstWalletCreation.run(
            mnemonic: mnemonic,
            persistMnemonic: {
                storedMnemonic = mnemonic
            },
            retrieveMnemonic: {
                storedMnemonic ?? ""
            },
            rollbackMnemonic: {
                storedMnemonic = nil
            },
            createWallet: { () throws -> Int in
                throw WalletLifecycleTestError.walletCreation
            }
        )) { error in
            guard case MnemonicFirstWalletCreationError.walletCreation = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        XCTAssertNil(storedMnemonic)
    }

    func testCreationFailureRestoresPreviousMnemonic() {
        let previousMnemonic = "previous mnemonic"
        let replacementMnemonic = "replacement mnemonic"
        var storedMnemonic: String? = previousMnemonic

        XCTAssertThrowsError(try MnemonicFirstWalletCreation.run(
            mnemonic: replacementMnemonic,
            persistMnemonic: {
                storedMnemonic = replacementMnemonic
            },
            retrieveMnemonic: {
                storedMnemonic ?? ""
            },
            rollbackMnemonic: {
                storedMnemonic = previousMnemonic
            },
            createWallet: { () throws -> Int in
                throw WalletLifecycleTestError.walletCreation
            }))

        XCTAssertEqual(storedMnemonic, previousMnemonic)
    }
}
