//
//  AuthenticationService.swift
//  DashWallet
//
//  App-side PIN/biometric authentication core (C7) — the replacement for
//  DashSync's `DSAuthenticationManager`, over the byte-compatible
//  `PinStore` and the D5 `SecureTimeService` clock. This file holds the
//  NON-presenting half: PIN lifecycle, verification with the ported
//  fail-count/lockout semantics, session state, and the biometric
//  spending-limit policy. The interactive prompt (the SwiftUI modal that
//  replaces the pod's `DSRequestPinViewController`) lands with the
//  `AuthenticationGate` flip (C7.3).
//
//  Semantics are ported line-for-line from `DSAuthenticationManager.m`
//  (`performPinVerificationAgainstCurrentPin:` :896-940,
//  `performAuthenticationPrecheck:` :826-878, spending limits :306-374) —
//  see the goldens in `scripts/auth_keychain_goldens/` for the byte
//  contract this relies on.
//
//  Protocol seam (guardrail 4): consumers type against
//  `AuthenticationServiceProtocol`; `shared` is the default instance and
//  `init(secureTime:)` the test seam.
//

import Foundation
import LocalAuthentication
import os.log
import UIKit

// MARK: - Protocol

protocol AuthenticationServiceProtocol: AnyObject {
    // Session
    var didAuthenticate: Bool { get }
    var usesAuthentication: Bool { get }

    // PIN lifecycle
    func hasPin() -> Bool
    @discardableResult func setupNewPin(_ pin: String) -> Bool
    func removePin()

    // Verification primitives (non-presenting; the lock screen and the
    // C7.3 modal drive these)
    func verifyPin(_ inputPin: String) -> AuthenticationService.PinVerification
    func authenticationPrecheck() -> AuthenticationService.Precheck
    var failCount: UInt64 { get }
    var lockoutWaitTime: TimeInterval { get }

    // Biometric policy
    var biometryType: LABiometryType { get }
    var isBiometricAuthenticationAllowed: Bool { get }
    func canUseBiometricAuthentication(forAmount amount: UInt64) -> Bool
    func updateBiometricsAmountLeft(afterSpending amount: UInt64)
    @discardableResult func setBiometricSpendingLimitIfAuthenticated(_ limit: UInt64) -> Bool
    var biometricSpendingLimit: UInt64 { get }

    var secureTime: TimeInterval { get }
}

// MARK: - Service

@objc(DWAuthenticationService)
final class AuthenticationService: NSObject, AuthenticationServiceProtocol {

    @objc static let shared = AuthenticationService()

    /// `BIOMETRIC_SPENDING_LIMIT_NOT_SET` — the pod's "no limit" sentinel.
    static let spendingLimitNotSet = UInt64.max

