//
//  VotingKeyImportTests.swift
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

import SwiftDashSDK
import XCTest
@testable import dashpay

// MARK: - Stand-ins

/// In-memory vault whose writes and reads can be made to fail per node.
private final class FakeVault: TrackedMasternodeKeyVaulting {
    var keys: [Data: [MasternodeKeyRole: String]] = [:]
    var failingStores: Set<Data> = []
    var removeSucceeds = true
    var presence: [MasternodeKeyRole: TrackedMasternodeKeyPresence] = [:]

    func key(for proTxHash: Data, role: MasternodeKeyRole) -> String? {
        keys[proTxHash]?[role]
    }

    func store(_ keyText: String, for proTxHash: Data, role: MasternodeKeyRole) -> Bool {
        guard !failingStores.contains(proTxHash) else { return false }
        keys[proTxHash, default: [:]][role] = keyText
        return true
    }

    func removeKey(for proTxHash: Data, role: MasternodeKeyRole) -> Bool {
        guard removeSucceeds else { return false }
        keys[proTxHash]?[role] = nil
        return true
    }

    func attachedRoles(for proTxHash: Data) -> Set<MasternodeKeyRole> {
        Set(keys[proTxHash]?.keys.map { $0 } ?? [])
    }

    func keyPresence(for proTxHash: Data, role: MasternodeKeyRole) -> TrackedMasternodeKeyPresence {
        presence[role] ?? .absent
    }

    func removeAllKeys(for proTxHash: Data) {
        keys[proTxHash] = nil
    }
}

@MainActor
private final class FakeTracker: VotingKeyMasternodeTracking {
    var located: [VotingKeyLocatedNode] = []
    private(set) var tracked: Set<Data> = []
    private(set) var untrackCalls: [Data] = []

    func locateVotingKeyNodes(_ key: String) async throws -> [VotingKeyLocatedNode] {
        located
    }

    func trackForVoting(proTxHash: Data) throws {
        tracked.insert(proTxHash)
    }

    func untrackForVoting(proTxHash: Data) {
        untrackCalls.append(proTxHash)
        tracked.remove(proTxHash)
    }
}

private func proTx(_ byte: UInt8) -> Data { Data(repeating: byte, count: 32) }

private func node(_ byte: UInt8, inWallet: Bool = false) -> VotingKeyLocatedNode {
    VotingKeyLocatedNode(
        proTxHash: proTx(byte),
        isVotingKeyMatch: true,
        isValid: true,
        isInLoadedWallet: inWallet,
        alreadyTracked: false)
}

// MARK: - Import

/// `VotingKeyInputViewModel.verifyAndAdd()` outcomes when some nodes the key
/// votes with cannot be added.
@MainActor
final class VotingKeyImportTests: XCTestCase {
    private var vault: FakeVault!
    private var tracker: FakeTracker!
    private var viewModel: VotingKeyInputViewModel!

    override func setUp() async throws {
        vault = FakeVault()
        tracker = FakeTracker()
        let tracker = tracker!
        viewModel = VotingKeyInputViewModel(
            vault: vault,
            tracker: { tracker },
            votableProTxHashes: { [] })
        viewModel.keyText = WalletEnvironment.network == .mainnet
            ? VotingKeyFormat.mainnetExample
            : VotingKeyFormat.testnetExample
    }

    func testAllExternalNodesAddedIsComplete() async {
        tracker.located = [node(1), node(2)]

        let outcome = await viewModel.verifyAndAdd()

        XCTAssertEqual(outcome, .added)
        XCTAssertEqual(tracker.tracked, [proTx(1), proTx(2)])
        XCTAssertEqual(vault.attachedRoles(for: proTx(2)), [.voting])
    }

    func testSecondNodeKeychainFailureKeepsFirstAndReportsPartial() async {
        tracker.located = [node(1), node(2)]
        vault.failingStores = [proTx(2)]

        let outcome = await viewModel.verifyAndAdd()

        guard case .partiallyAdded(let notice) = outcome else {
            return XCTFail("expected a partial outcome, got \(outcome)")
        }
        XCTAssertTrue(notice.contains("Added 1 of 2"), notice)
        XCTAssertTrue(notice.contains("keychain"), notice)
        // The first node is complete; the second was tracked by this attempt
        // and is rolled back.
        XCTAssertEqual(tracker.tracked, [proTx(1)])
        XCTAssertEqual(tracker.untrackCalls, [proTx(2)])
        XCTAssertEqual(vault.attachedRoles(for: proTx(1)), [.voting])
        XCTAssertTrue(vault.attachedRoles(for: proTx(2)).isEmpty)
        XCTAssertNil(viewModel.error)
    }

