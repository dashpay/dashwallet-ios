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

    /// The wiper's per-wallet deletion removes that wallet's keys only.
    func testRemovesOneWalletsPerWalletKeys() {
        let removed = RetiredCrowdNodeDefaults.perWalletKeys.map { "\($0)_aa01" }
        let kept = RetiredCrowdNodeDefaults.perWalletKeys.map { "\($0)_bb02" }
        for key in removed + kept {
            defaults.set(1, forKey: key)
        }

        RetiredCrowdNodeDefaults.removePerWalletKeys(forWalletIdHex: "aa01", from: defaults)

        for key in removed {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        for key in kept {
            XCTAssertNotNil(defaults.object(forKey: key), key)
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

    /// A per-wallet name is removed only with a wallet id after the
    /// underscore: lowercase hex, as the old code wrote it.
    func testLeavesAPerWalletNameWithANonHexSuffix() {
        let walletKey = "crowdNodeAccountAddressKey_0a1b2c3d"
        let others = [
            "crowdNodeAccountAddressKey_backup",
            "crowdNodeAccountAddressKey_",
            "crowdNodeAccountAddressKey_0A1B2C3D",
            "lastWithdrawalBlockKey_aa01_extra",
        ]
        for key in [walletKey] + others {
            defaults.set(1, forKey: key)
        }

        RetiredCrowdNodeDefaults.removeAll(from: defaults)

        XCTAssertNil(defaults.object(forKey: walletKey))
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

    func testSecondRunIsHarmless() {
        defaults.set(1, forKey: "crowdNodeInfoShownKey")

        RetiredCrowdNodeDefaults.removeAll(from: defaults)
        RetiredCrowdNodeDefaults.removeAll(from: defaults)

        XCTAssertNil(defaults.object(forKey: "crowdNodeInfoShownKey"))
    }
}
