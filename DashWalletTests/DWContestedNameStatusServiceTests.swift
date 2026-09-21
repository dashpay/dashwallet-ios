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

    func testLegacyLookupFailureDoesNotBlockOtherBookmarks() async throws {
        let walletId = Data([0x91, 0x25])
        let key = "DWPendingContestedDPNSEntries.\(Network.testnet.persistenceScope).9125"
        UserDefaults.standard.set(["a": ["submitted": 100.0], "b": ["submitted": 100.0]], forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        do {
            try await service.rehydrateUnattributed(network: .testnet, walletId: walletId,
                owners: { label in
                    if label == "a" { throw NSError(domain: "test", code: 1) }
                    return [Data([2])]
                }, resolved: { _ in false })
            XCTFail("Expected the first lookup error")
        } catch { }
        XCTAssertEqual(service.unattributedLabels(for: .testnet, walletId: walletId), ["a"])
        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([2]), walletId: walletId), ["b"])
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

    private enum LookupFailure: Error { case offline }

    func testUpgradeBookmarkSurvivesFailureAndAmbiguityThenUsesUniqueOwner() async throws {
        let walletId = Data([0x91, 0x23])
        let key = "DWPendingContestedDPNSEntries.\(Network.testnet.persistenceScope).9123"
        let entries: [String: [String: Any]] = ["legacy": ["submitted": 100.0, "end": 200.0]]
        UserDefaults.standard.set(entries, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        do {
            try await service.rehydrateUnattributed(network: .testnet, walletId: walletId,
                owners: { _ in throw LookupFailure.offline }, resolved: { _ in XCTFail("Failed read"); return true })
            XCTFail("Expected lookup failure")
        } catch LookupFailure.offline {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertEqual(service.unattributedLabels(for: .testnet, walletId: walletId), ["legacy"])
        try await service.rehydrateUnattributed(network: .testnet, walletId: walletId,
            owners: { _ in [Data([1]), Data([2])] }, resolved: { _ in XCTFail("Ambiguous owner"); return true })
        XCTAssertEqual(service.unattributedLabels(for: .testnet, walletId: walletId), ["legacy"])
        try await service.rehydrateUnattributed(network: .testnet, walletId: walletId,
            owners: { _ in [Data([2])] }, resolved: { _ in false })
        XCTAssertTrue(service.unattributedLabels(for: .testnet, walletId: walletId).isEmpty)
        XCTAssertTrue(service.pendingLabels(for: .testnet, identityId: Data([1]), walletId: walletId).isEmpty)
        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([2]), walletId: walletId), ["legacy"])
        XCTAssertEqual(service.pendingVotingEndTime(label: "legacy", for: .testnet, walletId: walletId), Date(timeIntervalSince1970: 200))
    }

    func testResolvedLegacyBookmarkCanClearWithoutGuessingAnOwner() async throws {
        let walletId = Data([0x91, 0x24])
        let key = "DWPendingContestedDPNSEntries.\(Network.testnet.persistenceScope).9124"
        UserDefaults.standard.set(["legacy": ["submitted": 100.0, "end": 200.0]], forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        try await service.rehydrateUnattributed(network: .testnet, walletId: walletId,
            owners: { _ in [] }, resolved: { _ in false })
        XCTAssertEqual(service.unattributedLabels(for: .testnet, walletId: walletId), ["legacy"])
        try await service.rehydrateUnattributed(network: .testnet, walletId: walletId,
            owners: { _ in [] }, resolved: { _ in true })
        XCTAssertTrue(service.unattributedLabels(for: .testnet, walletId: walletId).isEmpty)
    }

}
