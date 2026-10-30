//
//  ShortcutActionTypeTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//

import XCTest
@testable import dashpay

final class ShortcutActionTypeTests: XCTestCase {
    /// Raw values persist in `DWGlobalOptions.shortcuts`; a shifted value
    /// silently swaps the buttons on every saved bar.
    func testRawValuesArePinned() {
        let pinned: [(ShortcutActionType, Int)] = [
            (.secureWallet, 1), (.scanToPay, 2), (.payToAddress, 3), (.buySellDash, 4),
            (.payWithNFC, 5), (.localCurrency, 6), (.importPrivateKey, 7), (.switchToTestnet, 8),
            (.switchToMainnet, 9), (.reportAnIssue, 10), (.createUsername, 11), (.receive, 12),
            (.explore, 13), (.spend, 14), (.send, 15), (.atm, 16), (.sendToContact, 17),
            (.coinbase, 19), (.uphold, 20), (.topper, 21), (.getTestDash, 22),
            (.switchWallet, 23), (.dashDEX, 24), (.nodes, 25),
        ]
        for (type, rawValue) in pinned {
            XCTAssertEqual(type.rawValue, rawValue, "\(type)")
        }
    }

    func testRetiredRawValueIsNotACase() {
        XCTAssertNil(ShortcutActionType(rawValue: ShortcutActionType.retiredRawValue))
    }

    func testRetiredSlotBecomesSpendOrFaucet() {
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [.receive, .send, .explore, nil], isTestnet: false),
                       [.receive, .send, .explore, .spend])
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [.receive, .send, .explore, nil], isTestnet: true),
                       [.receive, .send, .explore, .getTestDash])
    }

    /// Compared against the actions as shown: a slot that already fell back
    /// to Spend counts, so the retired slot takes the next free candidate.
    func testRetiredSlotNeverDuplicatesAShownButton() {
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [.spend, nil, .explore, .send], isTestnet: false),
                       [.spend, .receive, .explore, .send])
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [.getTestDash, .explore, .receive, nil], isTestnet: true),
                       [.getTestDash, .explore, .receive, .send])
    }

    func testBarWithoutRetiredSlotIsUnchanged() {
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [.receive, .send, .coinbase, .nodes], isTestnet: false),
                       [.receive, .send, .coinbase, .nodes])
    }
}
