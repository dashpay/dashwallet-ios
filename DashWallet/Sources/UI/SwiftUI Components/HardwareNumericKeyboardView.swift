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
        field.locale = locale
        // Both input paths run the same rules: `key` is whatever the on-screen
        // keypad would have sent, and `applyKeyPress` decides what it does to
        // the value.
        field.onKey = { key in
            value = NumericKeyboardLocaleSupport.applyKeyPress(
                value: value,
                key: key,
                showDecimalSeparator: showDecimalSeparator,
                locale: locale
            )
        }
        field.onReturn = returnEnabled ? onReturn : nil
        // SwiftUI re-runs the body of the screen underneath a sheet when that
        // sheet is dismissed, so this is the reclaim path for the modals that
        // post no end-editing notification of their own.
        field.syncFirstResponderState()
    }
}

/// Hidden `UITextField` whose `UIKeyInput` overrides forward hardware keys to
/// the keypad's value instead of the field's own text. An empty `inputView`
/// suppresses the software keyboard (as in `TwoFactorAuthViewController`).
///
/// The field only acts while its own screen is the frontmost interactive one —
/// see `ownsHardwareKeyboard`. Everything else in the app that takes focus
/// (PIN prompt, currency picker, lock screen) presents *over* a keypad screen
/// that stays in the window, so without that check the keypad would keep
/// eating keys from behind the modal.
final class HardwareNumericKeyboardTextField: UITextField, UITextFieldDelegate {
    var inputEnabled = true
    var locale: Locale = .autoupdatingCurrent
    /// Receives the on-screen keypad key a hardware keystroke maps to.
    var onKey: ((String) -> Void)?
    var onReturn: (() -> Void)?

    /// The field's text stays pinned to this zero-width sentinel so `hasText`
    /// is always true and UIKit keeps routing hardware Backspace to
    /// `deleteBackward()` even when the keypad's logical value is empty.
    private static let sentinel = "\u{200B}"

    private var editingObservers: [NSObjectProtocol] = []
    private var isHandlingReturn = false

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
        guard ownsHardwareKeyboard else {
            relinquishHardwareKeyboard()
            return
        }
        guard inputEnabled else { return }
        for character in text {
            if character == "\n" || character == "\r" {
                handleReturn()
            } else if let key = NumericKeyboardLocaleSupport.key(forTyped: character, locale: locale) {
                onKey?(key)
            }
        }
    }

    override func deleteBackward() {
        guard ownsHardwareKeyboard else {
            relinquishHardwareKeyboard()
            return
        }
        guard inputEnabled else { return }
        onKey?(NumericKeyboardLocaleSupport.deleteKey)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        handleReturn()
        return false
    }

    /// A single hardware Return can arrive twice — once as `insertText("\n")`
    /// and once as `textFieldShouldReturn` — and both land in the same runloop
    /// turn, before SwiftUI can propagate `inProgress` and clear `onReturn`.
    /// Some action handlers send money outright (`PayContactSheet.pay()`), so
    /// the two deliveries are collapsed into one.
    private func handleReturn() {
        guard inputEnabled, ownsHardwareKeyboard, !isHandlingReturn else { return }
        isHandlingReturn = true
        DispatchQueue.main.async { [weak self] in self?.isHandlingReturn = false }
        onReturn?()
    }

    // MARK: - Editing menu

    /// The field's text is a sentinel, not the user's amount. Cut/copy/paste
    /// against it would corrupt the sentinel and, for paste, bypass
    /// `PastedAmountParser` — which is what the screens' own paste affordance
    /// uses to read grouped input correctly.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override func paste(_ sender: Any?) { }

    override func replace(_ range: UITextRange, withText text: String) { }

    // MARK: - First responder management

    override func didMoveToWindow() {
        super.didMoveToWindow()

        editingObservers.forEach(NotificationCenter.default.removeObserver)
        editingObservers = []
        guard window != nil else { return }

        syncFirstResponderState()

        // Anything that takes focus over a keypad screen leaves this view in
        // the window, so `didMoveToWindow` alone would leave hardware input
        // dead after the overlay goes away. Listen broadly and let
        // `ownsHardwareKeyboard` decide whether the reclaim is appropriate:
        // end-editing covers `UITextField`-based overlays (currency-picker
        // search, the SwiftUI PIN prompt), keyboard-did-hide covers responders
        // that post no end-editing notification (`DWPinField` is a
        // `UIView<UITextInput>`), and the window/app notifications cover the
        // separate lock window and backgrounding.
        let names: [Notification.Name] = [
            UITextField.textDidEndEditingNotification,
            UITextView.textDidEndEditingNotification,
            UIResponder.keyboardDidHideNotification,
            UIWindow.didBecomeKeyNotification,
            UIApplication.didBecomeActiveNotification,
        ]
        for name in names {
            editingObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, (notification.object as? UIView) !== self else { return }
                self.syncFirstResponderState()
            })
        }
    }

    /// Takes focus when this screen owns the hardware keyboard and gives it up
    /// when it doesn't, so a modal presented over the keypad gets the keys and
    /// the keypad gets them back once the modal is gone.
    func syncFirstResponderState() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.ownsHardwareKeyboard else {
                self.relinquishHardwareKeyboard()
                return
            }
            guard !self.isFirstResponder else { return }
            // Don't yank focus from a text input the user is actively editing
            // (e.g. the contact Alias field beneath a Pay sheet).
            if let current = UIResponder.dw_currentFirstResponder, current !== self, current is UITextInput {
                return
            }
            self.becomeFirstResponder()
        }
    }

    private func relinquishHardwareKeyboard() {
        guard isFirstResponder else { return }
        resignFirstResponder()
    }

    /// True only while this field's own screen is frontmost and interactive:
    /// its window is key, and its view controller is (or is contained in) the
    /// frontmost presented controller of that window. A SwiftUI `.sheet` is a
    /// `pageSheet` and the PIN prompt is `.overFullScreen`, so in both cases
    /// the presenting screen stays in the window and would otherwise still
    /// hold first responder behind the modal.
    private var ownsHardwareKeyboard: Bool {
        guard let window, window.isKeyWindow, let owner = owningViewController else { return false }

        var frontmost = window.rootViewController
        while let presented = frontmost?.presentedViewController {
            frontmost = presented
        }
        guard let frontmost else { return false }

        var viewController: UIViewController? = owner
        while let current = viewController {
            if current === frontmost { return true }
            viewController = current.parent
        }
        return false
    }

    private var owningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController { return viewController }
            responder = current.next
        }
        return nil
    }
}

private extension UIResponder {
    private enum FirstResponderProbe {
        static weak var current: UIResponder?
    }

    static var dw_currentFirstResponder: UIResponder? {
        FirstResponderProbe.current = nil
        UIApplication.shared.sendAction(#selector(dw_captureFirstResponder), to: nil, from: nil, for: nil)
        return FirstResponderProbe.current
    }

    // `private` does not scope the ObjC selector, which is installed on
    // `UIResponder` process-wide — hence the prefix.
    @objc private func dw_captureFirstResponder() {
        FirstResponderProbe.current = self
    }
}
