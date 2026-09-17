//
//  DWContestedNameStatusServiceTests.swift
//  DashWalletTests
//
//  Regression coverage for pending contested-name recovery when Platform
//  has not indexed the vote state before the app is closed.
//

import SwiftDashSDK
import XCTest
@testable import dashpay

@MainActor
final class DWContestedNameStatusServiceTests: XCTestCase {

    private let service = DWContestedNameStatusService.shared

    override func setUp() {
        super.setUp()
        service.clearPending(for: .mainnet)
        service.clearPending(for: .testnet)
    }

    override func tearDown() {
        service.clearPending(for: .mainnet)
        service.clearPending(for: .testnet)
        super.tearDown()
    }

    func testSubmissionPersistsConservativeTestnetDeadlineImmediately() {
        let submittedAt = Date(timeIntervalSince1970: 1_000_000)

        service.recordSubmission(
            label: "Beta",
            network: .testnet,
            identityId: Data([1]),
            submittedAt: submittedAt)

        XCTAssertEqual(service.pendingLabel(for: .testnet), "beta")
        XCTAssertEqual(
            service.pendingVotingEndTime(for: .testnet),
            submittedAt.addingTimeInterval(95 * 60))
    }

    func testPendingStateIsScopedByNetwork() {
        let submittedAt = Date(timeIntervalSince1970: 2_000_000)

        service.recordSubmission(
            label: "TestnetName",
            network: .testnet,
            identityId: Data([1]),
            submittedAt: submittedAt)

        XCTAssertNil(service.pendingLabel(for: .mainnet))
        XCTAssertNil(service.pendingVotingEndTime(for: .mainnet))

        service.recordSubmission(
            label: "MainnetName",
            network: .mainnet,
            identityId: Data([1]),
            submittedAt: submittedAt)

        XCTAssertEqual(service.pendingLabel(for: .testnet), "testnetname")
        XCTAssertEqual(service.pendingLabel(for: .mainnet), "mainnetname")
        XCTAssertEqual(
            service.pendingVotingEndTime(for: .mainnet),
            submittedAt.addingTimeInterval((14 * 24 * 60 + 5) * 60))
    }

    func testAuthoritativeDeadlineReplacesFallback() {
        let submittedAt = Date(timeIntervalSince1970: 3_000_000)
        let authoritativeEnd = submittedAt.addingTimeInterval(42 * 60)
        service.recordSubmission(
            label: "Gamma",
            network: .testnet,
            identityId: Data([1]),
            submittedAt: submittedAt)

        service.recordVotingEndTime(authoritativeEnd, label: "Gamma", network: .testnet)

        XCTAssertEqual(
            service.pendingVotingEndTime(for: .testnet),
            authoritativeEnd)
    }
    func testPendingContestDoesNotHideRecoveryForAnotherIdentity() {
        service.recordSubmission(label: "Alpha", network: .testnet, identityId: Data([1]))
        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([1])), ["alpha"])
        XCTAssertTrue(service.pendingLabels(for: .testnet, identityId: Data([2])).isEmpty)
        XCTAssertTrue(service.pendingLabels(for: .testnet, identityId: nil).isEmpty)
        service.recordSubmission(label: "Beta", network: .testnet, identityId: Data([2]))
        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([2])), ["beta"])
        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([1])), ["alpha"])
    }

}
