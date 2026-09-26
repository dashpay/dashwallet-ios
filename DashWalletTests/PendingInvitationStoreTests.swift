//
//  PendingInvitationStoreTests.swift
//  DashWalletTests
//
//  The store keeps a bearer secret, so the properties that matter are where
//  it lives (which network + wallet sees it), that one never overwrites
//  another, and that every way out removes it.
//

import SwiftDashSDK
import XCTest
@testable import dashpay

/// In-memory stand-in for the Keychain, with switchable failures.
@MainActor
private final class FakeSecretStorage: InvitationSecretStorage {
    var items: [String: Data] = [:]
    var failWrites = false
    var failDeletes = false
    var failListing = false

    func read(_ account: String) -> Data? { items[account] }

    func write(_ data: Data, account: String) -> Bool {
        guard !failWrites else { return false }
        items[account] = data
        return true
    }

    func delete(_ account: String) -> Bool {
        guard !failDeletes else { return false }
        items[account] = nil
        return true
    }

    func accounts(withPrefix prefix: String) -> [String]? {
        failListing ? nil : items.keys.filter { $0.hasPrefix(prefix) }
    }
}

@MainActor
final class PendingInvitationStoreTests: XCTestCase {

    private var storage: FakeSecretStorage!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var scope = "1.walletA"
    private var hasUsername = false

    private let linkA = "dashpay://invite?du=alice&assetlocktx=\(String(repeating: "ab", count: 32))&pk=A&islock=null"
    private let linkB = "dashpay://invite?du=bob&assetlocktx=\(String(repeating: "cd", count: 32))&pk=B&islock=null"

    override func setUp() {
        super.setUp()
        // Fake storage and a unique defaults suite: nothing here touches the
        // app's own Keychain items or preferences.
        storage = FakeSecretStorage()
        suiteName = "PendingInvitationStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scope = "1.walletA"
        hasUsername = false
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> PendingInvitationStore {
        PendingInvitationStore(
            storage: storage,
            defaults: defaults,
            scope: { [unowned self] in self.scope },
            hasRegisteredUsername: { [unowned self] in self.hasUsername })
    }

    func testStoredInvitationSurvivesANewStore() {
        XCTAssertEqual(makeStore().receive(linkA), .stored)
        XCTAssertEqual(makeStore().pending?.rawLink, linkA, "a relaunch must find the invitation")
    }

    func testSameLinkIsDuplicateAndADifferentOneIsRefused() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        XCTAssertEqual(store.receive(linkA), .duplicate)
        XCTAssertEqual(store.receive(linkB), .busy)
        XCTAssertEqual(store.pending?.rawLink, linkA, "the pending invitation is never overwritten")
    }

    func testNotAnInvitationIsNotStored() {
        let store = makeStore()
        XCTAssertEqual(store.receive("https://example.org/"), .notAnInvitation)
        XCTAssertNil(store.pending)
    }

    func testRegisteredUsernameRefusesWithoutStoring() {
        hasUsername = true
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .alreadyHasIdentity)
        XCTAssertNil(store.pending)
    }

    func testOtherWalletAndNetworkDoNotSeeIt() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)

        scope = "1.walletB"
        store.reload()
        XCTAssertNil(store.pending, "another wallet must not see the invitation")

        scope = "2.walletA"
        store.reload()
        XCTAssertNil(store.pending, "another network must not see the invitation")

        scope = "1.walletA"
        store.reload()
        XCTAssertEqual(store.pending?.rawLink, linkA)
    }

    func testClearRemovesItFromTheKeychain() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        store.clear(reason: .hidden)
        XCTAssertNil(store.pending)
        XCTAssertNil(makeStore().pending)
        XCTAssertEqual(store.receive(linkA), .stored, "opening the link again brings it back")
    }

    func testWipeRemovesEveryScope() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        scope = "2.walletB"
        XCTAssertEqual(store.receive(linkB), .stored)

        store.wipeAllScopes()

        XCTAssertNil(makeStore().pending)
        scope = "1.walletA"
        XCTAssertNil(makeStore().pending)
    }

    // MARK: - Binding a pre-onboarding invitation to the new wallet

    private func receiveBeforeWallet(_ link: String) -> PendingInvitationStore {
        scope = "1.unbound"
        let store = makeStore()
        XCTAssertEqual(store.receive(link), .stored)
        scope = "1.walletA"
        return store
    }

    func testBindingMovesTheInvitationUnderTheWallet() {
        let store = receiveBeforeWallet(linkA)
        XCTAssertTrue(store.bindUnboundToCurrentWallet())
        XCTAssertEqual(store.pending?.rawLink, linkA)
        XCTAssertEqual(store.pending?.fromOnboarding, true)
        scope = "1.unbound"
        XCTAssertNil(makeStore().pending, "the unbound copy is gone once moved")
    }

    func testFailedBindingKeepsTheUnboundInvitation() {
        let store = receiveBeforeWallet(linkA)
        storage.failWrites = true
        XCTAssertFalse(store.bindUnboundToCurrentWallet())
        scope = "1.unbound"
        XCTAssertEqual(makeStore().pending?.rawLink, linkA, "a failed move must not lose the invitation")

        storage.failWrites = false
        scope = "1.walletA"
        XCTAssertTrue(store.bindUnboundToCurrentWallet(), "the next attempt moves it")
        XCTAssertEqual(store.pending?.rawLink, linkA)
    }

    func testBindingKeepsTheWalletsOwnInvitation() {
        XCTAssertEqual(makeStore().receive(linkB), .stored)
        let store = receiveBeforeWallet(linkA)
        XCTAssertTrue(store.bindUnboundToCurrentWallet())
        XCTAssertEqual(store.pending?.rawLink, linkB, "an invitation already under the wallet wins")
    }

    // MARK: - Failures are reported, not hidden

    func testFailedReceiveWriteStoresNothing() {
        storage.failWrites = true
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .storageFailed)
        XCTAssertNil(store.pending)
    }

    func testFailedDeleteKeepsTheInvitationPending() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        storage.failDeletes = true
        XCTAssertFalse(store.clear(reason: .hidden))
        XCTAssertEqual(store.pending?.rawLink, linkA)
        XCTAssertFalse(store.wipeAllScopes())
        XCTAssertEqual(makeStore().pending?.rawLink, linkA)
    }

    func testUnlistableStorageFailsTheWipe() {
        XCTAssertEqual(makeStore().receive(linkA), .stored)
        storage.failListing = true
        XCTAssertFalse(makeStore().wipeAllScopes())
    }

    // MARK: - Clearing by link

    func testClearingByLinkReachesItsScopeAndSparesOthers() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        scope = "1.walletB"
        XCTAssertEqual(store.receive(linkB), .stored)

        // The claim for A finishes after the user switched to wallet B.
        XCTAssertTrue(store.clear(normalizedURI: linkA, reason: .claimed))
        XCTAssertEqual(store.pending?.rawLink, linkB, "B's invitation is untouched")
        scope = "1.walletA"
        XCTAssertNil(makeStore().pending, "A's consumed invitation is gone")
    }

    func testReceivedBeforeTheWalletIsMarkedFromOnboarding() {
        scope = PendingInvitationStore.scope(networkRawValue: 1, walletIdHex: nil)
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        XCTAssertEqual(store.pending?.fromOnboarding, true)
    }
}
