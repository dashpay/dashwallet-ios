//
//  DWInvitationLinkNormalizer.swift
//  DashWallet
//
//  Normalizes every inbound DashPay-invitation transport down to the
//  canonical URI the SDK parser (`ManagedPlatformWallet.parseInvitation`)
//  accepts. Pure string/URL logic — no SDK, no network — so it is
//  unit-testable and safe to call from Obj-C deep-link plumbing.
//
//  Accepted transports:
//    1. `dashpay://invite?…` — the canonical DIP-13 link (also what
//       Android's `InvitationLinkData` emits). Passed through verbatim.
//    2. `https://invitations.dashpay.io/applink?…` — the legacy
//       universal-link form. The SDK parser accepts it natively, so it
//       is passed through verbatim too.
//    3. AppsFlyer OneLink URLs from Android-generated invites
//       (`dashpay.onelink.me` / `dashpaytest.onelink.me`) — the inner
//       `dashpay://invite` URI rides in a query parameter; unwrapped
//       here (checked in Android's key order: af_dp, deep_link_value,
//       link, af_sub1) and re-normalized.
//
//  The returned URI embeds the voucher private key (`pk`) — a bearer
//  credential. Never log it.
//

import Foundation

@objc(DWInvitationLinkNormalizer)
final class DWInvitationLinkNormalizer: NSObject {

    private static let invitationScheme = "dashpay"
    private static let invitationHost = "invite"
    private static let applinkHost = "invitations.dashpay.io"
    private static let applinkPath = "/applink"
    private static let oneLinkHosts: Set<String> = [
        "dashpay.onelink.me",
        "dashpaytest.onelink.me",
    ]
    /// OneLink query keys that may carry the inner deep link, in the
    /// order Android's attribution handler tries them
    /// (`WalletApplication.extractDeepLink`).
    private static let oneLinkPayloadKeys = ["af_dp", "deep_link_value", "link", "af_sub1"]

    private override init() {}

    /// Canonical invitation URI for any accepted transport, or nil when
    /// the input is not an invitation link. Pasted text is trimmed; the
    /// result is suitable for `ManagedPlatformWallet.parseInvitation`
    /// (which performs the actual structural validation — this function
    /// only recognizes and unwraps transports).
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return normalize(url)
    }

    /// URL-typed variant of `normalize(_:)`.
    static func normalize(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let host = url.host?.lowercased() ?? ""

        switch scheme {
        case invitationScheme:
            guard host == invitationHost else { return nil }
            return url.absoluteString

        case "https", "http":
            if host == applinkHost {
                // Tolerate the hosting redirect's trailing slash, same
                // as the SDK parser.
                guard url.path.trimmingSuffix("/") == applinkPath else { return nil }
                return url.absoluteString
            }
            if oneLinkHosts.contains(host) {
                return unwrapOneLink(url)
            }
            return nil

        default:
            return nil
        }
    }

    /// Obj-C entry for the AppDelegate's URL routing: `true` when the
    /// URL is one of the invitation transports (without validating the
    /// payload — that happens at parse time in the claim flow).
    @objc static func isInvitationURL(_ url: URL) -> Bool {
        normalize(url) != nil
    }

    /// Extract and re-normalize the inner deep link from a OneLink
    /// long-form URL. Short OneLinks carry no payload in the URL and
    /// cannot be resolved without the AppsFlyer SDK — those return nil
    /// (the redeem UI's paste hint covers them).
    private static func unwrapOneLink(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        for key in oneLinkPayloadKeys {
            guard let value = items.first(where: { $0.name == key })?.value,
                  !value.isEmpty else { continue }
            if let inner = normalize(value) {
                return inner
            }
        }
        return nil
    }
}

private extension String {
    /// `hasSuffix`-conditional drop, e.g. `"/applink/" → "/applink"`.
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
