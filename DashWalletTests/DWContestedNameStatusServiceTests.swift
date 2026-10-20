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

    /// Bookmarks are scoped to the wallet that made them, and the no-`walletId`
    /// accessors resolve the ACTIVE wallet — which a test host without a wallet
    /// (CI, a fresh simulator) does not have, so they answer nil by design. The
    /// tests therefore pin their own wallet scope explicitly.
    private let walletId = Data([0x77])

    override func setUp() {
        super.setUp()
        clearWalletScopedEntries()
        service.clearPending(for: .mainnet)
        service.clearPending(for: .testnet)
    }

    override func tearDown() {
        clearWalletScopedEntries()
        service.clearPending(for: .mainnet)
        service.clearPending(for: .testnet)
        super.tearDown()
    }

    private func clearWalletScopedEntries() {
        for network in [Network.mainnet, .testnet] {
            UserDefaults.standard.removeObject(
                forKey: "DWPendingContestedDPNSEntries.\(network.persistenceScope).77")
        }
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
            walletId: walletId,
            submittedAt: submittedAt)

        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([1]), walletId: walletId), ["beta"])
        XCTAssertEqual(
            service.pendingVotingEndTime(label: "beta", for: .testnet, walletId: walletId),
            submittedAt.addingTimeInterval(95 * 60))
    }

    func testPendingStateIsScopedByNetwork() {
        let submittedAt = Date(timeIntervalSince1970: 2_000_000)

        service.recordSubmission(
            label: "TestnetName",
            network: .testnet,
            identityId: Data([1]),
            walletId: walletId,
            submittedAt: submittedAt)

        XCTAssertTrue(service.pendingLabels(for: .mainnet, identityId: Data([1]), walletId: walletId).isEmpty)
        XCTAssertNil(service.pendingVotingEndTime(label: "testnetname", for: .mainnet, walletId: walletId))

        service.recordSubmission(
            label: "MainnetName",
            network: .mainnet,
            identityId: Data([1]),
            walletId: walletId,
            submittedAt: submittedAt)

        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([1]), walletId: walletId), ["testnetname"])
        XCTAssertEqual(service.pendingLabels(for: .mainnet, identityId: Data([1]), walletId: walletId), ["mainnetname"])
        XCTAssertEqual(
            service.pendingVotingEndTime(label: "mainnetname", for: .mainnet, walletId: walletId),
            submittedAt.addingTimeInterval((14 * 24 * 60 + 5) * 60))
    }

    func testAuthoritativeDeadlineReplacesFallback() {
        let submittedAt = Date(timeIntervalSince1970: 3_000_000)
        let authoritativeEnd = submittedAt.addingTimeInterval(42 * 60)
        service.recordSubmission(
            label: "Gamma",
            network: .testnet,
            identityId: Data([1]),
            walletId: walletId,
            submittedAt: submittedAt)

        service.recordVotingEndTime(authoritativeEnd, label: "Gamma", network: .testnet, walletId: walletId)

        XCTAssertEqual(
            service.pendingVotingEndTime(label: "gamma", for: .testnet, walletId: walletId),
            authoritativeEnd)
    }

    func testPendingContestDoesNotHideRecoveryForAnotherIdentity() {
        service.recordSubmission(label: "Alpha", network: .testnet, identityId: Data([1]), walletId: walletId)
        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([1]), walletId: walletId), ["alpha"])
        XCTAssertTrue(service.pendingLabels(for: .testnet, identityId: Data([2]), walletId: walletId).isEmpty)
        XCTAssertTrue(service.pendingLabels(for: .testnet, identityId: nil, walletId: walletId).isEmpty)
        service.recordSubmission(label: "Beta", network: .testnet, identityId: Data([2]), walletId: walletId)
        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([2]), walletId: walletId), ["beta"])
        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: Data([1]), walletId: walletId), ["alpha"])
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

    /// The app is killed after the pre-submission marker is written but before
    /// `registerDpnsName` returns. After the relaunch the marker still hides
    /// the name from owned names, but is no submission: it must not read as
    /// Voting, and outcome resolution must never see it.
    func testProvisionalMarkerFromEarlierLaunchIsNotASubmission() {
        let walletId = Data([0x91, 0x26])
        let key = "DWPendingContestedDPNSEntries.\(Network.testnet.persistenceScope).9126"
        let identity = Data([1])
        let launch = service.launchToken
        defer {
            service.launchToken = launch
            UserDefaults.standard.removeObject(forKey: key)
        }

        service.recordSubmission(
            label: "Alpha", network: .testnet, identityId: identity, walletId: walletId,
            promoteOnWin: true, provisional: true)
        // Same launch: the registration that wrote it is still running.
        XCTAssertEqual(service.pendingLabels(for: .testnet, identityId: identity, walletId: walletId), ["alpha"])
        XCTAssertTrue(service.pendingLabels(
            for: .testnet, identityId: identity, walletId: walletId, confirmedOnly: true).isEmpty)
        XCTAssertTrue(service.provisionalLabels(for: .testnet, identityId: identity, walletId: walletId).isEmpty)

        // Relaunch before the DPNS write returned.
        service.launchToken = UUID().uuidString
        XCTAssertTrue(service.pendingLabels(for: .testnet, identityId: identity, walletId: walletId).isEmpty,
                      "A marker from an earlier launch must not report the request as submitted")
        XCTAssertTrue(service.pendingLabels(
            for: .testnet, identityId: identity, walletId: walletId, confirmedOnly: true).isEmpty)
        XCTAssertEqual(service.provisionalLabels(for: .testnet, identityId: identity, walletId: walletId), ["alpha"],
                       "Still held for ownership filtering and reconciliation")
        XCTAssertTrue(service.provisionalLabels(for: .testnet, identityId: Data([2]), walletId: walletId).isEmpty)

        // Reconciliation found our contender: confirmed, deadline kept.
        let end = service.pendingVotingEndTime(label: "alpha", for: .testnet, walletId: walletId)
        service.recordSubmission(label: "alpha", network: .testnet, identityId: identity, walletId: walletId)
        XCTAssertEqual(service.pendingLabels(
            for: .testnet, identityId: identity, walletId: walletId, confirmedOnly: true), ["alpha"])
        XCTAssertTrue(service.provisionalLabels(for: .testnet, identityId: identity, walletId: walletId).isEmpty)
        XCTAssertEqual(service.pendingVotingEndTime(label: "alpha", for: .testnet, walletId: walletId), end)
    }

    func testProvisionalMarkerIsWithdrawnAndNeverDowngradesAConfirmedEntry() {
        let walletId = Data([0x91, 0x27])
        let key = "DWPendingContestedDPNSEntries.\(Network.testnet.persistenceScope).9127"
        let identity = Data([1])
        let launch = service.launchToken
        defer {
            service.launchToken = launch
            UserDefaults.standard.removeObject(forKey: key)
        }

        // Nothing was submitted: dropping the marker leaves no request behind.
        service.recordSubmission(
            label: "Beta", network: .testnet, identityId: identity, walletId: walletId, provisional: true)
        service.launchToken = UUID().uuidString
        service.clearPending(label: "beta", for: .testnet, walletId: walletId)
        XCTAssertTrue(service.provisionalLabels(for: .testnet, identityId: identity, walletId: walletId).isEmpty)
        XCTAssertTrue(service.pendingLabels(for: .testnet, identityId: identity, walletId: walletId).isEmpty)

        // A retry's marker over a confirmed request keeps it confirmed.
        service.recordSubmission(label: "Gamma", network: .testnet, identityId: identity, walletId: walletId)
        service.recordSubmission(
            label: "Gamma", network: .testnet, identityId: identity, walletId: walletId, provisional: true)
        service.launchToken = UUID().uuidString
        XCTAssertEqual(service.pendingLabels(
            for: .testnet, identityId: identity, walletId: walletId, confirmedOnly: true), ["gamma"])
        XCTAssertTrue(service.provisionalLabels(for: .testnet, identityId: identity, walletId: walletId).isEmpty)
    }

}
