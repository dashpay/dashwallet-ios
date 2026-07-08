//
//  PinPromptView.swift
//  DashWallet
//
//  App-side PIN entry modal (C7) — the replacement for DashSync's
//  in-flow `DSRequestPinViewController`. Presented by `PinPromptPresenter`
//  over the top-most controller from any context (the auth gate is called
//  from ObjC completion facades and async Swift alike), driven by
//  `PinPromptViewModel`, verified through `AuthenticationService`.
//
//  Reproduces the pod's request loop: precheck → collect 4 digits →
//  verify → re-prompt on a wrong PIN with the attempts-remaining line →
//  render lockout inline (live countdown; "no attempts remaining" at the
//  permanent-lock threshold) instead of a pre-flight alert (D-c7-a).
//

import SwiftUI

// MARK: - Result

enum PinPromptResult {
    case authenticated
    case cancelled
    case failed
}

// MARK: - ViewModel

@MainActor
final class PinPromptViewModel: ObservableObject {
    @Published var enteredPin = ""
    @Published private(set) var titleMessage: String
    @Published private(set) var subtitleMessage: String?
    /// Non-nil ⇒ the keypad is locked out; drives the inline countdown.
    @Published private(set) var lockoutMessage: String?
    @Published private(set) var isLockedOut = false
    @Published var shakeToken = 0

    private let service: AuthenticationServiceProtocol
    private let completion: (PinPromptResult) -> Void
    private var didComplete = false
    private var countdownTimer: Timer?

    let pinLength = LockoutPolicy.pinLength

    init(service: AuthenticationServiceProtocol = AuthenticationService.shared,
         completion: @escaping (PinPromptResult) -> Void) {
        self.service = service
        self.completion = completion
        self.titleMessage = NSLocalizedString("Enter PIN", comment: "PIN prompt")
        applyPrecheck()
    }

    deinit {
        countdownTimer?.invalidate()
    }

    // MARK: Input

    /// Bound to the (hidden) system-keyboard field: keep only digits, clamp
    /// to the PIN length, and verify once full.
    func inputChanged(_ text: String) {
        guard !isLockedOut else {
            if !enteredPin.isEmpty { enteredPin = "" }
            return
        }
        let digits = String(text.filter(\.isNumber).prefix(pinLength))
        if digits != enteredPin { enteredPin = digits }
        if digits.count == pinLength { verify() }
    }

    func cancel() {
        finish(.cancelled)
    }

    // MARK: Verification

    private func verify() {
        switch service.verifyPin(enteredPin) {
        case .authenticated:
            finish(.authenticated)
        case .wrongPinTryAgain:
            rejectEntry(refreshPrecheck: true)
        case .wrongPinLockout:
            rejectEntry(refreshPrecheck: true)
        case .storeError:
            finish(.failed)
        }
    }

    private func rejectEntry(refreshPrecheck: Bool) {
        enteredPin = ""
        shakeToken += 1
        if refreshPrecheck {
            applyPrecheck()
        }
    }

    /// Mirror the pod's `performAuthenticationPrecheck:` gate into UI state.
    private func applyPrecheck() {
        let precheck = service.authenticationPrecheck()
        subtitleMessage = precheck.attemptsMessage
        if precheck.shouldLockout {
            enterLockout()
        } else {
            isLockedOut = false
            lockoutMessage = nil
            countdownTimer?.invalidate()
        }
    }

    private func enterLockout() {
        isLockedOut = true
        enteredPin = ""
        refreshLockoutMessage()
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLockoutMessage() }
        }
    }

    private func refreshLockoutMessage() {
        if service.failCount >= LockoutPolicy.maxFailCount {
            lockoutMessage = NSLocalizedString("Wallet disabled. Recover with your recovery phrase.", comment: "PIN permanent lockout")
            return
        }
        let wait = service.lockoutWaitTime
        if wait <= 0 {
            // The countdown elapsed — re-open the keypad for another try.
            countdownTimer?.invalidate()
            applyPrecheck()
            return
        }
        let formatted = Self.durationFormatter.string(from: wait) ?? "\(Int(wait))s"
        lockoutMessage = String(format: NSLocalizedString("Try again in %@", comment: "PIN lockout"), formatted)
    }

    private func finish(_ result: PinPromptResult) {
        guard !didComplete else { return }
        didComplete = true
        countdownTimer?.invalidate()
        completion(result)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
}

// MARK: - View

struct PinPromptView: View {
    @ObservedObject var viewModel: PinPromptViewModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            // Dimmed pass-through backdrop (the send screen shows through).
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            card
                .frame(maxWidth: 340)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { fieldFocused = true }
    }

    /// Centered alert-style card (the DWAlertController the pod used for the
    /// in-flow PIN prompt): title, PIN dots, feedback, Cancel.
    private var card: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(viewModel.titleMessage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primaryText)

                dots
                    .modifier(ShakeEffect(animatableData: CGFloat(viewModel.shakeToken)))

                if let subtitle = viewModel.subtitleMessage, viewModel.lockoutMessage == nil {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.tertiaryText)
                        .multilineTextAlignment(.center)
                }

                if let lockout = viewModel.lockoutMessage {
                    Text(lockout)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.systemRed)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)

            Divider()

            Button(action: viewModel.cancel) {
                Text(NSLocalizedString("Cancel", comment: ""))
                    .font(.system(size: 17))
                    .foregroundColor(.dashBlue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
        }
        .background(
            // Hidden field owns the system numeric keyboard, exactly as the
            // pod's pinField.becomeFirstResponder did.
            TextField("", text: Binding(
                get: { viewModel.enteredPin },
                set: { viewModel.inputChanged($0) }))
                .keyboardType(.numberPad)
                .focused($fieldFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .disabled(viewModel.isLockedOut)
        )
        .background(Color.primaryBackground)
        .cornerRadius(14)
    }

    /// Rounded-square boxes matching the pod's `DSPinField`: a light-gray
    /// slot that fills with a dark dot as each digit is entered.
    private var dots: some View {
        HStack(spacing: 12) {
            ForEach(0 ..< viewModel.pinLength, id: \.self) { index in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .fill(Color.primaryText)
                            .frame(width: 14, height: 14)
                            .opacity(index < viewModel.enteredPin.count ? 1 : 0)
                    )
            }
        }
    }
}

// MARK: - Shake

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 10 * sin(animatableData * .pi * 2)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
