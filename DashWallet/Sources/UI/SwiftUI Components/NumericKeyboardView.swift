import SwiftUI

struct NumericKeyboardView: View {
    @Binding var value: String
    let showDecimalSeparator: Bool
    let actionButtonText: String
    let actionEnabled: Bool
    let inProgress: Bool
    let actionHandler: () -> Void
    
    private var rows: [[String]] {
        let lastRow: [String]
        if showDecimalSeparator {
            lastRow = [".", "0", "⌫"]
        } else {
            lastRow = ["", "0", "⌫"]
        }
        
        return [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            lastRow
        ]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { key in
                        Button(action: {
                            handleKeyPress(key)
                        }) {
                            if key == "⌫" {
                                Image(systemName: "delete.left")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .font(.system(size: 20))
                                    .foregroundColor(.primaryText)
                            } else {
                                Text(key)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.primaryText)
                            }
                        }
                        .disabled(inProgress)
                    }
                }
                .opacity(inProgress ? 0.5 : 1.0)
            }
            
            DashButton(
                text: actionButtonText,
                isEnabled: !value.isEmpty && actionEnabled,
                isLoading: inProgress,
                action: actionHandler
            )
            .padding(.top, 20)
        }
        .background(Color.secondaryBackground)
    }
    
    private func handleKeyPress(_ key: String) {
        if key == "⌫" {
            if !value.isEmpty {
                value.removeLast()
            }
        } else if key == "." {
            if showDecimalSeparator && !value.contains(".") {
                value += "."
            }
        } else if !key.isEmpty {
            value += key
        }
    }
}

#Preview {
    NumericKeyboardView(
        value: .constant(""),
        showDecimalSeparator: true,
        actionButtonText: NSLocalizedString("Verify", comment: "Button title for numeric keyboard action"),
        actionEnabled: true,
        inProgress: false,
        actionHandler: { print("Action button tapped") }
    ).frame(height: 400)
}
