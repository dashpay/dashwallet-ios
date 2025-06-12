import SwiftUI
import UIKit

struct TransactionFilterDialog: View {
    @Environment(\.presentationMode) private var presentationMode
    let selectedFilter: HomeTxDisplayMode
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
                    RadioButtonRow(
                        title: option.title,
                        icon: option.icon,
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

