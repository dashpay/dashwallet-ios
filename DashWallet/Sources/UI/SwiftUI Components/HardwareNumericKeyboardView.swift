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
}

/// DashUIKit's numeric keypad is made of buttons and therefore has no text
/// responder for a connected keyboard. This wrapper keeps the visible keypad
/// unchanged while installing a responder for physical-keyboard input.
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
                inputEnabled: !inProgress
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

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeUIView(context: Context) -> HardwareNumericKeyboardResponderView {
        let view = HardwareNumericKeyboardResponderView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: HardwareNumericKeyboardResponderView, context: Context) {
        context.coordinator.value = $value
        configure(view, coordinator: context.coordinator)
    }

    private func configure(_ view: HardwareNumericKeyboardResponderView, coordinator: Coordinator) {
        view.inputEnabled = inputEnabled
        view.onKey = { [weak coordinator] key in
            guard let coordinator else { return }
            coordinator.value.wrappedValue = HardwareNumericKeyboardInput.applying(
                key,
                to: coordinator.value.wrappedValue,
                showDecimalSeparator: showDecimalSeparator,
                locale: locale
            )
        }
    }

    final class Coordinator {
        var value: Binding<String>

        init(value: Binding<String>) {
            self.value = value
        }
    }
}

private final class HardwareNumericKeyboardResponderView: UIView {
    var inputEnabled = true
    var onKey: ((HardwareNumericKeyboardKey) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let inputs = (0 ... 9).map(String.init) + [".", ","]
        var commands = inputs.map {
            UIKeyCommand(input: $0, modifierFlags: [], action: #selector(handleKeyCommand(_:)))
        }
        commands.append(UIKeyCommand(input: UIKeyCommand.inputDelete, modifierFlags: [], action: #selector(handleKeyCommand(_:))))
        return commands
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.becomeFirstResponder()
        }
    }

    @objc private func handleKeyCommand(_ command: UIKeyCommand) {
        guard let input = command.input else { return }

        guard inputEnabled else { return }
        switch input {
        case UIKeyCommand.inputDelete:
            onKey?(.delete)
        case ".", ",":
            onKey?(.decimalSeparator)
        default:
            if input.count == 1, input.first?.isNumber == true {
                onKey?(.digit(input))
            }
        }
    }
}
