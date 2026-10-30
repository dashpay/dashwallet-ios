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

    func testRetiredEntryBecomesSpendOrFaucet() {
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [12, 15, 13, 18], isTestnet: false), [12, 15, 13, 14])
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [12, 15, 13, 18], isTestnet: true), [12, 15, 13, 22])
    }

    func testRetiredEntryNeverDuplicatesAButtonOnTheBar() {
        // Spend and Explore are taken, so the retired slot gets Receive.
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [14, 18, 13, 15], isTestnet: false), [14, 12, 13, 15])
        // Faucet taken on testnet: the next free fallback.
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [22, 13, 12, 18], isTestnet: true), [22, 13, 12, 15])
    }

    func testBarWithoutRetiredEntryIsUnchanged() {
        XCTAssertEqual(ShortcutActionType.replacingRetired(in: [12, 15, 19, 999], isTestnet: false), [12, 15, 19, 999])
    }
}
