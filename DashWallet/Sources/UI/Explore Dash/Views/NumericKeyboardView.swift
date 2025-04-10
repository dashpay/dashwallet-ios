import SwiftUI

struct NumericKeyboardView: View {
    @Binding var value: String
    
    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"]
    ]
    
    var body: some View {
        VStack(spacing: 1) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(row, id: \.self) { key in
                        Button(action: {
                            handleKeyPress(key)
                        }) {
                            if key == "⌫" {
                                Image(systemName: "delete.left")
                                    .font(.system(size: 24))
                            } else if key.isEmpty {
                                Color.clear
                            } else {
                                Text(key)
                                    .font(.system(size: 24, weight: .medium))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.primaryBackground)
                        .foregroundColor(.primaryText)
                    }
                }
            }
        }
        .background(Color.gray300)
    }
    
    private func handleKeyPress(_ key: String) {
        if key == "⌫" {
            if !value.isEmpty {
                value.removeLast()
            }
        } else if !key.isEmpty {
            value += key
        }
    }
}

struct NumericKeyboardView_Previews: PreviewProvider {
    static var previews: some View {
        NumericKeyboardView(value: .constant(""))
            .frame(height: 200)
    }
} 
