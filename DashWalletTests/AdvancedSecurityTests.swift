//
//  AdvancedSecurityTests.swift
//  DashWalletTests
//
//  Advanced Security moved from Objective-C to SwiftUI. These pin the parts
//  that must not drift in the port: the security-level table, the slider
//  stops, the defaults "Reset to Default" writes, and that a refused limit
//  change is shown as refused rather than as applied.
//

import XCTest
@testable import dashpay

@MainActor
final class AdvancedSecurityTests: XCTestCase {

    // MARK: - Security level

    func testBothOffIsNone() {
        XCTAssertEqual(WalletSecurityLevel.level(lockTime: nil, spendingLimit: nil), .none)
    }

    func testImmediateLockAndAlwaysPinIsVeryHigh() {
        XCTAssertEqual(WalletSecurityLevel.level(lockTime: 0, spendingLimit: 0), .veryHigh)
    }

    func testBothOnIsHigh() {
        XCTAssertEqual(WalletSecurityLevel.level(lockTime: 60, spendingLimit: kOneDash / 2), .high)
        XCTAssertEqual(WalletSecurityLevel.level(lockTime: 0, spendingLimit: kOneDash), .high)
    }

    func testLongLockWithoutConfirmationIsLow() {
        XCTAssertEqual(WalletSecurityLevel.level(lockTime: 60 * 60, spendingLimit: nil), .low)
        XCTAssertEqual(WalletSecurityLevel.level(lockTime: 60 * 60 * 24, spendingLimit: nil), .low)
    }

    func testShortLockWithoutConfirmationIsMedium() {
        XCTAssertEqual(WalletSecurityLevel.level(lockTime: 60 * 5, spendingLimit: nil), .medium)
    }

    func testConfirmationWithoutLockIsMedium() {
        XCTAssertEqual(WalletSecurityLevel.level(lockTime: nil, spendingLimit: 0), .medium)
    }

    // MARK: - View model

    private final class StoreSpy: AdvancedSecuritySettingsStore {
        var autoLogout = false
        var lockTimerInterval = 60 * 5
        var spendingConfirmationEnabled = false
        var canConfigureSpendingConfirmation = true
        var spendingLimit: UInt64 = kOneDash
        var biometry: AdvancedSecurityBiometry = .faceID
        /// Simulates `AuthenticationService` refusing the write.
        var refusesLimitChanges = false

        func setSpendingLimit(_ duffs: UInt64) {
            guard !refusesLimitChanges else { return }
            spendingLimit = duffs
        }
    }

    func testSlidersSelectTheStoredStops() {
        let store = StoreSpy()
        let viewModel = AdvancedSecurityViewModel(store: store)

        XCTAssertEqual(viewModel.lockTimerIndex, 2) // 5 min
        XCTAssertEqual(viewModel.spendingLimitIndex, 3) // 1 Dash
    }

    func testSelectingStopsWritesTheStore() {
        let store = StoreSpy()
        let viewModel = AdvancedSecurityViewModel(store: store)

        viewModel.selectLockTimer(at: 4)
        viewModel.selectSpendingLimit(at: 1)

        XCTAssertEqual(store.lockTimerInterval, 60 * 60 * 24)
        XCTAssertEqual(store.spendingLimit, kOneDash / 10)
        XCTAssertEqual(viewModel.lockTimerIndex, 4)
        XCTAssertEqual(viewModel.spendingLimitIndex, 1)
    }

    func testRefusedLimitChangeKeepsTheStoredLimit() {
        let store = StoreSpy()
        store.refusesLimitChanges = true
        let viewModel = AdvancedSecurityViewModel(store: store)

        viewModel.selectSpendingLimit(at: 0)

        XCTAssertEqual(viewModel.spendingLimitIndex, 3, "A refused change must not show as applied")
    }

    func testUnsetLimitSelectsNoStopAndCountsAsOff() {
        let store = StoreSpy()
        store.spendingLimit = AuthenticationService.spendingLimitNotSet
        store.spendingConfirmationEnabled = true
        store.autoLogout = true
        let viewModel = AdvancedSecurityViewModel(store: store)

        XCTAssertNil(viewModel.spendingLimitIndex)
        XCTAssertNil(viewModel.spendingLimitAmount)
        XCTAssertEqual(viewModel.securityLevel, .medium) // 5 min lock, no limit
    }

    func testUnsetLimitPromisesNoPaymentPolicy() {
        let store = StoreSpy()
        store.spendingLimit = AuthenticationService.spendingLimitNotSet
        store.spendingConfirmationEnabled = true
        let viewModel = AdvancedSecurityViewModel(store: store)

        XCTAssertFalse(viewModel.descriptionShowsAmount)
        XCTAssertEqual(viewModel.spendingLimitDescription,
                       NSLocalizedString("No biometric spending limit is set", comment: ""))
        XCTAssertEqual(viewModel.spendingLimitValueText, NSLocalizedString("None", comment: ""))
    }

    func testZeroLimitReadsAsAlwaysRequiringPIN() {
        let store = StoreSpy()
        store.spendingLimit = 0
        store.spendingConfirmationEnabled = true
        let viewModel = AdvancedSecurityViewModel(store: store)

        XCTAssertFalse(viewModel.descriptionShowsAmount)
        XCTAssertEqual(viewModel.spendingLimitDescription,
                       NSLocalizedString("PIN is always required to make a payment", comment: ""))
    }

    func testOffStopLockTimerKeepsItsValueText() {
        let store = StoreSpy()
        store.lockTimerInterval = 120
        let viewModel = AdvancedSecurityViewModel(store: store)

        XCTAssertNil(viewModel.lockTimerIndex)
        XCTAssertFalse(viewModel.lockTimerValueText.isEmpty)
    }

    func testResetToDefault() {
        let store = StoreSpy()
        let viewModel = AdvancedSecurityViewModel(store: store)

        viewModel.resetToDefault()

        XCTAssertTrue(store.autoLogout)
        XCTAssertEqual(store.lockTimerInterval, 60)
        XCTAssertTrue(store.spendingConfirmationEnabled)
        XCTAssertEqual(store.spendingLimit, kOneDash / 2)
        XCTAssertEqual(viewModel.securityLevel, .high)
    }

    func testLimitSliderNeedsBiometricsAndConfirmation() {
        let store = StoreSpy()
        store.spendingConfirmationEnabled = true
        store.canConfigureSpendingConfirmation = false
        let viewModel = AdvancedSecurityViewModel(store: store)

        XCTAssertFalse(viewModel.showsSpendingLimit)

        store.canConfigureSpendingConfirmation = true
        viewModel.setSpendingConfirmation(true)

        XCTAssertTrue(viewModel.showsSpendingLimit)
    }

    func testDemoStoreNeverTouchesTheWalletSettings() {
        let options = DWGlobalOptions.sharedInstance()
        let lockScreenDisabled = options.lockScreenDisabled()
        let interval = options.autoLockAppInterval
        let viewModel = AdvancedSecurityViewModel(store: DemoAdvancedSecuritySettingsStore(), isInteractive: false)

        viewModel.setAutoLogout(false)
        viewModel.selectLockTimer(at: 4)

        XCTAssertEqual(options.lockScreenDisabled(), lockScreenDisabled)
        XCTAssertEqual(options.autoLockAppInterval, interval)
        XCTAssertFalse(viewModel.isInteractive)
    }
}
