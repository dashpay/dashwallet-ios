//
//  PinStore.swift
//  DashWallet
//
//  Byte-compatible store for the auth keychain items DashSync's
//  `DSAuthenticationManager` owns today — the C7 zero-migration strategy:
//  the app-side auth stack adopts the SAME service/accounts/encodings, so
//  existing users' PINs, fail counters and biometric limits carry over
//  with no migration step. Every encoding below is frozen as raw bytes
//  captured from a live DashSync-written keychain in
//  `scripts/auth_keychain_goldens/goldens.txt` (PIN "1111" → `31313131`,
//  int64 little-endian, `pdmn=cku`).
//
//  Layout (service `org.dashfoundation.dash`, this-device-only, never
//  synchronizable):
//    pin                                — UTF-8 string
//    pinfailcount / pinfailheight       — int64, 8-byte native-endian (LE)
//    USES_AUTHENTICATION                — int64 bool (absent ⇒ true)
//    BIOMETRIC_ALLOWED_AMOUNT_LEFT_KEY  — int64 (allowance left)
//    SPEND_LIMIT_AMOUNT                 — int64; the ONE item written
//                                         `WhenUnlockedThisDeviceOnly`
//                                         (all others `AfterFirstUnlock…`)
//
//  `PinCodec` (pure functions) carries the byte contract and is
//  harness-testable without a keychain (scripts/auth_keychain_goldens).
//

import Foundation
import Security

// MARK: - KeychainCodec (pure byte contract)

/// Value ↔ bytes, exactly as DashSync's `setKeychainString`/`setKeychainInt`
/// produce them (NSData+Dash.m): UTF-8 external representation without BOM;
/// `*(int64_t *)bytes = value` — native endianness (little-endian on every
/// supported platform).
enum KeychainCodec {
    static func encode(string: String) -> Data {
        Data(string.utf8)
    }

    static func decodeString(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }

    static func encode(int64 value: Int64) -> Data {
        var le = value.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }

    static func decodeInt64(_ data: Data) -> Int64? {
        guard data.count == MemoryLayout<Int64>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }.littleEndian
    }
}

/// Keep the authentication-facing name used by the frozen golden harness.
typealias PinCodec = KeychainCodec

// MARK: - KeychainStore

/// App-owned access to the generic-password records historically written by
/// DashSync's NSData+Dash helpers. This adopts the existing records in place:
/// callers provide the same service/account/accessibility and no migration or
/// copy is performed.
enum KeychainStore {
    static let dashService = "org.dashfoundation.dash"

    enum Accessibility {
        case whenUnlockedThisDeviceOnly
        case afterFirstUnlockThisDeviceOnly

        fileprivate var securityValue: CFString {
            switch self {
            case .whenUnlockedThisDeviceOnly:
                return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlockThisDeviceOnly:
                return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }

    static func data(service: String = dashService, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    static func string(service: String = dashService, account: String) -> String? {
        data(service: service, account: account).flatMap(KeychainCodec.decodeString)
    }

    /// Matches `getKeychainInt`: a missing or malformed item reads as zero.
    static func int64(service: String = dashService, account: String) -> Int64 {
        data(service: service, account: account).flatMap(KeychainCodec.decodeInt64) ?? 0
    }

    @discardableResult
    static func set(data: Data?,
                    service: String = dashService,
                    account: String,
                    accessibility: Accessibility) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecItemNotFound {
            var attributes = query
            attributes[kSecAttrAccessible as String] = accessibility.securityValue
            attributes[kSecValueData as String] = data
            return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }

        let update: [String: Any] = [
            kSecAttrAccessible as String: accessibility.securityValue,
            kSecValueData as String: data,
        ]
        return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
    }

    @discardableResult
    static func set(string: String?,
                    service: String = dashService,
                    account: String,
                    accessibility: Accessibility) -> Bool {
        set(data: string.map { KeychainCodec.encode(string: $0) },
            service: service,
            account: account,
            accessibility: accessibility)
    }

    @discardableResult
    static func set(int64: Int64,
                    service: String = dashService,
                    account: String,
                    accessibility: Accessibility) -> Bool {
        set(data: KeychainCodec.encode(int64: int64),
            service: service,
            account: account,
            accessibility: accessibility)
    }
}

/// Narrow Objective-C boundary for the two remaining ObjC consumers.
@objc final class DWKeychainStore: NSObject {
    private static func accessibility(authenticated: Bool) -> KeychainStore.Accessibility {
        authenticated ? .whenUnlockedThisDeviceOnly : .afterFirstUnlockThisDeviceOnly
    }

    @objc(dataForAccount:)
    static func data(forAccount account: String) -> Data? {
        KeychainStore.data(account: account)
    }

    @objc(stringForAccount:)
    static func string(forAccount account: String) -> String? {
        KeychainStore.string(account: account)
    }

    @objc(int64ForAccount:)
    static func int64(forAccount account: String) -> Int64 {
        KeychainStore.int64(account: account)
    }

    @objc(setData:forAccount:authenticated:)
    @discardableResult
    static func set(data: Data?, forAccount account: String, authenticated: Bool) -> Bool {
        KeychainStore.set(data: data,
                          account: account,
                          accessibility: accessibility(authenticated: authenticated))
    }

