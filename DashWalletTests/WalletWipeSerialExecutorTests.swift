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

final class WipeAcceptancePhraseTests: XCTestCase {
    private let polishPhrase =
        "Akceptuję to, że stracę wszystkie moje monety jeśli nie będę miał frazy do odzyskiwania portfela"

    func testRawPrecomposedPhraseMatchesDecomposedUnicodeWithoutRemovingPunctuation() {
        let decomposed = polishPhrase.decomposedStringWithCompatibilityMapping

        XCTAssertTrue(DWRecoverModel.wipeAcceptancePhraseMatches(
            polishPhrase,
            expectedPhrase: decomposed))
    }

    func testCaseAndWhitespaceAreNormalized() {
        let typed =
            "  AKCEPTUJĘ   TO, ŻE  STRACĘ WSZYSTKIE MOJE MONETY JEŚLI NIE BĘDĘ MIAŁ FRAZY DO ODZYSKIWANIA PORTFELA  "

        XCTAssertTrue(DWRecoverModel.wipeAcceptancePhraseMatches(
            typed,
            expectedPhrase: polishPhrase))
    }

    func testSemanticChangesAreRejected() {
        let missingDiacritic = polishPhrase.replacingOccurrences(
            of: "Akceptuję",
            with: "Akceptuje")
        let missingComma = polishPhrase.replacingOccurrences(
            of: "to, że",
            with: "to że")
        let changedWord = polishPhrase.replacingOccurrences(
            of: "monety",
            with: "środki")

        XCTAssertFalse(DWRecoverModel.wipeAcceptancePhraseMatches(
            missingDiacritic,
            expectedPhrase: polishPhrase))
        XCTAssertFalse(DWRecoverModel.wipeAcceptancePhraseMatches(
            missingComma,
            expectedPhrase: polishPhrase))
        XCTAssertFalse(DWRecoverModel.wipeAcceptancePhraseMatches(
            changedWord,
            expectedPhrase: polishPhrase))
    }

    func testAcceptanceTextCanMatchBelowMnemonicWordThreshold() {
        let phrase = "確認"

        XCTAssertLessThan((phrase as NSString).wordsCount, 10)
        XCTAssertTrue(DWRecoverModel.wipeAcceptancePhraseMatches(
            phrase,
            expectedPhrase: phrase))
    }

    func testObjectiveCBridgeAcceptsPhraseOnlyInSupportWipeMode() {
        let supportModel = DWRecoverModel(action: .supportWipe)
        let regularWipeModel = DWRecoverModel(action: .wipe)
        let resetPinModel = DWRecoverModel(action: .resetPin)
        let localizedPhrase = supportModel.wipeAcceptPhrase()

        XCTAssertTrue(supportModel.isWipeAcceptancePhrase(localizedPhrase))
        XCTAssertFalse(regularWipeModel.isWipeAcceptancePhrase(localizedPhrase))
        XCTAssertFalse(resetPinModel.isWipeAcceptancePhrase(localizedPhrase))
        XCTAssertFalse(supportModel.isWipeAcceptancePhrase("wipe"))
        XCTAssertFalse(supportModel.isWipeAcceptancePhrase("exterminate!"))
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
