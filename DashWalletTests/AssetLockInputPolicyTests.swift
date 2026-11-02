//
//  AssetLockInputPolicyTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
@testable import dashpay
import SwiftDashSDK

/// Pins the pre-check every Core-funded asset-lock route runs before building
/// a lock: an asset lock over 100 inputs is dropped by Dash Core and refused
/// by Platform (dashpay/platform#5513), so a lock the coins could only cover
/// with more inputs than the route's budget must be refused before anything
/// is built — and the SDK's own refusal must reach the same sheet.
final class AssetLockInputPolicyTests: XCTestCase {

    private typealias Policy = AssetLockInputPolicy

    /// Coin size well above the per-input fee step, so the input count a
    /// lock needs is set by the amount alone.
    private let coin: UInt64 = 10_000

    /// The lock amount that `inputs` coins of `coin` cover exactly, fee
    /// included — so `inputs - 1` coins fall short.
    private func amountNeeding(inputs: Int) -> UInt64 {
        UInt64(inputs) * coin - Policy.estimatedFeeDuffs(inputCount: inputs)
    }

    private func coins(_ count: Int) -> [UInt64] {
        Array(repeating: coin, count: count)
    }

    // MARK: - Budgets

    func testBudgetsMatchTheNetworkCapAndTheShieldThreshold() {
        XCTAssertEqual(Policy.platformInputBudget, 100)
        XCTAssertEqual(Policy.shieldInputBudget, 50)
    }

    // MARK: - Input count against the budget

    func testHundredInputsFitAndHundredAndOneDoNotAtTheNetworkCap() {
        XCTAssertEqual(
            Policy.verdict(utxoValues: coins(150), amountDuffs: amountNeeding(inputs: 100), inputBudget: 100),
            .fits)
        XCTAssertEqual(
            Policy.verdict(utxoValues: coins(150), amountDuffs: amountNeeding(inputs: 101), inputBudget: 100),
            .needsConsolidation)
    }

    func testFiftyInputsFitAndFiftyOneDoNotAtTheShieldBudget() {
        XCTAssertEqual(
            Policy.verdict(utxoValues: coins(150), amountDuffs: amountNeeding(inputs: 50), inputBudget: 50),
            .fits)
        XCTAssertEqual(
            Policy.verdict(utxoValues: coins(150), amountDuffs: amountNeeding(inputs: 51), inputBudget: 50),
            .needsConsolidation)
    }

    func testHundredAndOneCoinsOverTheCapAreFineWhenFewerCoverTheAmount() {
        // Only the coins the selection takes count, not the coins held.
        XCTAssertEqual(
            Policy.verdict(utxoValues: coins(101), amountDuffs: amountNeeding(inputs: 10), inputBudget: 100),
            .fits)
    }

    // MARK: - Largest first

    func testAFewLargeCoinsCoverTheAmountAheadOfManySmallOnes() {
        let values = Array(repeating: UInt64(1_000), count: 500) + [100_000_000, 100_000_000, 100_000_000]
        XCTAssertEqual(
            Policy.verdict(utxoValues: values.shuffled(), amountDuffs: 250_000_000, inputBudget: 100),
            .fits)
    }

    func testManySmallCoinsBehindOneLargeOneStillCountWhenNeeded() {
        // The large coin goes first, and the rest of the amount takes 150
        // small ones.
        let values = [50_000_000] + coins(200)
        let amount: UInt64 = 50_000_000 + 150 * coin - Policy.estimatedFeeDuffs(inputCount: 151)
        XCTAssertEqual(
            Policy.verdict(utxoValues: values, amountDuffs: amount, inputBudget: 100),
            .needsConsolidation)
    }

    // MARK: - Fee

    func testTheFeePushesABorderlineAmountOverTheBudget() {
        // 100 coins hold the amount exactly, but not the fee on top of it.
        let amount = 100 * coin
        XCTAssertEqual(
            Policy.verdict(utxoValues: coins(100), amountDuffs: amount, inputBudget: 100),
            .insufficientFunds)
        XCTAssertEqual(
            Policy.verdict(utxoValues: coins(150), amountDuffs: amount, inputBudget: 100),
            .needsConsolidation)
    }

    func testFeeGrowsWithEachInput() {
        XCTAssertGreaterThan(Policy.estimatedFeeDuffs(inputCount: 101), Policy.estimatedFeeDuffs(inputCount: 100))
        XCTAssertGreaterThan(
            Policy.estimatedFeeDuffs(inputCount: 1),
            SwiftDashSDKTransactionSender.estimatedSignalFee(inputCount: 1))
    }

    // MARK: - Insufficient funds

    func testCoinsThatCannotCoverTheLockAreLeftToTheSDK() {
        XCTAssertEqual(
            Policy.verdict(utxoValues: coins(10), amountDuffs: 10 * coin, inputBudget: 100),
            .insufficientFunds)
        XCTAssertEqual(
            Policy.verdict(utxoValues: [], amountDuffs: 1, inputBudget: 100),
            .insufficientFunds)
    }

