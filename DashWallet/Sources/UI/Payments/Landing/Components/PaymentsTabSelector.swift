//
//  Created by Roman Chornyi
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
import DashUIKit

/// The payments landing's Receive / Internal / Send selector: an arrow icon
/// over a label per segment, the selected one raised on a filled pill.
///
/// The drawing is the app's `SegmentedControl` in its icon variant, not a
/// local lookalike. The landing used to hand-roll the same pill and had already
/// drifted from it — flatter corners, a tighter shadow — while also missing the
/// sliding indicator, drag-to-select and the `.isSelected` accessibility trait
/// the shared control provides.
///
/// What stays here is the landing's own decision: which tabs to offer, and how
/// a `PaymentsLandingTab` names and illustrates itself. The balance-row sheets
/// narrow the list to two, so the caller passes it in rather than the selector
/// reading `PaymentsLandingViewModel`.
struct PaymentsTabSelector: View {
    let tabs: [PaymentsLandingTab]
    @Binding var selection: PaymentsLandingTab

    var body: some View {
        SegmentedControl(
            options: tabs,
            selection: $selection,
            label: { $0.title },
            icon: { $0.iconSystemName })
    }
}

#if DEBUG

/// Live selection, so the canvas exercises the tap path rather than a frozen
/// snapshot of one state.
private struct PaymentsTabSelectorPreview: View {
    let tabs: [PaymentsLandingTab]
    @State private var selection: PaymentsLandingTab

    init(tabs: [PaymentsLandingTab] = PaymentsLandingTab.allCases,
         selection: PaymentsLandingTab = .internalTransfer) {
        self.tabs = tabs
        _selection = State(initialValue: selection)
    }

    var body: some View {
        PaymentsTabSelector(tabs: tabs, selection: $selection)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.dash.primaryBackground)
    }
}

@available(iOS 17, *)
#Preview("Three tabs") {
    PaymentsTabSelectorPreview()
}

/// Each end of the track — the pill's corners sit inside the container's, so
/// the first and last segments are where that reads worst.
@available(iOS 17, *)
#Preview("First selected") {
    PaymentsTabSelectorPreview(selection: .receive)
}

@available(iOS 17, *)
#Preview("Last selected") {
    PaymentsTabSelectorPreview(selection: .send)
}

/// The balance-row receive sheet narrows to two tabs — the segments must
/// redistribute rather than leave a gap where Send was.
@available(iOS 17, *)
#Preview("Two tabs") {
    PaymentsTabSelectorPreview(
        tabs: [.receive, .internalTransfer],
        selection: .receive)
}

/// One tab: the pill spans the whole track.
@available(iOS 17, *)
#Preview("One tab") {
    PaymentsTabSelectorPreview(tabs: [.internalTransfer])
}

@available(iOS 17, *)
#Preview("Dark") {
    PaymentsTabSelectorPreview()
        .preferredColorScheme(.dark)
}

/// Labels grow but the icons don't, and the labels are the only thing that can
/// wrap — the widest point for the selected pill.
@available(iOS 17, *)
#Preview("Large type") {
    PaymentsTabSelectorPreview()
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
