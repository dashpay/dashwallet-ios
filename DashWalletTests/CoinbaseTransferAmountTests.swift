//
//  CoinbaseTransferAmountTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//

import Combine
import XCTest
@testable import dashwallet

@MainActor
final class CoinbaseTransferAmountTests: XCTestCase {

    func testNoCrowdNodeBalanceDoesNotRequireWarning() {
        XCTAssertFalse(
            TransferAmountViewModel.requiresLeftoverWarning(
                crowdNodeBalance: 0,
                transferAmount: UInt64.max,
                minimumLeftover: 30_000,
                maxSendable: 0))
    }

    func testAmountExactlyAtLeftoverThresholdDoesNotRequireWarning() {
        XCTAssertFalse(
            TransferAmountViewModel.requiresLeftoverWarning(
                crowdNodeBalance: 1,
                transferAmount: 70_000,
                minimumLeftover: 30_000,
                maxSendable: 100_000))
    }

    func testAmountAboveLeftoverThresholdRequiresWarning() {
        XCTAssertTrue(
            TransferAmountViewModel.requiresLeftoverWarning(
                crowdNodeBalance: 1,
                transferAmount: 70_001,
                minimumLeftover: 30_000,
                maxSendable: 100_000))
    }

    func testMaxSendableBelowMinimumLeftoverRequiresWarning() {
        XCTAssertTrue(
            TransferAmountViewModel.requiresLeftoverWarning(
                crowdNodeBalance: 1,
                transferAmount: 0,
                minimumLeftover: 30_000,
                maxSendable: 29_999))
    }

    func testLargeTransferAmountDoesNotOverflow() {
        XCTAssertTrue(
            TransferAmountViewModel.requiresLeftoverWarning(
                crowdNodeBalance: 1,
                transferAmount: UInt64.max,
                minimumLeftover: 1,
                maxSendable: UInt64.max))
    }

    func testSyntheticSDKBalanceRefreshesDisplayedBalanceAndValidation() async {
        let walletState = SwiftDashSDKWalletState.shared
        walletState.clearAllState()

        let viewModel = TransferAmountViewModel()
        viewModel.switchDirection()
        let separator = Locale.current.decimalSeparator ?? "."
        viewModel.setInput("0\(separator)00001")
        XCTAssertFalse(viewModel.canContinue)

        let balanceExpectation = expectation(description: "SDK balance reaches Coinbase transfer UI")
        let cancellable = viewModel.$fromItem
            .filter { $0.dashBalance == 2_000 }
            .prefix(1)
            .sink { _ in balanceExpectation.fulfill() }

        walletState.applyBalance(WalletBalance(confirmed: 2_000))

        await fulfillment(of: [balanceExpectation], timeout: 2)
        XCTAssertTrue(viewModel.canContinue)
        withExtendedLifetime(cancellable) {}
        walletState.clearAllState()
    }

    func testClearAndReseedReplacePreviousWalletBalance() async {
        let walletState = SwiftDashSDKWalletState.shared
        walletState.clearAllState()

        let viewModel = TransferAmountViewModel()
        viewModel.switchDirection()

        await applyBalance(9_000, expecting: 9_000, in: viewModel, walletState: walletState)

        let clearExpectation = expectation(description: "Previous wallet balance clears")
        let clearCancellable = viewModel.$fromItem
            .filter { $0.dashBalance == 0 }
            .prefix(1)
            .sink { _ in clearExpectation.fulfill() }
        walletState.clearAllState()
        await fulfillment(of: [clearExpectation], timeout: 2)
        withExtendedLifetime(clearCancellable) {}

        await applyBalance(4_000, expecting: 4_000, in: viewModel, walletState: walletState)
        walletState.clearAllState()
    }

    private func applyBalance(
        _ confirmed: UInt64,
        expecting expectedBalance: Int64,
        in viewModel: TransferAmountViewModel,
        walletState: SwiftDashSDKWalletState
    ) async {
        let expectation = expectation(description: "Displayed balance becomes \(expectedBalance)")
        let cancellable = viewModel.$fromItem
            .filter { $0.dashBalance == expectedBalance }
            .prefix(1)
            .sink { _ in expectation.fulfill() }

        walletState.applyBalance(WalletBalance(confirmed: confirmed))

        await fulfillment(of: [expectation], timeout: 2)
        withExtendedLifetime(cancellable) {}
    }
}
