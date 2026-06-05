//
//  CoinJoinWithdrawalTxSet.swift
//  DashWallet
//
//  Groups the app's CoinJoin "offload" sweep transaction(s) into a single
//  "CoinJoin Withdrawals" home-screen cell — the withdrawal-side mirror of
//  `CoinJoinMixingTxSet`. Membership is by txid tag (see
//  `CoinJoinWithdrawalStore` / `Transaction.isCoinJoinWithdrawal`), NOT by tx
//  role, because only the sweep the app itself performed should appear here.
//
//  The sweep is a once-per-lifetime event (CoinJoin is being dropped, so coins
//  can't be re-mixed), so this is a single combined group rather than per-day —
//  it still tolerates 1..N tagged txs (e.g. if a sweep is ever split for
//  tx-size reasons).
//

import Foundation

final class CoinJoinWithdrawalTxSet: GroupedTransactions {

    let id = "coinjoin-withdrawal"

    var title: String {
        NSLocalizedString("CoinJoin Withdrawals", comment: "CoinJoin")
    }

    var iconName: String {
        "tx.item.internal.icon"
    }

    var infoText: String {
        NSLocalizedString("Your mixed Dash was moved to your spendable balance using these transactions.", comment: "CoinJoin")
    }

    var fiatAmount: String {
        (try? CurrencyExchanger.shared.convertDash(amount: UInt64(abs(amount)).dashAmount, to: App.fiatCurrency).formattedFiatAmount) ??
            NSLocalizedString("Updating Price", comment: "Updating Price")
    }

    /// The day this group sorts under on the home screen (latest included tx).
    private(set) var groupDay: Date = Date.now

    private let lock = NSLock()
    private var _amount: Int64 = 0
    var amount: Int64 {
        lock.lock(); defer { lock.unlock() }
        return _amount
    }

    private var _transactionMap: [Data: Transaction] = [:]
    var transactionMap: [Data: Transaction] {
        lock.lock(); defer { lock.unlock() }
        return _transactionMap
    }

    var transactions: [Transaction] {
        lock.lock(); defer { lock.unlock() }
        return _transactionMap.values.sorted { $0.date > $1.date }
    }

    /// Include `tx` if it is a tagged CoinJoin sweep. Idempotent. The set is
    /// rebuilt from scratch on every full `reloadTxDataSource`, so `_amount`
    /// accumulates each tx exactly once per build (no cross-reload double count).
    @discardableResult
    func tryInclude(_ tx: Transaction) -> Bool {
        guard tx.isCoinJoinWithdrawal else { return false }
        let key = tx.txHashData

        lock.lock(); defer { lock.unlock() }
        if _transactionMap[key] != nil {
            // Already in this build — refresh the stored wrapper (state may have
            // advanced) without re-counting the amount.
            _transactionMap[key] = tx
            return true
        }
        if _transactionMap.isEmpty || tx.date > groupDay {
            groupDay = tx.date
        }
        _transactionMap[key] = tx
        _amount += (tx.sdkNetAmount ?? 0)
        return true
    }
}
