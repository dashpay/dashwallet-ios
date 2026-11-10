//
//  CallbackScheme.swift
//  DashWallet
//
//  The `sender=` of a payment link names the app that gets an x-callback once the wallet has
//  acted on the link: `<sender>://callback=payack&address=…&txid=…` after a payment,
//  `<sender>://callback=address&address=…&source=dashwallet` after an address request. Whoever
//  writes the link writes `sender`, so it is checked here, once, before anything opens it or
//  shows it to the user.
//
//  Pure: Foundation only.
//

import Foundation

@objc(DWCallbackScheme)
final class CallbackScheme: NSObject {
    /// Schemes the system or the wallet itself answers. A callback to one of these would open a
    /// web page, a call, a message or a settings pane, or send the wallet back to itself.
    private static let blocked: Set<String> = [
        "http", "https", "file", "ftp", "data", "javascript", "about", "blob",
        "tel", "telprompt", "sms", "smsto", "mailto", "message", "maps", "geo", "music", "videos",
        "prefs", "app-prefs", "app-settings", "shortcuts", "workflow", "webcal", "calshow", "feed",
        "shareddocuments", "mobilenotes", "x-web-search",
        // Every scheme in the wallet's own `CFBundleURLSchemes`, and `bitcoin`.
        "dash", "dashwallet", "dashpay", "dashid", "dash-key", "dash-st", "pay", "bitcoin",
    ]
    private static let blockedPrefixes = ["facetime", "itms", "x-apple"]
    /// Longer than any real scheme. The value is shown to the user, so it is kept short.
    private static let maxLength = 64

    private static let schemeTail = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-.")
    private static let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    /// RFC 3986 `unreserved`. A value encoded to this set cannot add a `&`, `=`, `/`, `?` or `#`.
    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// `raw` unchanged when it is a bare custom URL scheme (RFC 3986:
    /// `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`, ASCII only, at most 64 characters) that
    /// neither the system nor the wallet answers. nil otherwise.
    @objc(validated:)
    static func validated(_ raw: String?) -> String? {
        guard let raw, raw.utf8.count <= maxLength,
              let first = raw.unicodeScalars.first, letters.contains(first),
              raw.unicodeScalars.allSatisfy(schemeTail.contains) else {
            return nil
        }
        let lowercased = raw.lowercased()
        guard !blocked.contains(lowercased), !blockedPrefixes.contains(where: lowercased.hasPrefix) else {
            return nil
        }
        return raw
    }

    /// The x-callback the wallet opens after a payment. nil without an address or a valid scheme.
    @objc(payAckURLWithScheme:address:txid:)
    static func payAckURL(scheme: String?, address: String?, txid: String) -> URL? {
        guard let address else { return nil }
        return url(scheme: scheme, items: [("callback", "payack"), ("address", address), ("txid", txid)])
    }

    /// The x-callback that answers a `dashwallet://request=address` link with a receive address.
    @objc(addressRequestURLWithScheme:request:address:)
    static func addressRequestURL(scheme: String?, request: String, address: String?) -> URL? {
        guard let address else { return nil }
        return url(scheme: scheme, items: [("callback", request), ("address", address), ("source", "dashwallet")])
    }

    /// `<scheme>://<name>=<value>&…`. The pairs sit where a host would: that is the form the
    /// wallet has always sent, and the form the receiving apps read. The scheme is checked again
    /// here, so a caller that skipped `validated` still cannot open anything else.
    private static func url(scheme: String?, items: [(name: String, value: String)]) -> URL? {
        guard let scheme = validated(scheme) else { return nil }
        var pairs: [String] = []
        for item in items {
            guard let value = item.value.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
            pairs.append("\(item.name)=\(value)")
        }
        return URL(string: "\(scheme)://\(pairs.joined(separator: "&"))")
    }
}
