import SwiftUI

enum NumericKeyboardLocaleSupport {
    static func decimalSeparator(for locale: Locale) -> String {
        locale.decimalSeparator ?? "."
    }

    static func rows(showDecimalSeparator: Bool, locale: Locale) -> [[String]] {
        let lastRow: [String]
        if showDecimalSeparator {
            lastRow = [decimalSeparator(for: locale), Layout.zeroKey, Layout.deleteKey]
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

    static func applyKeyPress(
        value: String,
        key: String,
        showDecimalSeparator: Bool,
        locale: Locale
    ) -> String {
        if key == Layout.deleteKey {
            var updatedValue = value
            if !updatedValue.isEmpty {
                updatedValue.removeLast()
            }
            return updatedValue
        }

        let decimalSeparator = decimalSeparator(for: locale)
        let groupingSeparator = locale.groupingSeparator ?? ","

        if !groupingSeparator.isEmpty, key == groupingSeparator, groupingSeparator != decimalSeparator {
            return value
        }

        if key == decimalSeparator {
            if showDecimalSeparator && !value.contains(decimalSeparator) {
                return value + decimalSeparator
            }
            return value
        }

        guard !key.isEmpty else { return value }
        return value + key
    }

    enum Layout {
        static let zeroKey = "0"
        static let emptyKey = ""
        static let deleteKey = "⌫"
    }
}

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

        static let deleteSymbol = "delete.left"
    }

    @Binding var value: String
    let showDecimalSeparator: Bool
    var locale: Locale = .autoupdatingCurrent
    let actionButtonText: String
    let actionEnabled: Bool
    let inProgress: Bool
    let helperText: String? = nil
    let actionHandler: () -> Void
    
    private var rows: [[String]] {
        NumericKeyboardLocaleSupport.rows(showDecimalSeparator: showDecimalSeparator, locale: locale)
    }
    
    var body: some View {
        VStack(spacing: Layout.rootSpacing) {
            keyboardRowsView
            helperTextRow(helperText)
            actionButtonView
        }
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
        if key == NumericKeyboardLocaleSupport.Layout.deleteKey {
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
        value = NumericKeyboardLocaleSupport.applyKeyPress(
            value: value,
            key: key,
            showDecimalSeparator: showDecimalSeparator,
            locale: locale
        )
    }
}

#Preview {

    VStack {
        Spacer()

        NumericKeyboardView(
            value: .constant(""),
            showDecimalSeparator: true,
            locale: Locale(identifier: "en_US"),
            actionButtonText: NSLocalizedString("Verify", comment: "Button title for numeric keyboard action"),
            actionEnabled: true,
            inProgress: false,
            actionHandler: { print("Action button tapped") }
        )
//        .frame(height: 400)
        .padding(.horizontal, 20)
        .background(.red.opacity(0.3))
    }


}
