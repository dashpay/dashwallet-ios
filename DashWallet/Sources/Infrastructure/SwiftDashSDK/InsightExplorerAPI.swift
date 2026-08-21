//
//  InsightExplorerAPI.swift
//  DashWallet
//

import Foundation
import SwiftDashSDK

/// Minimal read-only client for the network's Insight API — the one
/// third-party source the wallet consults about a transaction it cannot
/// answer for itself.
///
/// Every call sends a transaction id to a third party, so callers must have
/// a reason the local data cannot serve: today the never-accepted-transaction
/// removal check (is this tx known to the network at all?) and the fee of a
/// received transaction whose parent transactions this wallet doesn't hold.
enum InsightExplorerAPI {
    static func baseURL(network: Network) -> String {
        network == .mainnet
            ? "https://insight.dash.org/insight-api"
            : "https://insight.testnet.networks.dash.org/insight-api"
    }

    /// GET `/tx/<txid>`. Returns the HTTP status and, for a 200, the decoded
    /// JSON object. `nil` means the request never produced a response —
    /// transport failure, a malformed URL, or a body that isn't a JSON
    /// object — and is deliberately distinct from a 404 (an answer: the
    /// explorer doesn't know this transaction).
    static func transaction(displayTxid: String, network: Network) async -> (statusCode: Int, body: [String: Any])? {
        guard let url = URL(string: "\(baseURL(network: network))/tx/\(displayTxid)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return nil
        }
        guard http.statusCode == 200 else {
            return (http.statusCode, [:])
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (http.statusCode, body ?? [:])
    }

    /// Fee in duffs from a `/tx` body. Insight reports `fees` in whole DASH
    /// as a JSON number; `valueIn - valueOut` is the fallback for bodies that
    /// omit it. Nil when neither is present (a coinbase has no `fees`).
    static func feeDuffs(fromTransactionBody body: [String: Any]) -> UInt64? {
        if let fees = body["fees"] as? Double, fees >= 0 {
            return duffs(fromDash: fees)
        }
        if let valueIn = body["valueIn"] as? Double,
           let valueOut = body["valueOut"] as? Double,
           valueIn >= valueOut {
            return duffs(fromDash: valueIn - valueOut)
        }
        return nil
    }

    /// DASH → duffs. Rounded rather than truncated: the JSON number is a
    /// binary float, so 2.27e-06 arrives as 227.00000000000003 duffs.
    private static func duffs(fromDash dash: Double) -> UInt64 {
        UInt64((dash * 1e8).rounded())
    }
}
