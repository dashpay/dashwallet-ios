//
//  Created by Dash Core Group
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

// MARK: - SetupActionButtonStyle

/// The wallet setup screens' main button: Dash blue, 54pt tall, outlined
/// while pressed and grey while disabled — as the UIKit action button they had.
struct SetupActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, weight: .medium))
            .foregroundColor(foreground(isPressed: configuration.isPressed))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.dash.blue, lineWidth: configuration.isPressed ? 2 : 0)
            )
            .contentShape(Rectangle())
    }

    private func foreground(isPressed: Bool) -> Color {
        guard isEnabled else { return Color("DisabledButtonTextColor") }
        return isPressed ? Color.dash.blue : .white
    }

    private func background(isPressed: Bool) -> Color {
        guard isEnabled else { return Color("DisabledButtonColor") }
        return isPressed ? .clear : Color.dash.blue
    }
}

// MARK: - SetupTextButtonStyle

/// The wallet setup screens' secondary button: Dash blue text, 54pt tall.
struct SetupTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body))
            .foregroundColor(Color.dash.blue)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
    }
}

// MARK: - PinBoxes

/// Four boxes that turn Dash blue with a white dot as each digit is entered.
struct PinBoxes: View {
    let length: Int
    let filled: Int
    /// The colour of a box with no digit yet.
    var emptyColor: Color = PinBoxes.defaultEmptyColor

    /// The grey of the PIN boxes before a digit is entered.
    static let defaultEmptyColor = Color(red: 0xD8 / 255, green: 0xD8 / 255, blue: 0xD8 / 255)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0 ..< length, id: \.self) { index in
                let isFilled = index < filled
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFilled ? Color.dash.blue : emptyColor)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                            .opacity(isFilled ? 1 : 0)
                    }
            }
        }
        .accessibilityElement()
        .accessibilityValue(String(localized: "\(filled) of \(length) digits entered",
                                   comment: "Lock screen PIN, VoiceOver"))
    }
}

/// Moves a view side to side, `oscillations` times per bump of `shakes`: the
/// rejection shake of PIN entry and of a wrong pick.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var oscillations: CGFloat = 3

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakes * .pi * 2 * oscillations), y: 0))
    }
}

// MARK: - PinKeypad

/// The digits for PIN entry, laid out as the app's number keyboard: keys up
/// to 115pt wide and 50pt tall, highlighted Dash blue while pressed, with an
/// optional text key (Cancel) left of the zero.
struct PinKeypad: View {
    var isEnabled = true
    var leftKeyTitle: String?
    var onLeftKey: () -> Void = { }
    let onDigit: (Int) -> Void
    let onDelete: () -> Void

    private static let rows: [[Int]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { digit in
                        digitKey(digit)
                    }
                }
            }
            HStack(spacing: 5) {
                if let leftKeyTitle {
                    key(action: onLeftKey) {
                        Text(leftKeyTitle)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                } else {
                    Color.clear
                        .frame(maxWidth: 115, maxHeight: 50)
                        .accessibilityHidden(true)
                }
                digitKey(0)
                key(action: onDelete) {
                    Image(systemName: "delete.left")
                }
                .accessibilityLabel(String(localized: "Delete", comment: "Number keyboard"))
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(!isEnabled)
    }

    private func digitKey(_ digit: Int) -> some View {
        key(action: { onDigit(digit) }) {
            Text(String(digit))
        }
    }

    private func key(action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .font(.system(.title3))
                .frame(maxWidth: 115, maxHeight: 50)
                .frame(height: 50)
        }
        .buttonStyle(PinKeypadKeyStyle())
    }
}

private struct PinKeypadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed
                ? Color("NumberKeyboardHighlightedTextColor")
                : Color("NumberKeyboardTextColor"))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.dash.blue : Color("SecondaryBackgroundColor"))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Hosting

extension UIViewController {
    /// Embeds `content` full screen in a hosting controller child.
    @discardableResult
    func embedSwiftUI(_ content: some View) -> UIViewController {
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        return hosting
    }
}

// MARK: - SetupScreenViewController

/// What DashUIKit's bar shows over a setup screen. The controller fills it in.
@MainActor
final class SetupNavigationBarModel: ObservableObject {
    @Published var title = ""
    /// A line over the title, such as which wallet the screen is about.
    @Published var prompt: String?
    @Published var back: (() -> Void)?
    @Published var close: (() -> Void)?
}

/// A setup screen: SwiftUI content under DashUIKit's navigation bar, which
/// takes the place of the system one. Back shows when the screen was pushed;
/// close shows when the presenter sets `closeHandler`.
class SetupScreenViewController: UIViewController, NavigationFullscreenable {
    let navigationBar = SetupNavigationBarModel()

    /// Shown as the close element, top right. For a screen at the root of a
    /// modal navigation stack.
    @objc var closeHandler: (() -> Void)? {
        didSet { navigationBar.close = closeHandler }
    }

    override var title: String? {
        didSet { navigationBar.title = title ?? "" }
    }

    /// The line over the title, in place of the navigation item's prompt.
    var prompt: String? {
        get { navigationBar.prompt }
        set { navigationBar.prompt = newValue }
    }

    var requiresNoNavigationBar: Bool { true }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let isPushed = navigationController.map { $0.viewControllers.first !== self } ?? false
        navigationBar.back = isPushed
            ? { [weak self] in self?.navigationController?.popViewController(animated: true) }
            : nil
    }

    /// Embeds `content` full screen under the bar.
    @discardableResult
    func embedScreen(_ content: some View) -> UIViewController {
        embedSwiftUI(SetupScreen(navigationBar: navigationBar, content: content))
    }
}

private struct SetupScreen<Content: View>: View {
    @ObservedObject var navigationBar: SetupNavigationBarModel
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(
                leading: {
                    if let back = navigationBar.back {
                        DashUIKit.NavigationBarElement.back.button(action: back)
                    }
                },
                central: {
                    VStack(spacing: 2) {
                        if let prompt = navigationBar.prompt {
                            Text(prompt)
                                .dashFont(.caption1)
                                .foregroundColor(.dash.secondaryText)
                        }
                        Text(navigationBar.title)
                            .dashFont(.subheadMedium)
                            .foregroundColor(.dash.primaryText)
                            .accessibilityAddTraits(.isHeader)
                    }
                },
                trailing: {
                    if let close = navigationBar.close {
                        DashUIKit.NavigationBarElement.close.button(action: close)
                    }
                })

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
