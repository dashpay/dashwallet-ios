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
/// chevron that opens the contest, where each request is listed. The pill that
/// carries this wallet's vote is filled.
struct VotingContestCard: View {
    let contest: DPNSContest
    /// The choices this wallet's nodes hold on the contest.
    let myChoices: Set<VoteChoice>
    /// A vote on this contest is being sent.
    let isCasting: Bool
    /// Show when voting ends on the card: the list is not grouped by end day.
    var showsDeadline = false
    /// Whether a tap on this choice may start a vote (it may lead to the key flow).
    let canStartVote: (VoteChoice) -> Bool
    let onVote: (VoteChoice) -> Void
    let onOpen: () -> Void

    /// A vote of this wallet's that no pill on the row carries.
    private var hasVoteWithoutPill: Bool {
        var carried: Set<VoteChoice> = [.lock]
        if let sole { carried.insert(.towards(identityId: sole.identityId)) }
        return !myChoices.subtracting(carried).isEmpty
    }

    private var sole: DPNSContender? {
        contest.contenders.count == 1 ? contest.contenders.first : nil
    }

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onOpen) {
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
                    if contest.contenders.count > 1 {
                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("%d requests", comment: "Voting"),
                            contest.contenders.count))
                            .dashFont(.footnote)
                            .foregroundStyle(Color.dash.tertiaryText)
                    }
                    if showsDeadline {
                        ContestDeadlineLabel(endTime: contest.endTime)
                    }
                    // A vote no pill on this row carries (an approve on a
                    // several-request name, an abstain anywhere): say it, so
                    // the name does not read as still to vote on.
                    if hasVoteWithoutPill {
                        Text(NSLocalizedString("You voted", comment: "Voting"))
                            .dashFont(.footnoteMedium)
                            .foregroundStyle(Color.dash.blueText)
                    }
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(NSLocalizedString("Opens the requests for this name", comment: "Voting"))

            HStack(spacing: 10) {
                pill(.block, count: contest.lockVotes, choice: .lock)
                if let sole {
                    pill(.approve, count: sole.voteTally, choice: .towards(identityId: sole.identityId))
                } else if contest.contenders.count > 1 {
                    VotePill(
                        kind: .expand(isExpanded: false),
                        accessibilityLabel: String(
                            format: NSLocalizedString("Show requests for %@", comment: "Voting"),
                            contest.displayTitle),
                        action: onOpen)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.vertical, 8)
        .modifier(MenuViewModifier(shadowRadius: 20))
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
        return VotePill(
            kind: kind,
            count: Int(count),
            isSelected: myChoices.contains(choice),
            status: isCasting ? .busy : (canStartVote(choice) ? .enabled : .disabled),
            accessibilityLabel: label,
            accessibilityValue: isCasting
                ? votes + ", " + NSLocalizedString("Sending", comment: "Voting")
                : votes,
            action: { onVote(choice) })
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
