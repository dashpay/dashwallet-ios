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
    var unreadable: Set<String> = []

    func read(_ account: String) -> InvitationSecretRead {
        if unreadable.contains(account) { return .failed }
        return items[account].map(InvitationSecretRead.found) ?? .missing
    }

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
    private var scope = InvitationScope(networkRawValue: 1, walletIdHex: "walletA")
    private var hasUsername = false

    private let walletA = InvitationScope(networkRawValue: 1, walletIdHex: "walletA")
    private let walletB = InvitationScope(networkRawValue: 1, walletIdHex: "walletB")
    private let otherNetworkA = InvitationScope(networkRawValue: 2, walletIdHex: "walletA")
    private let unbound = InvitationScope(networkRawValue: 1, walletIdHex: nil)

    private let linkA = "dashpay://invite?du=alice&assetlocktx=\(String(repeating: "ab", count: 32))&pk=A&islock=null"
    private let linkB = "dashpay://invite?du=bob&assetlocktx=\(String(repeating: "cd", count: 32))&pk=B&islock=null"

    override func setUp() {
        super.setUp()
        // Fake storage and a unique defaults suite: nothing here touches the
        // app's own Keychain items or preferences.
        storage = FakeSecretStorage()
        suiteName = "PendingInvitationStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scope = walletA
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
            currentScope: { [unowned self] in self.scope },
            hasRegisteredUsername: { [unowned self] in self.hasUsername })
    }

    private func pending(in scope: InvitationScope) -> PendingInvitation? {
        self.scope = scope
        return makeStore().pending
    }

    // MARK: - Receiving

    func testStoredInvitationSurvivesANewStoreAndCarriesItsScope() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        let reloaded = makeStore().pending
        XCTAssertEqual(reloaded, store.pending, "a reloaded invitation equals the one shown, timestamp included")
        XCTAssertEqual(reloaded?.rawLink, linkA, "a relaunch must find the invitation")
        XCTAssertEqual(reloaded?.scope, walletA)
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

    func testFailedReceiveWriteStoresNothing() {
        storage.failWrites = true
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .storageFailed)
        XCTAssertNil(store.pending)
    }

    func testOtherWalletAndNetworkDoNotSeeIt() {
        XCTAssertEqual(makeStore().receive(linkA), .stored)
        XCTAssertNil(pending(in: walletB), "another wallet must not see the invitation")
        XCTAssertNil(pending(in: otherNetworkA), "another network must not see the invitation")
        XCTAssertEqual(pending(in: walletA)?.rawLink, linkA)
    }

    // MARK: - Removal: one scope, or the voucher everywhere

    func testRemovingAnInvitationTouchesOnlyItsOwnScope() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        let shownInA = store.pending!
        scope = otherNetworkA
        XCTAssertEqual(store.receive(linkA), .stored, "the same link opened on the other network")

        // A wallet-local verdict (e.g. wrong network) for the copy on the
        // other network must not delete wallet A's copy.
        XCTAssertTrue(store.remove(store.pending!, reason: .definitiveOutcome))
        XCTAssertNil(pending(in: otherNetworkA))
        // Scope and link, not whole-value equality: `receivedAt` loses
        // sub-microsecond precision through the defaults round trip.
        let stillInA = pending(in: walletA)
        XCTAssertEqual(stillInA?.scope, shownInA.scope)
        XCTAssertEqual(stillInA?.rawLink, shownInA.rawLink)
    }

    func testRemovingSparesADifferentInvitationStoredSince() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        let old = store.pending!
        XCTAssertTrue(store.remove(old, reason: .hidden))
        XCTAssertEqual(store.receive(linkB), .stored)
        XCTAssertTrue(store.remove(old, reason: .hidden), "the old one is already gone")
        XCTAssertEqual(store.pending?.rawLink, linkB, "a stale removal must not delete the new invitation")
    }

    func testRemovingEverywhereReachesEveryScopeAndSparesOtherLinks() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        scope = walletB
        XCTAssertEqual(store.receive(linkA), .stored)
        scope = otherNetworkA
        XCTAssertEqual(store.receive(linkB), .stored)

        XCTAssertTrue(store.removeEverywhere(normalizedURI: linkA, reason: .claimed))
        XCTAssertNil(pending(in: walletA))
        XCTAssertNil(pending(in: walletB))
        XCTAssertEqual(pending(in: otherNetworkA)?.rawLink, linkB)
    }

    func testRemovingAWalletRemovesOnlyItsInvitation() {
        XCTAssertEqual(makeStore().receive(linkA), .stored)
        scope = walletB
        XCTAssertEqual(makeStore().receive(linkB), .stored)

        XCTAssertTrue(makeStore().removeAll(walletIdHex: "walletA"))
        XCTAssertNil(pending(in: walletA))
        XCTAssertEqual(pending(in: walletB)?.rawLink, linkB)
    }

    // MARK: - Binding a pre-onboarding invitation (runs on every reload)

    private func receiveBeforeWallet(_ link: String) {
        scope = unbound
        XCTAssertEqual(makeStore().receive(link), .stored)
        XCTAssertEqual(makeStore().pending?.fromOnboarding, true)
        scope = walletA
    }

    func testReloadMovesTheInvitationUnderTheNewWallet() {
        receiveBeforeWallet(linkA)
        let store = makeStore()
        XCTAssertEqual(store.pending?.rawLink, linkA)
        XCTAssertEqual(store.pending?.scope, walletA)
        XCTAssertEqual(store.pending?.fromOnboarding, true)
        XCTAssertNil(pending(in: unbound), "the unbound copy is gone once moved")
    }

    func testFailedMoveKeepsTheUnboundInvitationAndTheNextReloadRetries() {
        receiveBeforeWallet(linkA)
        storage.failWrites = true
        let store = makeStore()
        XCTAssertNil(store.pending)
        XCTAssertNotNil(storage.items[PendingInvitationStore.keychainPrefix + unbound.storageKey],
                        "a failed move must not lose the invitation")

        storage.failWrites = false
        store.reload()
        XCTAssertEqual(store.pending?.rawLink, linkA, "the next reload moves it")
    }

    func testBindingKeepsTheWalletsOwnInvitation() {
        XCTAssertEqual(makeStore().receive(linkB), .stored)
        receiveBeforeWallet(linkA)
        XCTAssertEqual(makeStore().pending?.rawLink, linkB, "an invitation already under the wallet wins")
    }

    // MARK: - Failures are reported, not hidden

    func testFailedDeleteKeepsTheInvitationPending() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        storage.failDeletes = true
        XCTAssertFalse(store.remove(store.pending!, reason: .hidden))
        XCTAssertEqual(store.pending?.rawLink, linkA)
        XCTAssertFalse(store.wipeAllScopes())
        XCTAssertEqual(makeStore().pending?.rawLink, linkA)
    }

    // MARK: - An unreadable item is not an absent one

    private var accountA: String { PendingInvitationStore.keychainPrefix + walletA.storageKey }

    func testUnreadableSlotIsNeverOverwrittenOrReportedRemoved() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        let shown = store.pending!
        storage.unreadable = [accountA]

        XCTAssertEqual(store.receive(linkB), .storageFailed, "must not overwrite what could not be read")
        XCTAssertFalse(store.remove(shown, reason: .hidden))
        XCTAssertFalse(store.removeEverywhere(normalizedURI: linkA, reason: .claimed))
        store.reload()
        XCTAssertEqual(store.pending?.rawLink, linkA, "an unreadable slot keeps the last known state")

        storage.unreadable = []
        XCTAssertTrue(store.remove(shown, reason: .hidden))
        XCTAssertNil(store.pending)
    }

    /// Switching to a wallet whose slot cannot be read must not leave the
    /// previous wallet's card up: Create would then spend that wallet's
    /// voucher from the new one, and Hide would delete it.
    func testUnreadableSlotAfterASwitchDropsThePreviousWalletsCard() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        XCTAssertEqual(store.pending?.scope, walletA)

        storage.unreadable = [PendingInvitationStore.keychainPrefix + walletB.storageKey]
        scope = walletB
        store.reload()
        XCTAssertNil(store.pending, "wallet A's card must not stand in for wallet B's unreadable slot")

        scope = walletA
        store.reload()
        XCTAssertEqual(store.pending?.rawLink, linkA, "wallet A's invitation is untouched")
    }

    func testUnreadableWalletSlotBlocksTheMove() {
        receiveBeforeWallet(linkA)
        storage.unreadable = [accountA]
        _ = makeStore()
        XCTAssertNotNil(storage.items[PendingInvitationStore.keychainPrefix + unbound.storageKey],
                        "the pre-onboarding copy stays while the wallet's slot cannot be read")
        storage.unreadable = []
        XCTAssertEqual(makeStore().pending?.rawLink, linkA)
    }

    func testUnlistableStorageFailsWipeAndBroadRemovals() {
        XCTAssertEqual(makeStore().receive(linkA), .stored)
        storage.failListing = true
        let store = makeStore()
        XCTAssertFalse(store.wipeAllScopes())
        XCTAssertFalse(store.removeEverywhere(normalizedURI: linkA, reason: .claimed))
        XCTAssertFalse(store.removeAll(walletIdHex: "walletA"))
    }

    func testWipeRemovesEveryScope() {
        let store = makeStore()
        XCTAssertEqual(store.receive(linkA), .stored)
        scope = otherNetworkA
        XCTAssertEqual(store.receive(linkB), .stored)

        XCTAssertTrue(store.wipeAllScopes())

        XCTAssertNil(pending(in: otherNetworkA))
        XCTAssertNil(pending(in: walletA))
    }

    // MARK: - Scope value

    /// Mid-switch the selected wallet is B while the SDK host is still bound
    /// to A: nothing may read wallet-local state or spend for B yet.
    func testScopeIsActiveOnlyWhenSelectedAndBound() {
        XCTAssertTrue(InvitationScope.isActiveAndBound(walletB, selected: walletB, bound: walletB))
        XCTAssertFalse(InvitationScope.isActiveAndBound(walletB, selected: walletB, bound: walletA),
                       "the host still exposes the outgoing wallet")
        XCTAssertFalse(InvitationScope.isActiveAndBound(walletB, selected: walletB, bound: nil),
                       "no wallet bound yet")
        XCTAssertFalse(InvitationScope.isActiveAndBound(walletA, selected: walletB, bound: walletA),
                       "the user already switched away")
    }

    func testScopeStorageKeyRoundTrips() {
        for scope in [walletA, unbound, otherNetworkA] {
            XCTAssertEqual(InvitationScope(storageKey: scope.storageKey), scope)
        }
        XCTAssertEqual(InvitationScope(networkRawValue: 1, walletIdHex: ""), unbound)
        XCTAssertNil(InvitationScope(storageKey: "garbage"))
    }
}
