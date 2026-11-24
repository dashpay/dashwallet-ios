//
//  MasternodeClaimableBalanceTests.swift
//  DashWalletTests
//

import XCTest
@testable import dashpay

final class MasternodeClaimableBalanceTests: XCTestCase {
    private let identity = Data(repeating: 7, count: 32)
    private let other = Data(repeating: 9, count: 32)

    func testAnIdentityWithABalanceReportsItsCredits() {
        XCTAssertEqual(MasternodeClaimableBalance.resolve([identity: 1_500], identityId: identity), .credits(1_500))
        XCTAssertEqual(MasternodeClaimableBalance.resolve([identity: 0], identityId: identity), .credits(0))
    }

    func testAnIdentityTheReadDoesNotHoldHasNoPlatformIdentity() {
        XCTAssertEqual(MasternodeClaimableBalance.resolve([:], identityId: identity), .noIdentity)
        XCTAssertEqual(MasternodeClaimableBalance.resolve([other: 1_500], identityId: identity), .noIdentity)
        let withoutBalance: [Data: UInt64?] = [identity: nil]
        XCTAssertEqual(MasternodeClaimableBalance.resolve(withoutBalance, identityId: identity), .noIdentity)
    }
}
