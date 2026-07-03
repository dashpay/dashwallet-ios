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
/// (CrowdNode's) requires decoding the stored bytes. A deprecated bridge from
/// `DSTransaction` exists solely for the deferred online-account/withdrawal
/// scans that still read DashSync's (empty post-M6) `allTransactions`.
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
    /// Display wrapper; supplies direction/dashAmount with the existing
    /// FFI → DSTransactionDirection mapping (including the outgoing → moved
    /// fee-only promotion the top-up matcher relies on).
    let wrapped: Transaction

    var direction: DSTransactionDirection { wrapped.direction }
}

protocol TransactionFilter {
    func matches(_ tx: ObservedTransaction) -> Bool
}

extension TransactionFilter {
    /// DashSync bridge for the deferred scans still reading DashSync's
    /// `wallet.allTransactions` (empty post-M6): `getWithdrawalsForTheLast`,
    /// `hasDepositConfirmations`, `getApiAddressConfirmationTx` in
    /// CrowdNode.swift. Kept only so those flows compile until the
    /// online-account/withdrawal port. Do not add callers.
    @available(*, deprecated, message: "DashSync bridge for deferred CrowdNode flows; match ObservedTransaction instead")
    func matches(tx: DSTransaction) -> Bool {
        matches(ObservedTransaction(legacy: tx))
    }
}

extension ObservedTransaction {
    /// DashSync bridge — see the deprecated `matches(tx:)` adapter above.
    init(legacy tx: DSTransaction) {
        txid = tx.txHashData
        txidHexDisplay = tx.txHashData.reversed().map { String(format: "%02x", $0) }.joined()
        outputs = tx.outputs.map { Output(address: $0.address, amount: $0.amount) }
        inputAddresses = Set(tx.inputAddresses.compactMap { $0 as? String })
        timestamp = Date(timeIntervalSince1970: tx.timestamp)
        wrapped = Transaction(transaction: tx)
    }
}
