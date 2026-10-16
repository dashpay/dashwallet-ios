//
//  CoinbaseTransferAmountTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//

import Combine
import XCTest
@testable import dashpay

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

    /// A hardware Return during a pending wallet broadcast must not start a
    /// second transfer: the window HUD blocks touches only, so the keypad's
    /// own `inProgress` (`isProcessing`) is what turns the keyboard's input and
    /// Return off, and the host refuses a transfer that would replace the
    /// controller still waiting for the first one's outcome.
    func testAWalletTransferKeepsTheKeypadOffAndRefusesASecondUntilItsOutcome() throws {
        let viewModel = TransferAmountViewModel()
        let host = TransferAmountHostingController(viewModel: viewModel)
        host.loadViewIfNeeded()
        let processor = DWPaymentProcessor()
        // Processing an empty input does nothing: the send is driven by hand.
        let input = DWPaymentInputBuilder().emptyPaymentInput(with: .plainAddress)

        viewModel.initiatePayment(with: input)
        let first = try XCTUnwrap(host.paymentController)
        XCTAssertTrue(host.isWalletPaymentInFlight)
        XCTAssertEqual(first.sendInProgressHandler?(true), false, "the window HUD still shows the wait")
        XCTAssertTrue(viewModel.isProcessing, "keypad input and Return are off during the broadcast")

        viewModel.initiatePayment(with: input)
        XCTAssertTrue(host.paymentController === first, "a second transfer must not replace the waiting one")
        XCTAssertTrue(viewModel.isProcessing)

        _ = first.sendInProgressHandler?(false)
        XCTAssertTrue(viewModel.isProcessing, "the wait is over, but its outcome is not shown yet")

        // A failure with no error ("Not a valid Dash address", failed
        // authentication) shows nothing, and still ends the payment.
        first.paymentProcessor(processor, didFailWithError: nil, title: nil, message: nil)
        XCTAssertFalse(host.isWalletPaymentInFlight)
        XCTAssertFalse(viewModel.isProcessing, "the outcome is in: the keypad takes input again")

        viewModel.initiatePayment(with: input)
        let second = try XCTUnwrap(host.paymentController)
        XCTAssertFalse(second === first, "the next transfer gets a fresh controller")
        first.paymentProcessorDidCancelTransactionSigning(processor)
        XCTAssertTrue(host.isWalletPaymentInFlight, "a late callback from the ended controller changes nothing")
        second.paymentProcessorDidCancelTransactionSigning(processor)
        XCTAssertFalse(host.isWalletPaymentInFlight, "a cancelled PIN prompt ends it")
    }

    func testATransferWithNoHostToHandItToEndsItsProcessing() {
        let viewModel = TransferAmountViewModel()
        viewModel.walletPaymentDidStart()
        viewModel.initiatePayment(with: DWPaymentInputBuilder().emptyPaymentInput(with: .plainAddress))
        XCTAssertFalse(viewModel.isProcessing)
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