    func testAnAmountThatOverflowsWithTheFeeIsInsufficient() {
        XCTAssertEqual(
            Policy.verdict(utxoValues: [UInt64.max], amountDuffs: UInt64.max, inputBudget: 100),
            .insufficientFunds)
    }

    // MARK: - Whole-balance drain

    func testADrainCountsEveryFinalCoin() {
        XCTAssertEqual(Policy.drainVerdict(finalCount: 100, inputBudget: 100), .fits)
        XCTAssertEqual(Policy.drainVerdict(finalCount: 101, inputBudget: 100), .needsConsolidation)
        XCTAssertEqual(Policy.drainVerdict(finalCount: 0, inputBudget: 100), .insufficientFunds)
    }

    // MARK: - The SDK's refusal

    private typealias Limit = AssetLockInputLimit

    private let check = AssetLockInputLimit.Check(amountDuffs: 1_000_000, inputBudget: 100)

    func testTheSDKRefusalIsFFICodeSixty() {
        XCTAssertEqual(PlatformWalletResultCode.errorAssetLockTooManyInputs.rawValue, 60)
        XCTAssertTrue(Limit.isTooManyInputs(PlatformWalletError.assetLockTooManyInputs("121 inputs, max 100")))
    }

    func testOtherAssetLockErrorsAreNotTheInputLimit() {
        XCTAssertFalse(Limit.isTooManyInputs(PlatformWalletError.assetLockInsufficientFunds("short")))
        XCTAssertFalse(Limit.isTooManyInputs(PlatformWalletError.noSelectableInputs("none")))
        XCTAssertFalse(Limit.isTooManyInputs(
            ShieldedTransferCoordinator.CoordinatorError.transferFailed(PlatformWalletError.coreInsufficientFunds("short"))))
        XCTAssertNil(Limit.check(for: PlatformWalletError.assetLockInsufficientFunds("short")))
    }

    func testTheRefusalIsRecognisedThroughTheCoordinatorsWrappers() {
        let sdk = PlatformWalletError.assetLockTooManyInputs("121 inputs, max 100")
        XCTAssertTrue(Limit.isTooManyInputs(ShieldedTransferCoordinator.CoordinatorError.transferFailed(sdk)))
        XCTAssertTrue(Limit.isTooManyInputs(DWIdentityRegistrationCoordinator.CoordinatorError.identityRegistration(sdk)))
        XCTAssertTrue(Limit.isTooManyInputs(DWIdentityRegistrationCoordinator.CoordinatorError.identityTopUp(sdk)))
        XCTAssertTrue(Limit.isTooManyInputs(DWIdentityRegistrationCoordinator.CoordinatorError.purchase(sdk)))
        XCTAssertFalse(Limit.isTooManyInputs(DWIdentityRegistrationCoordinator.CoordinatorError.dpnsRegistration(sdk)))
    }

    func testTheRefusalSurvivesTheRegistrationBridge() {
        // `DWIdentityRegistrationBridge` hands the create screen an NSError.
        let bridged = DWIdentityRegistrationCoordinator.CoordinatorError.identityRegistration(
            Limit.TooManyInputsError(check: check)) as NSError
        XCTAssertEqual(Limit.check(for: bridged), check)
        XCTAssertEqual(bridged.localizedDescription, Limit.message)
    }

    func testARefusalCarriesTheLockToRecheck() {
        let wrapped = ShieldedTransferCoordinator.CoordinatorError.transferFailed(Limit.TooManyInputsError(check: check))
        XCTAssertEqual(Limit.check(for: wrapped), check)
        // An SDK refusal no route mapped re-checks as a drain within the cap.
        XCTAssertEqual(
            Limit.check(for: PlatformWalletError.assetLockTooManyInputs("x")),
            .drain(inputBudget: Policy.platformInputBudget))
    }

    func testTheRefusalReadsAsTheSharedMessage() {
        XCTAssertEqual(Limit.TooManyInputsError(check: check).localizedDescription, Limit.message)
        XCTAssertEqual(
            DWIdentityRegistrationCoordinator.CoordinatorError
                .identityTopUp(Limit.TooManyInputsError(check: check)).localizedDescription,
            Limit.message)
        XCTAssertEqual(Limit.userMessage(for: PlatformWalletError.assetLockTooManyInputs("x")), Limit.message)
    }

    func testMappingRefusalTurnsTheSDKErrorIntoTheCarriedCheck() async {
        do {
            _ = try await Limit.mappingRefusal(check) { () async throws -> Int in
                throw PlatformWalletError.assetLockTooManyInputs("x")
            }
            XCTFail("expected the refusal")
        } catch {
            XCTAssertEqual((error as? Limit.TooManyInputsError)?.check, check)
        }
        do {
            _ = try await Limit.mappingRefusal(check) { () async throws -> Int in
                throw PlatformWalletError.assetLockInsufficientFunds("short")
            }
            XCTFail("expected the error")
        } catch {
            XCTAssertFalse(error is Limit.TooManyInputsError)
        }
    }
}