    @objc(setString:forAccount:authenticated:)
    @discardableResult
    static func set(string: String?, forAccount account: String, authenticated: Bool) -> Bool {
        KeychainStore.set(string: string,
                          account: account,
                          accessibility: accessibility(authenticated: authenticated))
    }

    @objc(setInt64:forAccount:authenticated:)
    @discardableResult
    static func set(int64: Int64, forAccount account: String, authenticated: Bool) -> Bool {
        KeychainStore.set(int64: int64,
                          account: account,
                          accessibility: accessibility(authenticated: authenticated))
    }
}

// MARK: - LockoutPolicy (pure)

/// DashSync's PIN-lockout arithmetic, ported verbatim
/// (DSAuthenticationManager.m: ALLOWED/MAX fail counts, `lockoutWaitTime`).
enum LockoutPolicy {
    static let pinLength = 4
    /// Free attempts before the exponential backoff starts.
    static let allowedFailCount: UInt64 = 3
    /// At this wrong-PIN count the wallet is permanently disabled
    /// (wipe-with-phrase is the only recovery).
    static let maxFailCount: UInt64 = 8

    /// Show the "N attempts left before your wallet is disabled" warning
    /// once this few remain before `maxFailCount` — below it a wrong PIN
    /// just shakes (the temporary cooldown at `allowedFailCount` is
    /// communicated by its own countdown, not a counter).
    static let permanentLockWarningThreshold: UInt64 = 2

    /// Remaining lockout in seconds:
    /// `failHeight + 6^(failCount−3)·60 − secureTime` (≤ 0 ⇒ not locked).
    /// `failHeight` is a secure-time timestamp stamped on unique wrong PINs.
    static func waitTime(failCount: UInt64, failHeight: TimeInterval, secureTime: TimeInterval) -> TimeInterval {
        guard failCount >= allowedFailCount else { return 0 }
        let backoff = pow(6.0, Double(failCount) - 3.0) * 60.0 / debugTimeScale
        return failHeight + backoff - secureTime
    }

    /// Smoke shortcut (`SPEED_UP_WAIT_TIME` precedent in the pod):
    /// `DW_LOCKOUT_SCALE=60` in the scheme/simctl launch environment turns
    /// the 6-minute tier into 6 seconds. Environment-gated rather than
    /// `#if DEBUG` — the dashpay target defines no DEBUG Swift compilation
    /// condition, and a production app launch carries no custom environment
    /// (only Xcode/simctl can inject one).
    private static var debugTimeScale: Double {
        if let raw = ProcessInfo.processInfo.environment["DW_LOCKOUT_SCALE"],
           let scale = Double(raw), scale > 0 {
            return scale
        }
        return 1
    }
}

// MARK: - PinStore (keychain I/O)

/// Keychain I/O over the DashSync auth items. Not a migrator: it adopts
/// ownership of the live accounts, so writes here are the same mutations
/// DashSync performs today (`setupNewPin` overwrite, wipe-time `removePin`).
///
/// `service`/`SecItem` plumbing injectable-by-init is deliberately absent —
/// the whole point of this type is the ONE hard-coded, golden-frozen layout;
/// tests exercise `PinCodec`/`LockoutPolicy` (pure) and the runtime parity
/// check covers the I/O.
enum PinStore {
    /// Same constant `SwiftDashSDKKeyMigrator.dashSyncService` reads.
    static let service = KeychainStore.dashService

    enum Account: String {
        case pin
        case pinFailCount = "pinfailcount"
        case pinFailHeight = "pinfailheight"
        case usesAuthentication = "USES_AUTHENTICATION"
        case spendingLimit = "SPEND_LIMIT_AMOUNT"
        case biometricAmountLeft = "BIOMETRIC_ALLOWED_AMOUNT_LEFT_KEY"

    }

    // MARK: Typed accessors

    static func string(for account: Account) -> String? {
        KeychainStore.string(account: account.rawValue)
    }

    static func int64(for account: Account) -> Int64? {
        readData(account: account).flatMap(KeychainCodec.decodeInt64)
    }

    static func hasValue(for account: Account) -> Bool {
        readData(account: account) != nil
    }

    @discardableResult
    static func set(string: String, for account: Account) -> Bool {
        KeychainStore.set(string: string,
                          account: account.rawValue,
                          accessibility: account.keychainAccessibility)
    }

    @discardableResult
    static func set(int64 value: Int64, for account: Account) -> Bool {
        KeychainStore.set(int64: value,
                          account: account.rawValue,
                          accessibility: account.keychainAccessibility)
    }

    @discardableResult
    static func delete(account: Account) -> Bool {
        KeychainStore.set(data: nil,
                          account: account.rawValue,
                          accessibility: account.keychainAccessibility)
    }

    // MARK: Raw I/O

    static func readData(account: Account) -> Data? {
        readData(service: service, account: account.rawValue)
    }

    /// Shared raw read over any `org.dashfoundation.dash`-style item —
    /// also the primitive behind `SwiftDashSDKKeyMigrator`'s mnemonic reads
    /// (promoted here so the byte-level keychain query exists exactly once).
    static func readData(service: String, account: String) -> Data? {
        KeychainStore.data(service: service, account: account)
    }
}

private extension PinStore.Account {
    var keychainAccessibility: KeychainStore.Accessibility {
        switch self {
        case .spendingLimit:
            return .whenUnlockedThisDeviceOnly
        default:
            return .afterFirstUnlockThisDeviceOnly
        }
    }
}
