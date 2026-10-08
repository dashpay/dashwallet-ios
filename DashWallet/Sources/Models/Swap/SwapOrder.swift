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

    /// The provider's in-progress statuses.
    var isProviderProgress: Bool {
        switch self {
        case .pending, .swapping, .unknown: return true
        case .notStarted, .completed, .refunded, .failed, .expired: return false
        }
    }

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
    var fromAmount: String?      // Buy: human-unit amount of `fromAsset` the user was asked to send
    var depositDeadline: Int64?  // Buy: unix s — the provider's own deadline for the deposit address
    var depositSeenAt: Int64?    // Buy: unix s — when the deposit was first known to exist: seen on
                                 // the source chain, proven by the provider's status, or paid out
    var providerDeniedAt: Int64? // Buy: unix s — the provider answered "no deposit" this long
                                 // after `depositSeenAt` that the order counts as stuck
    var depositMemo: String?     // Buy: memo the deposit must carry ("" = none, the address is
                                 // this order's alone; nil = unknown, saved before this field)
    var ownerWalletId: String?   // Buy: hex id of the wallet the order was made in (nil = unknown)
    var ownerNetwork: String?    // Buy: network that wallet was on (nil = unknown)

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
    static let colFromAmount = Expression<String?>("fromAmount")
    static let colDepositDeadline = Expression<Int64?>("depositDeadline")
    static let colDepositSeenAt = Expression<Int64?>("depositSeenAt")
    static let colProviderDeniedAt = Expression<Int64?>("providerDeniedAt")
    static let colDepositMemo = Expression<String?>("depositMemo")
    static let colOwnerWalletId = Expression<String?>("ownerWalletId")
    static let colOwnerNetwork = Expression<String?>("ownerNetwork")

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
        // `try?`, not the trapping subscript: these columns come from a later migration, and
        // a launch whose migration failed must not crash reading the orders it has. (Writes
        // still name these columns, so in that state they fail and are logged by the DAO.)
        fromAmount = (try? row.get(SwapOrder.colFromAmount)) ?? nil
        depositDeadline = (try? row.get(SwapOrder.colDepositDeadline)) ?? nil
        depositSeenAt = (try? row.get(SwapOrder.colDepositSeenAt)) ?? nil
        providerDeniedAt = (try? row.get(SwapOrder.colProviderDeniedAt)) ?? nil
        depositMemo = (try? row.get(SwapOrder.colDepositMemo)) ?? nil
        ownerWalletId = (try? row.get(SwapOrder.colOwnerWalletId)) ?? nil
        ownerNetwork = (try? row.get(SwapOrder.colOwnerNetwork)) ?? nil
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
        lastChecked: Int64 = Int64(Date().timeIntervalSince1970),
        fromAmount: String? = nil,
        depositDeadline: Int64? = nil,
        depositSeenAt: Int64? = nil,
        providerDeniedAt: Int64? = nil,
        depositMemo: String? = nil,
        ownerWalletId: String? = nil,
        ownerNetwork: String? = nil
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
        self.fromAmount = fromAmount
        self.depositDeadline = depositDeadline
        self.depositSeenAt = depositSeenAt
        self.providerDeniedAt = providerDeniedAt
        self.depositMemo = depositMemo
        self.ownerWalletId = ownerWalletId
        self.ownerNetwork = ownerNetwork
    }
}

// MARK: - BuySwapPhase

/// What a Buy order looks like to the user. Derived from the stored fields, never stored
/// itself. The provider cannot tell "nothing was sent" from "sent, but not noticed", so the
/// second signal is the source chain itself — the deposit address holding the coin.
enum BuySwapPhase: Equatable {
    /// Order exists; no deposit on the source chain, none reported by the provider.
    case awaitingPayment
    /// The deposit is on the source chain; the provider has not picked it up yet, within the
    /// normal wait.
    case waitingForProvider
    /// The provider has seen the deposit and is working on it.
    case processing
    /// The deposit is on the source chain and the provider, asked more than
    /// `stuckAfterSeconds` later, answered that it does not see it.
    case stuck
    case completed
    case refunded
    case failed
    case expired
}

extension SwapOrder {
    /// How long a completed order keeps its own row while the Dash payout has not shown up in
    /// the wallet yet.
    static let completedRowSeconds: Int64 = 60 * 60

    /// How long after an order with a deposit on record expired its payout is still looked
    /// for, and the order completed when it arrives.
    static let latePayoutSeconds: Int64 = 7 * 24 * 60 * 60


