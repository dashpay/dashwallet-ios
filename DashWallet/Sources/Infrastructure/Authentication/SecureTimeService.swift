//
//  SecureTimeService.swift
//  DashWallet
//
//  The auth stack's trusted clock — the D5 hybrid (decision 2026-07-08):
//  a never-decreasing local ratchet re-fed opportunistically from the
//  `Date` header of the app's own HTTPS traffic (the CTX rates poll runs
//  every 60 s, so the clock tracks real time whenever the app is online).
//
//  Persists to the SAME UserDefaults key DashSync's
//  `DSAuthenticationManager` reads for its PIN-lockout countdown
//  (`SECURE_TIME`), with the same only-forward update rule — so feeding
//  it fixes Bug #2 (a lockout frozen against the post-M6 dead DashSync
//  clock) for users mid-lockout with zero state migration, and the
//  eventual app-side LockoutPolicy inherits the value seamlessly.
//
//  Deliberate delta vs DashSync: its "rare case" allowed lowering a
//  corrupted-forward value when the server time still beat the chain
//  checkpoint/tip timestamps. We have no chain clock to cross-check
//  against, so this service never decreases the stored value — a
//  too-far-forward clock only ever shortens a lockout (the residual
//  D5 explicitly accepts).
//
//  Singleton justification (guardrail 4): one persisted scalar with a
//  cross-launch monotonicity invariant; `init(userDefaults:)` is the
//  test seam.
//

import Foundation

@objc(DWSecureTimeService)
final class SecureTimeService: NSObject {

    @objc static let shared = SecureTimeService()

    /// Same literal DashSync's `SECURE_TIME_KEY` writes/reads.
    private static let secureTimeKey = "SECURE_TIME"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// The trusted "now" (seconds since 1970): the stored ratchet advanced
    /// to the wall clock first, so offline devices' lockouts still elapse.
    @objc var currentSecureTime: TimeInterval {
        ratchetToWallClock()
        return userDefaults.double(forKey: Self.secureTimeKey)
    }

    /// Advance the stored value to the local wall clock (never backward).
    /// Called at app launch (AppDelegate) and on every read, so the ratchet
    /// moves even when no HTTP traffic ever happens.
    @objc func ratchetToWallClock() {
        advance(to: Date().timeIntervalSince1970)
    }

    /// Feed a server-authenticated timestamp (TLS-protected `Date` response
    /// header). Only ever moves the clock forward.
    func observe(serverDate: Date) {
        advance(to: serverDate.timeIntervalSince1970)
    }

    /// RFC-1123 `Date` header parser (`Sun, 06 Nov 1994 08:49:37 GMT`).
    /// Returns nil for absent/malformed headers — callers just skip the feed.
    static func parseHTTPDate(_ header: String) -> Date? {
        httpDateFormatter.date(from: header)
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private func advance(to candidate: TimeInterval) {
        let stored = userDefaults.double(forKey: Self.secureTimeKey)
        if candidate > stored {
            userDefaults.set(candidate, forKey: Self.secureTimeKey)
        }
    }
}
