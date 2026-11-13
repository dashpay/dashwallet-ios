//
//  QuickVotingViewModel.swift
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

import Combine
import Foundation
import SwiftDashSDK

// MARK: - QuickVotingHosting

/// What Quick voting reads and does outside itself.
@MainActor
protocol QuickVotingHosting: AnyObject {
    /// "Add your voting keys" was confirmed once on this install (AC-12).
    var isVotingSetUp: Bool { get }
    /// The masternodes the user votes with.
    var tickedNodeIDs: Set<Data> { get }
    /// A masternode of this wallet may be missing from the list (the sync is
    /// not done, or the list may be incomplete), so a plan cannot be trusted (AC-20).
    var nodeListMayMissNodes: Bool { get }
    /// Tells why Quick voting did not open while ``nodeListMayMissNodes``.
    func reportNodeListMayMissNodes()
    /// The names on screen, the filter and the search together, each with its shown requests.
    var shownContests: [DPNSContest] { get }
    /// "Only requests with links" is on: each name shows only its linked requests.
    var showsOnlyRequestsWithLinks: Bool { get }
    /// Reads this wallet's vote history again, so the plan decides on today's;
    /// `false` when it could not be read, and the list's lasting card then
    /// says voting is paused.
    func reloadVoteHistory() async -> Bool
    func quickVotePlan(for shown: [DPNSContest]) -> QuickVotePlan
    /// The name a user reads for a contest.
    func username(of normalizedLabel: String) -> String
    /// Sends the plan as one run; its outcome is the host's to show.
    func startQuickVoting(_ plan: QuickVotePlan)
    /// «Quick voting» was tapped in the list's menu: the last vote's toast and outcome go now,
    /// so neither sits under the sheet or comes back after Cancel (AC-06).
    func quickVotingWillStart()
}

// MARK: - QuickVotingViewModel

/// The «Quick voting» menu item (AC-18): "Add your voting keys" first when voting is not set
/// up, then the Quick voting sheet with how many names get a vote and how many
/// are skipped, then "One vote left" when some name gets its last vote, then
/// the run. Cancel at any step sends nothing.
@MainActor
final class QuickVotingViewModel: ObservableObject {
    enum Step: Equatable {
        /// "Add your voting keys"; its vote button goes on to the sheet.
        case addKeys
        /// The Quick voting sheet (SCR-06).
        case confirm
        /// "One vote left" for these names (SCR-07, Quick voting).
        case lastVotes(usernames: [String])
    }

    @Published private(set) var step: Step?
    /// The plan the sheet shows and Vote for all sends.
    private(set) var plan: QuickVotePlan?
    /// The plan approves the first linked request of each name, as the list shows only those (AC-18).
    private(set) var approvesLinkedRequests = false

    /// Weak: the host owns this model.
    private weak var host: QuickVotingHosting?

    init(host: QuickVotingHosting) {
        self.host = host
    }

    /// Names that get a vote: at least one ticked masternode sends on them.
    var votedCount: Int { plan?.votes.count ?? 0 }
    /// Names no ticked masternode sends on.
    var skippedCount: Int { plan?.skipped.count ?? 0 }
    /// Some name gets a vote; otherwise the sheet offers Close only.
    var canVote: Bool { votedCount > 0 }

    /// «Quick voting» tapped in the list's menu. Ignored while a step is up.
    func start() async {
        guard step == nil else { return }
        host?.quickVotingWillStart()
        await openSheetOrKeys()
    }

    /// "Add your voting keys" closed; with its vote button the sheet opens.
    func finishKeys(continueToVote: Bool) async {
        guard step == .addKeys else { return }
        step = nil
        if continueToVote { await openSheetOrKeys() }
    }

    /// The sheet's «Vote for all».
    func voteForAll() {
        guard step == .confirm, let plan, canVote, let host else { return }
        let lastVotes = plan.lastVoteLabels
        guard lastVotes.isEmpty else {
            step = .lastVotes(usernames: lastVotes.map(host.username(of:)))
            return
        }
        run(plan)
    }

    /// "One vote left"'s Vote.
    func confirmLastVotes() {
        guard case .lastVotes = step, let plan else { return }
        run(plan)
    }

    /// Cancel, Close, or a sheet or dialog dismissed: nothing is sent.
    func cancel() {
        step = nil
        plan = nil
    }

    private func openSheetOrKeys() async {
        guard let host else { return }
        guard host.isVotingSetUp, !host.tickedNodeIDs.isEmpty else {
            step = .addKeys
            return
        }
        // Read at the tap (``QuickVotingHosting/quickVotingWillStart()``), so a
        // sync that finished since the list was read does not hold it back.
        guard !host.nodeListMayMissNodes else {
            host.reportNodeListMayMissNodes()
            return
        }
        // Voting is paused on an unreadable history (AC-15): a plan on the
        // last one cached could replace votes it does not know about. The
        // list's card says so; a lasting state gets no toast as well.
        guard await host.reloadVoteHistory() else { return }
        plan = host.quickVotePlan(for: host.shownContests)
        approvesLinkedRequests = host.showsOnlyRequestsWithLinks
        step = .confirm
    }

    private func run(_ plan: QuickVotePlan) {
        cancel()
        host?.startQuickVoting(plan)
    }
}
