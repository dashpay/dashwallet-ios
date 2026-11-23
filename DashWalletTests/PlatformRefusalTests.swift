//
//  PlatformRefusalTests.swift
//  DashWalletTests
//

import SwiftDashSDK
import XCTest
@testable import dashpay

final class PlatformRefusalTests: XCTestCase {
    private func consensus(_ code: UInt32, _ kind: PlatformConsensusError.Kind = .state) -> PlatformConsensusError {
        PlatformConsensusError(code: code, kind: kind)
    }

    func testEveryCodeInTheTableMapsToItsCase() {
        let table: [(UInt32, PlatformRefusal)] = [
            (10_504, .assetLockOutPointConsumed),
            (40_101, .documentNotFound),
            (40_105, .duplicateUniqueIndex),
            (40_210, .identityBalanceTooLow),
            (40_300, .voterNotFound),
            (40_301, .votePollNotFound),
            (40_302, .votePollNotAvailable),
            (40_303, .votedTooManyTimes),
            (40_304, .voteAlreadyPresent),
            (40_305, .incorrectVotingAddress),
            (40_306, .incorrectVoterIdentityId),
            (40_601, .addressBalanceTooLow),
            (40_602, .addressBalanceTooLow)
        ]
        for (code, expected) in table {
            XCTAssertEqual(PlatformRefusal(code: code), expected, "\(code)")
        }
    }

    func testACodeOutsideTheTableKeepsItsNumberAndIsNoNamedCase() {
        for code: UInt32 in [10_000, 40_100, 40_106, 40_722, 49_999] {
            XCTAssertEqual(PlatformRefusal(code: code), .other(code: code))
        }
    }

    func testTheCodeIsReadFromEitherSDKErrorType() {
        XCTAssertEqual(
            PlatformRefusal.of(SDKError.consensusRejection(consensus(40_105), "rendered text")),
            .duplicateUniqueIndex)
        XCTAssertEqual(
            PlatformRefusal.of(PlatformWalletError.consensusRejection(consensus(40_105), "rendered text")),
            .duplicateUniqueIndex)
        XCTAssertEqual(
            PlatformRefusal.consensusError(in: SDKError.consensusRejection(consensus(10_504, .basic), "rendered text")),
            consensus(10_504, .basic))
    }

    func testAnErrorWithoutAConsensusCodeIsNoRefusalWhateverItsTextSays() {
        let text = "Asset lock transaction abc output 0 already completely used; duplicate unique properties"
        let errors: [Error] = [
            SDKError.internalError(text),
            SDKError.protocolError(text),
            SDKError.notFound(text),
            SDKError.unknown(text),
            SDKError.stateTransitionResultUnconfirmed(text),
            PlatformWalletError.unknown(text),
            PlatformWalletError.walletOperation(text),
            PlatformWalletError.assetLockAlreadyConsumed(text),
            URLError(.timedOut),
            CancellationError(),
            NSError(domain: "test", code: 40_105, userInfo: [NSLocalizedDescriptionKey: text])
        ]
        for error in errors {
            XCTAssertNil(PlatformRefusal.of(error), "\(error)")
            XCTAssertNil(PlatformRefusal.consensusError(in: error), "\(error)")
        }
    }
}