    /// UserDefaults key DashSync stamps on PIN success; gates the 7-day
    /// biometric re-enable window. Same literal (`PIN_UNLOCK_TIME_KEY`).
    private static let pinUnlockTimeKey = "PIN_UNLOCK_TIME"

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "authentication")

    private let secureTimeService: SecureTimeService
    private let userDefaults: UserDefaults

    private var sessionAuthenticated = false

    /// Copy for the lock screen: how many attempts remain before the
    /// permanent lock.
    var remainingAttempts: UInt64 {
        failCount >= LockoutPolicy.maxFailCount ? 0 : LockoutPolicy.maxFailCount - failCount
    }

    /// Set on PIN/biometric success, cleared when the app backgrounds so the
    /// lock screen re-arms (pod parity — `applicationDidEnterBackground` reset
    /// `didAuthenticate`).
    @objc var didAuthenticate: Bool {
        get { sessionAuthenticated }
        set { sessionAuthenticated = newValue }
    }

    override init() {
        self.secureTimeService = .shared
        self.userDefaults = .standard
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(deauthenticateOnBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// Test seam.
    init(secureTime: SecureTimeService, userDefaults: UserDefaults) {
        self.secureTimeService = secureTime
        self.userDefaults = userDefaults
        super.init()
    }

    @objc private func deauthenticateOnBackground() {
        sessionAuthenticated = false
    }

    // MARK: Session

    /// Keychain `USES_AUTHENTICATION`; an absent item reads as true
    /// (pod parity — the flag can be set, never unset).
    @objc var usesAuthentication: Bool {
        guard let value = PinStore.int64(for: .usesAuthentication) else { return true }
        return value != 0
    }

    private var didRunEnableAuthenticationCheck = false

    /// Pod's `setOneTimeShouldUseAuthentication:YES`, called once at launch:
    /// persist the enabled flag on first run, and upgrade a legacy "disabled"
    /// (0) flag to enabled. Never disables authentication. Idempotent; the
    /// run-once guard mirrors the pod's `dispatch_once`.
    @objc func enableAuthenticationIfNeeded() {
        guard !didRunEnableAuthenticationCheck else { return }
        didRunEnableAuthenticationCheck = true

        let stored = PinStore.int64(for: .usesAuthentication)
        if stored == nil || stored == 0 {
            PinStore.set(int64: 1, for: .usesAuthentication)
        }
    }

    // MARK: PIN lifecycle

    @objc func hasPin() -> Bool {
        PinStore.hasValue(for: .pin)
    }

    /// The stored PIN, or nil when none is set. The pod's `getPin:` for the
    /// callers that need the digits directly (wallet create/recover, which
    /// hand the PIN to SwiftDashSDK).
    @objc var currentPin: String? {
        PinStore.string(for: .pin)
    }

    /// Pod's `setupNewPin:` — write the PIN, flip the flags, stamp the
    /// biometric window.
    ///
    /// Deliberate divergence from the pod: also zero the fail counters. Every
    /// call site carries strong auth — new-wallet setup, change-PIN (the
    /// Security menu PIN-verifies first), and forgot-PIN (seed-phrase proof) —
    /// so a new PIN must not inherit failures banked against the old one.
    /// The pod left them, which (a) let a fresh wallet inherit a stale
    /// keychain counter from a previous install and (b) made forgot-PIN
    /// recovery from the permanent lockout a dead end (the keypad stayed
    /// disabled, and only a successful PIN entry — impossible while
    /// disabled — could clear the counter).
    @objc @discardableResult
    func setupNewPin(_ pin: String) -> Bool {
        guard PinStore.set(string: pin, for: .pin) else { return false }
        PinStore.set(int64: 1, for: .usesAuthentication)
        PinStore.set(int64: 0, for: .pinFailCount)
        PinStore.set(int64: 0, for: .pinFailHeight)
        didAuthenticate = true
        userDefaults.set(Date().timeIntervalSince1970, forKey: Self.pinUnlockTimeKey)
        return true
    }

    /// Wipe-path only (`DWEnvironment.clearAllWalletsAndRemovePin`).
    @objc func removePin() {
        PinStore.delete(account: .pin)
        PinStore.delete(account: .pinFailCount)
        PinStore.delete(account: .pinFailHeight)
        didAuthenticate = false
    }

    // MARK: Verification

    /// Result shape of the pod's 4-flag verification completion, minus the
    /// UI-only `cancelled`.
    @objc(DWPinVerification) enum PinVerification: Int {
        /// Wrong PIN, another prompt round is allowed.
        case wrongPinTryAgain
        case authenticated
        /// Wrong PIN and the fail count crossed the lockout threshold.
        case wrongPinLockout
        /// Keychain read failure — treat as terminal for this round.
        case storeError
    }

    /// Success resets counters + biometric allowance; a wrong PIN increments
    /// the fail counter and re-stamps `failHeight` to the current secure time
    /// so the backoff window restarts from the latest attempt.
    ///
    /// Deliberate divergence from `performPinVerificationAgainstCurrentPin:`
    /// (:896-940): DashSync deduplicated identical wrong PINs via an
    /// in-memory `failedPins` set, so re-entering the same wrong code never
    /// advanced the counter. Owner decision 2026-07-08: count every attempt —
    /// the dedup only shielded a fumbling legit user (an attacker types
    /// distinct guesses regardless) and made the lock untestable/ineffective.
    @objc func verifyPin(_ inputPin: String) -> PinVerification {
        guard let storedPin = PinStore.string(for: .pin) else { return .storeError }

        if inputPin == storedPin {
            didAuthenticate = true
            PinStore.set(int64: 0, for: .pinFailCount)
            PinStore.set(int64: 0, for: .pinFailHeight)
            resetSpendingLimitsIfAuthenticated()
            userDefaults.set(Date().timeIntervalSince1970, forKey: Self.pinUnlockTimeKey)
            return .authenticated
        }

        let previousFailCount = failCount
        let newFailCount = previousFailCount &+ 1
        PinStore.set(int64: Int64(bitPattern: newFailCount), for: .pinFailCount)
        PinStore.set(int64: Int64(secureTime), for: .pinFailHeight)

        // Never log the PIN itself. The transition makes a surprise lockout
        // diagnosable from the log stream (banked counter vs. double-counted
        // entry).
        Self.logger.notice("PIN verify failed: failCount \(previousFailCount) → \(newFailCount)")

        return newFailCount >= LockoutPolicy.allowedFailCount ? .wrongPinLockout : .wrongPinTryAgain
    }

    struct Precheck {
        let shouldContinueAuthentication: Bool
        let shouldLockout: Bool
        /// "N attempt(s) remaining" once past the free attempts; nil before.
        let attemptsMessage: String?
    }

    /// Ported from `performAuthenticationPrecheck:` (:826-878), with the
    /// attempts-remaining message surfaced from the first failure on (not
    /// only past the free attempts) so the modal always shows live feedback.
    /// Two tiers with distinct copy so the temporary cooldown at 3 doesn't
    /// get confused with the PERMANENT (wipe-only) lock at 8: below the
    /// cooldown it counts toward the cooldown; near the permanent lock it
    /// warns about the wallet being disabled.
    func authenticationPrecheck() -> Precheck {
        let count = failCount
        if count >= LockoutPolicy.maxFailCount {
            return Precheck(shouldContinueAuthentication: false, shouldLockout: true, attemptsMessage: nil)
        }
        if count >= LockoutPolicy.allowedFailCount, lockoutWaitTime > 0 {
            return Precheck(shouldContinueAuthentication: false, shouldLockout: true, attemptsMessage: nil)
        }
        let remaining = LockoutPolicy.maxFailCount - count
        if count > 0, remaining <= LockoutPolicy.permanentLockWarningThreshold {
            let message = String(format: NSLocalizedString("%ld attempt(s) left before your wallet is disabled", comment: ""), Int(remaining))
            return Precheck(shouldContinueAuthentication: true, shouldLockout: false, attemptsMessage: message)
        }
        if count > 0, count < LockoutPolicy.allowedFailCount {
            let untilCooldown = LockoutPolicy.allowedFailCount - count
            let message = String(format: NSLocalizedString("%ld attempt(s) remaining", comment: "PIN attempts before temporary lockout"), Int(untilCooldown))
            return Precheck(shouldContinueAuthentication: true, shouldLockout: false, attemptsMessage: message)
        }
        return Precheck(shouldContinueAuthentication: true, shouldLockout: false, attemptsMessage: nil)
    }

    // MARK: Lock-screen ObjC facades (DWLockScreenModel / DWSetPinModel)

    /// ObjC-visible box for `Precheck` (the struct can't cross into ObjC).
    @objc(DWAuthPrecheck)
    final class ObjCPrecheck: NSObject {
        @objc let shouldContinueAuthentication: Bool
        @objc let shouldLockout: Bool
        @objc let attemptsMessage: String?
        init(_ precheck: Precheck) {
            shouldContinueAuthentication = precheck.shouldContinueAuthentication
            shouldLockout = precheck.shouldLockout
            attemptsMessage = precheck.attemptsMessage
        }
    }

    @objc func authenticationPrecheckObjc() -> ObjCPrecheck {
        ObjCPrecheck(authenticationPrecheck())
    }

    /// Whether `pin` matches (recording the failure/success as `verifyPin`
    /// does). The lock screen only needs the boolean.
    @objc(verifyPinString:)
    func verifyPinObjc(_ pin: String) -> Bool {
        verifyPin(pin) == .authenticated
    }

    /// Biometrics-only unlock (no PIN fallback) — the lock screen's
    /// Face/Touch ID button.
    @MainActor
    @objc func authenticateUsingBiometricsOnly(_ completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let result = await evaluateBiometrics()
            if case .success = result { didAuthenticate = true }
            completion(result == .success)
        }
    }

    @objc var maxFailCount: UInt64 { LockoutPolicy.maxFailCount }

    // MARK: - Biometric capability (DSBiometricsAuthenticator replacement)

    /// Biometric hardware present and enrolled.
    @objc var biometricsAuthenticationEnabled: Bool { biometryType != .none }
    @objc var touchIDEnabled: Bool { biometryType == .touchID }
    @objc var faceIDEnabled: Bool { biometryType == .faceID }

    /// A device passcode is set (gates whether wallet operations are allowed).
    @objc var passcodeEnabled: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// One-shot biometric evaluation for the enable-biometrics setup flow
    /// (pod's `DSBiometricsAuthenticator.performBiometricsAuthentication…`).
    @MainActor
    @objc func performBiometricsAuthentication(reason: String, completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let result = await evaluateBiometrics(reason: reason)
            completion(result == .success)
        }
    }

    @objc var failCount: UInt64 {
        UInt64(bitPattern: PinStore.int64(for: .pinFailCount) ?? 0)
    }

    @objc var lockoutWaitTime: TimeInterval {
        LockoutPolicy.waitTime(
            failCount: failCount,
            failHeight: TimeInterval(PinStore.int64(for: .pinFailHeight) ?? 0),
            secureTime: secureTime)
    }

    // MARK: Biometric policy

    @objc var biometryType: LABiometryType {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return .none
        }
        return context.biometryType
    }

    /// Hardware available AND a PIN entry within the last 7 days AND a clean
    /// fail counter (pod's `isBiometricAuthenticationAllowed`).
    @objc var isBiometricAuthenticationAllowed: Bool {
        guard biometryType != .none else { return false }
        let pinUnlockTime = userDefaults.double(forKey: Self.pinUnlockTimeKey)
        return pinUnlockTime + 7 * 24 * 60 * 60 > Date().timeIntervalSince1970
            && failCount == 0
    }

    @objc func canUseBiometricAuthentication(forAmount amount: UInt64) -> Bool {
        guard isBiometricAuthenticationAllowed else { return false }
        guard let left = PinStore.int64(for: .biometricAmountLeft) else { return false }
        return amount <= UInt64(bitPattern: left)
    }

    /// Pod's `updateBiometricsAmountLeftAfterSpendingAmount:` — subtract, or
    /// zero the allowance when it can't cover the amount.
    @objc func updateBiometricsAmountLeft(afterSpending amount: UInt64) {
        let left = UInt64(bitPattern: PinStore.int64(for: .biometricAmountLeft) ?? 0)
        let remaining = left >= amount ? left - amount : 0
        PinStore.set(int64: Int64(bitPattern: remaining), for: .biometricAmountLeft)
    }

    /// Zero the allowance (pod parity on a failed biometric evaluate: the
    /// next spend requires the PIN).
    @objc func zeroBiometricsAmountLeft() {
        PinStore.set(int64: 0, for: .biometricAmountLeft)
    }

    @objc @discardableResult
    func setBiometricSpendingLimitIfAuthenticated(_ limit: UInt64) -> Bool {
        guard didAuthenticate else { return false }
        guard PinStore.set(int64: Int64(bitPattern: limit), for: .biometricAmountLeft) else { return false }
        PinStore.set(int64: Int64(bitPattern: limit), for: .spendingLimit)
        return true
    }

    /// Keychain limit, with the pod's legacy NSUserDefaults migrate-on-read
    /// fallback (pre-keychain installs; same `SPEND_LIMIT_AMOUNT` literal).
    @objc var biometricSpendingLimit: UInt64 {
        if !PinStore.hasValue(for: .spendingLimit) {
            let legacy = userDefaults.double(forKey: PinStore.Account.spendingLimit.rawValue)
            guard legacy != 0 else { return Self.spendingLimitNotSet }
            if setBiometricSpendingLimitIfAuthenticated(UInt64(legacy)) {
                userDefaults.removeObject(forKey: PinStore.Account.spendingLimit.rawValue)
            } else {
                return Self.spendingLimitNotSet
            }
        }
        return UInt64(bitPattern: PinStore.int64(for: .spendingLimit) ?? 0)
    }

    @objc @discardableResult
    func resetSpendingLimitsIfAuthenticated() -> Bool {
        guard didAuthenticate else { return false }
        let limit = biometricSpendingLimit
        if limit > 0 {
            PinStore.set(int64: Int64(bitPattern: limit), for: .biometricAmountLeft)
        }
        return true
    }

    // MARK: Interactive authentication

    enum AuthOutcome {
        case authenticated(usedBiometrics: Bool)
        case cancelled
        case failed
    }

    /// The presenting entry point behind `AuthenticationGate`. Biometrics are
    /// attempted only when allowed AND (for a spend) within the remaining
    /// allowance; a biometric failure zeroes the allowance and falls through
    /// to the PIN modal, matching the pod. `spendAmount` threads Bug #3's
    /// limit enforcement (wired at the call sites in C7.4); nil for
    /// non-monetary gates.
    @MainActor
    func authenticate(usingBiometrics: Bool, spendAmount: UInt64?) async -> AuthOutcome {
        guard usesAuthentication else { return .authenticated(usedBiometrics: false) }

        let biometricsPermitted: Bool = {
            guard usingBiometrics, isBiometricAuthenticationAllowed else { return false }
            if let amount = spendAmount { return canUseBiometricAuthentication(forAmount: amount) }
            return true
        }()

        if biometricsPermitted {
            switch await evaluateBiometrics() {
            case .success:
                didAuthenticate = true
                if let amount = spendAmount { updateBiometricsAmountLeft(afterSpending: amount) }
                return .authenticated(usedBiometrics: true)
            case .cancelled:
                return .cancelled
            case .failed:
                zeroBiometricsAmountLeft() // next spend requires PIN (pod parity)
                // fall through to PIN
            }
        }

        switch await PinPromptPresenter.present(service: self) {
        case .authenticated:
            return .authenticated(usedBiometrics: false)
        case .cancelled:
            return .cancelled
        case .failed:
            return .failed
        }
    }

    /// Pod-selector-compatible completion facade so the direct
    /// `DSAuthenticationManager.authenticate(withPrompt:...)` call sites cut
    /// over mechanically. `prompt` is accepted and ignored (every app caller
    /// passes nil); `alertIfLockout` is implicit — the modal renders lockout
    /// inline. Completion tuple: (authenticatedOrSuccess, usedBiometrics,
    /// cancelled), matching the pod.
    @objc(authenticateWithPrompt:usingBiometricAuthentication:alertIfLockout:completion:)
    func authenticate(withPrompt prompt: String?,
                      usingBiometricAuthentication biometric: Bool,
                      alertIfLockout: Bool,
                      completion: @escaping (Bool, Bool, Bool) -> Void) {
        Task { @MainActor in
            switch await authenticate(usingBiometrics: biometric, spendAmount: nil) {
            case .authenticated(let usedBiometrics):
                completion(true, usedBiometrics, false)
            case .cancelled:
                completion(false, false, true)
            case .failed:
                completion(false, false, false)
            }
        }
    }

    private enum BiometricResult { case success, cancelled, failed }

    @MainActor
    private func evaluateBiometrics(
        reason: String = NSLocalizedString("Authenticate to access your wallet", comment: "Biometric prompt")
    ) async -> BiometricResult {
        let context = LAContext()
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .success)
                } else if let laError = error as? LAError, laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
                    continuation.resume(returning: .cancelled)
                } else {
                    continuation.resume(returning: .failed)
                }
            }
        }
    }

    // MARK: Secure time

    @objc var secureTime: TimeInterval {
        secureTimeService.currentSecureTime
    }
}
