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
    func testDepositFailureShowsThePlainTransferError() throws {
        let message = Coinbase.Error.general(.depositFailed).localizedDescription

        let key = "Couldn't complete the transfer"
        let missing = "<missing>"
        let en = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))

        XCTAssertNotEqual(Bundle.main.localizedString(forKey: key, value: missing, table: nil), missing)
        XCTAssertEqual(en.localizedString(forKey: key, value: missing, table: nil), key)
        XCTAssertEqual(message, Bundle.main.localizedString(forKey: key, value: missing, table: nil))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("crowdnode"), message)
    }
}
