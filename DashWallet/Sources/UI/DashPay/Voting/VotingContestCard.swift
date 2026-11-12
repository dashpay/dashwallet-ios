//
//  VotingContestCard.swift
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

import DashUIKit
import SwiftDashSDK
import SwiftUI

// MARK: - VotingContestCard

/// One name in the voting list, as a card.
///
/// A name with one request shows its block (lock) and approve counts as vote
/// pills. A name with several requests shows how many, its block count and a
/// chevron that opens the row in place, listing each request with its own
/// approve pill. The pill that carries this wallet's vote is filled.
struct VotingContestCard: View {
    let contest: DPNSContest
    /// The choices this wallet's nodes hold on the contest.
    let myChoices: Set<VoteChoice>
    /// A vote on this contest is being sent.
    let isCasting: Bool
    /// Whether a tap on this choice's pill can start anything: a vote (it may
    /// lead to the key flow) or, on a filled pill, taking that vote back.
    let canTapPill: (VoteChoice) -> Bool
    let onVote: (VoteChoice) -> Void
    /// Opens one request's details, by its identity.
    let onOpenRequest: (_ identityId: String) -> Void
    /// Opens the contest screen with every outcome (the row's context menu).
    let onOpenOutcomes: () -> Void
    /// What a tap on the name does, for VoiceOver.
    let headerHint: String
    /// The open-in-place state of a several-request name; `nil` for one request.
    var expansion: Expansion?

    /// What a several-request row shows and speaks, computed by the list's view model.
    struct Expansion {
        let isExpanded: Bool
        let countText: String
        let pillLabel: String
        let pillValue: String
        let requests: [VotingRequestRow]
        let onToggle: () -> Void
    }

    private var hasVoteWithoutPill: Bool {
        Self.hasVoteWithoutPill(myChoices, contenders: contest.contenders, isExpanded: expansion?.isExpanded ?? false)
    }

    /// A vote of this wallet's that no pill on the row carries. An abstain is
    /// not one: it takes a vote back, and the name is listed under
    /// "I have not voted" (AC-07).
    static func hasVoteWithoutPill(
        _ myChoices: Set<VoteChoice>,
        contenders: [DPNSContender],
        isExpanded: Bool
    ) -> Bool {
        var carried: Set<VoteChoice> = [.lock, .abstain]
        if contenders.count == 1 || isExpanded {
            carried.formUnion(contenders.map { .towards(identityId: $0.identityId) })
        }
        return !myChoices.subtracting(carried).isEmpty
    }

