//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import SQLite

// MARK: - SwapOrderStatus

enum SwapOrderStatus: String, Equatable {
    case notStarted = "not_started"
    case pending = "pending"
    case swapping = "swapping"
    case completed = "completed"
    case refunded = "refunded"
    case failed = "failed"
    case unknown = "unknown"
    /// Terminal, neutral outcome for an order we could not confirm within the tracking window
    /// (24 h age-out). NOT a failure — funds may well have arrived; we simply stopped tracking.
    /// Only produced by the age-out path, never by the `/track` status mapping.
    case expired = "expired"

    var isTerminal: Bool {
        switch self {
        case .completed, .refunded, .failed, .expired: return true
        default: return false
        }
    }

    var isActive: Bool { !isTerminal }

    /// Maps a normalised track-status string + observed flag to a `SwapOrderStatus`.
    /// `isObserved = false` means the provider hasn't seen the inbound tx yet.
    static func from(trackStatus: String?, isObserved: Bool) -> SwapOrderStatus {
        guard isObserved else { return .notStarted }
        switch trackStatus {
        case "done":               return .completed
        case "refunded", "aborted": return .refunded
        case "failed":             return .failed
        case "swapping":           return .swapping
        case "pending":            return .pending
        case "not_started":        return .notStarted
        case "unknown":            return .unknown
        default:                   return .pending
        }
    }
}

// MARK: - SwapOrder

struct SwapOrder: RowDecodable {
    /// Primary key.
    /// - Sell: DASH `txHashHexString` (Bitcoin-convention reversed hex, used for API tracking).
    /// - Buy:  deposit address (no local DASH tx at order creation time).
    var id: String
    var direction: String        // "sell" / "buy"
    var service: String          // "maya" / "swapkit"
    var provider: String?        // execution network / routing provider e.g. "Maya", "NEAR", "THORChain"
    var fromAsset: String        // "DASH" for Sell; sell asset for Buy
    var toAsset: String
    var toAddress: String        // destination crypto address (Sell) or user's Dash addr (Buy)
    var depositAddress: String?  // vault / deposit address — also used for NEAR track fallback
    var expectedToAmount: String?
    var actualToAmount: String?
    var status: SwapOrderStatus
    var outboundTxHash: String?  // outbound leg hash from /track (destination-chain tx for Sell;
                                 // incoming Dash tx for Buy once swap completes)
    var timestamp: Int64         // unix ms — order creation time
    var finalisedAt: Int64       // unix s; -1 = unknown / not yet finalised
    var lastChecked: Int64       // unix s — last time /track was polled

    // MARK: - SQLite schema

    static let table = Table("swap_orders")
    static let colId = Expression<String>("id")
    static let colDirection = Expression<String>("direction")
    static let colService = Expression<String>("service")
    static let colProvider = Expression<String?>("provider")
    static let colFromAsset = Expression<String>("fromAsset")
    static let colToAsset = Expression<String>("toAsset")
    static let colToAddress = Expression<String>("toAddress")
    static let colDepositAddress = Expression<String?>("depositAddress")
    static let colExpectedToAmount = Expression<String?>("expectedToAmount")
    static let colActualToAmount = Expression<String?>("actualToAmount")
    static let colStatus = Expression<String>("status")
    static let colOutboundTxHash = Expression<String?>("outboundTxHash")
    static let colTimestamp = Expression<Int64>("timestamp")
    static let colFinalisedAt = Expression<Int64>("finalisedAt")
    static let colLastChecked = Expression<Int64>("lastChecked")

    // MARK: - RowDecodable

    init(row: Row) {
        id = row[SwapOrder.colId]
        direction = row[SwapOrder.colDirection]
        service = row[SwapOrder.colService]
        provider = row[SwapOrder.colProvider]
        fromAsset = row[SwapOrder.colFromAsset]
        toAsset = row[SwapOrder.colToAsset]
        toAddress = row[SwapOrder.colToAddress]
        depositAddress = row[SwapOrder.colDepositAddress]
        expectedToAmount = row[SwapOrder.colExpectedToAmount]
        actualToAmount = row[SwapOrder.colActualToAmount]
        status = SwapOrderStatus(rawValue: row[SwapOrder.colStatus]) ?? .unknown
        outboundTxHash = row[SwapOrder.colOutboundTxHash]
        timestamp = row[SwapOrder.colTimestamp]
        finalisedAt = row[SwapOrder.colFinalisedAt]
        lastChecked = row[SwapOrder.colLastChecked]
    }

    // MARK: - Memberwise init

    init(
        id: String,
        direction: String,
        service: String,
        provider: String? = nil,
        fromAsset: String,
        toAsset: String,
        toAddress: String,
        depositAddress: String? = nil,
        expectedToAmount: String? = nil,
        actualToAmount: String? = nil,
        status: SwapOrderStatus = .notStarted,
        outboundTxHash: String? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        finalisedAt: Int64 = -1,
        lastChecked: Int64 = Int64(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.direction = direction
        self.service = service
        self.provider = provider
        self.fromAsset = fromAsset
        self.toAsset = toAsset
        self.toAddress = toAddress
        self.depositAddress = depositAddress
        self.expectedToAmount = expectedToAmount
        self.actualToAmount = actualToAmount
        self.status = status
        self.outboundTxHash = outboundTxHash
        self.timestamp = timestamp
        self.finalisedAt = finalisedAt
        self.lastChecked = lastChecked
    }
}
