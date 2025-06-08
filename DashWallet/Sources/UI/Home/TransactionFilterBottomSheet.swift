import SwiftUI
import UIKit

struct TransactionFilterBottomSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selectedFilter: HomeTxDisplayMode
    var shouldShowRewards: Bool
    var onFilterSelected: (HomeTxDisplayMode) -> Void
    
    private let filterOptions: [FilterOption] = [
        FilterOption(mode: .all, title: NSLocalizedString("All", comment: ""), icon: "list.bullet"),
        FilterOption(mode: .received, title: NSLocalizedString("Received", comment: ""), icon: "arrow.down.circle"),
        FilterOption(mode: .sent, title: NSLocalizedString("Sent", comment: ""), icon: "arrow.up.circle"),
        FilterOption(mode: .rewards, title: NSLocalizedString("Rewards", comment: ""), icon: "gift.circle")
    ]
    
    var body: some View {
        BottomSheet(
            title: NSLocalizedString("Filter Transactions", comment: ""),
            showBackButton: .constant(false)
        ) {
            VStack(spacing: 0) {
                ForEach(availableFilters) { option in
                    FilterOptionRow(
                        option: option,
                        isSelected: option.mode == selectedFilter
                    ) {
                        onFilterSelected(option.mode)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(Color.primaryBackground)
    }
    
    private var availableFilters: [FilterOption] {
        var filters = filterOptions.filter { $0.mode != .rewards }
        
        if shouldShowRewards {
            let account = DWEnvironment.sharedInstance().currentAccount
            if account.hasCoinbaseTransaction {
                filters.append(filterOptions.first { $0.mode == .rewards }!)
            }
        }
        
        return filters
    }
}

struct FilterOption: Identifiable {
    let id = UUID()
    let mode: HomeTxDisplayMode
    let title: String
    let icon: String
}

struct FilterOptionRow: View {
    let option: FilterOption
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: option.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.dashBlue)
                    .frame(width: 24, height: 24)
                
                Text(option.title)
                    .font(.body2)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.dashBlue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.dashBlue.opacity(0.05) : Color.secondaryBackground)
            )
        }
        .padding(.bottom, 8)
    }
}

#Preview {
    TransactionFilterBottomSheet(
        selectedFilter: .constant(.all),
        shouldShowRewards: true,
        onFilterSelected: { _ in }
    )
} 