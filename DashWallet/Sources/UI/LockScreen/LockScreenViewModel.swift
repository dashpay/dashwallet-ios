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

import Combine
import LocalAuthentication
import UIKit

/// What the lock screen shows and does: the PIN entered so far, what the
/// attempt counter allows, and unlocking by PIN or biometrics.
///
/// The PIN rules themselves stay in `AuthenticationService`; this asks it
/// once a second whether entry is allowed — a lockout ends on its own while
/// the screen is up — and hands it each full PIN.
@MainActor
final class LockScreenViewModel: ObservableObject {
    @Published private(set) var pin = ""
    @Published private(set) var title = ""
    /// How many attempts are left, while that is worth saying.
    @Published private(set) var attemptsText: String?
    /// Why no PIN can be entered; it takes the PIN boxes' place.
    @Published private(set) var errorText: String?
    @Published private(set) var isKeypadEnabled = true
    @Published private(set) var isScanEnabled = true
    @Published private(set) var showsBiometricButton = false
    /// Bumped on a wrong PIN, to shake the boxes.
    @Published private(set) var rejections = 0

    let pinLength = LockoutPolicy.pinLength

    /// Called once the wallet is unlocked, by PIN or biometrics.
    var onUnlock: (() -> Void)?

    private let service: AuthenticationService
    private var checkTimer: Timer?
    /// Set while a wrong PIN shakes, so no key lands on the boxes being cleared.
    private var isRejecting = false
    private var biometricsAttemptWasMade = false

    init(service: AuthenticationService = .shared) {
        self.service = service
        refresh()
    }

    // MARK: State

    /// A wallet can be left without a PIN record (a partial keychain restore,
    /// an interrupted setup). No entry could ever match then, so the screen
    /// says so and offers Set PIN, behind the recovery phrase, instead.
    var hasPinSet: Bool { service.hasPin() }

    var biometryType: LABiometryType {
        #if targetEnvironment(simulator)
        // The simulator has no biometrics; show the Touch ID button to work on it.
        return .touchID
        #else
        return service.biometryType
        #endif
    }

    /// After 6 wrong PINs, Forgot PIN also offers to wipe the wallets.
    var isAllowedToWipe: Bool { service.failCount >= 6 }

    private var isBiometricAuthenticationAllowed: Bool {
        DWGlobalOptions.sharedInstance().biometricAuthEnabled && service.isBiometricAuthenticationAllowed
    }

    /// Re-read every second while checking, so a lockout's countdown runs and
    /// the keypad comes back when it ends.
    func startCheckingAuthState() {
        guard checkTimer == nil else { return }
        refresh()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopCheckingAuthState() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func refresh() {
        showsBiometricButton = hasPinSet && isBiometricAuthenticationAllowed

        // No PIN record wins over a stale lockout too: there is nothing to
        // guess, and setting a PIN resets the counters.
        guard hasPinSet else {
            isKeypadEnabled = false
            isScanEnabled = false
            title = String(localized: "PIN Not Set", comment: "")
            attemptsText = nil
            errorText = String(localized: "Verify your recovery phrase to set a new PIN.", comment: "")
            return
        }

        let precheck = service.authenticationPrecheck()
        isKeypadEnabled = precheck.shouldContinueAuthentication
        isScanEnabled = precheck.shouldContinueAuthentication

        if precheck.shouldContinueAuthentication {
            title = String(localized: "Enter PIN", comment: "")
            attemptsText = precheck.attemptsMessage
            errorText = nil
        } else {
            title = String(localized: "Wallet disabled", comment: "")
            attemptsText = nil
            errorText = precheck.shouldLockout
                ? service.lockoutErrorMessage
                : String(localized: "Authentication is unvailable", comment: "")
        }

        if !isKeypadEnabled, !isRejecting {
            pin = ""
        }
    }

    // MARK: PIN entry

    func enter(digit: Int) {
        guard isKeypadEnabled, !isRejecting, pin.count < pinLength else { return }
        pin.append(String(digit))
        if pin.count == pinLength {
            verify()
        }
    }

    func deleteBackward() {
        guard isKeypadEnabled, !isRejecting, !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func verify() {
        stopCheckingAuthState()

        if service.verifyPin(pin) == .authenticated {
            onUnlock?()
            return
        }

        // Shake with all the boxes filled, then clear them, as before.
        isRejecting = true
        rejections += 1
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        startCheckingAuthState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.pin = ""
            self.isRejecting = false
        }
    }

    // MARK: Biometrics

    /// Asks for Face ID or Touch ID once per time the screen comes up — on
    /// launch and on coming back to the app — unless the user is on a quick
    /// action over it.
    func tryOnceToUnlockUsingBiometrics(isCovered: Bool) {
        guard !biometricsAttemptWasMade else { return }
        biometricsAttemptWasMade = true
        guard !isCovered else { return }
        authenticateUsingBiometrics()
    }

    /// The app went to the background: ask again when it comes back.
    func resetBiometricsAttempt() {
        biometricsAttemptWasMade = false
    }

    func authenticateUsingBiometrics() {
        // Not without a PIN record: biometrics would let the user into a
        // wallet where every later PIN check fails. Set PIN repairs it first.
        guard hasPinSet, isBiometricAuthenticationAllowed else { return }

        service.authenticateUsingBiometricsOnly { [weak self] authenticated in
            guard let self else { return }
            if authenticated {
                self.onUnlock?()
            } else {
                self.refresh()
            }
        }
    }
}
