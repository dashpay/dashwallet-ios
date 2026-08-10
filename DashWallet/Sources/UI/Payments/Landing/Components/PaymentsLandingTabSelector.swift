//
//  PaymentsLandingTabSelector.swift
//  DashWallet
//
//  The Receive / Internal / Send switcher at the top of the payments landing.
//

import SwiftUI
import DashUIKit

/// Segmented switcher for the landing's hero tabs.
///
/// Takes the tabs and a binding rather than the view model: which tabs are
/// offered is the presentation's decision — the full landing shows all three,
/// the balance-row receive sheet narrows to two — and this view has no reason
/// to know why.
struct PaymentsLandingTabSelector: View {

    private enum Layout {
        static let spacing: CGFloat = 4
        static let itemSpacing: CGFloat = 4
        static let itemPadding: CGFloat = 10
        static let itemCornerRadius: CGFloat = 8
        static let cornerRadius: CGFloat = 10
    }

    let tabs: [PaymentsLandingTab]
    @Binding var selection: PaymentsLandingTab

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: Layout.spacing) {
            ForEach(tabs) { tab in
                Button { selection = tab } label: {
                    item(for: tab)
                }
            }
        }
        .padding(Layout.spacing)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(Layout.cornerRadius)
    }

    private func item(for tab: PaymentsLandingTab) -> some View {
        let isSelected = selection == tab
        return VStack(spacing: Layout.itemSpacing) {
            Image(systemName: tab.iconSystemName)
                .font(.system(size: 16, weight: .semibold))
            Text(tab.title)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(isSelected ? Color.dash.primaryText : Color.dash.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.itemPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.itemCornerRadius)
                // Selected pill: a solid white raised card in light mode; a
                // translucent light fill in dark so the primaryText label stays
                // legible (pure white would be invisible on the dark selector).
                // Mirrors the app's SegmentedControl selected-fill treatment.
                .fill(isSelected
                    ? (colorScheme == .dark ? Color.dash.whiteAlpha20 : Color.dash.white)
                    : Color.clear)
                .shadow(color: isSelected ? Color.dash.shadow : .clear, radius: 2, x: 0, y: 1))
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

#Preview("All three") {
    TabSelectorHost(tabs: PaymentsLandingTab.allCases, selection: .send)
}

/// The balance-row receive sheet offers only two — the pill has to fill the
/// wider slots without the layout shifting.
#Preview("Narrowed") {
    TabSelectorHost(tabs: [.receive, .internalTransfer], selection: .receive)
}

#Preview("Dark") {
    TabSelectorHost(tabs: PaymentsLandingTab.allCases, selection: .internalTransfer)
        .preferredColorScheme(.dark)
}

#endif
