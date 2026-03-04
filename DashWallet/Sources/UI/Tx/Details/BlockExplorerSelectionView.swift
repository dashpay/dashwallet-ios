import SwiftUI

struct BlockExplorerSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    var onExplorerSelected: (BlockExplorer) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
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
                                .frame(width: 24, height: 24)
                            
                            Text(explorer.title)
                                .font(.subhead)
                                .fontWeight(.medium)
                                .foregroundColor(.primaryText)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(6)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .shadow, radius: 5, y: 2)
            .padding(.horizontal, 20)
            .padding(.vertical, 40)
        }
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
            return "dashCurrency"
        }
    }
}

#Preview {
    BlockExplorerSelectionView { explorer in
        print("Selected explorer: \(explorer)")
    }
} 
