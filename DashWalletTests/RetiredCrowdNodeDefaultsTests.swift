//
//  RetiredCrowdNodeDefaultsTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//

import XCTest
@testable import dashpay

final class RetiredCrowdNodeDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RetiredCrowdNodeDefaultsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRemovesGlobalAndBarePerWalletKeys() {
        for key in RetiredCrowdNodeDefaults.globalKeys + RetiredCrowdNodeDefaults.perWalletKeys {
            defaults.set(true, forKey: key)
        }

        RetiredCrowdNodeDefaults.removeAll(from: defaults)

        for key in RetiredCrowdNodeDefaults.globalKeys + RetiredCrowdNodeDefaults.perWalletKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
    }

    func testRemovesPerWalletKeysOfEveryWallet() {
        let keys = RetiredCrowdNodeDefaults.perWalletKeys.flatMap { ["\($0)_aa01", "\($0)_bb02"] }
        for key in keys {
            defaults.set(1, forKey: key)
        }

        RetiredCrowdNodeDefaults.removeAll(from: defaults)

        for key in keys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
    }

    /// The online-state key starts with a Cyrillic "с": a Latin spelling
    /// would match nothing a real install wrote.
    func testRemovesTheCyrillicPrefixedKey() {
        let written = "\u{0441}rowdNodeOnlineAccountStateKey"
        XCTAssertNotEqual(written, "crowdNodeOnlineAccountStateKey")
        defaults.set(3, forKey: written)
        defaults.set(3, forKey: "\(written)_aa01")

        RetiredCrowdNodeDefaults.removeAll(from: defaults)

        XCTAssertNil(defaults.object(forKey: written))
        XCTAssertNil(defaults.object(forKey: "\(written)_aa01"))
    }

    func testLeavesOtherKeysAlone() {
        let others = [
            "lastKnownCrowdNodeBalanceKeyExtra",
            "feePercentageKey_aa01",
            "coinJoinWithdrawalTags_aa01",
            "shortcuts",
        ]
        for key in others {
            defaults.set(1, forKey: key)
        }

        RetiredCrowdNodeDefaults.removeAll(from: defaults)

        for key in others {
            XCTAssertNotNil(defaults.object(forKey: key), key)
        }
    }

    func testRunsOnceWithProtectedDataAndRecordsIt() {
        defaults.set(1, forKey: "crowdNodeInfoShownKey")

        RetiredCrowdNodeDefaults.removeAllOnce(from: defaults, isProtectedDataAvailable: true)

        XCTAssertNil(defaults.object(forKey: "crowdNodeInfoShownKey"))
        XCTAssertTrue(defaults.bool(forKey: RetiredCrowdNodeDefaults.doneKey))
        // Recorded as done: a later run touches nothing.
        defaults.set(1, forKey: "crowdNodeInfoShownKey")
        RetiredCrowdNodeDefaults.removeAllOnce(from: defaults, isProtectedDataAvailable: true)
        XCTAssertNotNil(defaults.object(forKey: "crowdNodeInfoShownKey"))
    }

    /// Before the first unlock the defaults can read back empty, so nothing
    /// is recorded and the next launch does the work.
    func testWithoutProtectedDataNothingIsRecorded() {
        defaults.set(1, forKey: "crowdNodeInfoShownKey")

        RetiredCrowdNodeDefaults.removeAllOnce(from: defaults, isProtectedDataAvailable: false)

        XCTAssertNotNil(defaults.object(forKey: "crowdNodeInfoShownKey"))
        XCTAssertFalse(defaults.bool(forKey: RetiredCrowdNodeDefaults.doneKey))
    }

    func testWebDomainMatchesTheServiceAndItsSubdomainsOnly() {
        XCTAssertTrue(RetiredCrowdNodeDefaults.isWebDomain("crowdnode.io"))
        XCTAssertTrue(RetiredCrowdNodeDefaults.isWebDomain(".crowdnode.io"))
        XCTAssertTrue(RetiredCrowdNodeDefaults.isWebDomain("app.crowdnode.io"))
        XCTAssertTrue(RetiredCrowdNodeDefaults.isWebDomain("test.crowdnode.io"))
        XCTAssertTrue(RetiredCrowdNodeDefaults.isWebDomain("App.CrowdNode.io"))
        XCTAssertTrue(RetiredCrowdNodeDefaults.isWebDomain("app.crowdnode.io."))
        XCTAssertFalse(RetiredCrowdNodeDefaults.isWebDomain("mycrowdnode.io"))
        XCTAssertFalse(RetiredCrowdNodeDefaults.isWebDomain("crowdnode.io.example.com"))
    }

    func testWebsiteDataGoesOnlyInTheForegroundWithProtectedDataUntilDone() {
        XCTAssertTrue(RetiredCrowdNodeDefaults.shouldRemoveWebsiteData(
            defaults: defaults, isProtectedDataAvailable: true, isActive: true))
        XCTAssertFalse(RetiredCrowdNodeDefaults.shouldRemoveWebsiteData(
            defaults: defaults, isProtectedDataAvailable: true, isActive: false))
        XCTAssertFalse(RetiredCrowdNodeDefaults.shouldRemoveWebsiteData(
            defaults: defaults, isProtectedDataAvailable: false, isActive: true))
        // The defaults pass being done doesn't stand in for the website data.
        RetiredCrowdNodeDefaults.removeAllOnce(from: defaults, isProtectedDataAvailable: true)
        XCTAssertTrue(RetiredCrowdNodeDefaults.shouldRemoveWebsiteData(
            defaults: defaults, isProtectedDataAvailable: true, isActive: true))
        defaults.set(true, forKey: RetiredCrowdNodeDefaults.websiteDataDoneKey)
        XCTAssertFalse(RetiredCrowdNodeDefaults.shouldRemoveWebsiteData(
            defaults: defaults, isProtectedDataAvailable: true, isActive: true))
    }

    func testSecondRunIsHarmless() {
        defaults.set(1, forKey: "crowdNodeInfoShownKey")

        RetiredCrowdNodeDefaults.removeAll(from: defaults)
        RetiredCrowdNodeDefaults.removeAll(from: defaults)

        XCTAssertNil(defaults.object(forKey: "crowdNodeInfoShownKey"))
    }
}