    func testFirstNodeFailureAddsNothing() async {
        tracker.located = [node(1), node(2)]
        vault.failingStores = [proTx(1)]

        let outcome = await viewModel.verifyAndAdd()

        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(tracker.tracked.isEmpty)
        XCTAssertNotNil(viewModel.error)
    }

    func testWalletOwnedMatchNextToExternalNodeIsNotAComplete() async {
        tracker.located = [node(1), node(2, inWallet: true)]

        let outcome = await viewModel.verifyAndAdd()

        guard case .partiallyAdded(let notice) = outcome else {
            return XCTFail("a skipped wallet-owned node must not read as complete, got \(outcome)")
        }
        XCTAssertTrue(notice.contains("registered to a wallet in this app"), notice)
        // Re-entering the key cannot add a wallet-owned node.
        XCTAssertFalse(notice.contains("Enter the key again"), notice)
        XCTAssertEqual(tracker.tracked, [proTx(1)])
        XCTAssertTrue(vault.attachedRoles(for: proTx(2)).isEmpty)
    }

    func testRetryCountExcludesWalletOwnedNodes() async {
        tracker.located = [node(1), node(2), node(3, inWallet: true)]
        vault.failingStores = [proTx(2)]

        let outcome = await viewModel.verifyAndAdd()

        guard case .partiallyAdded(let notice) = outcome else {
            return XCTFail("expected a partial outcome, got \(outcome)")
        }
        // "The rest" is only what a retry can add: node 2, not node 3.
        XCTAssertTrue(notice.contains("Added 1 of 2"), notice)
        XCTAssertTrue(notice.contains("registered to a wallet in this app"), notice)
    }

    func testOnlyWalletOwnedMatchesFail() async {
        tracker.located = [node(1, inWallet: true)]

        let outcome = await viewModel.verifyAndAdd()

        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(tracker.tracked.isEmpty)
        XCTAssertTrue(viewModel.error?.contains("registered to a wallet in this app") == true)
    }
}

// MARK: - Removal

/// `VotingViewModel.removeImportedVotingKey(for:)` untracks a node only once
/// every other key of it is confirmed gone.
@MainActor
final class VotingKeyRemovalTests: XCTestCase {
    private var vault: FakeVault!
    private var tracker: FakeTracker!
    private var viewModel: VotingViewModel!
    private let voter = VoterNode(
        proTxHash: proTx(7),
        isEvonode: false,
        typeIndex: 1,
        serviceAddress: nil,
        keySource: .trackedVault)

    override func setUp() async throws {
        vault = FakeVault()
        tracker = FakeTracker()
        let tracker = tracker!
        viewModel = VotingViewModel(vault: vault, tracker: { tracker })
        _ = vault.store("key", for: voter.proTxHash, role: .voting)
    }

    func testFailedDeleteChangesNothing() {
        vault.removeSucceeds = false

        XCTAssertNotNil(viewModel.removeImportedVotingKey(for: voter))
        XCTAssertEqual(vault.key(for: voter.proTxHash, role: .voting), "key")
        XCTAssertTrue(tracker.untrackCalls.isEmpty)
    }

    func testNodeHoldingAnotherKeyStaysTracked() {
        vault.presence = [.owner: .present]

        XCTAssertNil(viewModel.removeImportedVotingKey(for: voter))
        XCTAssertNil(vault.key(for: voter.proTxHash, role: .voting))
        XCTAssertTrue(tracker.untrackCalls.isEmpty)
    }

    func testUnreadableOtherKeyKeepsNodeTracked() {
        vault.presence = [.ownerPayout: .unknown]

        XCTAssertNil(viewModel.removeImportedVotingKey(for: voter))
        XCTAssertTrue(tracker.untrackCalls.isEmpty)
    }

    func testNodeWithNoOtherKeyIsUntracked() {
        XCTAssertNil(viewModel.removeImportedVotingKey(for: voter))
        XCTAssertEqual(tracker.untrackCalls, [voter.proTxHash])
    }

    func testWalletDerivedNodeIsLeftAlone() {
        let walletNode = VoterNode(
            proTxHash: proTx(8),
            isEvonode: false,
            typeIndex: 1,
            serviceAddress: nil,
            keySource: .walletIndex(0))

        XCTAssertNil(viewModel.removeImportedVotingKey(for: walletNode))
        XCTAssertTrue(tracker.untrackCalls.isEmpty)
    }
}
