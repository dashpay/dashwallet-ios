//
//  MaxSendFeeReserveTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//

import XCTest
@testable import dashpay

/// Pins the Max fee reserve to the previous build's formula, so the Max
/// amount stays the same for the same wallet: base 10 + 148 per input +
/// 34 × 2 outputs, plus half of that as a margin.
final class MaxSendFeeReserveTests: XCTestCase {
    func testEstimatedFeeMatchesThePreviousFormula() {
        XCTAssertEqual(SwiftDashSDKTransactionSender.estimatedFee(inputCount: 1), 226)
        XCTAssertEqual(SwiftDashSDKTransactionSender.estimatedFee(inputCount: 2), 374)
        XCTAssertEqual(SwiftDashSDKTransactionSender.estimatedFee(inputCount: 10), 1558)
        XCTAssertEqual(SwiftDashSDKTransactionSender.estimatedFee(inputCount: 250), 37078)
    }

    func testMaxReserveIsTheFeePlusHalf() {
        XCTAssertEqual(SwiftDashSDKTransactionSender.maxSendFeeReserve(forInputCount: 1), 339)
        XCTAssertEqual(SwiftDashSDKTransactionSender.maxSendFeeReserve(forInputCount: 2), 561)
        XCTAssertEqual(SwiftDashSDKTransactionSender.maxSendFeeReserve(forInputCount: 10), 2337)
        XCTAssertEqual(SwiftDashSDKTransactionSender.maxSendFeeReserve(forInputCount: 250), 55617)
    }
}
