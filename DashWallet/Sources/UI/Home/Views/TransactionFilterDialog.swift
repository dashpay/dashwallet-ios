import SwiftUI
import UIKit

struct TransactionFilterDialog: View {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selectedFilter: HomeTxDisplayMode
    var shouldShowRewards: Bool
    var onFilterSelected: (HomeTxDisplayMode) -> Void
    
    private let filterOptions: [FilterOption] = [
        FilterOption(mode: .all, title: NSLocalizedString("All", comment: ""), icon: .system("line.horizontal.3"), color: .dashBlue),
        FilterOption(mode: .sent, title: NSLocalizedString("Sent", comment: ""), icon: .system("arrow.up"), color: .dashBlue),
        FilterOption(mode: .received, title: NSLocalizedString("Received", comment: ""), icon: .system("arrow.down"), color: Color.green),
        FilterOption(mode: .rewards, title: NSLocalizedString("Gift card", comment: ""), icon: .system("gift"), color: Color.orange)
    ]
    
    var body: some View {
        BottomSheet(
            title: NSLocalizedString("Filter transactions", comment: ""),
            showBackButton: .constant(false)
        ) {
            VStack(spacing: 24) {
                ForEach(availableFilters) { option in
                    FilterOptionRow(
                        option: option,
                        isSelected: option.mode == selectedFilter
                    ) {
                        onFilterSelected(option.mode)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)
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
    let icon: IconName
    let color: Color
}

struct FilterOptionRow: View {
    let option: FilterOption
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(option.color)
                        .frame(width: 40, height: 40)
                    
                    Icon(name: option.icon)
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .medium))
                }
                
                // Title
                Text(option.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primaryText)
                
                Spacer()
                
                // Radio button
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.dashBlue : Color.gray400, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.dashBlue)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TransactionFilterDialog(
        selectedFilter: .constant(.all),
        shouldShowRewards: true,
        onFilterSelected: { _ in }
    )
} 
