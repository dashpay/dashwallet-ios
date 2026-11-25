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

import LocalAuthentication
import SwiftUI

// MARK: - LockScreenView

/// The screen the app opens on: the Dash logo over the photo, the PIN boxes
/// with Forgot PIN under them, the quick actions, and the keypad.
struct LockScreenView: View {
    @ObservedObject var viewModel: LockScreenViewModel

    let onForgotPin: () -> Void
    let onQuickReceive: () -> Void
    let onScanToSend: () -> Void

    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                top(topInset: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
            LockScreenKeypad(
                isEnabled: viewModel.isKeypadEnabled,
                onDigit: viewModel.enter(digit:),
                onDelete: viewModel.deleteBackward
            )
        }
        .background {
            Image("image_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        // Typing on a hardware keyboard, as the old PIN field took it.
        .focusable()
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(characters: .decimalDigits) { press in
            guard let digit = press.characters.first?.wholeNumberValue else { return .ignored }
            viewModel.enter(digit: digit)
            return .handled
        }
        .onKeyPress(.delete) {
            viewModel.deleteBackward()
            return .handled
        }
        .onAppear { hasKeyboardFocus = true }
    }

    /// The PIN sits in the middle of the area above the keypad — measured
    /// from the top of the screen, not from under the status bar — whatever
    /// the logo and the quick actions take.
    private func top(topInset: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 0) {
                Image("dash_logo_template")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 109)
                    .foregroundColor(.white)
                    .padding(.top, topInset + 42)
                    .accessibilityLabel("Dash") // a11y-ignore: A11Y009 the brand name, never translated
                Spacer()
                actions
                    .padding(.bottom, 4)
            }

            VStack(spacing: 8) {
                LockScreenPinInput(viewModel: viewModel)
                Button(action: onForgotPin) {
                    Text(viewModel.hasPinSet
                        ? String(localized: "Forgot PIN?", comment: "")
                        : String(localized: "Set PIN", comment: ""))
                        .font(.system(.body))
                        .foregroundColor(.white)
                        .frame(minHeight: 54)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            LockScreenActionButton(
                title: String(localized: "Quick Receive", comment: ""),
                image: "icon_lock_receive",
                action: onQuickReceive
            )
            if viewModel.showsBiometricButton, let biometrics = biometricButton {
                LockScreenActionButton(
                    title: biometrics.title,
                    image: biometrics.image,
                    action: viewModel.authenticateUsingBiometrics
                )
            }
            LockScreenActionButton(
                title: String(localized: "Scan to Send", comment: ""),
                image: "icon_lock_scan_to_pay",
                action: onScanToSend
            )
            .disabled(!viewModel.isScanEnabled)
        }
        .frame(height: 96)
    }

    private var biometricButton: (title: String, image: String)? {
        switch viewModel.biometryType {
        case .faceID:
            return (String(localized: "Login with Face ID", comment: ""), "icon_lock_faceid")
        case .touchID:
            return (String(localized: "Login with Touch ID", comment: ""), "icon_lock_touchid")
        default:
            return nil
        }
    }
}

// MARK: - LockScreenPinInput

/// "Enter PIN", the attempts left, and the four boxes — or, when no PIN can
/// be entered, the reason in their place.
private struct LockScreenPinInput: View {
    @ObservedObject var viewModel: LockScreenViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text(viewModel.title)
                .font(.system(.title3))
                .foregroundColor(Color("LightTitleColor"))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)

            VStack(spacing: 8) {
                if let attempts = viewModel.attemptsText {
                    Text(attempts)
                        .font(.system(.footnote))
                        .foregroundColor(Color("LightTitleColor"))
                        .multilineTextAlignment(.center)
                }

                if let error = viewModel.errorText {
                    Text(error)
                        .font(.system(.subheadline))
                        .foregroundColor(Color("LightTitleColor"))
                        .multilineTextAlignment(.center)
                } else {
                    boxes
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(viewModel.errorText == nil
            ? String(localized: "\(viewModel.pin.count) of \(viewModel.pinLength) digits entered",
                     comment: "Lock screen PIN, VoiceOver")
            : "")
    }

    /// White boxes that turn Dash blue with a dot as each digit is entered.
    private var boxes: some View {
        HStack(spacing: 10) {
            ForEach(0 ..< viewModel.pinLength, id: \.self) { index in
                let isFilled = index < viewModel.pin.count
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFilled ? Color.dash.blue : Color.white)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                            .opacity(isFilled ? 1 : 0)
                    }
            }
        }
        .modifier(ShakeEffect(shakes: CGFloat(viewModel.rejections)))
        .animation(.linear(duration: 0.4), value: viewModel.rejections)
    }
}

/// Moves the boxes side to side, three times per wrong PIN.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakes * .pi * 6), y: 0))
    }
}

// MARK: - LockScreenActionButton

/// An icon over a caption: Quick Receive, biometric login, Scan to Send.
private struct LockScreenActionButton: View {
    let title: String
    let image: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(image)
                Text(title)
                    .font(.system(.caption))
                    .foregroundColor(Color("LightTitleColor"))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(FadingButtonStyle())
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct FadingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(.easeOut(duration: 0.075), value: configuration.isPressed)
    }
}

// MARK: - LockScreenKeypad

/// The digits under the lock screen, laid out as the app's number keyboard:
/// keys up to 115pt wide, highlighted Dash blue while pressed.
private struct LockScreenKeypad: View {
    let isEnabled: Bool
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
                Color.clear
                    .frame(maxWidth: 115, maxHeight: 50)
                    .accessibilityHidden(true)
                digitKey(0)
                key(action: onDelete) {
                    Image(systemName: "delete.left")
                }
                .accessibilityLabel(String(localized: "Delete", comment: "Number keyboard"))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Color("SecondaryBackgroundColor").ignoresSafeArea())
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
        .buttonStyle(KeypadKeyStyle())
    }
}

/// Disabled keys look the same, as the old keyboard's did: while no PIN can
/// be entered the reason shows in place of the boxes.
private struct KeypadKeyStyle: ButtonStyle {
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
