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
    /// `nil` on success; the reason in plain words otherwise.
    let failure: String?
    /// `false` when Platform accepted the vote but the local history write
    /// failed, so the stored cast count is one low.
    var historyRecorded: Bool = true
    /// The masternode has spent all its votes on this contest, whichever step
    /// found it: the vote gates, the recheck before a cast, or Platform's
    /// refusal. Set by ``noVotesLeft(_:)``, never read from the text.
    private(set) var hasNoVotesLeft = false

    var id: Data { node.proTxHash }
    var succeeded: Bool { failure == nil }

    init(node: VoterNode, failure: String?, historyRecorded: Bool = true) {
        self.node = node
        self.failure = failure
        self.historyRecorded = historyRecorded
    }

    /// A masternode with no vote left here: "No votes left".
    static func noVotesLeft(_ node: VoterNode) -> VoteOutcome {
        var outcome = VoteOutcome(node: node, failure: NSLocalizedString("No votes left", comment: "Voting"))
        outcome.hasNoVotesLeft = true
        return outcome
    }
}

/// Aggregate result of casting one choice with a set of nodes.
struct VoteCastReport {
    let normalizedLabel: String
    let choice: VoteChoice
    let outcomes: [VoteOutcome]
    /// Platform answered that the poll is closed, so nothing was sent.
    var contestClosed = false

    var succeeded: [VoteOutcome] { outcomes.filter(\.succeeded) }
    var failed: [VoteOutcome] { outcomes.filter { !$0.succeeded } }
    /// Platform voting weight that was actually accepted.
    var acceptedWeight: UInt32 { succeeded.map(\.node).totalVoteWeight }
    var isCompleteSuccess: Bool { !outcomes.isEmpty && failed.isEmpty }
    /// Some failed masternode could still land a vote on a retry; one with no
    /// vote left never can (AC-15).
    var offersTryAgain: Bool { failed.contains { !$0.hasNoVotesLeft } }
}

// MARK: - QuickVoteCast

/// One name of a Quick voting run: the choice and the masternodes that send it.
struct QuickVoteCast {
    let normalizedLabel: String
    let choice: VoteChoice
    let nodes: [VoterNode]
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

    /// Vote history is per Platform network — a testnet contest and a mainnet
    /// one can share a label, and their counts must never merge.
    static var networkKey: String {
        // Same "mainnet"/"testnet" strings as before; each configured devnet's
        // contests are recorded under their own key.
        WalletEnvironment.network?.persistenceScope ?? "mainnet"
    }

    private let contests: ContestedNamesService
    private let history: VoteHistoryDAO
    private let votingKey: (VoterNode) -> Data?
    private let send: VoteSender
    private let authenticate: @MainActor () async -> AuthenticationGate.Outcome
    private let isContestOpen: @MainActor (_ normalizedLabel: String) async throws -> Bool
    private let isSDKConnected: @MainActor () -> Bool

    /// Broadcasts one vote for one node. Throws on any failure.
    typealias VoteSender = (
        _ node: VoterNode, _ votingKey: Data, _ choice: VoteChoice, _ normalizedLabel: String
    ) async throws -> Void

    /// - Parameters:
    ///   - votingKey: derives a node's voting key; `nil` uses the registry.
    ///   - send: broadcasts one vote; `nil` uses the SDK.
    ///   - authenticate: the PIN/biometric prompt of a Quick voting run;
    ///     `nil` uses ``AuthenticationGate``.
    ///   - isContestOpen: a run's pre-flight per name; `nil` asks Platform.
    ///   - isSDKConnected: whether a run can reach Platform at all; `nil`
    ///     asks ``SwiftDashSDKHost``.
    init(
        registry: MasternodeVoterRegistry,
        contests: ContestedNamesService,
        history: VoteHistoryDAO,
        votingKey: ((VoterNode) -> Data?)? = nil,
        send: VoteSender? = nil,
        authenticate: (@MainActor () async -> AuthenticationGate.Outcome)? = nil,
        isContestOpen: (@MainActor (_ normalizedLabel: String) async throws -> Bool)? = nil,
        isSDKConnected: (@MainActor () -> Bool)? = nil
    ) {
        self.contests = contests
        self.history = history
        self.authenticate = authenticate ?? {
            await AuthenticationGate.authenticate(biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled)
        }
        self.isContestOpen = isContestOpen ?? { try await contests.contestIsOpen(normalizedLabel: $0) }
        self.isSDKConnected = isSDKConnected ?? { SwiftDashSDKHost.shared.sdk != nil }
        self.votingKey = votingKey ?? { registry.votingPrivateKey(for: $0) }
        self.send = send ?? { node, votingKey, choice, normalizedLabel in
            guard let sdk = SwiftDashSDKHost.shared.sdk else { throw CastError.sdkUnavailable }
            try await sdk.castContestedResourceVote(
                dataContractId: DPNSVotePoll.contractId,
                documentTypeName: DPNSVotePoll.documentTypeName,
                indexName: DPNSVotePoll.indexName,
                indexValues: DPNSVotePoll.indexValues(normalizedLabel: normalizedLabel),
                choice: choice.sdkChoice,
                proTxHash: node.proTxHash,
                votingPrivateKey: votingKey)
        }
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
    /// ``castAfterAuthentication(choice:onNormalizedLabel:with:)``.
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
        guard SwiftDashSDKHost.shared.sdk != nil else { throw CastError.sdkUnavailable }

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

        return await castAfterAuthentication(
            choice: choice, onNormalizedLabel: normalizedLabel, with: nodes)
    }

