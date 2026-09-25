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

@MainActor
final class PendingInvitationStoreTests: XCTestCase {

    private var keychain: KeychainManager!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var scope = "1.walletA"
    private var hasUsername = false

    private let linkA = "dashpay://invite?du=alice&assetlocktx=\(String(repeating: "ab", count: 32))&pk=A&islock=null"
    private let linkB = "dashpay://invite?du=bob&assetlocktx=\(String(repeating: "cd", count: 32))&pk=B&islock=null"

    override func setUp() {
        super.setUp()
        // Unique service and defaults suite: nothing here touches the app's
        // own Keychain items or preferences.
        keychain = KeychainManager(serviceName: "org.dash.tests.invitations.\(UUID().uuidString)")
        suiteName = "PendingInvitationStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scope = "1.walletA"
        hasUsername = false
    }

    override func tearDown() {
        makeStore().wipeAllScopes()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> PendingInvitationStore {
        PendingInvitationStore(
            keychain: keychain,
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

    func testReceivedBeforeTheWalletIsMarkedFromOnboarding() {
        scope = PendingInvitationStore.scope(networkRawValue: 1, walletIdHex: nil)
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        XCTAssertEqual(store.pending?.fromOnboarding, true)
    }
}
