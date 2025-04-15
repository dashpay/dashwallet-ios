import SwiftUI

struct NumericKeyboardView: View {
    @Binding var value: String
    let actionButtonText: String
    let actionHandler: () -> Void
    
    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "⌫"]
    ]
    
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
                    }
                }
            }
            
            DashButton(
                text: actionButtonText,
                isEnabled: !value.isEmpty,
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
        } else if key != "." && !key.isEmpty {
            value += key
        }
    }
}

#Preview {
    NumericKeyboardView(
        value: .constant(""),
        actionButtonText: NSLocalizedString("Verify", comment: "Button title for numeric keyboard action"),
        actionHandler: { print("Action button tapped") }
    ).frame(height: 400)
}
