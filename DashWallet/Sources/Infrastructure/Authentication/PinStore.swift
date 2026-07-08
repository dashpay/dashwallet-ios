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

// MARK: - PinCodec (pure byte contract)

/// Value ↔ bytes, exactly as DashSync's `setKeychainString`/`setKeychainInt`
/// produce them (NSData+Dash.m): UTF-8 external representation without BOM;
/// `*(int64_t *)bytes = value` — native endianness (little-endian on every
/// supported platform).
enum PinCodec {
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

// MARK: - LockoutPolicy (pure)

/// DashSync's PIN-lockout arithmetic, ported verbatim
/// (DSAuthenticationManager.m: ALLOWED/MAX fail counts, `lockoutWaitTime`).
enum LockoutPolicy {
    static let pinLength = 4
    /// Free attempts before the exponential backoff starts.
    static let allowedFailCount: UInt64 = 3
    /// At this unique-wrong-PIN count the wallet is permanently disabled
    /// (wipe-with-phrase is the only recovery).
    static let maxFailCount: UInt64 = 8

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
    static let service = "org.dashfoundation.dash"

    enum Account: String {
        case pin
        case pinFailCount = "pinfailcount"
        case pinFailHeight = "pinfailheight"
        case usesAuthentication = "USES_AUTHENTICATION"
        case spendingLimit = "SPEND_LIMIT_AMOUNT"
        case biometricAmountLeft = "BIOMETRIC_ALLOWED_AMOUNT_LEFT_KEY"

        /// DashSync's `authenticated:` flag per item: only the spending
        /// limit uses the stricter class (DSAuthenticationManager.m:337).
        var accessibility: CFString {
            switch self {
            case .spendingLimit:
                return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            default:
                return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }

    // MARK: Typed accessors

    static func string(for account: Account) -> String? {
        readData(account: account).flatMap(PinCodec.decodeString)
    }

    static func int64(for account: Account) -> Int64? {
        readData(account: account).flatMap(PinCodec.decodeInt64)
    }

    static func hasValue(for account: Account) -> Bool {
        readData(account: account) != nil
    }

    @discardableResult
    static func set(string: String, for account: Account) -> Bool {
        writeData(PinCodec.encode(string: string), account: account)
    }

    @discardableResult
    static func set(int64 value: Int64, for account: Account) -> Bool {
        writeData(PinCodec.encode(int64: value), account: account)
    }

    @discardableResult
    static func delete(account: Account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: Raw I/O

    static func readData(account: Account) -> Data? {
        readData(service: service, account: account.rawValue)
    }

    /// Shared raw read over any `org.dashfoundation.dash`-style item —
    /// also the primitive behind `SwiftDashSDKKeyMigrator`'s mnemonic reads
    /// (promoted here so the byte-level keychain query exists exactly once).
    static func readData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String:  kSecMatchLimitOne,
            kSecReturnData as String:  true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    /// Add-if-missing, else update-in-place with the accessibility class in
    /// the update dictionary — the exact shape of DashSync's
    /// `setKeychainData` (NSData+Dash.m:38-73), so no transient no-item
    /// window exists during a write.
    private static func writeData(_ data: Data, account: Account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecItemNotFound {
            var attributes = query
            attributes[kSecAttrAccessible as String] = account.accessibility
            attributes[kSecValueData as String] = data
            return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }
        let update: [String: Any] = [
            kSecAttrAccessible as String: account.accessibility,
            kSecValueData as String:      data,
        ]
        return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
    }
}
