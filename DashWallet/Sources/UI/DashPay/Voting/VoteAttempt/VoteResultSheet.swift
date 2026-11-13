//
//  VoteResultSheet.swift
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
import SwiftUI

// MARK: - VoteResultSheet

/// A vote that landed on some masternodes and not on others (SCR-10): what
/// landed and what did not, per masternode, never rounded up to "done" or
/// down to "failed". Try again resends the failed ones only (AC-06b), and
/// is not offered when every failed one has no vote left (AC-15).
struct VoteResultSheet: View {
    let report: VoteCastReport
    let username: String
    let isRetrying: Bool
    let onTryAgain: () -> Void
    let onClose: () -> Void

    var body: some View {
        DashUIKit.BottomSheet(showBackButton: .constant(false), showsCloseButton: false) {
            VStack(alignment: .leading, spacing: 20) {
                DashUIKit.TopIntroView(
                    title: NSLocalizedString("Vote partly cast", comment: "Voting"),
                    mainDescription: Self.summary(of: report, username: username),
                    descriptionColor: Color.dash.secondaryText)

                // Many ticked masternodes or long reasons scroll here, so
                // Close and Try again stay on screen below the report.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(report.outcomes) { outcome in
                            row(outcome)
                        }
                    }
                    .modifier(DashUIKit.MenuViewModifier(shadowRadius: 20))
                    .padding(.vertical, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 360)

                HStack(spacing: 10) {
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Close", comment: ""),
                        fillsWidth: true,
                        size: .large,
                        style: .tintedGray,
                        action: onClose)
                    // Not while every failed masternode has no vote left: a retry cannot land.
                    if report.offersTryAgain {
                        DashUIKit.DashButton(
                            text: NSLocalizedString("Try again", comment: "Voting"),
                            isLoading: isRetrying,
                            fillsWidth: true,
                            size: .large,
                            style: .filledBlue,
                            action: onTryAgain)
                    }
                }
            }
            .padding(20)
        }
    }

    private func row(_ outcome: VoteOutcome) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(outcome.node.serviceAddress ?? outcome.node.displayName)
                .dashFont(.subheadMedium)
                .foregroundStyle(Color.dash.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(Self.status(of: outcome, isRetrying: isRetrying))
                .dashFont(.footnote)
                .foregroundStyle(outcome.succeeded ? Color.dash.green : Color.dash.red)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// "1 of 2 masternodes voted to approve johndoe. The other vote was not cast."
    static func summary(of report: VoteCastReport, username: String) -> String {
        let landed = report.succeeded.count, total = report.outcomes.count
        let format: String
        switch report.choice {
        case .towards:
            format = NSLocalizedString("%1$d of %2$d masternodes voted to approve %3$@.", comment: "Voting")
        case .lock:
            format = NSLocalizedString("%1$d of %2$d masternodes voted to block %3$@.", comment: "Voting")
        case .abstain:
            format = NSLocalizedString("%1$d of %2$d masternodes cancelled their vote on %3$@.", comment: "Voting")
        }
        let notCast = report.failed.count == 1
            ? NSLocalizedString("The other vote was not cast.", comment: "Voting")
            : String(format: NSLocalizedString("The other %d votes were not cast.", comment: "Voting"),
                     report.failed.count)
        return String(format: format, landed, total, username) + " " + notCast
    }

    /// "✓ Voted", "Not cast — <reason>", or "Sending…" while Try again runs.
    static func status(of outcome: VoteOutcome, isRetrying: Bool) -> String {
        if outcome.succeeded { return NSLocalizedString("✓ Voted", comment: "Voting") }
        if isRetrying { return NSLocalizedString("Sending…", comment: "Voting") }
        return String(format: NSLocalizedString("Not cast — %@", comment: "Voting"), outcome.failure ?? "")
    }
}

// MARK: - QuickVotingResultSheet

/// A Quick voting run where some names' votes failed (SCR-10, Quick voting):
/// the names whose votes did not land, each with why. Try again resends the
/// failed votes only (AC-06b), and is not offered when every failed vote has
/// no vote left (AC-15).
struct QuickVotingResultSheet: View {
    let run: QuickVoteRunReport
    let username: (_ normalizedLabel: String) -> String
    let isRetrying: Bool
    let onTryAgain: () -> Void
    let onClose: () -> Void

