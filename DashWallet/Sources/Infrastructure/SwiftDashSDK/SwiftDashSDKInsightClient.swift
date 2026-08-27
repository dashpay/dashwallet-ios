//
//  SwiftDashSDKInsightClient.swift
//  DashWallet
//
//  Minimal port of DashSync's `DSInsightManager findExistingAddresses:` —
//  the on-chain address-existence check the phrase-repair engine uses to
//  pick the one candidate word whose wallet actually exists. Faithful to
//  the original (DSInsightManager.m:199–247):
//    • POST {base}/addrs/txs with a form body `addrs=<comma-joined list>`
//    • 20 s timeout, cache ignored, no pagination params, no retry
//      (DashSync's "failover" URL is byte-identical to the primary)
//    • an address "exists" if it appears in any returned item's
//      `vin[].addr` or `vout[].scriptPubKey.addresses[]`
//  Deliberate deviation: we set the Content-Type header DashSync omitted.
//
//  Mainnet is HARDCODED — phrase repair always recovers against mainnet,
//  exactly like DashSync (`[DSChain mainnet]` in DSBIP39Mnemonic.m:542).
//  The URLSession is injected so tests can stub transport via URLProtocol.
//

import Foundation

// MARK: - InsightAddressQuerying

/// Transport seam for the phrase-repair engine: which of `addresses`
/// have any transaction history on mainnet?
protocol InsightAddressQuerying {
    func findExistingAddresses(_ addresses: [String]) async throws -> Set<String>
}

// MARK: - InsightClient

final class InsightClient: InsightAddressQuerying {

    enum InsightError: Error {
        case invalidResponse // non-HTTP / non-2xx / missing `items`
    }

    /// Mainnet Insight API base (same constant DashSync used).
    private static let mainnetBaseURL = URL(string: "https://insight.dash.org/insight-api")!

    private let session: URLSession

    init(session: URLSession = InsightClient.makeDefaultSession()) {
        self.session = session
    }

    static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20.0
        return URLSession(configuration: configuration)
    }

    func findExistingAddresses(_ addresses: [String]) async throws -> Set<String> {
        guard !addresses.isEmpty else { return [] }

        var request = URLRequest(url: Self.mainnetBaseURL.appendingPathComponent("addrs/txs"),
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 20.0)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Parity with DashSync: percent-encode with the URL-query set minus
        // "&=" (a no-op for base58 addresses, kept for faithfulness).
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=")
        let joined = addresses.joined(separator: ",")
        let encoded = joined.addingPercentEncoding(withAllowedCharacters: allowed) ?? joined
        request.httpBody = Data("addrs=\(encoded)".utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw InsightError.invalidResponse
        }

        // Insight payloads are heterogeneous — JSONSerialization mirrors
        // DashSync's tolerant parsing rather than a rigid Codable model.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            throw InsightError.invalidResponse
        }

        let queried = Set(addresses)
        var existing = Set<String>()

        for item in items {
            if let vins = item["vin"] as? [[String: Any]] {
                for vin in vins {
                    if let address = vin["addr"] as? String, queried.contains(address) {
                        existing.insert(address)
                    }
                }
            }
            if let vouts = item["vout"] as? [[String: Any]] {
                for vout in vouts {
                    if let scriptPubKey = vout["scriptPubKey"] as? [String: Any],
                       let voutAddresses = scriptPubKey["addresses"] as? [String] {
                        for address in voutAddresses where queried.contains(address) {
                            existing.insert(address)
                        }
                    }
                }
            }
        }

        return existing
    }
}
