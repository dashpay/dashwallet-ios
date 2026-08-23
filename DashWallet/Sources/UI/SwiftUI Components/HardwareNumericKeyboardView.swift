//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import DashUIKit
import SwiftUI
import UIKit

enum HardwareNumericKeyboardKey: Equatable {
    case digit(String)
    case decimalSeparator
    case delete
}

enum HardwareNumericKeyboardInput {
    static func applying(
        _ key: HardwareNumericKeyboardKey,
        to value: String,
        showDecimalSeparator: Bool,
        locale: Locale
    ) -> String {
        switch key {
        case .digit(let digit):
            return value + digit
        case .decimalSeparator:
            let separator = locale.decimalSeparator ?? "."
            guard showDecimalSeparator, !value.contains(separator) else { return value }
            return value + separator
        case .delete:
            guard !value.isEmpty else { return value }
            return String(value.dropLast())
        }
    }

    /// Both "." and "," map to the decimal separator: European numpads emit ","
    /// for the decimal key, and the keypad has no grouping-separator concept.
    static func key(for character: Character) -> HardwareNumericKeyboardKey? {
        if character == "." || character == "," {
            return .decimalSeparator
        }
        if let digit = character.wholeNumberValue, (0 ... 9).contains(digit) {
            return .digit(String(digit))
        }
        return nil
    }
}

/// DashUIKit's numeric keypad is made of buttons and therefore has no text
/// responder for a connected keyboard. This wrapper keeps the visible keypad
/// unchanged while installing a hidden text responder for physical-keyboard
/// input — the same hidden-text-field pattern the PIN (`DWPinField`), 2FA
/// (`TwoFactorAuthViewController`), and legacy amount screens already use.
struct HardwareNumericKeyboardView: View {
    @Binding private var value: String
    private let showDecimalSeparator: Bool
    private let locale: Locale
    private let actionButtonText: String
    private let actionEnabled: Bool
    private let inProgress: Bool
    private let helperText: String?
    private let actionHandler: () -> Void

    init(
        value: Binding<String>,
        showDecimalSeparator: Bool,
        locale: Locale = .autoupdatingCurrent,
        actionButtonText: String,
        actionEnabled: Bool,
        inProgress: Bool,
        helperText: String? = nil,
        actionHandler: @escaping () -> Void
    ) {
        _value = value
        self.showDecimalSeparator = showDecimalSeparator
        self.locale = locale
        self.actionButtonText = actionButtonText
        self.actionEnabled = actionEnabled
        self.inProgress = inProgress
        self.helperText = helperText
        self.actionHandler = actionHandler
    }

    var body: some View {
        DashUIKit.NumericKeyboardView(
            value: $value,
            showDecimalSeparator: showDecimalSeparator,
            locale: locale,
            actionButtonText: actionButtonText,
            actionEnabled: actionEnabled,
            inProgress: inProgress,
            helperText: helperText,
            actionHandler: actionHandler
        )
        .background {
            HardwareNumericKeyboardResponder(
                value: $value,
                showDecimalSeparator: showDecimalSeparator,
                locale: locale,
                inputEnabled: !inProgress,
                // Mirror the visible action button's gate, which DashUIKit
                // computes as `!value.isEmpty && actionEnabled`.
                returnEnabled: !value.isEmpty && actionEnabled && !inProgress,
                onReturn: actionHandler
            )
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
    }
}

private struct HardwareNumericKeyboardResponder: UIViewRepresentable {
    @Binding var value: String
    let showDecimalSeparator: Bool
    let locale: Locale
    let inputEnabled: Bool
    let returnEnabled: Bool
    let onReturn: () -> Void

    func makeUIView(context: Context) -> HardwareNumericKeyboardTextField {
        let field = HardwareNumericKeyboardTextField()
        configure(field)
        return field
    }

    func updateUIView(_ field: HardwareNumericKeyboardTextField, context: Context) {
        configure(field)
    }

    private func configure(_ field: HardwareNumericKeyboardTextField) {
        field.inputEnabled = inputEnabled
        field.onKey = { key in
            value = HardwareNumericKeyboardInput.applying(
                key,
                to: value,
                showDecimalSeparator: showDecimalSeparator,
                locale: locale
            )
        }
        field.onReturn = returnEnabled ? onReturn : nil
    }
}

/// Hidden `UITextField` whose `UIKeyInput` overrides forward hardware keys to
/// the keypad's value instead of the field's own text. An empty `inputView`
/// suppresses the software keyboard (as in `TwoFactorAuthViewController`).
final class HardwareNumericKeyboardTextField: UITextField, UITextFieldDelegate {
    var inputEnabled = true
    var onKey: ((HardwareNumericKeyboardKey) -> Void)?
    var onReturn: (() -> Void)?

    /// The field's text stays pinned to this zero-width sentinel so `hasText`
    /// is always true and UIKit keeps routing hardware Backspace to
    /// `deleteBackward()` even when the keypad's logical value is empty.
    private static let sentinel = "\u{200B}"

    private var editingObservers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        text = Self.sentinel
        inputView = UIView()
        autocorrectionType = .no
        spellCheckingType = .no
        tintColor = .clear
        textColor = .clear
        backgroundColor = .clear
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        editingObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - UIKeyInput

    override func insertText(_ text: String) {
        guard inputEnabled else { return }
        for character in text {
            if character == "\n" || character == "\r" {
                onReturn?()
            } else if let key = HardwareNumericKeyboardInput.key(for: character) {
                onKey?(key)
            }
        }
    }

    override func deleteBackward() {
        guard inputEnabled else { return }
        onKey?(.delete)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onReturn?()
        return false
    }

    // MARK: - First responder management

    override func didMoveToWindow() {
        super.didMoveToWindow()

        editingObservers.forEach(NotificationCenter.default.removeObserver)
        editingObservers = []
        guard window != nil else { return }

        claimFirstResponderIfIdle()

        // A sheet or alert with a text field (currency-picker search, PIN
        // prompt) steals first responder while this view stays in the window,
        // so `didMoveToWindow` alone would leave hardware input dead after
        // dismissal. Reclaim whenever any other editor ends editing.
        for name in [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification] {
            editingObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, (notification.object as? UIView) !== self else { return }
                self.claimFirstResponderIfIdle()
            })
        }
    }

    private func claimFirstResponderIfIdle() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, !self.isFirstResponder else { return }
            // Don't yank focus from a text input the user is actively editing
            // (e.g. the contact Alias field beneath a Pay sheet).
            if let current = UIResponder.currentFirstResponder, current !== self, current is UITextInput {
                return
            }
            self.becomeFirstResponder()
        }
    }
}

private extension UIResponder {
    private enum FirstResponderProbe {
        static weak var current: UIResponder?
    }

    static var currentFirstResponder: UIResponder? {
        FirstResponderProbe.current = nil
        UIApplication.shared.sendAction(#selector(captureFirstResponder), to: nil, from: nil, for: nil)
        return FirstResponderProbe.current
    }

    @objc private func captureFirstResponder() {
        FirstResponderProbe.current = self
    }
}
