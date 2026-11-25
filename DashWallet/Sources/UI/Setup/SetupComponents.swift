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

import SwiftUI
import UIKit

// MARK: - SetupActionButtonStyle

/// The wallet setup screens' main button: Dash blue, 54pt tall, outlined
/// while pressed — as the UIKit action button they had.
struct SetupActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, weight: .medium))
            .foregroundColor(configuration.isPressed ? Color.dash.blue : .white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Color.clear : Color.dash.blue)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.dash.blue, lineWidth: configuration.isPressed ? 2 : 0)
            )
            .contentShape(Rectangle())
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

/// Moves a view side to side, three times per bump of `shakes`.
struct PinShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakes * .pi * 6), y: 0))
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
        Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
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
