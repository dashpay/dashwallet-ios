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

    /// GET `/tx/<txid>`. Returns the HTTP status and, for a 200 whose body
    /// decodes to a JSON object, that object.
    ///
    /// A `nil` result means the request never produced a response at all —
    /// transport failure or a malformed URL — and is deliberately distinct
    /// from a 404, which is an answer: the explorer doesn't know this
    /// transaction. A `nil` *body* on a 200 means the explorer answered but
    /// said nothing usable; it stays separate from an empty object so a
    /// caller that only needs "does this transaction exist" is not made to
    /// fail on an unparseable body.
    static func transaction(displayTxid: String, network: Network) async -> (statusCode: Int, body: [String: Any]?)? {
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
            return (http.statusCode, nil)
        }
        return (http.statusCode, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }

    /// Fee in duffs from a `/tx` body. Insight reports `fees` in whole DASH
    /// as a JSON number; `valueIn - valueOut` is the fallback for bodies that
    /// omit it. Nil when neither is present (a coinbase has no `fees`) or
    /// when the number is not a plausible duff amount.
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
    ///
    /// Failable because the input is a number a third party chose:
    /// `UInt64(_: Double)` traps — in release builds too — on NaN, on an
    /// infinity, and on anything outside `UInt64`'s range, so a nonsense
    /// `fees` would crash the detail sheet rather than fail to fill one row.
    /// The ceiling is Dash's max supply, well below the 2^64 trap boundary:
    /// nothing above it is a fee.
    private static func duffs(fromDash dash: Double) -> UInt64? {
        let duffs = (dash * 1e8).rounded()
        guard duffs.isFinite, duffs >= 0, duffs <= Double(kMaxDashSupplyDuffs) else { return nil }
        return UInt64(duffs)
    }
}
