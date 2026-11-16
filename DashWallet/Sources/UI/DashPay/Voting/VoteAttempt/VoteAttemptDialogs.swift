//
//  VoteAttemptDialogs.swift
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

import SwiftUI

// MARK: - VoteAttemptDialog

/// The dialogs of a vote attempt: "One vote left" (SCR-07), "No votes left"
/// (SCR-08) and the lock-is-final confirmation (SCR-09), and Quick voting's
/// "One vote left" for the names getting their last vote.
struct VoteAttemptDialog: View {
    enum Kind: Equatable {
        case oneVoteLeft
        case noVotesLeft
        /// On a last vote the block cannot be taken back, so the dialog does not offer it.
        case confirmBlock(username: String, isLastVote: Bool)
        /// Quick voting: these names get their last vote (AC-18).
        case lastVotes(usernames: [String])
    }

    let kind: Kind
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch kind {
        case .oneVoteLeft:
            LegacyModalDialog(
                style: .warning,
                heading: NSLocalizedString("One vote left", comment: "Voting"),
                textBlock1: NSLocalizedString(
                    "You have already voted for this username 4 times. You can only cast one more vote for this username.",
                    comment: "Voting"),
                positiveButtonText: NSLocalizedString("Vote", comment: "Voting"),
                positiveButtonAction: onConfirm,
                negativeButtonText: NSLocalizedString("Cancel", comment: ""),
                negativeButtonAction: onDismiss)
        case .noVotesLeft:
            LegacyModalDialog(
                style: .warning,
                heading: NSLocalizedString("No votes left", comment: "Voting"),
                textBlock1: NSLocalizedString(
                    "You have already voted for this username 5 times. You cannot vote on it any more.",
                    comment: "Voting"),
                positiveButtonText: NSLocalizedString("OK", comment: ""),
                positiveButtonAction: onDismiss)
        case .confirmBlock(let username, let isLastVote):
            LegacyModalDialog(
                style: .error,
                heading: String(format: NSLocalizedString("Block %@?", comment: "Voting"), username),
                textBlock1: isLastVote
                    ? NSLocalizedString(
                        "If block wins when voting ends, nobody can ever request this username again.",
                        comment: "Voting")
                    : NSLocalizedString(
                        "If block wins when voting ends, nobody can ever request this username again. You can cancel your vote until voting ends.",
                        comment: "Voting"),
                positiveButtonText: NSLocalizedString("Block", comment: "Voting"),
                positiveButtonAction: onConfirm,
                negativeButtonText: NSLocalizedString("Cancel", comment: ""),
                negativeButtonAction: onDismiss,
                buttonsStyle: .danger)
        case .lastVotes(let usernames):
            LastVotesDialog(usernames: usernames, onConfirm: onConfirm, onDismiss: onDismiss)
        }
    }
}

/// Quick voting's "One vote left": the names stay behind «Show all usernames»,
/// and the dialog scrolls when they are many, so the buttons stay reachable.
private struct LastVotesDialog: View {
    let usernames: [String]
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    @State private var showsUsernames = false

    var body: some View {
        GeometryReader { space in
            ScrollView {
                dialog.frame(maxWidth: .infinity, minHeight: space.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var dialog: some View {
        LegacyModalDialog(
            style: .warning,
            heading: NSLocalizedString("One vote left", comment: "Voting"),
            textBlock1: NSLocalizedString(
                "This is your last vote for some of these usernames. After it, you cannot vote on them again.",
                comment: "Voting: Quick voting"),
            textBlock2: showsUsernames ? usernames.joined(separator: ", ") : nil,
            smallButtonText: showsUsernames ? nil : NSLocalizedString("Show all usernames", comment: "Voting"),
            smallButtonIcon: .system("plus"),
            smallButtonAction: { showsUsernames = true },
            positiveButtonText: NSLocalizedString("Vote", comment: "Voting"),
            positiveButtonAction: onConfirm,
            negativeButtonText: NSLocalizedString("Cancel", comment: ""),
            negativeButtonAction: onDismiss)
    }
}

extension VoteAttemptCoordinator.Presentation {
    /// The dialog this presentation shows; `nil` for the keys sheet.
    var dialog: VoteAttemptDialog.Kind? {
        switch self {
        case .oneVoteLeft: return .oneVoteLeft
        case .noVotesLeft: return .noVotesLeft
        case .confirmBlock(let username, let isLastVote): return .confirmBlock(username: username, isLastVote: isLastVote)
        case .addKeys: return nil
        }
    }
}

// MARK: - Previews

#if DEBUG
private struct VoteAttemptDialogPreview: View {
    let kind: VoteAttemptDialog.Kind

    var body: some View {
        VoteAttemptDialog(kind: kind, onConfirm: {}, onDismiss: {})
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dash.backgroundOverlay)
    }
}

#Preview("One vote left") {
    VoteAttemptDialogPreview(kind: .oneVoteLeft)
}

#Preview("No votes left") {
    VoteAttemptDialogPreview(kind: .noVotesLeft)
}

#Preview("Block") {
    VoteAttemptDialogPreview(kind: .confirmBlock(username: "johndoe", isLastVote: false))
}

#Preview("Block, last vote") {
    VoteAttemptDialogPreview(kind: .confirmBlock(username: "johndoe", isLastVote: true))
}

#Preview("Quick voting, last votes") {
    VoteAttemptDialogPreview(kind: .lastVotes(usernames: ["johndoe", "dreamchaser22", "alice"]))
}

#Preview("Quick voting, many last votes") {
    VoteAttemptDialogPreview(kind: .lastVotes(usernames: (1...150).map { "username\($0)" }))
}

#Preview("Block, long name") {
    VoteAttemptDialogPreview(kind: .confirmBlock(username: "a-very-long-requested-username-or-another-one", isLastVote: false))
}
#endif
