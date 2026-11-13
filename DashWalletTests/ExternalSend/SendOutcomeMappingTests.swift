//
//  Created by Roman Chornyi
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

@testable import dashpay
import SwiftDashSDK
import XCTest

/// The seam-error -> outcome mapping behind the send result (AC-19, ADR-0040): Retry is offered only for a
/// failure proven to be before the money left the source; any doubt is `inFlight`.
final class SendOutcomeMappingTests: XCTestCase {
    private typealias SenderError = SwiftDashSDKTransactionSender.SendError
    private typealias CoordinatorError = ShieldedTransferCoordinator.CoordinatorError

    // MARK: - Fixtures

    // `WalletSendService` throws `NSError`s in this domain; its `ErrorCode` and `makeError` are file-private,
    // so the fixture builds the same value from the raw domain and code.
    private static let walletSendDomain = "org.dashfoundation.dash.wallet-send-service"

    private enum WalletSendCode: Int {
        case authenticationCancelled = 1
        case authenticationFailed = 2
        case alreadyBroadcast = 5
        case offline = 8
        case broadcastRejected = 9
        case broadcastUnknown = 10
    }

    private static let rawSdkText = "RAW-SDK-TEXT-7f3a"

    private func walletSend(_ code: WalletSendCode) -> NSError {
        NSError(domain: Self.walletSendDomain, code: code.rawValue,
                userInfo: [NSLocalizedDescriptionKey: Self.rawSdkText])
    }

    private func outcome(_ error: Error) -> SendOutcome {
        SendOutcome(error: error)
    }

    private func assertNotSent(_ error: Error, file: StaticString = #filePath, line: UInt = #line) -> NotSentReason? {
        guard case .notSent(let reason) = outcome(error) else {
            XCTFail("expected .notSent for \(error), got \(outcome(error))", file: file, line: line)
            return nil
        }
        return reason
    }

    private func assertInFlight(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard case .inFlight = outcome(error) else {
            XCTFail("expected .inFlight for \(error), got \(outcome(error))", file: file, line: line)
            return
        }
    }

    // MARK: - WalletSendService errors

    func testOfflineIsNotSentOffline() {
        guard case .offline? = assertNotSent(walletSend(.offline)) else {
            return XCTFail("expected reason .offline")
        }
    }

    func testBroadcastRejectedIsNotSentRejected() {
        guard case .rejected? = assertNotSent(walletSend(.broadcastRejected)) else {
            return XCTFail("expected reason .rejected")
        }
    }

    func testBroadcastUnknownIsInFlight() {
        assertInFlight(walletSend(.broadcastUnknown))
    }

    func testAlreadyBroadcastIsInFlight() {
        assertInFlight(walletSend(.alreadyBroadcast))
    }

    // MARK: - SwiftDashSDKTransactionSender.SendError

    func testSenderRejectedIsNotSentRejected() {
        let error = SenderError.transactionRejected(txid: "t", reason: Self.rawSdkText)
        guard case .rejected? = assertNotSent(error) else {
            return XCTFail("expected reason .rejected")
        }
    }

    func testSenderStatusUnknownIsInFlight() {
        assertInFlight(SenderError.transactionStatusUnknown(txid: "t", reason: Self.rawSdkText))
    }

    // MARK: - PlatformWalletError

    func testUnconfirmedBroadcastsAreInFlight() {
        assertInFlight(PlatformWalletError.transactionBroadcastUnconfirmed(Self.rawSdkText))
        assertInFlight(PlatformWalletError.shieldedSpendUnconfirmed(Self.rawSdkText))
        assertInFlight(PlatformWalletError.shieldedBroadcastUnconfirmed(Self.rawSdkText))
        assertInFlight(PlatformWalletError.masternodeWithdrawalUnconfirmed(Self.rawSdkText))
    }

    func testAssetLockAlreadyConsumedIsInFlight() {
        // The SDK documents it as not proving the operation did not complete.
        assertInFlight(PlatformWalletError.assetLockAlreadyConsumed(Self.rawSdkText))
    }

    // Core network rejection: PlatformWalletResult.swift:633 "Core definitively rejected the transaction and its
    // input reservation was released".
    func testCoreBroadcastRejectionIsNotSentRejected() {
        guard case .rejected? = assertNotSent(PlatformWalletError.transactionBroadcastRejected(Self.rawSdkText)) else {
            return XCTFail("expected reason .rejected")
        }
    }

    // Platform answered after the handover (relay/CheckTx or Platform's own execution error, platform
    // rs-platform-wallet-ffi/src/error.rs:137 and :185): a rejection there does not prove the credits stay.
    func testPlatformRejectionAfterHandoverIsInFlight() {
        assertInFlight(PlatformWalletError.shieldedBroadcastFailed(Self.rawSdkText))
        assertInFlight(PlatformWalletError.addressNonceMismatch(Self.rawSdkText))
    }

