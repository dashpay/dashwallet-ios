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
import DashUIKit

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

    /// Identity token for the hidden text field. Clearing `enteredPin`
    /// inside the binding setter does NOT reliably propagate back into the
    /// UIKit field — the stale text then made every subsequent keypress
    /// re-deliver the rejected 4 digits, burning one attempt per key.
    /// Bumping this recreates the field empty; the view re-focuses it.
    @Published private(set) var fieldGeneration = 0

    private let service: AuthenticationServiceProtocol
    private let completion: (PinPromptResult) -> Void
    private var didComplete = false
    private var countdownTimer: Timer?
    /// The last rejected entry, kept until the next partial input. Defends
    /// the window before the recreated field takes over: a keystroke landing
    /// on the old field re-delivers the just-verified digits (a real retype
    /// passes through 1–3 digit states first) — swallowing keeps one
    /// physical entry from burning two attempts.
    private var justRejectedPin: String?

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

    /// Bound to the (hidden) system-keyboard field: keep only digits, drop
    /// anything longer than the PIN length, and verify once full.
    func inputChanged(_ text: String) {
        guard !isLockedOut else {
            if !enteredPin.isEmpty { enteredPin = "" }
            return
        }
        let digits = text.filter(\.isNumber)
        // A fresh field can never exceed the PIN length (entry verifies and
        // the field is recreated at exactly `pinLength` digits). More means
        // the old field's stale buffer — drop it; never clamp it back to
        // full length with a prefix, which is what re-verified the rejected
        // PIN on every keypress.
        guard digits.count <= pinLength else { return }
        if digits.count < pinLength {
            justRejectedPin = nil
        } else if enteredPin.isEmpty, digits == justRejectedPin {
            // Absorb a re-delivery from the outgoing field, but let a
            // deliberate identical re-entry count as the attempt it is.
            justRejectedPin = nil
            return
        }
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
        justRejectedPin = enteredPin
        enteredPin = ""
        fieldGeneration += 1
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
        fieldGeneration += 1
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
            Color.dash.backgroundOverlay
                .ignoresSafeArea()

            card
                .frame(maxWidth: 340)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { fieldFocused = true }
        // On a stable ancestor: the field itself is recreated by the
        // `.id(fieldGeneration)` swap, so observers on it would miss the
        // very change that replaced it.
        .onChange(of: viewModel.fieldGeneration) {
            if !viewModel.isLockedOut { refocus() }
        }
        .onChange(of: viewModel.isLockedOut) {
            if !viewModel.isLockedOut { refocus() }
        }
    }

    /// Focus doesn't survive the field's identity swap (or a disable
    /// round-trip) — re-assert it a tick later so the recreated field is
    /// attached before it becomes first responder.
    private func refocus() {
        Task { @MainActor in
            fieldFocused = true
        }
    }

    /// Centered alert-style card (the DWAlertController the pod used for the
    /// in-flow PIN prompt): title, PIN dots, feedback, Cancel.
    private var card: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(viewModel.titleMessage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.dash.primaryText)

                dots
                    .modifier(ShakeEffect(animatableData: CGFloat(viewModel.shakeToken)))

                if let subtitle = viewModel.subtitleMessage, viewModel.lockoutMessage == nil {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.dash.tertiaryText)
                        .multilineTextAlignment(.center)
                }

                if let lockout = viewModel.lockoutMessage {
                    Text(lockout)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.dash.red)
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
                    .foregroundColor(.dash.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
        }
        .background(
            // Hidden field owns the system numeric keyboard, exactly as the
            // pod's pinField.becomeFirstResponder did. `.id(fieldGeneration)`
            // recreates it empty after each rejected entry — see
            // `fieldGeneration` for why a programmatic clear isn't enough.
            TextField("", text: Binding(
                get: { viewModel.enteredPin },
                set: { viewModel.inputChanged($0) }))
                .keyboardType(.numberPad)
                .focused($fieldFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .disabled(viewModel.isLockedOut)
                .id(viewModel.fieldGeneration)
        )
        .background(Color.dash.primaryBackground)
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
                            .fill(Color.dash.primaryText)
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