    /// Quick voting (ADR-0037): one PIN/biometric prompt, then name by name and
    /// masternode by masternode through the per-node path, which re-reads the
    /// vote limit and records each landed vote before the next cast.
    /// `progress` gets 0 once the prompt is passed, so nothing tells of the
    /// run before it, then the number of names done after each one.
    ///
    /// A name whose poll is closed, or whose pre-flight cannot be read, sends
    /// nothing and the run goes on. Once the task is cancelled (the screen went
    /// away, the app went to the background) nothing more is sent, and every
    /// vote not sent is reported as not cast, so Try again covers it.
    ///
    /// - Throws: ``CastError`` when Platform is not connected or the prompt
    ///   is refused: nothing was sent.
    func castRun(
        _ casts: [QuickVoteCast], progress: @escaping @MainActor (Int) -> Void
    ) async throws -> [VoteCastReport] {
        guard !casts.isEmpty else { return [] }
        // Before the prompt, as a single cast does: without Platform no vote
        // can be sent, and a PIN asked for nothing is a broken promise.
        guard isSDKConnected() else { throw CastError.sdkUnavailable }
        // A run stopped before it starts (a Try again stopped while it re-read
        // the history) asks for no PIN and tells no progress: the loop below
        // reports every vote as not cast.
        let authenticated = !Task.isCancelled
        if authenticated {
            switch await authenticate() {
            case .ok:
                progress(0)
            case .cancelled:
                throw CastError.authenticationCancelled
            case .failed, .timedOut:
                throw CastError.authenticationFailed
            }
        }
        var reports: [VoteCastReport] = []
        for (index, cast) in casts.enumerated() {
            reports.append(await castAfterAuthentication(cast))
            if authenticated { progress(index + 1) }
        }
        return reports
    }

    /// One name of a run, after authentication.
    private func castAfterAuthentication(_ cast: QuickVoteCast) async -> VoteCastReport {
        func notSent(_ reason: String, closed: Bool = false) -> VoteCastReport {
            DWLogger.log("Voting: Quick voting \(cast.choice.logDescription) on \(cast.normalizedLabel) not sent: \(reason)")
            return VoteCastReport(
                normalizedLabel: cast.normalizedLabel, choice: cast.choice,
                outcomes: cast.nodes.map { VoteOutcome(node: $0, failure: reason) }, contestClosed: closed)
        }
        let stopped = NSLocalizedString("Quick voting stopped before this vote was sent.", comment: "Voting")
        guard !Task.isCancelled else { return notSent(stopped) }
        do {
            guard try await isContestOpen(cast.normalizedLabel) else {
                return notSent(CastError.contestClosed(cast.normalizedLabel).errorDescription ?? stopped, closed: true)
            }
        } catch {
            return notSent(VoteErrorMessage.plain(for: error))
        }
        var outcomes: [VoteOutcome] = []
        for node in cast.nodes {
            guard !Task.isCancelled else {
                DWLogger.log("Voting: Quick voting on \(cast.normalizedLabel) with \(Self.logName(node)) not sent: stopped")
                outcomes.append(VoteOutcome(node: node, failure: stopped))
                continue
            }
            let report = await castAfterAuthentication(
                choice: cast.choice, onNormalizedLabel: cast.normalizedLabel, with: [node])
            outcomes.append(contentsOf: report.outcomes)
        }
        return VoteCastReport(normalizedLabel: cast.normalizedLabel, choice: cast.choice, outcomes: outcomes)
    }

