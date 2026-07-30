//
//  Created by Andrei Ashikhmin
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

/// Source-neutral transaction view the CrowdNode filters match on.
///
/// Built on the main actor from a `PersistentTransaction` row plus a consensus
/// decode of its raw bytes (`TransactionDecoder`) — persistence materializes
/// TXO rows only for the wallet's own outputs, so matching external addresses
/// (CrowdNode's) requires decoding the stored bytes.
struct ObservedTransaction {
    struct Output {
        /// nil for non-standard scripts (OP_RETURN etc.).
        let address: String?
        /// duffs
        let amount: UInt64
    }

    /// 32-byte txid in wire/internal order (matches `PersistentTransaction.txid`
    /// and `Transaction.txHashData`).
    let txid: Data
    /// Explorer-style reversed-hex txid for logs.
    let txidHexDisplay: String
    let outputs: [Output]
    /// Best-effort per-input sender addresses (P2PKH scriptSig recovery; inputs
    /// spending coinbase/P2SH yield no address), deduped. CrowdNode pays from
    /// P2PKH, so its request/response txs always carry recoverable addresses.
    let inputAddresses: Set<String>
    /// Row `firstSeen`, falling back to `blockTimestamp`; nil when both are 0.
    let timestamp: Date?
    /// Sum of this tx's outputs paying the wallet's own addresses (the row's
    /// materialized TXOs) — DashSync's `amountReceived(from:)`, in duffs.
    let ownOutputsAmount: UInt64
    /// Own destination addresses in wire output order — DashSync's
    /// `externalAddresses(of:)` stand-in for "which of our addresses this tx
    /// paid" (own TXO rows projected onto the decoded output order).
    let ownOutputAddresses: [String]
    /// True once the row is past mempool — IS-locked, mined, or chain-locked
    /// (context ≥ 1) or carrying a block height (rows restored from chain
    /// data). SDK-side stand-in for DashSync's `account.transactionIsValid`.
    let isChainAccepted: Bool
    /// Display wrapper; supplies direction/dashAmount with the existing
    /// FFI → TransactionDirection mapping (including the outgoing → moved
    /// fee-only promotion the top-up matcher relies on).
    let wrapped: Transaction

    var direction: TransactionDirection { wrapped.direction }
}

protocol TransactionFilter {
    func matches(_ tx: ObservedTransaction) -> Bool
}
