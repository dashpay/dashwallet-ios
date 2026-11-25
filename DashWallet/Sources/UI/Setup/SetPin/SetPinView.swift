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

// MARK: - SetPinViewModel

/// A new PIN, entered twice: Set PIN, then Confirm PIN. A mismatch shakes
/// the boxes and asks for the confirmation again; Cancel on Confirm PIN goes
/// back to Set PIN.
@MainActor
final class SetPinViewModel: ObservableObject {
    enum Step {
        case set
        case confirm
    }

    @Published private(set) var step: Step = .set
    @Published private(set) var pin = ""
    @Published private(set) var confirmation = ""
    /// Bumped on a mismatch, to shake the boxes.
    @Published private(set) var rejections = 0
    /// Off while the step slides or a mismatch shakes.
    @Published private(set) var isInputEnabled = true

    let pinLength = LockoutPolicy.pinLength

    /// The PIN was confirmed and saved.
    var onSet: (() -> Void)?
    /// Cancel on Set PIN, or saving the PIN failed.
    var onCancel: (() -> Void)?

    private let service: AuthenticationService
    private let feedback = UINotificationFeedbackGenerator()

    init(service: AuthenticationService = .shared) {
        self.service = service
    }

    /// Whether the wallet still needs its first PIN.
    static var shouldSetPin: Bool { !AuthenticationService.shared.hasPin() }

    var entered: String { step == .set ? pin : confirmation }

    func enter(digit: Int) {
        guard isInputEnabled, entered.count < pinLength else { return }
        switch step {
        case .set:
            pin.append(String(digit))
            if pin.count == pinLength { moveToConfirmation() }
        case .confirm:
            confirmation.append(String(digit))
            if confirmation.count == pinLength { check() }
        }
    }

    func deleteBackward() {
        guard isInputEnabled else { return }
        switch step {
        case .set:
            if !pin.isEmpty { pin.removeLast() }
        case .confirm:
            if !confirmation.isEmpty { confirmation.removeLast() }
        }
    }

    /// Cancel: leaves from Set PIN, starts over from Confirm PIN.
    func cancel() {
        guard isInputEnabled else { return }
        switch step {
        case .set:
            onCancel?()
        case .confirm:
            pin = ""
            confirmation = ""
            slide(to: .set)
        }
    }

    private func moveToConfirmation() {
        slide(to: .confirm)
        feedback.prepare()
    }

    private func slide(to step: Step) {
        isInputEnabled = false
        withAnimation(.spring(response: 0.35, dampingFraction: 1)) {
            self.step = step
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isInputEnabled = true
        }
    }

    private func check() {
        isInputEnabled = false

        guard confirmation == pin else {
            feedback.notificationOccurred(.error)
            rejections += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.confirmation = ""
                self.isInputEnabled = true
                self.feedback.prepare()
            }
            return
        }

        feedback.notificationOccurred(.success)
        if service.setupNewPin(pin) {
            onSet?()
        } else {
            onCancel?()
        }
    }
}

// MARK: - SetPinView

/// Set PIN and Confirm PIN over the keypad, with Cancel left of the zero.
struct SetPinView: View {
    @ObservedObject var viewModel: SetPinViewModel

    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ZStack {
                    if viewModel.step == .set {
                        step(title: String(localized: "Set PIN", comment: ""), filled: viewModel.pin.count)
                            .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                    } else {
                        step(title: String(localized: "Confirm PIN", comment: ""), filled: viewModel.confirmation.count)
                            .modifier(PinShakeEffect(shakes: CGFloat(viewModel.rejections)))
                            .animation(.linear(duration: 0.4), value: viewModel.rejections)
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()

                Text(String(localized: "This PIN will be required to unlock your app every time when you use it.", comment: ""))
                    .font(.system(.callout))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity)

            PinKeypad(
                isEnabled: viewModel.isInputEnabled,
                leftKeyTitle: String(localized: "Cancel", comment: ""),
                onLeftKey: viewModel.cancel,
                onDigit: viewModel.enter(digit:),
                onDelete: viewModel.deleteBackward
            )
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
        .background(Color("SecondaryBackgroundColor").ignoresSafeArea())
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

    private func step(title: String, filled: Int) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(.title3))
                .foregroundColor(Color("DarkTitleColor"))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            PinBoxes(length: viewModel.pinLength, filled: filled)
        }
    }
}