    // Auth precedes build and sign, so it is pre-broadcast; the executor filters cancel before mapping.
    func testAuthErrorsAreNotSentFailed() {
        let errors: [Error] = [
            walletSend(.authenticationCancelled), walletSend(.authenticationFailed),
            CoordinatorError.authCancelled, CoordinatorError.authFailed,
        ]
        for error in errors {
            guard case .failed? = assertNotSent(error) else {
                return XCTFail("expected reason .failed for \(error)")
            }
        }
    }

    func testSenderPreparationFailuresAreNotSent() {
        XCTAssertNotNil(assertNotSent(SenderError.walletNotReady(Self.rawSdkText)))
        XCTAssertNotNil(assertNotSent(SenderError.invalidInput(Self.rawSdkText)))
    }

    // After the asset lock is built (ShieldedTransferCoordinator.CoordinatorError drain cases).
    func testDrainRecipientErrorsAreInFlight() {
        assertInFlight(CoordinatorError.drainRecipientUnknown)
        assertInFlight(CoordinatorError.drainRecipientUnavailable)
    }

    func testTransferFailedMapsTheWrappedErrorRecursively() {
        let inner = PlatformWalletError.transactionBroadcastRejected(Self.rawSdkText)
        let rejected = CoordinatorError.transferFailed(inner)
        guard case .rejected? = assertNotSent(rejected) else {
            return XCTFail("expected reason .rejected")
        }
        assertInFlight(CoordinatorError.transferFailed(PlatformWalletError.shieldedBroadcastFailed(Self.rawSdkText)))
    }

    func testSigningKeyUnavailableIsNotSentSigningKeyUnavailable() {
        let error = PlatformWalletError.signingKeyUnavailable(Self.rawSdkText)
        guard case .signingKeyUnavailable? = assertNotSent(error) else {
            return XCTFail("expected reason .signingKeyUnavailable")
        }
    }

    func testRefusedBeforeNetworkIsNotSent() {
        XCTAssertNotNil(assertNotSent(PlatformWalletError.staleReservationToken(Self.rawSdkText)))
        XCTAssertNotNil(assertNotSent(PlatformWalletError.coreInsufficientFunds(Self.rawSdkText)))
        XCTAssertNotNil(assertNotSent(PlatformWalletError.shieldedNoRecordedAnchor(Self.rawSdkText)))
    }

    func testUnlistedPlatformWalletErrorIsInFlight() {
        assertInFlight(PlatformWalletError.walletOperation(Self.rawSdkText))
    }

    func testIdentityNotFoundIsNotSentIdentityNotFound() {
        guard case .identityNotFound? = assertNotSent(PlatformWalletError.identityNotFound(Self.rawSdkText)) else {
            return XCTFail("expected .identityNotFound")
        }
    }

    func testOtherRefusalsProvenBeforeSubmissionAreNotSentFailed() {
        guard case .failed? = assertNotSent(PlatformWalletError.invalidNetwork(Self.rawSdkText)) else {
            return XCTFail("expected .failed for invalidNetwork")
        }
        guard case .failed? = assertNotSent(PlatformWalletError.shieldedInsufficientBalance(Self.rawSdkText)) else {
            return XCTFail("expected .failed for shieldedInsufficientBalance")
        }
    }

    func testRefusalsNotProvenBeforeSubmissionStayInFlight() {
        assertInFlight(PlatformWalletError.invalidParameter(Self.rawSdkText))
        assertInFlight(PlatformWalletError.invalidIdentifier(Self.rawSdkText))
        assertInFlight(PlatformWalletError.identityBalanceUnavailable(Self.rawSdkText))
        // The Rust `IdentityNotFound` reaches Swift as `.unknown` at the pin; on the Core -> Identity top-up it can
        // follow the asset-lock broadcast.
        assertInFlight(PlatformWalletError.unknown("Identity not found: \(Self.rawSdkText)"))
    }

    // MARK: - ShieldedTransferCoordinator.CoordinatorError

    func testShieldedSweepWaitingIsNotSentEarlierPaymentPending() {
        guard case .earlierPaymentPending? = assertNotSent(CoordinatorError.shieldedSweepWaiting(1000)) else {
            return XCTFail("expected reason .earlierPaymentPending")
        }
    }

    func testCoordinatorPreflightFailuresAreNotSent() {
        let errors: [CoordinatorError] = [
            .noWallet, .noShieldedAddress, .shieldedBalanceUnavailable,
            .platformShieldCapacityChanged(maxShieldableCredits: nil), .coinJoinDrainRequiresSync,
        ]
        for error in errors {
            XCTAssertNotNil(assertNotSent(error), "\(error)")
        }
    }

    // Thrown by `performAssetLock` / `performFundPlatform` before any asset lock is built
    // (ShieldedTransferCoordinator.swift: noManager :1747, noNetwork :1753, noModelContainer :1756 in
    // `resolveBasicEnvironment`, which both call before authorizing; shieldedPoolFeeUnavailable :713 before
    // authorizing and :766 before the SDK call; addressFundingFeeUnavailable :1428 before authorizing; walletReloading
    // when `beginFundingCall` is refused, before authorizing).
    func testErrorsThrownBeforeTheAssetLockIsBuiltAreNotSentFailed() {
        let errors: [CoordinatorError] = [
            .noManager, .noNetwork, .noModelContainer, .shieldedPoolFeeUnavailable, .addressFundingFeeUnavailable,
            .walletReloading,
        ]
        for error in errors {
            guard case .failed? = assertNotSent(error) else {
                XCTFail("expected reason .failed for \(error)")
                continue
            }
        }
    }

