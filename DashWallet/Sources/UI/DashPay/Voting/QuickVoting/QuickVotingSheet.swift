//
//  QuickVotingSheet.swift
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

// MARK: - QuickVotingSheet

/// The Quick voting confirmation (SCR-06): how many of the names on screen get
/// an approve for their first request and how many are skipped, with Cancel
/// and «Vote for all»; Close only when no name can get a vote.
struct QuickVotingSheet: View {
    let votedCount: Int
    let skippedCount: Int
    /// "Only requests with links" is on, so the first *linked* request gets
    /// the approve, which may not be the one submitted first (AC-18).
    var approvesLinkedRequests = false
    let onVote: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // Sized to its content, over the list, as in the design (3830:20930).
        DashUIKit.BottomSheet.selfSizing(showBackButton: .constant(false), showsCloseButton: false) {
            VStack(alignment: .leading, spacing: 20) {
                DashUIKit.TopIntroView(
                    title: NSLocalizedString("Quick voting", comment: "Voting"),
                    mainDescription: Self.description(
                        votedCount: votedCount, skippedCount: skippedCount,
                        approvesLinkedRequests: approvesLinkedRequests),
                    descriptionColor: Color.dash.secondaryText)

                if votedCount > 0 {
                    HStack(spacing: 10) {
                        DashUIKit.DashButton(
                            text: NSLocalizedString("Cancel", comment: ""),
                            fillsWidth: true,
                            size: .large,
                            style: .tintedGray,
                            action: onCancel)
                        DashUIKit.DashButton(
                            text: NSLocalizedString("Vote for all", comment: "Voting"),
                            fillsWidth: true,
                            size: .large,
                            style: .filledBlue,
                            action: onVote)
                    }
                } else {
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Close", comment: ""),
                        fillsWidth: true,
                        size: .large,
                        style: .tintedGray,
                        action: onCancel)
                }
            }
            .padding(20)
        }
    }

    /// «By tapping Vote for all, you approve the request submitted first for
    /// 95 usernames. 5 usernames are skipped.» With links only, «…the linked
    /// request submitted first…».
    static func description(votedCount: Int, skippedCount: Int, approvesLinkedRequests: Bool = false) -> String {
        guard votedCount > 0 else {
            return NSLocalizedString("None of the filtered usernames can get a vote.", comment: "Voting")
        }
        let format = approvesLinkedRequests
            ? NSLocalizedString("Vote for all approves the linked request for %d usernames", comment: "Voting: Quick voting sheet")
            : NSLocalizedString("Vote for all approves %d usernames", comment: "Voting: Quick voting sheet")
        let voted = String.localizedStringWithFormat(format, votedCount)
        guard skippedCount > 0 else { return voted }
        let skipped = String.localizedStringWithFormat(
            NSLocalizedString("%d usernames are skipped", comment: "Voting: Quick voting sheet"),
            skippedCount)
        return voted + " " + skipped
    }
}

// MARK: - Previews

#if DEBUG
#Preview("95 to vote, 5 skipped") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickVotingSheet(votedCount: 95, skippedCount: 5, onVote: {}, onCancel: {})
    }
}

#Preview("One to vote, none skipped") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickVotingSheet(votedCount: 1, skippedCount: 0, onVote: {}, onCancel: {})
    }
}

#Preview("Only requests with links") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickVotingSheet(votedCount: 12, skippedCount: 2, approvesLinkedRequests: true, onVote: {}, onCancel: {})
    }
}

#Preview("Nothing to vote") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickVotingSheet(votedCount: 0, skippedCount: 3, onVote: {}, onCancel: {})
    }
}

#Preview("Dark") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickVotingSheet(votedCount: 1_234, skippedCount: 1, onVote: {}, onCancel: {})
    }
    .preferredColorScheme(.dark)
}
#endif
