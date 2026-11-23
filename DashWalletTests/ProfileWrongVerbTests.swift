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

    func testAnUpdateWithNoProfileIsRetriedAsACreate() {
        // The SDK's own refusal, raised before anything is broadcast.
        let local = PlatformWalletError.unknown("SDK error: SDK error: No existing profile document found to update")

        XCTAssertTrue(DWProfileUpdateCoordinator.isWrongVerb(local, preferCreate: false))
        XCTAssertTrue(DWProfileUpdateCoordinator.isWrongVerb(rejection(40_101), preferCreate: false))
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
            PlatformWalletError.unknown("duplicate unique properties"),
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
