import DashUIKit
import SwiftUI

/// Multi-select transaction filter: one checkbox per category plus an "Only"
/// shortcut per row, applied live through the binding (the sheet stays open
/// while toggling). The "All" row checks every box; a fully checked selection
/// means "show everything", including transactions that fit no category
/// (internal transfers, CoinJoin mixing groups). The Rewards and Masternode
/// rows are offered only when the wallet has ever had a masternode/mining
/// reward or a masternode special transaction, respectively.
struct TransactionFilterDialog: View {
    @Binding var selectedFilters: Set<TransactionFilterCategory>
    let showRewards: Bool
    let showMasternode: Bool

    /// Sheet detent height for the current row count (options + the All row),
    /// matching the BottomSheet's title + row + padding metrics.
    static func height(showRewards: Bool, showMasternode: Bool) -> CGFloat {
        let rows = 6 + (showRewards ? 1 : 0) + (showMasternode ? 1 : 0)
        return CGFloat(134 + rows * 54)
    }

    private var filterOptions: [FilterOption] {
        var options = [
            FilterOption(category: .sent, title: NSLocalizedString("Sent", comment: ""), icon: .custom("tx.item.sent.icon")),
            FilterOption(category: .received, title: NSLocalizedString("Received", comment: ""), icon: .custom("tx.item.received.icon"))
        ]
        if showRewards {
            options.append(FilterOption(category: .rewards, title: NSLocalizedString("Rewards", comment: "Transaction filter"), icon: .system("trophy")))
        }
        if showMasternode {
            options.append(FilterOption(category: .masternode, title: NSLocalizedString("Masternode", comment: "Transaction filter"), icon: .system("server.rack")))
        }
        options.append(contentsOf: [
            FilterOption(category: .giftCard, title: NSLocalizedString("Gift card", comment: ""), icon: .custom("image.dashspend.giftcard")),
            FilterOption(category: .shieldedSent, title: NSLocalizedString("Shielded sent", comment: "Transaction filter"), icon: .system("shield.fill")),
            FilterOption(category: .shieldedReceived, title: NSLocalizedString("Shielded received", comment: "Transaction filter"), icon: .system("shield"))
        ])
        return options
    }

    private var offeredCategories: Set<TransactionFilterCategory> {
        Set(filterOptions.map { $0.category })
    }

    private var allChecked: Bool {
        selectedFilters.isSuperset(of: offeredCategories)
    }

    var body: some View {
        BottomSheet(
            title: NSLocalizedString("Filter transactions", comment: ""),
            showBackButton: .constant(false)
        ) {
            VStack(spacing: 4) {
                FilterCheckboxRow(
                    title: NSLocalizedString("All", comment: ""),
                    icon: .custom("image.filter.options"),
                    isChecked: allChecked,
                    onToggle: {
                        selectedFilters = Set(TransactionFilterCategory.allCases)
                    }
                )

                ForEach(filterOptions) { option in
                    FilterCheckboxRow(
                        title: option.title,
                        icon: option.icon,
                        isChecked: selectedFilters.contains(option.category),
                        onOnly: {
                            selectedFilters = [option.category]
                        },
                        onToggle: {
                            toggle(option.category)
                        }
                    )
                }
            }
            .padding(.vertical, 6)
            .background(Color.secondaryBackground)
            .clipShape(RoundedShape(corners: .allCorners, radii: 12))
            .padding(.horizontal, 20)
            .padding(.top, 25)
        }
        .background(Color.primaryBackground)
    }

    private func toggle(_ category: TransactionFilterCategory) {
        var selection = selectedFilters
        if selection.contains(category) {
            selection.remove(category)
            // Never allow an empty filter — the last checked box stays checked.
            if selection.intersection(offeredCategories).isEmpty {
                return
            }
        } else {
            selection.insert(category)
        }
        selectedFilters = selection
    }
}

private struct FilterCheckboxRow: View {
    let title: String
    let icon: IconName
    let isChecked: Bool
    var onOnly: (() -> Void)? = nil
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Icon(name: icon)
                    .frame(width: 30, height: 30)

                Text(title)
                    .font(.subhead)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)

                Spacer()

                if let onOnly = onOnly {
                    Button(action: onOnly) {
                        Text(NSLocalizedString("Only", comment: "Transaction filter"))
                            .font(.subhead)
                            .fontWeight(.medium)
                            .foregroundColor(.dashBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Image(isChecked ? "icon_checkbox_square_checked" : "icon_checkbox_square")
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .frame(minHeight: 54)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct FilterOption: Identifiable {
    let category: TransactionFilterCategory
    let title: String
    let icon: IconName

    var id: TransactionFilterCategory { category }
}
