//
//  RequestDetailsViewModel.swift
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

// MARK: - RequestDetailsViewModel

/// One request for a username, as the owner checks it before approving: the
/// name, the identity behind it, the proof it published and the voting period.
/// Everything but the link comes from the already-loaded ``VotingStore``.
@MainActor
final class RequestDetailsViewModel: ObservableObject {
    /// What the link lookup has to say. Four answers, because collapsing
    /// "nothing published" and "the check failed" tells the owner there is no
    /// proof when in truth the query did not run.
    enum LinkState: Equatable {
        case reading
        case published(URL)
        case none
        case failed
    }

    enum ApproveAction: Equatable {
        case voteToApprove
        case cancelApproval
    }

    let identityId: String
    let normalizedLabel: String

    @Published private(set) var linkState: LinkState = .reading

    private let store: VotingStore
    private let linkLookup: (_ normalizedLabel: String, _ identityId: String) async throws -> URL?
    private let dateFormatter: DateFormatter
    private let openLink: @MainActor (URL) -> Void
    private var changes = Set<AnyCancellable>()
    /// The contest as last seen in the store, so the fields keep what they
    /// showed once it leaves the list.
    private var lastKnownContest: DPNSContest?

    init(
        store: VotingStore,
        normalizedLabel: String,
        identityId: String,
        linkLookup: @escaping (_ normalizedLabel: String, _ identityId: String) async throws -> URL?,
        dateFormatter: DateFormatter,
        openLink: @escaping @MainActor (URL) -> Void
    ) {
        self.store = store
        self.normalizedLabel = normalizedLabel
        self.identityId = identityId
        self.linkLookup = linkLookup
        self.dateFormatter = dateFormatter
        self.openLink = openLink
        self.lastKnownContest = store.contests.first { $0.normalizedLabel == normalizedLabel }
        // The approve button follows votes cast from the sheet this screen opens.
        store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &changes)
    }

    /// The screen's lookup: the link this identity published for the name.
    static func publishedLink(normalizedLabel: String, identityId: String) async throws -> URL? {
        try await IdentityVerifyService.shared.publishedURL(forLabel: normalizedLabel, ownedBy: identityId)
    }

    // MARK: Fields

    /// The contest in the store, or the last one seen there.
    var contest: DPNSContest? {
        if let live = liveContest { lastKnownContest = live }
        return lastKnownContest
    }

    private var liveContest: DPNSContest? { store.contests.first { $0.normalizedLabel == normalizedLabel } }

    var username: String {
        contest?.contenders.first { $0.identityId == identityId }?.displayLabel ?? normalizedLabel
    }

    var votingEnd: Date? { contest?.endTime }

    // TODO(voting-5b): the request's date, once the request dates are read.
    /// Always unknown for now; `createdAt` is not the request date.
    var requestDate: Date? { nil }

    /// «<start> – <end>». Without a request date the start reads «Not provided»;
    /// without a voting end either, the whole field does.
    var votingPeriodText: String {
        let notProvided = NSLocalizedString("Not provided", comment: "Voting")
        guard let votingEnd else { return notProvided }
        let end = dateFormatter.string(from: votingEnd)
        guard let requestDate else {
            return String(format: NSLocalizedString("Not provided – %@", comment: "Voting"), end)
        }
        return "\(dateFormatter.string(from: requestDate)) – \(end)"
    }

    // MARK: Link

    /// `nil` while the check is in flight.
    var linkText: String? {
        switch linkState {
        case .reading: return nil
        case .none: return NSLocalizedString("Not provided", comment: "Voting")
        case .failed: return NSLocalizedString("Couldn't check for a link", comment: "Voting")
        case .published(let url): return url.absoluteString
        }
    }

    /// Hands a web link to the system to open outside the app. Anything else
    /// is written by anyone, through any client, and is never opened.
    func open(_ url: URL) {
        guard Self.isOpenableInBrowser(url) else { return }
        openLink(url)
    }

    /// `http` or `https` and nothing else, matching what the publish path accepts.
    static func isOpenableInBrowser(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func loadLink() async {
        linkState = .reading
        do {
            if let url = try await linkLookup(normalizedLabel, identityId) {
                linkState = .published(url)
            } else {
                linkState = .none
            }
        } catch {
            linkState = .failed
        }
    }

    // MARK: Approve

    /// Cancel approval when a ticked node's last choice approves this request,
    /// once voting is set up.
    var approveAction: ApproveAction {
        let ticked = store.myNodeIDs ?? []
        let mine = store.votableNodes.contains { node in
            ticked.contains(node.proTxHash)
                && store.liveChoice(of: node, on: normalizedLabel) == .towards(identityId: identityId)
        }
        return mine ? .cancelApproval : .voteToApprove
    }

    /// Whether the button is enabled: the contest is still on the list,
    /// voting is not paused, and no other name's vote is being sent (one at a
    /// time). While this name's own vote is sent the button stays enabled and
    /// shows the loading look; its spinner takes the taps. Every tap runs the
    /// vote gates, which tell an ended contest, the key flow and "No votes
    /// left" themselves.
    var canApprove: Bool {
        liveContest != nil && !store.historyUnavailable
            && (!store.isVoteBusy || store.isSending(normalizedLabel: normalizedLabel))
    }

    /// A vote or cancel from here that landed everywhere returns to the list,
    /// whose toast tells it; anything else stays on this screen (SCR-03).
    func returnsToList(after outcome: VoteAttemptOutcome?) -> Bool {
        guard isOwnAttempt, case .success = outcome else { return false }
        return true
    }

    /// A failed vote from here, or one its masternodes already held, is told
    /// on this screen; another name's toast, from a vote sent from the list,
    /// stays on the list (SCR-03).
    func showsToast(_ toast: VotingToast) -> Bool {
        isOwnAttempt && (toast.style == .error || toast.isAlreadyVoted)
    }

    private var isOwnAttempt: Bool { store.attemptLabel == normalizedLabel }

    /// The vote the button asks for: this request's approve, or an abstain
    /// from the nodes holding it.
    func voteRequest() -> VoteFlowRequest? {
        guard let contest = liveContest else { return nil }
        let approve = VoteChoice.towards(identityId: identityId)
        switch approveAction {
        case .voteToApprove:
            return VoteFlowRequest(contest: contest, choice: approve)
        case .cancelApproval:
            return VoteFlowRequest(contest: contest, choice: .abstain, cancelling: approve)
        }
    }

    var approveTitle: String {
        switch approveAction {
        case .voteToApprove: return NSLocalizedString("Vote to approve", comment: "Voting")
        case .cancelApproval: return NSLocalizedString("Cancel approval", comment: "Voting")
        }
    }
}
