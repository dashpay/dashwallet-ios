//
//  ProfileWrongVerbTests.swift
//  DashWalletTests
//

import SwiftDashSDK
import XCTest
@testable import dashpay

final class ProfileWrongVerbTests: XCTestCase {
    private func rejection(_ code: UInt32) -> PlatformWalletError {
        .consensusRejection(PlatformConsensusError(code: code, kind: .state), "reworded by Platform")
    }

    func testACreateRefusedForAnExistingProfileIsRetriedAsAnUpdate() {
        XCTAssertTrue(DWProfileUpdateCoordinator.isWrongVerb(rejection(40_105), preferCreate: true))
    }

    func testACreateRefusedWithoutACodeIsRetriedByItsText() {
        let undecoded = PlatformWalletError.unknown("Document abc has duplicate unique properties [\"$ownerId\"]")

        XCTAssertTrue(DWProfileUpdateCoordinator.isWrongVerb(undecoded, preferCreate: true))
        XCTAssertFalse(DWProfileUpdateCoordinator.isWrongVerb(undecoded, preferCreate: false))
        // A code that names another refusal wins over the text beside it.
        let other = PlatformWalletError.consensusRejection(
            PlatformConsensusError(code: 40_210, kind: .state), "duplicate unique")
        XCTAssertFalse(DWProfileUpdateCoordinator.isWrongVerb(other, preferCreate: true))
    }

    func testAnUpdateWithNoProfileIsRetriedAsACreate() {
        // The SDK's own refusal, raised before anything is broadcast.
        let local = PlatformWalletError.unknown("SDK error: SDK error: No existing profile document found to update")

        XCTAssertTrue(DWProfileUpdateCoordinator.isWrongVerb(local, preferCreate: false))
        XCTAssertTrue(DWProfileUpdateCoordinator.isWrongVerb(rejection(40_101), preferCreate: false))
        // A code that names another refusal wins over the text beside it.
        let other = PlatformWalletError.consensusRejection(
            PlatformConsensusError(code: 40_210, kind: .state), "No existing profile document found to update")
        XCTAssertFalse(DWProfileUpdateCoordinator.isWrongVerb(other, preferCreate: false))
    }

    func testTheRefusalOfOneVerbDoesNotFlipTheOther() {
        XCTAssertFalse(DWProfileUpdateCoordinator.isWrongVerb(rejection(40_105), preferCreate: false))
        XCTAssertFalse(DWProfileUpdateCoordinator.isWrongVerb(rejection(40_101), preferCreate: true))
        XCTAssertFalse(DWProfileUpdateCoordinator.isWrongVerb(
            PlatformWalletError.unknown("SDK error: SDK error: No existing profile document found to update"),
            preferCreate: true))
    }

    func testOtherFailuresAreNeverRetriedWithTheOppositeVerb() {
        let errors: [Error] = [
            PlatformWalletError.identityNotFound("Identity not found: abc"),
            PlatformWalletError.unknown("Wallet not found: abc"),
            rejection(40_210),
            SDKError.timeout("Timeout expired"),
            URLError(.notConnectedToInternet)
        ]
        for error in errors {
            XCTAssertFalse(DWProfileUpdateCoordinator.isWrongVerb(error, preferCreate: true), "\(error)")
            XCTAssertFalse(DWProfileUpdateCoordinator.isWrongVerb(error, preferCreate: false), "\(error)")
        }
    }
}
