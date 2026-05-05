import SwiftUI

struct NumericKeyboardView: View {
    private enum Layout {
        static let rootSpacing: CGFloat = 20
        static let rowsSpacing: CGFloat = 10
        static let rowSpacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 40
        static let keyFontSize: CGFloat = 20
        static let keyFontWeight: Font.Weight = .medium
        static let disabledOpacity: CGFloat = 0.5
        static let enabledOpacity: CGFloat = 1.0

        static let decimalKey = "."
        static let zeroKey = "0"
        static let emptyKey = ""
        static let deleteKey = "⌫"
        static let deleteSymbol = "delete.left"
    }

    @Binding var value: String
    let showDecimalSeparator: Bool
    let actionButtonText: String
    let actionEnabled: Bool
    let inProgress: Bool
    let helperText: String? = nil
    let actionHandler: () -> Void
    
    private var rows: [[String]] {
        let lastRow: [String]
        if showDecimalSeparator {
            lastRow = [Layout.decimalKey, Layout.zeroKey, Layout.deleteKey]
        } else {
            lastRow = [Layout.emptyKey, Layout.zeroKey, Layout.deleteKey]
        }
        
        return [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            lastRow
        ]
    }
    
    var body: some View {
        VStack(spacing: Layout.rootSpacing) {
            keyboardRowsView
            helperTextRow(helperText)
            actionButtonView
        }
        .background(Color.secondaryBackground)
    }

    private var keyboardRowsView: some View {
        VStack(spacing: Layout.rowsSpacing) {
            ForEach(rows, id: \.self) { row in
                keyboardRowView(row)
                    .opacity(inProgress ? Layout.disabledOpacity : Layout.enabledOpacity)

            }
        }
    }

    private func keyboardRowView(_ row: [String]) -> some View {
        HStack(spacing: Layout.rowSpacing) {
            ForEach(row, id: \.self) { key in
                keyButtonView(key)
            }
        }
    }

    private func keyButtonView(_ key: String) -> some View {
        Button {
            handleKeyPress(key)
        } label: {
            keyContentView(key)
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .disabled(inProgress)
    }

    @ViewBuilder
    private func keyContentView(_ key: String) -> some View {
        if key == Layout.deleteKey {
            Image(systemName: Layout.deleteSymbol)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .font(.system(size: Layout.keyFontSize))
                .foregroundColor(.primaryText)
        } else {
            Text(key)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .font(.system(size: Layout.keyFontSize, weight: Layout.keyFontWeight))
                .foregroundColor(.primaryText)
        }
    }

    private var actionButtonView: some View {
        DashButton(
            text: actionButtonText,
            isEnabled: !value.isEmpty && actionEnabled,
            isLoading: inProgress,
            action: actionHandler
        )
        .padding(.horizontal, Layout.horizontalPadding)
    }

    @ViewBuilder
    private func helperTextRow(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            EmptyView()
        }
    }
    
    private func handleKeyPress(_ key: String) {
        if key == Layout.deleteKey {
            if !value.isEmpty {
                value.removeLast()
            }
        } else if key == Layout.decimalKey {
            if showDecimalSeparator && !value.contains(".") {
                value += Layout.decimalKey
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
    )
    .frame(height: 400)
    .padding(.horizontal, 20)
}