    private var sole: DPNSContender? {
        contest.contenders.count == 1 ? contest.contenders.first : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let expansion, expansion.isExpanded {
                ForEach(expansion.requests, id: \.identityId) { request in
                    requestRow(request)
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .modifier(MenuViewModifier(shadowRadius: 20))
    }

    /// One request opens its details; several open in place.
    private func openHeader() {
        if let sole {
            onOpenRequest(sole.identityId)
        } else if let expansion {
            expansion.onToggle()
        } else {
            onOpenOutcomes()
        }
    }

    private var header: some View {
        HStack(spacing: 20) {
            Button(action: openHeader) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(contest.displayTitle)
                        .dashFont(.subheadMedium)
                        .foregroundStyle(Color.dash.primaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    // Platform keys the contest by the homograph-normalized
                    // form; keep it visible so the name voted on is never
                    // ambiguous, behind the spelling people typed.
                    if contest.displayTitleDiffersFromNormalized {
                        Text(contest.normalizedLabel)
                            .dashFont(.footnote)
                            .monospaced()
                            .foregroundStyle(Color.dash.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let expansion {
                        Text(expansion.countText)
                            .dashFont(.footnote)
                            .foregroundStyle(Color.dash.tertiaryText)
                    }
                    // A vote no pill on this row carries (an approve on a
                    // collapsed several-request name): say it, so the name
                    // does not read as still to vote on.
                    if hasVoteWithoutPill {
                        Text(NSLocalizedString("You voted", comment: "Voting"))
                            .dashFont(.footnoteMedium)
                            .foregroundStyle(Color.dash.blueText)
                            .transition(.opacity)
                    }
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(headerHint)
            .contextMenu {
                Button(NSLocalizedString("All outcomes", comment: "Voting"), action: onOpenOutcomes)
            }

            HStack(spacing: 10) {
                pill(.block, count: contest.lockVotes, choice: .lock)
                if let sole {
                    pill(.approve, count: sole.voteTally, choice: .towards(identityId: sole.identityId))
                } else if let expansion {
                    VotePill(
                        kind: .expand(isExpanded: expansion.isExpanded),
                        accessibilityLabel: expansion.pillLabel,
                        accessibilityValue: expansion.pillValue,
                        action: expansion.onToggle)
                }
            }
        }
        .padding(.leading, 10)
    }

    /// One request of an open several-request name: its identity (the request
    /// details open on tap) and its own approve pill.
    private func requestRow(_ request: VotingRequestRow) -> some View {
        let choice = VoteChoice.towards(identityId: request.identityId)
        let status: VotePill.Status = isCasting ? .busy : (canTapPill(choice) ? .enabled : .disabled)
        return HStack(spacing: 20) {
            Button(action: { onOpenRequest(request.identityId) }) {
                Text(request.identityId)
                    .dashFont(.footnote)
                    .monospaced()
                    .foregroundStyle(Color.dash.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(request.spokenIdentity))
            .accessibilityHint(NSLocalizedString("Opens the request details", comment: "Voting"))

            VotePill(
                kind: .approve,
                count: request.votes,
                isSelected: request.isMine,
                status: status,
                accessibilityLabel: request.accessibilityLabel,
                accessibilityValue: isCasting
                    ? request.accessibilityValue + ", " + NSLocalizedString("Sending", comment: "Voting")
                    : request.accessibilityValue,
                action: { onVote(choice) })
                .accessibilityHint(Self.pillAccessibilityHint(isSelected: request.isMine, status: status) ?? "")
        }
        .padding(.leading, 10)
        .padding(.top, 8)
    }

    /// VoiceOver's hint for a block or approve pill: a filled pill that can be
    /// tapped takes my vote back (AC-17), which its label and selected trait do
    /// not say.
    static func pillAccessibilityHint(isSelected: Bool, status: VotePill.Status) -> String? {
        guard isSelected, status == .enabled else { return nil }
        return NSLocalizedString("Takes your vote back", comment: "Voting")
    }

    /// The pill's spoken vote count, by the locale's plural rules: «1 vote», «3 votes».
    static func votesValue(count: UInt32) -> String {
        String.localizedStringWithFormat(NSLocalizedString("%d votes", comment: "Voting"), Int(count))
    }

    private func pill(_ kind: VotePill.Kind, count: UInt32, choice: VoteChoice) -> some View {
        let label = kind == .block
            ? String(format: NSLocalizedString("Block %@", comment: "Voting"), contest.displayTitle)
            : String(format: NSLocalizedString("Approve %@", comment: "Voting"), contest.displayTitle)
        let votes = Self.votesValue(count: count)
        let isSelected = myChoices.contains(choice)
        let status: VotePill.Status = isCasting ? .busy : (canTapPill(choice) ? .enabled : .disabled)
        return VotePill(
            kind: kind,
            count: Int(count),
            isSelected: isSelected,
            status: status,
            accessibilityLabel: label,
            accessibilityValue: isCasting
                ? votes + ", " + NSLocalizedString("Sending", comment: "Voting")
                : votes,
            action: { onVote(choice) })
            .accessibilityHint(Self.pillAccessibilityHint(isSelected: isSelected, status: status) ?? "")
    }
}

// MARK: - VotingToast view

extension VotingToast {
    /// The toast as drawn, shared by the list and the contest screen.
    var view: some View {
        DashUIKit.Toast(style: .success, message: message)
            .id(id)
    }
}

// MARK: - Previews

#if DEBUG
private enum CardPreview {
    static func contest(requests: Int, label: String = "johndoe") -> DPNSContest {
        DPNSContest(
            normalizedLabel: label, endTime: nil, hasWinner: false, abstainVotes: 0, lockVotes: 3,
            contenders: (1...requests).map {
                DPNSContender(identityId: "identity\($0)Xk3vQ9mT2pLw8RzYb5NcHf7Ud4Ea", voteTally: UInt32($0 * 2))
            })
    }

    static func card(
        _ contest: DPNSContest, expanded: Bool = false, mine: Int? = nil
    ) -> some View {
        let rows = contest.contenders.enumerated().map { index, contender in
            VotingRequestRow(identityId: contender.identityId, votes: Int(contender.voteTally), isMine: index == mine)
        }
        let myChoices: Set<VoteChoice> = mine.map { [.towards(identityId: contest.contenders[$0].identityId)] } ?? []
        return VotingContestCard(
            contest: contest, myChoices: myChoices, isCasting: false,
            canTapPill: { _ in true }, onVote: { _ in }, onOpenRequest: { _ in }, onOpenOutcomes: {},
            headerHint: contest.contenders.count > 1 ? "Opens the requests for this name" : "Opens the request details",
            expansion: contest.contenders.count > 1
                ? .init(
                    isExpanded: expanded, countText: "\(contest.contenders.count) requests",
                    pillLabel: (expanded ? "Hide" : "Show") + " requests for \(contest.displayTitle)",
                    pillValue: "\(contest.contenders.count) requests", requests: rows, onToggle: {})
                : nil)
            .padding(16)
    }
}

#Preview("One request") { CardPreview.card(CardPreview.contest(requests: 1)) }
#Preview("Several collapsed") { CardPreview.card(CardPreview.contest(requests: 3)) }
#Preview("Several expanded") { CardPreview.card(CardPreview.contest(requests: 3), expanded: true) }
#Preview("My vote on request 2 of 3") {
    CardPreview.card(CardPreview.contest(requests: 3), expanded: true, mine: 1)
}
#Preview("Long identity") {
    CardPreview.card(CardPreview.contest(requests: 2, label: "averyveryveryverylongusernamethatwraps"), expanded: true)
}
#Preview("Dark") {
    CardPreview.card(CardPreview.contest(requests: 3), expanded: true, mine: 0)
        .preferredColorScheme(.dark)
}
#endif
