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

/// Picks which masternodes cast the next vote.
///
/// The selection is remembered (``VotingPrefs/votingNodeSelection``) so the
/// next contest opens with the same nodes ticked — the user sets their voting
/// posture once rather than re-deciding under time pressure on every name.
///
/// Voting with several nodes at once is a privacy trade-off the user cannot
/// undo: the transitions land together and let an observer group those
/// masternodes as one operator. The sheet states that rather than burying it,
/// and never pre-ticks every node on the user's behalf.
struct VotingNodeSelectionSheet: View {
    let nodes: [VoterNode]
    @Binding var selectedNodeIDs: Set<Data>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(nodes) { node in
                        Button {
                            toggle(node)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(node.displayName)
                                        .foregroundColor(Color.dash.primaryText)
                                    if let service = node.serviceAddress, !service.isEmpty {
                                        Text(service)
                                            .font(.caption)
                                            .foregroundColor(Color.dash.secondaryText)
                                    }
                                }
                                Spacer(minLength: 0)
                                if selectedNodeIDs.contains(node.proTxHash) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle(NSLocalizedString("Vote with", comment: "Voting"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                        // The vote button keys off this selection, so an empty
                        // one would leave the user on a screen whose primary
                        // action silently does nothing.
                        .disabled(selectedNodeIDs.isEmpty)
                }
            }
        }
    }

    private var footerText: String {
        if selectedNodeIDs.count > 1 {
            return NSLocalizedString(
                "These nodes vote together, which publicly links them to each other. Choosing fewer nodes keeps them unlinked, at less voting weight.",
                comment: "Voting")
        }
        return NSLocalizedString(
            "Only this node votes, so it stays unlinked from your other masternodes. Add more nodes for greater voting weight.",
            comment: "Voting")
    }

    /// Never lets the last node be unticked — an empty selection reads as
    /// "vote with nothing", which is not a state the vote button can act on.
    private func toggle(_ node: VoterNode) {
        if selectedNodeIDs.contains(node.proTxHash) {
            guard selectedNodeIDs.count > 1 else { return }
            selectedNodeIDs.remove(node.proTxHash)
        } else {
            selectedNodeIDs.insert(node.proTxHash)
        }
    }
}