    /// A node as the voting log lines name it: its kind, the vote weight
    /// Platform gives it, and its short pro_tx_hash, which is public in the
    /// masternode list. Never the voting key.
    private static func logName(_ node: VoterNode) -> String {
        "\(node.isEvonode ? "evonode" : "masternode") \(node.typeIndex) \(node.shortProTxHash) (weight \(node.voteWeight))"
    }

    /// The per-node broadcast loop, after authentication and pre-flight.
    /// It asks for no PIN: internal only so the tests can reach it, and every
    /// app caller goes through ``cast(choice:onNormalizedLabel:with:)``.
    ///
    /// Nodes are processed **serially**: the SDK fetches an identity nonce for
    /// the voter identity on every broadcast, and two concurrent votes from
    /// the same node would race on it. Never throws — a node that fails is
    /// recorded and the loop continues, so one failure cannot discard the
    /// nodes that already succeeded.
    func castAfterAuthentication(
        choice: VoteChoice,
        onNormalizedLabel normalizedLabel: String,
        with nodes: [VoterNode]
    ) async -> VoteCastReport {
        var outcomes: [VoteOutcome] = []
        outcomes.reserveCapacity(nodes.count)

        for node in nodes {
            let attempt = "\(choice.logDescription) on \(normalizedLabel) with \(Self.logName(node))"
            // Re-read the count before every cast: Platform refuses the sixth,
            // and an unreadable count is unknown, never zero.
            guard let votes = await history.votes(forContest: normalizedLabel, network: Self.networkKey) else {
                DWLogger.log("Voting: \(attempt) not sent: vote count unreadable")
                outcomes.append(VoteOutcome(
                    node: node,
                    failure: NSLocalizedString(
                        "Could not check how many votes this node has left.",
                        comment: "Voting")))
                continue
            }
            let castCount = votes.first { $0.proTxHash == node.proTxHash }?.castCount ?? 0
            guard castCount < VoteLimit.maxCastsPerNode else {
                DWLogger.log("Voting: \(attempt) not sent: no votes left (\(castCount) cast)")
                outcomes.append(.noVotesLeft(node))
                continue
            }

            guard let votingKey = votingKey(node) else {
                DWLogger.log("Voting: \(attempt) not sent: no voting key")
                outcomes.append(VoteOutcome(
                    node: node,
                    failure: NSLocalizedString(
                        "This wallet could not derive the voting key for this node.",
                        comment: "Voting")))
                continue
            }

            // The last point before the broadcast: a run stopped while the
            // count was being read sends nothing more. Only a Quick voting
            // run is ever stopped.
            guard !Task.isCancelled else {
                DWLogger.log("Voting: \(attempt) not sent: stopped")
                outcomes.append(VoteOutcome(
                    node: node,
                    failure: NSLocalizedString("Quick voting stopped before this vote was sent.", comment: "Voting")))
                continue
            }

            do {
                try await send(node, votingKey, choice, normalizedLabel)
            } catch {
                // Stored in plain words: Platform's own text is never shown,
                // and never logged beyond the error's type.
                outcomes.append(VoteErrorMessage.isNoVotesLeft(error)
                    ? .noVotesLeft(node)
                    : VoteOutcome(node: node, failure: VoteErrorMessage.plain(for: error)))
                DWLogger.log("Voting: \(attempt) failed: \(String(describing: type(of: error)))")
                continue
            }

            // Recorded only on success, so the count the UI shows is
            // votes Platform accepted — not votes attempted.
            var historyRecorded = true
            do {
                try await history.record(
                    CastVoteRecord(
                        proTxHash: node.proTxHash,
                        normalizedLabel: normalizedLabel,
                        choice: choice,
                        castAt: Date()),
                    network: Self.networkKey)
            } catch {
                historyRecorded = false
                DWLogger.log("Voting: history write failed on \(normalizedLabel): \(String(describing: type(of: error)))")
            }
            outcomes.append(VoteOutcome(node: node, failure: nil, historyRecorded: historyRecorded))
            DWLogger.log("Voting: \(attempt) landed (cast \(castCount + 1) of \(VoteLimit.maxCastsPerNode))")
        }

        return VoteCastReport(
            normalizedLabel: normalizedLabel,
            choice: choice,
            outcomes: outcomes)
    }
}
