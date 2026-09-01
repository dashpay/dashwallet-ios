//
//  MasternodeVoteCaster.swift
//  DashWallet
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

import Foundation
import OSLog
import SwiftDashSDK

// MARK: - VoteChoice

/// What a masternode is voting for on a contested username.
///
/// Mirrors `SwiftDashSDK.ContestedResourceVoteChoice`; kept as an app-level
/// type so the UI and the local vote history can carry it without importing
/// FFI shapes into view code.
enum VoteChoice: Hashable {
    /// Award the name to this contender (base58 identity id).
    case towards(identityId: String)
    /// Take no side; still counts as this node having voted.
    case abstain
    /// Nobody should get the name.
    case lock

    var sdkChoice: ContestedResourceVoteChoice {
        switch self {
        case .towards(let identityId): return .towardsIdentity(identityId)
        case .abstain: return .abstain
        case .lock: return .lock
        }
    }

    var displayName: String {
        switch self {
        case .towards: return NSLocalizedString("Approve", comment: "Voting")
        case .abstain: return NSLocalizedString("Abstain", comment: "Voting")
        case .lock: return NSLocalizedString("Lock", comment: "Voting")
        }
    }

    /// Kind only, never the contender id. `String(describing:)` on this enum
    /// would expand `.towards` to include the base58 identity, and the voting
    /// log lines are `.public` — that would write a specific voter's choice of
    /// candidate into the device log in clear text.
    var logDescription: String {
        switch self {
        case .towards: return "towards"
        case .abstain: return "abstain"
        case .lock: return "lock"
        }
    }
}

// MARK: - VoteOutcome

/// Per-node result of a casting run. One node failing never cancels the rest,
/// so a partial run is reported as a partial run rather than as an error.
struct VoteOutcome: Identifiable {
    let node: VoterNode
    /// `nil` on success; the Platform or local error message otherwise.
    let failure: String?

    var id: Data { node.proTxHash }
    var succeeded: Bool { failure == nil }
}

/// Aggregate result of casting one choice with a set of nodes.
struct VoteCastReport {
    let normalizedLabel: String
    let choice: VoteChoice
    let outcomes: [VoteOutcome]

    var succeeded: [VoteOutcome] { outcomes.filter(\.succeeded) }
    var failed: [VoteOutcome] { outcomes.filter { !$0.succeeded } }
    /// Platform voting weight that was actually accepted.
    var acceptedWeight: UInt32 { succeeded.map(\.node).totalVoteWeight }
    var isCompleteSuccess: Bool { !outcomes.isEmpty && failed.isEmpty }
}

// MARK: - MasternodeVoteCaster

/// Signs and broadcasts contested-username votes with the wallet's own
/// masternodes.
///
/// The transition assembly, voter-identity derivation, nonce fetch, signing
/// and broadcast all happen inside the SDK's
/// `castContestedResourceVote`. This type owns only what is app-side:
/// authenticating the user before key material is derived, pre-flighting the
/// poll, fanning out across nodes, and reporting what actually landed.
@MainActor
final class MasternodeVoteCaster {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.voting")

    private static let history: VoteHistoryDAO = VoteHistoryDAOImpl.shared

    /// Vote history is per Platform network — a testnet contest and a mainnet
    /// one can share a label, and their counts must never merge.
    static var networkKey: String {
        // Same "mainnet"/"testnet" strings as before; devnet contests are
        // recorded under their own key.
        WalletEnvironment.network?.networkName ?? "mainnet"
    }

    private let registry: MasternodeVoterRegistry
    private let contests: ContestedNamesService

    init(registry: MasternodeVoterRegistry, contests: ContestedNamesService) {
        self.registry = registry
        self.contests = contests
    }

    enum CastError: LocalizedError {
        case authenticationFailed
        case authenticationCancelled
        case noNodesSelected
        case contestClosed(String)
        case sdkUnavailable

        var errorDescription: String? {
            switch self {
            case .authenticationFailed:
                return NSLocalizedString("Authentication failed. Your vote was not cast.", comment: "Voting")
            case .authenticationCancelled:
                return NSLocalizedString("Authentication cancelled. Your vote was not cast.", comment: "Voting")
            case .noNodesSelected:
                return NSLocalizedString("Select at least one masternode to vote with.", comment: "Voting")
            case .contestClosed(let label):
                return String(format: NSLocalizedString(
                    "Voting on “%@” has already closed. Refresh to see the result.",
                    comment: "Voting"), label)
            case .sdkUnavailable:
                return NSLocalizedString(
                    "Dash Platform is not connected yet. Wait for syncing to finish and try again.",
                    comment: "Voting")
            }
        }
    }

    /// Cast `choice` on `normalizedLabel` with each node in `nodes`.
    ///
    /// Prompts for PIN/biometric once, then hands off to
    /// ``castAuthenticated(choice:onNormalizedLabel:with:sdk:)``.
    ///
    /// - Throws: ``CastError`` when the run cannot start at all (auth refused,
    ///   poll already closed). Once broadcasting starts, per-node failures are
    ///   returned in the report instead of thrown — a node that fails must not
    ///   discard the nodes that succeeded.
    func cast(
        choice: VoteChoice,
        onNormalizedLabel normalizedLabel: String,
        with nodes: [VoterNode]
    ) async throws -> VoteCastReport {
        guard !nodes.isEmpty else { throw CastError.noNodesSelected }
        guard let sdk = SwiftDashSDKHost.shared.sdk else { throw CastError.sdkUnavailable }

        // Pre-flight: a closed poll otherwise fails only after a long
        // broadcast retry, with an error that says nothing useful.
        guard try await contests.contestIsOpen(normalizedLabel: normalizedLabel) else {
            throw CastError.contestClosed(normalizedLabel)
        }

        switch await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled) {
        case .ok:
            break
        case .cancelled:
            throw CastError.authenticationCancelled
        case .failed, .timedOut:
            throw CastError.authenticationFailed
        }

