//
//  BiometricAllowanceTests.swift
//  DashWalletTests
//
//  The biometric spending allowance rules in `AuthenticationService`: what a
//  PIN entry restores, and which amounts the remaining allowance covers.
//

import XCTest
@testable import dashpay

final class BiometricAllowanceTests: XCTestCase {
    private let notSet = AuthenticationService.spendingLimitNotSet
    private let halfDash = kOneDash / 2

    // MARK: - PIN entry

    func testPinEntryRestoresNoAllowanceWithoutStoredLimit() {
        XCTAssertEqual(AuthenticationService.allowanceAfterPinEntry(limit: notSet), 0)
    }

    func testPinEntryRestoresNoAllowanceForZeroLimit() {
        XCTAssertEqual(AuthenticationService.allowanceAfterPinEntry(limit: 0), 0)
    }

    func testPinEntryRestoresTheStoredLimit() {
        XCTAssertEqual(AuthenticationService.allowanceAfterPinEntry(limit: halfDash), halfDash)
    }

    // MARK: - Spending

    func testNoStoredLimitRefusesEvenWithAStoredAllowance() {
        let allowance = Int64(bitPattern: notSet)
        XCTAssertFalse(AuthenticationService.biometricAllowanceCovers(amount: 1, allowanceLeft: allowance, limit: notSet))
    }

    func testZeroAllowanceRefusesAnyAmount() {
        XCTAssertFalse(AuthenticationService.biometricAllowanceCovers(amount: 1, allowanceLeft: 0, limit: 0))
    }

    func testMissingAllowanceRefuses() {
        XCTAssertFalse(AuthenticationService.biometricAllowanceCovers(amount: 1, allowanceLeft: nil, limit: halfDash))
    }

    func testAllowanceCoversAmountsUpToWhatIsLeft() {
        let left = Int64(halfDash)
        XCTAssertTrue(AuthenticationService.biometricAllowanceCovers(amount: halfDash, allowanceLeft: left, limit: halfDash))
        XCTAssertFalse(AuthenticationService.biometricAllowanceCovers(amount: halfDash + 1, allowanceLeft: left, limit: halfDash))
    }
}
