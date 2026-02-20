import SwiftUI

struct BlockExplorerSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    var onExplorerSelected: (BlockExplorer) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("Select block explorer", comment: "Block explorer selection title"))
                .font(.calloutMedium)
                .foregroundColor(.primaryText)
                .padding(.vertical, 16)
            
            VStack(spacing: 2) {
                ForEach(BlockExplorer.allCases) { explorer in
                    Button(action: {
                        onExplorerSelected(explorer)
                        dismiss()
                    }) {
                        HStack(spacing: 16) {
                            Image(explorer.iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 26, height: 26)
                            
                            Text(explorer.title)
                                .font(.subhead)
                                .foregroundColor(.primaryText)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(6)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .shadow, radius: 5, y: 2)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryBackground)
    }
}

enum BlockExplorer: String, CaseIterable, Identifiable {
    case blockchair
    case insight
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .blockchair:
            return "Blockchair"
        case .insight:
            return "Insight"
        }
    }
    
    var iconName: String {
        switch self {
        case .blockchair:
            return "blockchair_logo"
        case .insight:
            return "insight_logo"
        }
    }
}

#Preview {
    BlockExplorerSelectionView { explorer in
        print("Selected explorer: \(explorer)")
    }
} 