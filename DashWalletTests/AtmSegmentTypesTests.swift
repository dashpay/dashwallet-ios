//
//  AtmSegmentTypesTests.swift
//  DashWalletTests
//
//  Each ATM segment lists every machine that supports its action: a two-way
//  machine belongs under Buy and under Sell as well as under Buy/Sell.
//

import XCTest
@testable import dashpay

final class AtmSegmentTypesTests: XCTestCase {

    private func types(for segment: AtmListSegmnets) -> Set<ExplorePointOfUse.Atm.`Type`>? {
        (segment.dataProvider as? BaseAtmsDataProvider)?.types.map(Set.init)
    }

    func testAllIsUnfiltered() {
        XCTAssertNotNil(AtmListSegmnets.all.dataProvider as? BaseAtmsDataProvider)
        XCTAssertNil(types(for: .all))
    }

    func testBuyIncludesTwoWayMachines() {
        XCTAssertEqual(types(for: .buy), [.buy, .buySell])
    }

    func testSellIncludesSellOnlyAndTwoWayMachines() {
        XCTAssertEqual(types(for: .sell), [.sell, .buySell])
    }

    func testBuyAndSellIsTwoWayOnly() {
        XCTAssertEqual(types(for: .buyAndSell), [.buySell])
    }
}
