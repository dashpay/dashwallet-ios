//
//  VotingFiltersSheet.swift
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

/// Sort, type and duplicates for the voting list (Figma "Voting / Filters").
///
/// Edits a copy of the filter: Apply hands it back, Cancel or a swipe down
/// drops it.
struct VotingFiltersSheet: View {
    let onApply: (VotingFilter) -> Void

    @State private var draft: VotingFilter
    @Environment(\.dismiss) private var dismiss

    init(filter: VotingFilter, onApply: @escaping (VotingFilter) -> Void) {
        _draft = State(initialValue: filter)
        self.onApply = onApply
    }

    var body: some View {
        DashUIKit.BottomSheet(showBackButton: .constant(false), showsCloseButton: false) {
            VStack(spacing: 0) {
                navigationBar
                ScrollView {
                    VStack(spacing: 20) {
                        block(title: NSLocalizedString("Sort by", comment: "Voting")) {
                            ForEach(ContestSort.allCases) { sortRow($0) }
                        }
                        block(title: NSLocalizedString("Type", comment: "Voting")) {
                            ForEach(VotingTypeFilter.allCases) { type in
                                DashUIKit.RadioButtonRow(
                                    title: type.title,
                                    isSelected: draft.type == type,
                                    style: .radio,
                                    highlightsSelectedTitle: true) { draft.type = type }
                            }
                        }
                        card {
                            DashUIKit.RadioButtonRow(
                                title: NSLocalizedString("Only duplicates", comment: "Voting"),
                                isSelected: draft.onlyDuplicates,
                                style: .checkbox) { draft.onlyDuplicates.toggle() }
                        }
                        card {
                            DashUIKit.RadioButtonRow(
                                title: NSLocalizedString("Only requests with links", comment: "Voting"),
                                isSelected: draft.onlyWithLinks,
                                style: .checkbox) { draft.onlyWithLinks.toggle() }
                        }
                        DashUIKit.DashButton(
                            text: NSLocalizedString("Reset filters", comment: "Voting"),
                            isEnabled: draft != .default,
                            fillsWidth: true,
                            size: .large,
                            style: .plainRed) { draft = .default }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var navigationBar: some View {
        DashUIKit.NavigationBar(
            leading: {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Cancel", comment: ""),
                    size: .small,
                    style: .plainBlack) { dismiss() }
            },
            central: {
                Text(NSLocalizedString("Filters", comment: "Voting"))
                    .dashFont(.subheadMedium)
                    .foregroundStyle(Color.dash.primaryText)
                    .accessibilityAddTraits(.isHeader)
            },
            trailing: {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Apply", comment: ""),
                    size: .small,
                    style: .tintedBlue) {
                    onApply(draft)
                    dismiss()
                }
            })
    }

    private func sortRow(_ sort: ContestSort) -> some View {
        DashUIKit.RadioButtonRow(
            title: sort.title,
            isSelected: draft.sort == sort,
            style: .radio,
            highlightsSelectedTitle: true) { draft.sort = sort }
    }

    /// A titled group: "Sort by", "Type".
    private func block<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .dashFont(.footnoteMedium)
                .foregroundStyle(Color.dash.tertiaryText)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            card(content: content)
        }
    }

    /// The design system's menu card around a list of rows.
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 2) {
            content()
        }
        .frame(maxWidth: .infinity)
        .modifier(DashUIKit.MenuViewModifier())
    }
}

#if DEBUG
#Preview("Default") {
    Color.dash.primaryBackground
        .sheet(isPresented: .constant(true)) {
            VotingFiltersSheet(filter: .default) { _ in }
        }
}

#Preview("Changed filter") {
    Color.dash.primaryBackground
        .sheet(isPresented: .constant(true)) {
            VotingFiltersSheet(
                filter: VotingFilter(sort: .votesHighToLow, type: .approved, onlyDuplicates: true)) { _ in }
        }
}

#Preview("Only requests with links") {
    Color.dash.primaryBackground
        .sheet(isPresented: .constant(true)) {
            VotingFiltersSheet(
                filter: VotingFilter(
                    sort: .dateOldToNew, type: .all, onlyDuplicates: true, onlyWithLinks: true)) { _ in }
        }
}

#Preview("Changed filter, dark") {
    Color.dash.primaryBackground
        .sheet(isPresented: .constant(true)) {
            VotingFiltersSheet(
                filter: VotingFilter(sort: .dateNewToOld, type: .hasBlockedVotes, onlyDuplicates: true)) { _ in }
        }
        .preferredColorScheme(.dark)
}
#endif
