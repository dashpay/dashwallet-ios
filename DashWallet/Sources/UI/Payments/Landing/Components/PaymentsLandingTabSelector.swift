//
//  PaymentsLandingTabSelector.swift
//  DashWallet
//
//  The Receive / Internal transfer / Send switcher at the top of the payments
//  landing.
//

import SwiftUI
import DashUIKit

/// A row of pills, one per tab. The active one carries the tab's colour and
/// its label and takes the space that is left; the others shrink to their
/// icon.
///
/// Takes the tabs and a binding rather than the view model: which tabs are
/// offered is the presentation's decision — the full landing shows all three,
/// the balance-row receive sheet narrows to two — and this view has no reason
/// to know why.
struct PaymentsLandingTabSelector: View {

    private enum Layout {
        static let spacing: CGFloat = 8
        static let contentGap: CGFloat = 8
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 10
        /// The inactive pill holds its icon and nothing else, so it is sized
        /// rather than left to hug — otherwise the three widths would shift
        /// with each glyph.
        static let collapsedWidth: CGFloat = 60
        /// Height of the box the glyph is centred in, whatever its own size.
        static let glyphBoxHeight: CGFloat = 20
    }

    let tabs: [PaymentsLandingTab]
    @Binding var selection: PaymentsLandingTab

    var body: some View {
        HStack(spacing: Layout.spacing) {
            ForEach(tabs) { tab in
                Button { selection = tab } label: {
                    pill(for: tab)
                }
                .buttonStyle(.plain)
            }
        }
        // Scoped to the pills rather than wrapping the binding write in
        // `withAnimation`: that would animate whatever else observes the
        // selection — the whole tab's content — which is the host's call to
        // make, not this view's.
        .animation(.snappy(duration: 0.25), value: selection)
    }

    @ViewBuilder
    private func pill(for tab: PaymentsLandingTab) -> some View {
        let isSelected = selection == tab

        HStack(spacing: Layout.contentGap) {
            icon(for: tab)

            if isSelected {
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dash.whiteText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    // Fades rather than appearing at full width: the pill is
                    // still growing underneath it, and a hard cut reads as a
                    // second, competing change.
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        // Selected takes what's left; the rest keep the fixed icon width.
        .frame(maxWidth: isSelected ? .infinity : Layout.collapsedWidth)
        .background(isSelected ? tab.accent : Color.dash.gray300Alpha20)
        .clipShape(Capsule())
    }

    private func icon(for tab: PaymentsLandingTab) -> some View {
        // Both dimensions are set from the design: the three glyphs have
        // different aspect ratios, and a single square frame would squash
        // the arrows.
        Image(tab.icon.name)
            .resizable()
            .frame(width: tab.icon.width, height: tab.icon.height)
            .foregroundStyle(selection == tab ? Color.dash.whiteText : Color.dash.secondaryText)
            .frame(height: Layout.glyphBoxHeight)
    }
}

#if DEBUG

private struct TabSelectorHost: View {
    let tabs: [PaymentsLandingTab]
    @State var selection: PaymentsLandingTab

    var body: some View {
        PaymentsLandingTabSelector(tabs: tabs, selection: $selection)
            .padding()
            .background(Color.dash.primaryBackground)
    }
}

/// One per state — the active pill's fill is the tab's own colour, so the
/// three look materially different.
#Preview("Receive") {
    TabSelectorHost(tabs: PaymentsLandingTab.allCases, selection: .receive)
}

#Preview("Internal transfer") {
    TabSelectorHost(tabs: PaymentsLandingTab.allCases, selection: .internalTransfer)
}

#Preview("Send") {
    TabSelectorHost(tabs: PaymentsLandingTab.allCases, selection: .send)
}

/// The balance-row receive sheet offers two, so the active pill grows wider.
#Preview("Narrowed") {
    TabSelectorHost(tabs: [.receive, .internalTransfer], selection: .receive)
}

#Preview("Dark") {
    TabSelectorHost(tabs: PaymentsLandingTab.allCases, selection: .send)
        .preferredColorScheme(.dark)
}

#endif
