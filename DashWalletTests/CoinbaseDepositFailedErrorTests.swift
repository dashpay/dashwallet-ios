//
//  CoinbaseDepositFailedErrorTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//

import XCTest
@testable import dashpay

/// A failed Coinbase transfer shows the plain, already translated transfer
/// error, with no CrowdNode text (AC-03).
final class CoinbaseDepositFailedErrorTests: XCTestCase {
    func testDepositFailureShowsThePlainTransferError() {
        let message = Coinbase.Error.general(.depositFailed).localizedDescription

        XCTAssertEqual(message, NSLocalizedString("Couldn't complete the transfer", comment: "Coinbase"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("crowdnode"), message)
    }
}
