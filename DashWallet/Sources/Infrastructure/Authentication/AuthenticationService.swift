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

    private let secureTimeService: SecureTimeService
    private let userDefaults: UserDefaults

    /// Unique wrong PINs of the current process lifetime — re-entering the
    /// same wrong PIN never double-increments the fail counter (pod parity;
    /// in-memory there too, so losing it on relaunch matches).
    private var failedPins = Set<String>()

    @objc private(set) var didAuthenticate = false

    init(secureTime: SecureTimeService = .shared, userDefaults: UserDefaults = .standard) {
        self.secureTimeService = secureTime
        self.userDefaults = userDefaults
    }

    // MARK: Session

    /// Keychain `USES_AUTHENTICATION`; an absent item reads as true
    /// (pod parity — the flag can be set, never unset).
    @objc var usesAuthentication: Bool {
        guard let value = PinStore.int64(for: .usesAuthentication) else { return true }
        return value != 0
    }

    // MARK: PIN lifecycle

    @objc func hasPin() -> Bool {
        PinStore.hasValue(for: .pin)
    }

    /// Pod's `setupNewPin:` — write the PIN, flip the flags, stamp the
    /// biometric window.
    @objc @discardableResult
    func setupNewPin(_ pin: String) -> Bool {
        guard PinStore.set(string: pin, for: .pin) else { return false }
        PinStore.set(int64: 1, for: .usesAuthentication)
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

    /// Ported from `performPinVerificationAgainstCurrentPin:` (:896-940):
    /// unique attempts pre-increment the fail counter, success resets
    /// everything, unique failures stamp `failHeight` with secure time.
    @objc func verifyPin(_ inputPin: String) -> PinVerification {
        guard let storedPin = PinStore.string(for: .pin) else { return .storeError }
        let previousFailCount = failCount

        if !failedPins.contains(inputPin) {
            PinStore.set(int64: Int64(bitPattern: previousFailCount &+ 1), for: .pinFailCount)
        }

        if inputPin == storedPin {
            failedPins.removeAll()
            didAuthenticate = true
            PinStore.set(int64: 0, for: .pinFailCount)
            PinStore.set(int64: 0, for: .pinFailHeight)
            resetSpendingLimitsIfAuthenticated()
            userDefaults.set(Date().timeIntervalSince1970, forKey: Self.pinUnlockTimeKey)
            return .authenticated
        }

        if !failedPins.contains(inputPin) {
            failedPins.insert(inputPin)

            let secureTime = self.secureTime
            let storedHeight = TimeInterval(PinStore.int64(for: .pinFailHeight) ?? 0)
            if secureTime > storedHeight {
                PinStore.set(int64: Int64(secureTime), for: .pinFailHeight)
            }

            if previousFailCount >= LockoutPolicy.allowedFailCount {
                return .wrongPinLockout
            }
        }

        return .wrongPinTryAgain
    }

    struct Precheck {
        let shouldContinueAuthentication: Bool
        let shouldLockout: Bool
        /// "N attempt(s) remaining" once past the free attempts; nil before.
        let attemptsMessage: String?
    }

    /// Ported from `performAuthenticationPrecheck:` (:826-878).
    func authenticationPrecheck() -> Precheck {
        let count = failCount
        if count >= LockoutPolicy.maxFailCount {
            return Precheck(shouldContinueAuthentication: false, shouldLockout: true, attemptsMessage: nil)
        }
        if count >= LockoutPolicy.allowedFailCount {
            if lockoutWaitTime > 0 {
                return Precheck(shouldContinueAuthentication: false, shouldLockout: true, attemptsMessage: nil)
            }
            let remaining = LockoutPolicy.maxFailCount - count
            let message = String(format: NSLocalizedString("%ld attempt(s) remaining", comment: ""), Int(remaining))
            return Precheck(shouldContinueAuthentication: true, shouldLockout: false, attemptsMessage: message)
        }
        return Precheck(shouldContinueAuthentication: true, shouldLockout: false, attemptsMessage: nil)
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

    // MARK: Secure time

    @objc var secureTime: TimeInterval {
        secureTimeService.currentSecureTime
    }
}

// MARK: - DEBUG DashSync parity check

extension AuthenticationService {
    /// TODO(C7-final: remove) — one-shot launch assertion that `PinStore`
    /// reads agree with the still-live `DSAuthenticationManager` getters,
    /// guarding the byte-compatibility contract across the whole C7 window.
    /// Reads only; never mutates either side.
    ///
    /// Not `#if DEBUG` on the Swift side — the dashpay target defines no
    /// DEBUG Swift compilation condition (only the ObjC preprocessor flag).
    /// The sole call site (AppDelegate) is ObjC `#if DEBUG`-gated, so this
    /// is unreachable in Release; `assertionFailure` no-ops there anyway.
    @objc static func debugAssertDashSyncParity() {
        let pod = DSAuthenticationManager.sharedInstance()
        let service = AuthenticationService.shared

        // getPin: (nullable NSString*, NSError**) imports as throwing —
        // `try?` collapses read-error and no-item to nil, which is exactly
        // the comparison we want. The strongest possible check: decoded-PIN
        // string equality across the two stacks.
        let podPin = try? pod.getPin()
        assertParity(podPin == PinStore.string(for: .pin),
                     "pin mismatch: pod=\(podPin == nil ? "nil" : "set") new=\(PinStore.string(for: .pin) == nil ? "nil" : "set")")

        var error: NSError?
        let podFailCount = pod.getFailCount(&error)
        assertParity(error == nil, "failCount read error \(String(describing: error))")
        assertParity(podFailCount == service.failCount, "failCount mismatch: pod=\(podFailCount) new=\(service.failCount)")

        assertParity(pod.usesAuthentication == service.usesAuthentication, "usesAuthentication mismatch")

        // Same persisted inputs + same formula ⇒ the two lockout clocks may
        // differ only by the secureTime read between the two calls (≤1s
        // skew). Compare only in the range the pod defines the value for:
        // below ALLOWED_FAIL_COUNT its uint64 `failCount - 3` underflows and
        // the getter returns inf (never consumed there — the precheck guards
        // it); our policy returns an honest 0 instead.
        if podFailCount >= LockoutPolicy.allowedFailCount {
            let podWait = pod.lockoutWaitTime
            let newWait = service.lockoutWaitTime
            assertParity(abs(podWait - newWait) < 2.0, "lockoutWaitTime mismatch: pod=\(podWait) new=\(newWait)")
        }

        NSLog("C7 PARITY :: PinStore agrees with DSAuthenticationManager (pinSet=\(podPin != nil) failCount=\(podFailCount))")
    }

    private static func assertParity(_ condition: Bool, _ message: String) {
        if !condition {
            NSLog("C7 PARITY FAILURE :: %@", message)
            assertionFailure("C7 keychain parity failure: \(message)")
        }
    }
}