        return await castAuthenticated(
            choice: choice, onNormalizedLabel: normalizedLabel, with: nodes, sdk: sdk)
    }

    /// The per-node broadcast loop, after authentication and pre-flight.
    ///
    /// Nodes are processed **serially**: the SDK fetches an identity nonce for
    /// the voter identity on every broadcast, and two concurrent votes from
    /// the same node would race on it. Never throws — a node that fails is
    /// recorded and the loop continues, so one failure cannot discard the
    /// nodes that already succeeded.
    private func castAuthenticated(
        choice: VoteChoice,
        onNormalizedLabel normalizedLabel: String,
        with nodes: [VoterNode],
        sdk: SDK
    ) async -> VoteCastReport {
        let indexValues = DPNSVotePoll.indexValues(normalizedLabel: normalizedLabel)
        var outcomes: [VoteOutcome] = []
        outcomes.reserveCapacity(nodes.count)

        for node in nodes {
            guard let votingKey = registry.votingPrivateKey(for: node) else {
                outcomes.append(VoteOutcome(
                    node: node,
                    failure: NSLocalizedString(
                        "This wallet could not derive the voting key for this node.",
                        comment: "Voting")))
                continue
            }

            do {
                try await sdk.castContestedResourceVote(
                    dataContractId: DPNSVotePoll.contractId,
                    documentTypeName: DPNSVotePoll.documentTypeName,
                    indexName: DPNSVotePoll.indexName,
                    indexValues: indexValues,
                    choice: choice.sdkChoice,
                    proTxHash: node.proTxHash,
                    votingPrivateKey: votingKey)
                outcomes.append(VoteOutcome(node: node, failure: nil))
                // Recorded only on success, so the count the UI shows is
                // votes Platform accepted — not votes attempted.
                await Self.history.record(
                    CastVoteRecord(
                        proTxHash: node.proTxHash,
                        normalizedLabel: normalizedLabel,
                        choice: choice,
                        castAt: Date()),
                    network: Self.networkKey)
                Self.logger.info(
                    "🗳️ VOTING :: cast \(choice.logDescription, privacy: .public) on \(normalizedLabel, privacy: .public) with \(node.displayName, privacy: .public)")
            } catch {
                // Platform's message is the useful one here — "already voted",
                // "too many vote changes", "masternode not found" each tell
                // the user something different. Surface it verbatim.
                let message = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
                outcomes.append(VoteOutcome(node: node, failure: message))
                Self.logger.error(
                    "🗳️ VOTING :: cast failed on \(normalizedLabel, privacy: .public) with \(node.displayName, privacy: .public): \(message, privacy: .public)")
            }
        }

        return VoteCastReport(
            normalizedLabel: normalizedLabel,
            choice: choice,
            outcomes: outcomes)
    }

    /// Cast the same choice across several contests with the same nodes —
    /// the bulk path behind "Vote on N usernames".
    ///
    /// Authenticates once for the whole run, then walks the contests in order.
    /// A contest that cannot be voted on at all (already closed, for instance)
    /// becomes a report with every node failed rather than aborting the run,
    /// so one stale row cannot discard the rest of the batch.
    ///
    /// - Note: Each entry carries its own choice. `abstain` and `lock`
    ///   generalize across contests, but "award it to the only requester"
    ///   names a different contender identity per contest, so the caller
    ///   resolves that and passes the result per label. This function does not
    ///   decide who a contest's contenders are.
    func castBulk(
        _ work: [(label: String, choice: VoteChoice, nodes: [VoterNode])]
    ) async throws -> [VoteCastReport] {
        // Nothing to do is not the same as nothing selected. An empty batch
        // means every selected contest was already fully voted or dropped, and
        // reporting "select a masternode" for that sends the user to fix a
        // selection that is fine.
        guard !work.isEmpty else { return [] }
        guard work.contains(where: { !$0.nodes.isEmpty }) else {
            throw CastError.noNodesSelected
        }
        guard let sdk = SwiftDashSDKHost.shared.sdk else { throw CastError.sdkUnavailable }

        switch await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled) {
        case .ok:
            break
        case .cancelled:
            throw CastError.authenticationCancelled
        case .failed, .timedOut:
            throw CastError.authenticationFailed
        }

        var reports: [VoteCastReport] = []
        reports.reserveCapacity(work.count)

        for (label, choice, nodes) in work {
            // "The check failed" and "the poll is closed" are different
            // outcomes: collapsing them would tell the user a live contest had
            // already resolved whenever the network hiccupped.
            let isOpen: Bool
            do {
                isOpen = try await contests.contestIsOpen(normalizedLabel: label)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
                reports.append(VoteCastReport(
                    normalizedLabel: label,
                    choice: choice,
                    outcomes: nodes.map { VoteOutcome(node: $0, failure: message) }))
                continue
            }
            guard isOpen else {
                reports.append(VoteCastReport(
                    normalizedLabel: label,
                    choice: choice,
                    outcomes: nodes.map {
                        VoteOutcome(node: $0, failure: CastError.contestClosed(label).errorDescription)
                    }))
                continue
            }
            reports.append(await castAuthenticated(
                choice: choice, onNormalizedLabel: label, with: nodes, sdk: sdk))
        }

        return reports
    }
}
