import SwiftUI
import UIKit

struct TransactionFilterDialog: View {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selectedFilter: HomeTxDisplayMode
    var onFilterSelected: (HomeTxDisplayMode) -> Void
    
    private let filterOptions: [FilterOption] = [
        FilterOption(mode: .all, title: NSLocalizedString("All", comment: ""), icon: .custom("image.filter.options")),
        FilterOption(mode: .sent, title: NSLocalizedString("Sent", comment: ""), icon: .custom("tx.item.sent.icon")),
        FilterOption(mode: .received, title: NSLocalizedString("Received", comment: ""), icon: .custom("tx.item.received.icon")),
        FilterOption(mode: .giftCard, title: NSLocalizedString("Gift card", comment: ""), icon: .custom("image.dashspend.giftcard"))
    ]
    
    var body: some View {
        BottomSheet(
            title: NSLocalizedString("Filter transactions", comment: ""),
            showBackButton: .constant(false)
        ) {
            VStack(spacing: 0) {
                ForEach(filterOptions) { option in
                    FilterOptionRow(
                        option: option,
                        isSelected: option.mode == selectedFilter
                    ) {
                        onFilterSelected(option.mode)
                        presentationMode.wrappedValue.dismiss()
                    }
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
}

struct FilterOption: Identifiable {
    let id = UUID()
    let mode: HomeTxDisplayMode
    let title: String
    let icon: IconName
}

struct FilterOptionRow: View {
    let option: FilterOption
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 16) {
                Icon(name: option.icon)
                    .frame(width: 30, height: 30)
                    .padding(.vertical, 16)
                
                Text(option.title)
                    .font(.body2)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)
                
                Spacer()
                
                Circle()
                    .stroke(isSelected ? Color.dashBlue : Color.gray300.opacity(0.5), lineWidth: isSelected ? 6 : 2)
                    .frame(width: isSelected ? 21 : 24, height: isSelected ? 21 : 24)
                    .padding(.trailing, isSelected ? 2 : 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