    // Thrown by the Shielded/Platform-source `perform*` calls before `authorize()` and before the phase advances to
    // proving/broadcasting (ShieldedTransferCoordinator.swift: noReceiveAddress :1252 and :1579, noPlatformAddress
    // :1357, shieldedSweepChanged :1231 :1337 :1647, shieldedAmountExceedsBundle :525
    // from `rejectIfAboveSpendCeiling`).
    func testShieldedAndPlatformSourceErrorsBeforeAuthorizeAreNotSentFailed() {
        let errors: [CoordinatorError] = [
            .noReceiveAddress, .noPlatformAddress, .shieldedSweepChanged, .shieldedAmountExceedsBundle(1_000),
        ]
        for error in errors {
            guard case .failed? = assertNotSent(error) else {
                XCTFail("expected reason .failed for \(error)")
                continue
            }
        }
    }

    // `highestBalanceRow` (PlatformAddressSyncCoordinator.swift:742, called by `transfer` and `withdrawAllToCore`
    // before the signer or the SDK call) and `withdrawToCore` (:863, before `addressWallet.withdraw`) throw
    // `noFundedAddress` before anything is signed or submitted. `mnemonicUnavailable` and `keyDecodeFailed` are
    // declared (:2011) but thrown nowhere in the app sources, so they stay `inFlight`.
    func testNoFundedPlatformAddressIsNotSentFailed() {
        guard case .failed? = assertNotSent(PlatformAddressSyncCoordinator.SendError.noFundedAddress) else {
            return XCTFail("expected reason .failed")
        }
        assertInFlight(PlatformAddressSyncCoordinator.SendError.mnemonicUnavailable)
        assertInFlight(PlatformAddressSyncCoordinator.SendError.keyDecodeFailed("x"))
    }

    // `AssetLockInputLimit.requireFits` refuses before authorizing and before any lock
    // (ShieldedTransferCoordinator.swift :733 and :1437); the error says nothing was broadcast.
    func testTooManyInputsRefusalIsNotSentFailed() {
        let check = AssetLockInputLimit.Check(
            amountDuffs: 1_000_000, inputBudget: AssetLockInputPolicy.platformInputBudget)
        guard case .failed? = assertNotSent(AssetLockInputLimit.TooManyInputsError(check: check)) else {
            return XCTFail("expected reason .failed")
        }
    }

    // `BIP70PaymentService` throws `.expired` before it claims, POSTs or broadcasts anything.
    func testExpiredPaymentRequestIsNotSentExpiredWithAMessage() throws {
        let reason = try XCTUnwrap(assertNotSent(BIP70Error.expired))

        XCTAssertEqual(reason.category, "expired")
        XCTAssertFalse(reason.localizedMessage.isEmpty)
    }

    func testTransferFailedWrappingUnconfirmedIsInFlight() {
        assertInFlight(CoordinatorError.transferFailed(PlatformWalletError.shieldedSpendUnconfirmed(Self.rawSdkText)))
    }

    // MARK: - Unknown errors

    func testUnknownErrorIsInFlight() {
        struct Unlisted: Error {}
        assertInFlight(Unlisted())
        assertInFlight(NSError(domain: "unlisted.domain", code: 42))
        assertInFlight(NSError(domain: Self.walletSendDomain, code: 9999))
    }

    func testTransferFailedWrappingUnknownIsInFlight() {
        struct Unlisted: Error {}
        assertInFlight(CoordinatorError.transferFailed(Unlisted()))
    }

    // MARK: - Localized text

    func testEveryNotSentReasonHasLocalizedTextWithoutRawSdkText() {
        let errors: [Error] = [
            walletSend(.offline), walletSend(.broadcastRejected),
            PlatformWalletError.transactionBroadcastRejected(Self.rawSdkText),
            PlatformWalletError.signingKeyUnavailable(Self.rawSdkText),
            CoordinatorError.shieldedSweepWaiting(1000),
            PlatformWalletError.coreInsufficientFunds(Self.rawSdkText),
            PlatformWalletError.identityNotFound(Self.rawSdkText),
        ]
        for error in errors {
            guard let reason = assertNotSent(error) else { continue }
            XCTAssertFalse(reason.localizedMessage.isEmpty, "\(error)")
            XCTAssertFalse(reason.localizedMessage.contains(Self.rawSdkText), "raw SDK text leaked for \(error)")
        }
    }

    func testMinimumAmountRefusalIsNotSentBelowMinimumWithAMessage() throws {
        let reason = try XCTUnwrap(assertNotSent(MinimumAmountRefusal(minimumCredits: 1_000_000)))

        XCTAssertEqual(reason.category, "belowMinimum")
        XCTAssertFalse(reason.localizedMessage.isEmpty)
    }
}