    var body: some View {
        DashUIKit.BottomSheet(showBackButton: .constant(false), showsCloseButton: false) {
            VStack(alignment: .leading, spacing: 20) {
                DashUIKit.TopIntroView(
                    title: NSLocalizedString("Quick voting partly done", comment: "Voting"),
                    mainDescription: NSLocalizedString(
                        "Some votes were not cast. These usernames were not voted for:", comment: "Voting"),
                    descriptionColor: Color.dash.secondaryText)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(run.reports.filter { !$0.failed.isEmpty }, id: \.normalizedLabel) { report in
                            row(report)
                        }
                    }
                    .modifier(DashUIKit.MenuViewModifier(shadowRadius: 20))
                    .padding(.vertical, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 360)

                HStack(spacing: 10) {
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Close", comment: ""),
                        fillsWidth: true,
                        size: .large,
                        style: .tintedGray,
                        action: onClose)
                    // Not while every failed vote has no vote left: a retry cannot land.
                    if run.offersTryAgain {
                        DashUIKit.DashButton(
                            text: NSLocalizedString("Try again", comment: "Voting"),
                            isLoading: isRetrying,
                            fillsWidth: true,
                            size: .large,
                            style: .filledBlue,
                            action: onTryAgain)
                    }
                }
            }
            .padding(20)
        }
    }

    /// The name, and the reason its first failed vote gives.
    private func row(_ report: VoteCastReport) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(username(report.normalizedLabel))
                .dashFont(.subheadMedium)
                .foregroundStyle(Color.dash.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(isRetrying
                 ? NSLocalizedString("Sending…", comment: "Voting")
                 : String(format: NSLocalizedString("Not cast — %@", comment: "Voting"),
                          report.failed.first?.failure ?? ""))
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.red)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#if DEBUG
private func resultPreviewNode(_ byte: UInt8) -> VoterNode {
    VoterNode(proTxHash: Data([byte]), isEvonode: false, typeIndex: UInt32(byte),
              serviceAddress: "172.16.\(byte).10:9999", keySource: .walletIndex(UInt32(byte)))
}

private let resultPreviewReport = VoteCastReport(
    normalizedLabel: "johndoe",
    choice: .towards(identityId: "contender"),
    outcomes: [
        VoteOutcome(node: resultPreviewNode(1), failure: nil),
        VoteOutcome(node: resultPreviewNode(2), failure: "The network did not answer. Try again in a moment."),
    ])

#Preview("One of two") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VoteResultSheet(report: resultPreviewReport, username: "johndoe", isRetrying: false,
                        onTryAgain: {}, onClose: {})
    }
}

private let quickRunPreview = QuickVoteRunReport(reports: [
    VoteCastReport(normalizedLabel: "alice", choice: .towards(identityId: "a"),
                   outcomes: [VoteOutcome(node: resultPreviewNode(1), failure: nil)]),
    VoteCastReport(normalizedLabel: "johndoe", choice: .towards(identityId: "j"),
                   outcomes: [VoteOutcome(node: resultPreviewNode(1), failure: "The network did not answer.")]),
    VoteCastReport(normalizedLabel: "averyveryverylongusernamethatkeepsgoing", choice: .towards(identityId: "v"),
                   outcomes: [VoteOutcome.noVotesLeft(resultPreviewNode(2))]),
])

#Preview("Quick voting, two names failed") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickVotingResultSheet(run: quickRunPreview, username: { $0 }, isRetrying: false,
                               onTryAgain: {}, onClose: {})
    }
}

#Preview("Quick voting, every failure out of votes") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickVotingResultSheet(
            run: QuickVoteRunReport(reports: [
                VoteCastReport(normalizedLabel: "alice", choice: .towards(identityId: "a"),
                               outcomes: [VoteOutcome(node: resultPreviewNode(1), failure: nil)]),
                VoteCastReport(normalizedLabel: "johndoe", choice: .towards(identityId: "j"),
                               outcomes: [VoteOutcome.noVotesLeft(resultPreviewNode(2))]),
            ]),
            username: { $0 }, isRetrying: false, onTryAgain: {}, onClose: {})
    }
}

#Preview("Quick voting, retrying") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickVotingResultSheet(run: quickRunPreview, username: { $0 }, isRetrying: true,
                               onTryAgain: {}, onClose: {})
    }
}

#Preview("Cancel, one masternode out of votes") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VoteResultSheet(
            report: VoteCastReport(
                normalizedLabel: "johndoe",
                choice: .abstain,
                outcomes: [
                    VoteOutcome(node: resultPreviewNode(1), failure: nil),
                    VoteOutcome.noVotesLeft(resultPreviewNode(2)),
                ]),
            username: "johndoe", isRetrying: false,
            onTryAgain: {}, onClose: {})
    }
}

#Preview("Retrying") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VoteResultSheet(report: resultPreviewReport, username: "johndoe", isRetrying: true,
                        onTryAgain: {}, onClose: {})
    }
}

#Preview("Block, three failed, long reason") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VoteResultSheet(
            report: VoteCastReport(
                normalizedLabel: "somelongusernamethatkeepsgoing",
                choice: .lock,
                outcomes: [VoteOutcome(node: resultPreviewNode(1), failure: nil)]
                    + (2...4).map {
                        VoteOutcome(
                            node: resultPreviewNode(UInt8($0)),
                            failure: "This masternode has already voted on this username 5 times.")
                    }),
            username: "somelongusernamethatkeepsgoing", isRetrying: false,
            onTryAgain: {}, onClose: {})
    }
}
#Preview("Twelve masternodes, long reasons") {
    Color.clear.sheet(isPresented: .constant(true)) {
        VoteResultSheet(
            report: VoteCastReport(
                normalizedLabel: "johndoe",
                choice: .towards(identityId: "contender"),
                outcomes: (1...12).map {
                    VoteOutcome(
                        node: resultPreviewNode(UInt8($0)),
                        failure: $0.isMultiple(of: 3)
                            ? nil : "The network did not answer in time. Check your connection and try again.")
                }),
            username: "johndoe", isRetrying: false,
            onTryAgain: {}, onClose: {})
    }
}
#endif
