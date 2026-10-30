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

    private func restored(_ saved: [Int],
                          isTestnet: Bool = false,
                          canSwitchWallet: Bool = true,
                          hasEvonodes: Bool = true,
                          isDashDEXAvailable: Bool = true) -> [ShortcutActionType] {
        ShortcutActionType.restoredBar(saved: saved, isTestnet: isTestnet, canSwitchWallet: canSwitchWallet,
                                       hasEvonodes: hasEvonodes, isDashDEXAvailable: isDashDEXAvailable)
    }

    func testRetiredSlotBecomesSpendOrFaucetInPlace() {
        XCTAssertEqual(restored([12, 18, 15, 13]), [.receive, .spend, .send, .explore])
        XCTAssertEqual(restored([12, 18, 15, 13], isTestnet: true), [.receive, .getTestDash, .send, .explore])
    }

    func testRetiredSlotSkipsAButtonAlreadyShown() {
        XCTAssertEqual(restored([14, 18, 13, 15]), [.spend, .receive, .explore, .send])
    }

    /// Compared against the bar as shown: a slot that falls back to Spend
    /// counts, so the retired slot takes the next free candidate.
    func testRetiredSlotSkipsAnActionAnotherSlotFallsBackTo() {
        // Faucet saved on testnet, shown as Spend on mainnet.
        XCTAssertEqual(restored([22, 18, 13, 15]), [.spend, .receive, .explore, .send])
        // Dash DEX unavailable.
        XCTAssertEqual(restored([24, 18, 13, 15], isDashDEXAvailable: false), [.spend, .receive, .explore, .send])
        // Nodes without evonodes, on testnet.
        XCTAssertEqual(restored([25, 18, 12, 13], isTestnet: true, hasEvonodes: false),
                       [.getTestDash, .send, .receive, .explore])
        // Switch Wallet with one wallet: shown as Receive.
        XCTAssertEqual(restored([23, 18, 14, 13], canSwitchWallet: false), [.receive, .send, .spend, .explore])
    }

    func testTwoRetiredSlotsGetDistinctActionsInPlace() {
        XCTAssertEqual(restored([18, 12, 18, 15]), [.spend, .receive, .explore, .send])
    }

    func testUnknownRawValueDropsItsSlot() {
        XCTAssertEqual(restored([12, 999, 15, 13]), [.receive, .send, .explore])
    }

    func testBarWithoutRetiredSlotKeepsItsActions() {
        XCTAssertEqual(restored([12, 15, 19, 25]), [.receive, .send, .coinbase, .nodes])
    }
}