    /// How long a deposit may sit on the source chain unseen by the provider before the order
    /// is called stuck. Per source chain: the deposit address shows a balance as soon as the
    /// transfer is broadcast or mined, while the provider waits for confirmations — minutes
    /// on most chains, up to an hour and more on the slow proof-of-work ones.
    static func stuckAfterSeconds(forAsset asset: String) -> Int64 {
        switch chain(ofAsset: asset) {
        case "BTC", "BCH": return 90 * 60
        case "LTC", "DOGE", "ZEC": return 45 * 60
        default: return 10 * 60
        }
    }

    var stuckAfterSeconds: Int64 { SwapOrder.stuckAfterSeconds(forAsset: fromAsset) }

    /// The chain part of a SwapKit asset identifier, upper-cased: "ARB" of "ARB.USDT-0x…".
    static func chain(ofAsset asset: String) -> String? {
        asset.split(separator: ".").first.map { $0.uppercased() }
    }

    /// The source chain of the order's `fromAsset`.
    var fromChain: String? { SwapOrder.chain(ofAsset: fromAsset) }

    var isBuy: Bool { direction == "buy" }

    /// Whether the deposit can be recognised by the deposit address's balance: only when the
    /// order is known to carry no memo. With a memo the address is shared between orders and
    /// its balance says nothing about this one; an order saved before the memo was recorded
    /// is unknown, and unknown is not watched.
    var canWatchDepositAddress: Bool {
        guard isBuy, let depositMemo else { return false }
        return depositMemo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the order's deposit is known to exist. The tracker stamps `depositSeenAt`
    /// when the coin is on the deposit address, when the provider's own status proves it has
    /// the deposit, or when the payout is in the wallet. A status alone does not count:
    /// some provider answers are only mapped onto "refunded" or "pending".
    var hasDepositOnRecord: Bool { depositSeenAt != nil }

    var buyPhase: BuySwapPhase {
        switch status {
        case .completed: return .completed
        case .refunded: return .refunded
        case .failed: return .failed
        case .expired: return .expired
        case .pending, .swapping, .unknown: return .processing
        case .notStarted:
            guard depositSeenAt != nil else { return .awaitingPayment }
            // Stuck is the provider's answer, stamped by the tracker — not elapsed time: with
            // the app in the background or offline nobody asked, and an order that completed
            // meanwhile must not read as stuck until the next poll.
            return providerDeniedAt != nil ? .stuck : .waitingForProvider
        }
    }

    /// The active wallet's id, as orders record it.
    static var currentOwnerWalletId: String? { WalletEnvironment.activeWalletIdHex as String? }

    /// The active network, as orders record it.
    static var currentOwnerNetwork: String? { String(WalletEnvironment.networkKind.rawValue) }

    /// Whether the order belongs to the given wallet on the given network. An order saved
    /// before the owner was recorded is unknown and belongs to nobody.
    func isOwned(byWalletId walletId: String?, network: String?) -> Bool {
        guard let ownerWalletId, let ownerNetwork, let walletId, let network else { return false }
        return ownerWalletId == walletId && ownerNetwork == network
    }

    /// Whether a Dash payout for this order can still turn up: not once the provider has
    /// ended it without one. An expired order still can for `latePayoutSeconds` when its
    /// deposit is on record — expiry is us no longer asking, and a deposit handed to the
    /// provider later is paid out all the same; the tracker completes the order when it
    /// is. An expired order nobody paid can not, and must not claim an unrelated receive of
    /// a similar amount.
    func mayStillBePaidOut(now: Date = Date()) -> Bool {
        switch status {
        case .refunded, .failed: return false
        case .expired:
            return hasDepositOnRecord && finalisedAt > 0
                && Int64(now.timeIntervalSince1970) - finalisedAt <= SwapOrder.latePayoutSeconds
        case .notStarted, .pending, .swapping, .unknown, .completed: return true
        }
    }

    /// Whether the order may be a history row of its own: only an order whose deposit is on
    /// record. An unpaid one is shown nowhere — whatever status it ends in.
    ///
    /// This is the order's side only. Home shows the row just while the Dash payout is not in
    /// the wallet — once that transaction is there it is the row, labelled by
    /// `SwapOrderMetadataProvider`. A completed order therefore keeps a row only briefly,
    /// covering the gap between the provider reporting the payout and the wallet seeing it.
    func isBuyHistoryRow(now: Date = Date()) -> Bool {
        guard isBuy, hasDepositOnRecord else { return false }
        switch buyPhase {
        case .waitingForProvider, .processing, .stuck, .refunded, .failed, .expired: return true
        case .completed:
            guard finalisedAt > 0 else { return false }
            return Int64(now.timeIntervalSince1970) - finalisedAt <= SwapOrder.completedRowSeconds
        case .awaitingPayment: return false
        }
    }
}
