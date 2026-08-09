//
//  DashPayUserLink.swift
//  DashWallet
//
//  QR/link payload identifying a DashPay user: the Platform identity
//  id (base58) plus the preferred DPNS username, encoded as
//
//      dashpay://user?id=<base58-identity-id>&username=<label>
//
//  Rendered as "my QR code" on the add-contact screen and parsed back
//  when another user scans it. Parsing is pure and offline; it proves
//  nothing — the username claim must be verified against Platform
//  (DPNS lookup, identity id match) before it is shown as that user.
//

import Foundation
import SwiftDashSDK

struct DashPayUserLink: Equatable {
    /// 32-byte Platform identity id.
    let identityId: Data
    /// Preferred DPNS label, stored without the ".dash" suffix.
    let username: String

    var identityIdBase58: String { identityId.toBase58String() }

    /// Canonical URI form — the QR payload.
    var uriString: String {
        var components = URLComponents()
        components.scheme = "dashpay"
        components.host = "user"
        components.queryItems = [
            URLQueryItem(name: "id", value: identityIdBase58),
            URLQueryItem(name: "username", value: username),
        ]
        return components.string ?? "dashpay://user"
    }

    /// Parse a scanned string. Accepts only the canonical
    /// `dashpay://user` shape carrying a valid 32-byte base58 `id` and
    /// a non-empty `username` (a trailing ".dash" is tolerated and
    /// stripped). Anything else — payment URIs, invitation links, bare
    /// usernames — returns nil.
    static func parse(_ string: String) -> DashPayUserLink? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "dashpay",
              components.host?.lowercased() == "user"
        else { return nil }

        var identityId: Data?
        var username: String?
        for item in components.queryItems ?? [] {
            switch item.name.lowercased() {
            case "id": identityId = item.value.flatMap { Data.identifier(fromBase58: $0) }
            case "username": username = item.value
            default: break
            }
        }

        guard let identityId, identityId.count == 32 else { return nil }
        let label = (username ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .withoutDashSuffix
        guard !label.isEmpty else { return nil }
        return DashPayUserLink(identityId: identityId, username: label)
    }
}
