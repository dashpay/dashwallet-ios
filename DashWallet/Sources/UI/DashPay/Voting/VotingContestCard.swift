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
    /// The pill whose vote is being sent, when the send started from one.
    var sendingPill: VoteChoice?
    /// Whether a tap on this choice's pill can start anything: a vote (it may
    /// lead to the key flow) or, on a filled pill, taking that vote back.
    let canTapPill: (VoteChoice) -> Bool
    let onVote: (VoteChoice) -> Void
    /// Opens one request's details, by its identity.
    let onOpenRequest: (_ identityId: String) -> Void
    /// What a tap on the name does, for VoiceOver; `nil` when it does nothing.
    let headerHint: String?
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
        } else {
            expansion?.onToggle()
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
            // A name with no request has nothing to open.
            .disabled(sole == nil && expansion == nil)
            .accessibilityHint(headerHint ?? "")

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

    /// One request of an open several-request name: its date (its identity
    /// when Platform gave no date; the request details open on tap), «Link
    /// included» under it when it has one, and its own approve pill.
    private func requestRow(_ request: VotingRequestRow) -> some View {
        let choice = VoteChoice.towards(identityId: request.identityId)
        let status = Self.pillStatus(
            of: choice, isCasting: isCasting, sendingPill: sendingPill, canTap: canTapPill(choice))
        return HStack(spacing: 20) {
            Button(action: { onOpenRequest(request.identityId) }) {
                VStack(alignment: .leading, spacing: 0) {
                    if let dateText = request.dateText {
                        // The day, then the time in a lighter colour (design 3830:20798).
                        (Text(dateText).foregroundStyle(Color.dash.primaryText)
                            + Text(request.timeText.map { " " + $0 } ?? "").foregroundStyle(Color.dash.tertiaryText))
                            .dashFont(.footnote)
                    } else {
                        Text(request.identityId)
                            .dashFont(.footnote)
                            .monospaced()
                            .foregroundStyle(Color.dash.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityLabel(Text(request.spokenIdentity))
                    }
                    if request.hasLink {
                        Text(NSLocalizedString("Link included", comment: "Voting"))
                            .dashFont(.footnote)
                            .foregroundStyle(Color.dash.tertiaryText)
                    }
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(NSLocalizedString("Opens the request details", comment: "Voting"))

            VotePill(
                kind: .approve,
                count: request.votes,
                isSelected: request.isMine,
                status: status,
                accessibilityLabel: request.accessibilityLabel,
                accessibilityValue: status == .busy
                    ? request.accessibilityValue + ", " + NSLocalizedString("Sending", comment: "Voting")
                    : request.accessibilityValue,
                action: { onVote(choice) })
                .accessibilityHint(Self.pillAccessibilityHint(isSelected: request.isMine, status: status) ?? "")
        }
        .padding(.leading, 10)
        // Each request takes the design's 56 pt row: 8 pt above and below its pill.
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }

    /// A pill's look: while a vote on the contest is sent, the tapped pill is
    /// busy and the others are disabled (screens.md SCR-01 «sending»).
    static func pillStatus(
        of choice: VoteChoice, isCasting: Bool, sendingPill: VoteChoice?, canTap: Bool
    ) -> VotePill.Status {
        guard isCasting else { return canTap ? .enabled : .disabled }
        // A send that did not start from a pill (Try again) busies them all.
        guard let sendingPill else { return .busy }
        return choice == sendingPill ? .busy : .disabled
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
        let status = Self.pillStatus(
            of: choice, isCasting: isCasting, sendingPill: sendingPill, canTap: canTapPill(choice))
        return VotePill(
            kind: kind,
            count: Int(count),
            isSelected: isSelected,
            status: status,
            accessibilityLabel: label,
            accessibilityValue: status == .busy
                ? votes + ", " + NSLocalizedString("Sending", comment: "Voting")
                : votes,
            action: { onVote(choice) })
            .accessibilityHint(Self.pillAccessibilityHint(isSelected: isSelected, status: status) ?? "")
    }
}

// MARK: - VotingToast view

extension VotingToast {
    /// The toast as drawn, shared by the list and Request details: the close
    /// button and the self-hide follow ``showsCloseButton`` and ``hidesAfter``.
    /// `onClose` gets this toast's id, so closing it never clears a newer one.
    func view(onClose: @escaping (ID) -> Void) -> some View {
        DashUIKit.Toast(
            style: style == .success ? .success : .error,
            message: message,
            onDismiss: showsCloseButton ? { onClose(id) } : nil)
            .id(id)
            .task(id: id) {
                guard let hidesAfter else { return }
                try? await Task.sleep(for: hidesAfter)
                if !Task.isCancelled { onClose(id) }
            }
    }
}

// MARK: - Previews

#if DEBUG
private enum CardPreview {
    /// 12 Feb 2023 9:45 UTC, then an hour apart.
    static let firstRequest = Date(timeIntervalSince1970: 1_676_195_100)

    static func contest(requests: Int, label: String = "johndoe", dated: Bool = false) -> DPNSContest {
        DPNSContest(
            normalizedLabel: label, endTime: nil, hasWinner: false, abstainVotes: 0, lockVotes: 3,
            contenders: (0..<requests).map { (offset: Int) -> DPNSContender in
                // Typed step by step: one inferred expression is too slow for CI's type checker.
                let index = offset + 1
                let createdAt: Date? = dated ? firstRequest.addingTimeInterval(Double(index - 1) * 3600) : nil
                return DPNSContender(
                    identityId: "identity\(index)Xk3vQ9mT2pLw8RzYb5NcHf7Ud4Ea",
                    voteTally: UInt32(index * 2),
                    createdAt: createdAt)
            })
    }

    static func card(
        _ contest: DPNSContest, expanded: Bool = false, mine: Int? = nil, sending: VoteChoice? = nil,
        linked: Set<Int> = []
    ) -> some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        let time = DateFormatter()
        time.dateStyle = .none
        time.timeStyle = .short
        time.timeZone = TimeZone(identifier: "UTC")
        let rows = contest.contenders.enumerated().map { index, contender in
            VotingRequestRow(
                identityId: contender.identityId, votes: Int(contender.voteTally), isMine: index == mine,
                dateText: contender.createdAt.map(formatter.string(from:)),
                timeText: contender.createdAt.map(time.string(from:)), hasLink: linked.contains(index))
        }
        let myChoices: Set<VoteChoice> = mine.map { [.towards(identityId: contest.contenders[$0].identityId)] } ?? []
        return VotingContestCard(
            contest: contest, myChoices: myChoices, isCasting: sending != nil, sendingPill: sending,
            canTapPill: { _ in sending == nil }, onVote: { _ in }, onOpenRequest: { _ in },
            headerHint: contest.contenders.isEmpty
                ? nil
                : contest.contenders.count > 1 ? "Opens the requests for this name" : "Opens the request details",
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
#Preview("No requests") { CardPreview.card(CardPreview.contest(requests: 0)) }
#Preview("Several collapsed") { CardPreview.card(CardPreview.contest(requests: 3)) }
#Preview("Several expanded") { CardPreview.card(CardPreview.contest(requests: 3), expanded: true) }
#Preview("Expanded, dates and links") {
    CardPreview.card(CardPreview.contest(requests: 3, dated: true), expanded: true, linked: [0, 2])
}
#Preview("Expanded, one request undated") {
    let dated = CardPreview.contest(requests: 2, dated: true)
    let contest = DPNSContest(
        normalizedLabel: dated.normalizedLabel, endTime: nil, hasWinner: false, abstainVotes: 0, lockVotes: 3,
        contenders: dated.contenders + [DPNSContender(identityId: "identity3NoDateXk3vQ9mT2pLw8RzYb5", voteTally: 1)])
    return CardPreview.card(contest, expanded: true, linked: [2])
}
#Preview("Sending") { CardPreview.card(CardPreview.contest(requests: 1), sending: .lock) }
#Preview("Sending, several expanded") {
    let contest = CardPreview.contest(requests: 3)
    return CardPreview.card(
        contest, expanded: true, sending: .towards(identityId: contest.contenders[1].identityId))
}
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
