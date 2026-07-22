//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
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
import SwiftDashSDK

// MARK: - Transaction

/// The app-side transaction wrapper for every tx-history surface, backed by an
/// immutable `SDKSnapshot` value — NOT the live `PersistentTransaction` @Model.
/// A `Transaction` is held by the home tx list across the wallet runtime's
/// stop/start (e.g. an SPV restart), which tears down the `ModelContainer` and
/// resets its context; reading any model property afterwards traps ("instance
/// was destroyed by calling ModelContext.reset"). Snapshotting every UI-read
/// field at wrap time — on the fetch thread, while the model is alive — makes
/// the wrapper immune to that teardown (and thread-safe to hand around).
class Transaction: TransactionDataItem, Identifiable {
    enum State {
        case ok
        case invalid
        case locked
        case processing
        case confirming
    }

    enum `Type`: UInt {
        case classic
        case reward
        case masternodeRegistration
        case masternodeUpdate
        case masternodeRevoke
        case blockchainIdentityRegistration
    }

    /// Frozen copy of the `PersistentTransaction` fields the UI reads, captured
    /// once at wrap time. Holding values (not the SwiftData model) is what keeps
    /// a `Transaction` valid after the model's context is reset/rebuilt.
    private struct SDKSnapshot {
        let txid: Data
        /// FFI direction encoding: 0=incoming, 1=outgoing, 2=internal, 3=coinjoin.
        let direction: UInt32
        let netAmount: Int64
        let fee: UInt64?
        /// 0=mempool, 1=instantSend, 2=inBlock, 3=chainLocked.
        let context: UInt32
        /// Block height the tx was mined at (0 when unconfirmed). Drives
        /// coinbase-reward maturity (locked until COINBASE_MATURITY deep).
        let blockHeight: UInt32
        /// The Rust transaction router's typed discriminant
        /// (`SwiftDashSDK.TransactionTypeKind` raw value; 0xFF = pre-feature
        /// sentinel for rows not yet re-persisted by SPV).
        let typeKind: UInt8
        /// Owned output addresses (non-empty), pre-deduped.
        let outputAddresses: [String]
        /// Spent-input addresses (non-empty), pre-deduped.
        let inputAddresses: [String]
        /// Raw number of inputs (UTXOs consumed) — NOT deduped by address.
        let inputCount: Int
        /// External recipient addresses of a *sent* tx. Persisted rows can't
        /// recover these (persistence stores owned outputs only), so this is
        /// always empty for them; only synthetic snapshots populate it, from
        /// the send intent (see the synthetic initializer).
        let externalSentAddresses: [String]

        /// Must be called on the thread that owns `p`'s `ModelContext` (the
        /// fetch thread) — reads `p`'s relationships (`outputs`/`inputs`),
        /// which are bound to that context.
        init(_ p: PersistentTransaction) {
            txid = p.txid
            direction = p.direction
            netAmount = p.netAmount
            fee = p.fee
            context = p.context
            blockHeight = p.blockHeight
            typeKind = p.transactionTypeKind
            outputAddresses = Array(Set(p.outputs.map { $0.address }.filter { !$0.isEmpty }))
            inputAddresses = Array(Set(p.inputs.map { $0.address }.filter { !$0.isEmpty }))
            inputCount = p.inputs.count
            externalSentAddresses = []
        }

        /// Snapshot for a transaction that has no persisted row: the
        /// onboarding demo list and the post-broadcast fallback (the Rust
        /// persister writes the row asynchronously). Display-only; never
        /// persisted.
        init(syntheticTxid: Data, direction: UInt32, netAmount: Int64,
             fee: UInt64?, context: UInt32, externalSentAddresses: [String]) {
            txid = syntheticTxid
            self.direction = direction
            self.netAmount = netAmount
            self.fee = fee
            self.context = context
            // Synthetics have no mined block yet (demo rows / just-broadcast sends).
            blockHeight = 0
            // Synthetics are only ever demo rows or our own standard sends.
            typeKind = TransactionTypeKind.standard.rawValue
            outputAddresses = []
            inputAddresses = []
            inputCount = 0
            self.externalSentAddresses = externalSentAddresses
        }
    }

    private let snapshot: SDKSnapshot

    /// Number of inputs (UTXOs consumed) in this transaction. For a CoinJoin
    /// sweep this is the count of mixed coins the tx moved. Raw count — not
    /// deduped by address.
    var inputCount: Int { snapshot.inputCount }

    /// CoinJoin "mixing operation" flag — drives grouping into the single
    /// "Mixing Transactions" home-screen row.
    ///
    /// Computed and cached at wrap time on the fetch thread
    /// (`SwiftDashSDKWalletSource.fetchAndWrap`), because deciding membership
    /// traverses SwiftData relationships (outputs → coreAddress → account)
    /// that are bound to the fetching `ModelContext` and must not be read
    /// after the wrap. Defaults to false; the home tx source is the sole
    /// producer of home-list wrappers and always populates it.
    var sdkCoinJoinMixing: Bool = false

    /// True only for CoinJoin mixing transactions. The flag is computed via
    /// CoinJoin-account *role* (a tx that deposits into the CoinJoin account,
    /// or spends a fee/collateral from it without depositing to a Standard
    /// account — see `SwiftDashSDKWalletSource.isCoinJoinMixingTx`), NOT just
    /// the SDK's structural `typedKind`, which only tags the mixing *rounds*
    /// and misses create-denomination / collateral / mixing-fee txs.
    var isCoinJoinMixing: Bool { sdkCoinJoinMixing }

    /// Raw signed wallet net change (duffs). Used to total a CoinJoin mixing
    /// group's cost: summing this across the group yields the net wallet
    /// change (mixing rounds net ~0; denomination / fee txs net `-fee`),
    /// i.e. the total mixing fee paid (negative).
    var sdkNetAmount: Int64? { snapshot.netAmount }

    /// True when this tx is the app's CoinJoin offload (sweep) tx — tagged on
    /// sweep success in `CoinJoinWithdrawalStore`. Drives grouping into the
    /// single "CoinJoin Withdrawals" home cell. Cheap, thread-safe txid lookup
    /// (no SwiftData traversal — unlike `isCoinJoinMixing`).
    var isCoinJoinWithdrawal: Bool {
        CoinJoinWithdrawalStore.shared.contains(txHashData)
    }

    var id: String { Self.displayHex(snapshot.txid) }

    /// Live DashPay payment record for this tx (`PersistentDashpayPayment`
    /// via `DashPayPaymentTxLookup`) — the authoritative direction/amount
    /// for a DIP-15 contact payment. dash-spv's net-change view misreads an
    /// outgoing contact payment as an incoming +amount (the jointly-derived
    /// payment address is watched by our wallet while the spent inputs
    /// aren't attributed), so the Rust payment history — which records the
    /// true direction at send/sync time — wins.
    var dashPayPayment: DashPayPaymentTxLookup.PaymentInfo? {
        DashPayPaymentTxLookup.shared.info(forTxidHex: shieldedDisplayTxid)
    }

    /// True when this tx is a recorded DashPay contact payment.
    var isDashPayPayment: Bool { dashPayPayment != nil }

    /// The counterparty's profile name for the row's gray details line —
    /// only when the title used the owner-set alias, so both render
    /// (alias on top, their actual name underneath). `nil` when the title
    /// already shows the profile name (or nothing is cached).
    var dashPayPaymentDetailsName: String? {
        guard let payment = dashPayPayment,
              payment.counterpartyAlias?.isEmpty == false,
              let name = payment.counterpartyName,
              name != payment.counterpartyAlias else { return nil }
        return name
    }

    var direction: DSTransactionDirection {
        if let payment = dashPayPayment {
            return payment.isOutgoing ? .sent : .received
        }
        return _direction
    }
    private lazy var _direction: DSTransactionDirection = {
        // FFI direction encoding: 0=incoming, 1=outgoing, 2=internal,
        // 3=coinjoin. Promote outgoing→moved when the wallet's net
        // change equals just the fee (self-send) — mirrors DashSync's
        // `received + fee == sent` check so the legacy code path that
        // still relies on `.moved` (e.g. CrowdNode top-up matcher,
        // "Internal Transfer" labelling) keeps working uniformly.
        switch snapshot.direction {
        case 0: return .received
        case 2: return .moved
        case 3: return .sent
        case 1:
            let fee = Int64(snapshot.fee ?? 0)
            if fee > 0 && snapshot.netAmount == -fee {
                return .moved
            }
            return .sent
        default:
            return snapshot.netAmount >= 0 ? .received : .sent
        }
    }()

    var outputReceiveAddresses: [String] { _outputReceiveAddresses }
    private lazy var _outputReceiveAddresses: [String] = {
        // Persistence only stores owned outputs (the FFI emits
        // `acc.utxos*` arrays — wallet UTXOs only — and external
        // recipient outputs aren't surfaced). For received txs that
        // matches "addresses receiving in this tx" semantics; for sent
        // txs the external destination is unrecoverable from the row
        // alone — only synthetic post-send snapshots carry it, from
        // the send intent.
        if direction == .received || direction == .moved {
            return snapshot.outputAddresses
        }
        return snapshot.externalSentAddresses
    }()

    var inputSendAddresses: [String] { _inputSendAddresses }
    private lazy var _inputSendAddresses: [String] = {
        // Populated only when the FFI links spent UTXOs back to the
        // spending tx. Today the spent-utxo notification carries only
        // the outpoint, so `inputs` is usually empty — fine, callers
        // already tolerate empty arrays.
        snapshot.inputAddresses
    }()

    var specialInfoAddresses: [String: Int]?

    /// Locked amount (duffs) when this L1 transaction is the funding tx of a
    /// "to Shielded" internal transfer — a Type-18 asset lock that tops up
    /// the private shielded balance. Sourced from the SDK's
    /// `PersistentAssetLock` store (funding type 5): the net-change view
    /// doesn't model the lock, so it reports a self-directed move of 0.
    /// `nil` for every other transaction.
    ///
    /// Joined by the display-order txid (reversed `txHashData`) to match the
    /// txid component of `PersistentAssetLock.outPointHex`. Drives both the
    /// "Shielded transfer" label (`stateTitle`) and the on-screen amount
    /// (`_dashAmount`).
    /// Display-order txid (reversed wire bytes) — the `ShieldedTxLookup` key.
    /// Stable for this tx, so cache it; the lookup itself is read live.
    private lazy var shieldedDisplayTxid: String = Self.displayHex(txHashData)

    /// Live shielded-funding info for this tx. Computed (not cached) so a row
    /// reflects pending → consumed transitions as soon as `ShieldedTxLookup`
    /// refreshes, without waiting for the `Transaction` instance to be rebuilt.
    private var shieldedLockInfo: ShieldedTxLookup.ShieldedLockInfo? {
        ShieldedTxLookup.shared.info(forTxidHex: shieldedDisplayTxid)
    }

    private var shieldedTransferAmountDuffs: UInt64? { shieldedLockInfo?.amountDuffs }

    /// True when this is the funding tx of a "to Shielded" transfer.
    var isShieldedTransfer: Bool { shieldedLockInfo != nil }

    /// Live info for this tx as a Core → Platform address funding (a Type-8
    /// asset lock with funding type 4). Same live-read rationale as
    /// `shieldedLockInfo`.
    var platformFundingLockInfo: ShieldedTxLookup.ShieldedLockInfo? {
        ShieldedTxLookup.shared.platformFundingInfo(forTxidHex: shieldedDisplayTxid)
    }

    private var platformFundingAmountDuffs: UInt64? { platformFundingLockInfo?.amountDuffs }

    /// True when this is the funding tx of a Core → Platform transfer.
    var isPlatformFundingTransfer: Bool { platformFundingLockInfo != nil }

    /// Live info for this tx as an identity funding asset lock (types 0…3 —
    /// registration / top-up / invitation). Same live-read rationale as
    /// `shieldedLockInfo`.
    var identityFundingLockInfo: ShieldedTxLookup.ShieldedLockInfo? {
        ShieldedTxLookup.shared.identityFundingInfo(forTxidHex: shieldedDisplayTxid)
    }

    private var identityFundingAmountDuffs: UInt64? { identityFundingLockInfo?.amountDuffs }

    /// True when this is the funding tx of an identity registration/top-up/
    /// invitation.
    var isIdentityFundingTransfer: Bool { identityFundingLockInfo != nil }

    /// Identity sibling of `isPendingShieldedTransfer` — drives the home
    /// row's "Pending" pill.
    var isPendingIdentityFunding: Bool {
        guard let status = identityFundingLockInfo?.statusRaw else { return false }
        return (1...3).contains(status)
    }

    /// True when this incoming tx is the L1 payout of a Shielded → Core
    /// withdrawal the app performed — matched by destination address via
    /// `ShieldedWithdrawalStore` (the SDK's opaque withdraw call returns no
    /// txid, so the app tags the receive address it handed the withdraw).
    /// Drives the "Shielded received" home filter category.
    var isShieldedWithdrawalReceipt: Bool {
        direction == .received
            && snapshot.outputAddresses.contains { ShieldedWithdrawalStore.shared.contains($0) }
    }

    /// The balance-to-balance route of an internal transfer, driving the
    /// route-specific icon pair on the tx row (source icon + destination
    /// badge). `nil` for anything that isn't a transfer of own funds.
    ///
    /// Only Core-side legs exist as L1 transactions, so these are the only
    /// routes a tx-list row can represent; Platform ↔ Shielded transfers
    /// happen entirely on Platform and never appear in this list.
    enum InternalTransferRoute {
        /// "To Shielded" funding asset lock (Core → Shielded).
        case coreToShielded
        /// L1 payout of a shielded withdrawal (Shielded → Core).
        case shieldedToCore
        /// "To Platform" address-funding asset lock (Core → Platform).
        case coreToPlatform
        /// Identity registration / top-up / invitation asset lock.
        case coreToIdentity
        /// Self-send within the transparent wallet.
        case coreToCore
    }

    var internalTransferRoute: InternalTransferRoute? {
        if isShieldedTransfer { return .coreToShielded }
        if isShieldedWithdrawalReceipt { return .shieldedToCore }
        if isPlatformFundingTransfer { return .coreToPlatform }
        if isIdentityFundingTransfer { return .coreToIdentity }
        if direction == .moved { return .coreToCore }
        return nil
    }

    /// True when the shielded transfer is still pending / stuck — its asset
    /// lock is broadcast/IS-locked/CL-locked (`statusRaw` 1…3) but the shield
    /// state transition hasn't consumed it yet (4 = consumed = success). Drives
    /// the "pending" history treatment and the tap-to-recover entry point.
    var isPendingShieldedTransfer: Bool {
        guard let status = shieldedLockInfo?.statusRaw else { return false }
        return (1...3).contains(status)
    }

    /// Platform-funding sibling of `isPendingShieldedTransfer`: the type-4
    /// lock is committed but the address-funding transition hasn't consumed
    /// it. Drives the home row's "Pending" pill (no tap-to-recover surface
    /// yet — retry lives in the transfer confirm sheet).
    var isPendingPlatformFunding: Bool {
        guard let status = platformFundingLockInfo?.statusRaw else { return false }
        return (1...3).contains(status)
    }

    /// Outpoint (wire-order txid + vout) of this transfer's shielded asset
    /// lock, for a recovery resume. `txHashData` is already wire order, so it
    /// is returned verbatim (the display↔wire reversal only happens when
    /// keying `ShieldedTxLookup`). `nil` for non-shielded-transfer txs.
    var shieldedOutPoint: (txidWire: Data, vout: UInt32)? {
        guard let info = shieldedLockInfo else { return nil }
        return (txHashData, info.vout)
    }

    private lazy var _dashAmount: UInt64 = {
        // A "to Shielded" / "to Platform" transfer's L1 funding tx is an
        // asset lock; surface the real locked amount the SDK recorded
        // instead of the 0 the generic logic below derives for a
        // self-directed move.
        if let locked = shieldedTransferAmountDuffs ?? platformFundingAmountDuffs ?? identityFundingAmountDuffs { return locked }
        let fee = Int64(snapshot.fee ?? 0)
        switch direction {
        case .received:
            return snapshot.netAmount > 0 ? UInt64(snapshot.netAmount) : 0
        case .sent:
            // Gross amount paid to external recipients. For an
            // external send `netAmount = -(amount + fee)`, so the
            // user-visible amount = `-netAmount - fee`. abs(netAmount)
            // (the previous fallback) double-counted the fee and
            // collapsed self-sends to a fee-sized number on screen.
            return UInt64(max(0, -snapshot.netAmount - fee))
        case .moved:
            return 0
        case .notAccountFunds:
            return 0
        @unknown default:
            return UInt64(abs(snapshot.netAmount))
        }
    }()

    /// Prefer the live shielded amount (computed from `ShieldedTxLookup`) over
    /// the lazily-cached generic `_dashAmount`, so a row that became a shielded
    /// transfer after its first render still shows the locked amount — matching
    /// the now-live `stateTitle` / `isPendingShieldedTransfer`. A DashPay
    /// contact payment likewise shows the recorded payment amount (the
    /// net-change view reads the wrong number for those — see `dashPayPayment`).
    var dashAmount: UInt64 {
        dashPayPayment?.amountDuffs
            ?? shieldedTransferAmountDuffs
            ?? platformFundingAmountDuffs
            ?? identityFundingAmountDuffs
            ?? _dashAmount
    }
    var signedDashAmount: Int64 {
        if dashAmount == UInt64.max {
            return Int64.max
        }

        return direction == .sent ? -Int64(dashAmount) : Int64(dashAmount)
    }

    var fiatAmount: String {
        // The shielded / DashPay-payment amount is read live (see
        // `dashAmount`), so compute its fiat live too; other rows keep the
        // lazily-cached value.
        if dashPayPayment != nil || shieldedTransferAmountDuffs != nil || platformFundingAmountDuffs != nil || identityFundingAmountDuffs != nil {
            return userInfo?.fiatAmountString(from: dashAmount) ?? NSLocalizedString("Not available", comment: "")
        }
        return storedFiatAmount
    }

    var iconName: String {
        state == .invalid ? "tx.invalid.icon" : direction.iconName
    }

    private lazy var storedFiatAmount = userInfo?.fiatAmountString(from: _dashAmount) ?? NSLocalizedString("Not available", comment: "");

    lazy var userInfo: TransactionMetadata? = TransactionMetadataDAOImpl.shared.get(by: txHashData)

    var transactionType: `Type` { _transactionType }
    private lazy var _transactionType: `Type` = {
        switch TransactionTypeKind(rawValue: snapshot.typeKind) {
        case .coinbase: return .reward
        case .providerRegistration: return .masternodeRegistration
        case .providerUpdateRegistrar, .providerUpdateService: return .masternodeUpdate
        case .providerUpdateRevocation: return .masternodeRevoke
        // assetLock/assetUnlock: a shielded transfer's label comes live
        // from ShieldedTxLookup (stateTitle checks it before this type
        // switch); other locks keep the classic label rather than guess
        // identity registration. TODO(dashpay-e2e): map identity-funding
        // locks to .blockchainIdentityRegistration once the DashPay
        // migration models them.
        case .assetLock, .assetUnlock: return .classic
        // standard / coinJoin (mixing rows label via isCoinJoinMixing) /
        // ignored / nil (0xFF pre-feature sentinel or future variants).
        case .standard, .coinJoin, .ignored, .none: return .classic
        }
    }()

    var state: State! { _state }
    private lazy var _state: State! = {
        // PersistentTransaction.context: 0=mempool, 1=instantSend,
        // 2=inBlock, 3=chainLocked. Anything past mempool counts as
        // "ok" — instant-send is a strong-enough confirmation for
        // home-screen UX (matches the legacy DSTransaction codepath
        // which exited `.processing` once `instantSendReceived` flipped).
        if snapshot.context == 0 { return .processing }
        // Coinbase rewards are unspendable until COINBASE_MATURITY blocks sit
        // on top of the minting block; surface that window as `.locked`
        // (mirrors the legacy DSTransaction.getBlocksToMaturity rule).
        if isCoinbaseTransaction, isCoinbaseRewardLocked { return .locked }
        return .ok
    }()

    /// Coinbase maturity in blocks — a coinbase output becomes spendable only
    /// once this many blocks sit on top of the one that minted it (network rule).
    private static let coinbaseMaturity: UInt32 = 100

    /// A confirmed coinbase reward that hasn't reached maturity yet. False when
    /// the block height or chain tip is unknown, so an unresolved state never
    /// gets stuck showing "Locked"; recomputed each time the home feed rebuilds
    /// its `Transaction` wrappers, so it clears once the reward matures.
    private var isCoinbaseRewardLocked: Bool {
        let height = snapshot.blockHeight
        guard height > 0 else { return false }
        let tip = SwiftDashSDKSPVCoordinator.shared.tipHeight
        guard tip >= height else { return false }
        return (tip - height) < Self.coinbaseMaturity
    }

    /// Display-order txid hex from wire-order bytes (block explorers, copy-to-
    /// pasteboard convention). The wire-order `Data` itself stays the
    /// storage/metadata key — only the human-facing hex string is byte-reversed.
    /// Internal: also the log/UI formatter for the wire-order txids the send
    /// boundary returns (WalletSendService/SendCoinsService).
    static func displayHex(_ wireTxid: Data) -> String {
        wireTxid.reversed().map { String(format: "%02x", $0) }.joined()
    }

    private lazy var _shortDateString: String =
        DWDateFormatter.sharedInstance.shortStringFromDate(date)

    var date: Date

    var shortDateString: String {
        _shortDateString
    }

    private lazy var _shortTimeString: String =
        DWDateFormatter.sharedInstance.timeOnly(from: date)

    var shortTimeString: String {
        _shortTimeString
    }

    var stateTitle: String {
        // Identity funding locks name their purpose — they buy identity
        // credits rather than moving between the wallet's balances.
        if let identityType = identityFundingLockInfo?.fundingTypeRaw {
            switch identityType {
            case 0:
                return NSLocalizedString("Identity registration", comment: "Asset lock funding a DashPay identity registration")
            case 3:
                return NSLocalizedString("Invitation", comment: "")
            default:
                return NSLocalizedString("Identity top-up", comment: "Asset lock topping up a DashPay identity's credits")
            }
        }
        // A DashPay contact payment names the counterparty — the owner-set
        // alias when one exists, else their profile display name (their
        // name then moves to the gray details line). No cached
        // name at all falls through to the generic Sent/Received (the
        // overlaid `direction` already points the right way).
        if let payment = dashPayPayment, let name = payment.titleName {
            return payment.isOutgoing
                ? String(format: NSLocalizedString("Sent to %@", comment: "DashPay payment row — recipient's display name"), name)
                : String(format: NSLocalizedString("Received from %@", comment: "DashPay payment row — sender's display name"), name)
        }
        // Every balance-to-balance transfer reads "Internal Transfer"; the
        // route is carried visually (source icon → destination badge), by
        // the home row's route pill, and by the detail sheet's From/To rows.
        // Covers the asset-lock fundings (which the generic .moved logic
        // would also label "Internal Transfer", but with a 0 amount) and the
        // Shielded → Transparent payout (which would read "Received").
        if let route = internalTransferRoute, route != .coreToCore {
            return NSLocalizedString("Internal Transfer", comment: "Transaction within the wallet, transfer of own funds")
        }
        switch transactionType {
        case .classic:
            switch direction {
            case .sent:
                if state == .processing {
                    return NSLocalizedString("Sending", comment: "")
                } else if state == .invalid {
                    return NSLocalizedString("Invalid", comment: "")
                } else {
                    return NSLocalizedString("Sent", comment: "")
                }
            case .received, .notAccountFunds:
                return NSLocalizedString("Received", comment: "")
            case .moved:
                return NSLocalizedString("Internal Transfer", comment:"Transaction within the wallet, transfer of own funds");
            default:
                fatalError()
            }
        case .reward:
            return NSLocalizedString("Mining Reward", comment: "Transaction type: coinbase/masternode mining reward")
        case .masternodeRegistration:
            return NSLocalizedString("Masternode Registration", comment: "")
        case .masternodeUpdate:
            return NSLocalizedString("Masternode Update", comment: "")
        case .masternodeRevoke:
            return NSLocalizedString("Masternode Revocation", comment: "")
        case .blockchainIdentityRegistration:
            return NSLocalizedString("DashPay Upgrade Fee", comment: "")
        }
    }

    init(persistentTransaction p: PersistentTransaction) {
        // Freeze every UI-read field now, on the thread where `p`'s model
        // context is alive. After this the wrapper never dereferences `p`
        // again, so it stays valid after a ModelContext reset (see SDKSnapshot).
        self.snapshot = SDKSnapshot(p)
        // PersistentTransaction.blockTimestamp is 0 until mined; firstSeen
        // is set when the tx is first observed (mempool entry). Use it as
        // the mempool fallback so the home screen doesn't group these
        // into a 1970 section. Re-evaluates on relaunch — acceptable for
        // typical mainnet confirmation latency.
        let ts: UInt64 = p.blockTimestamp == 0 ? p.firstSeen : UInt64(p.blockTimestamp)
        self.date = ts == 0
            ? Date()
            : Date(timeIntervalSince1970: TimeInterval(ts))
    }

    /// Synthetic wrapper for a transaction that has no persisted row: the
    /// onboarding demo list and the post-send success screen's fallback while
    /// the Rust persister hasn't written the row yet. Display-only — never
    /// stored, never fed back into persistence.
    ///
    /// - Parameters:
    ///   - txid: wire-order txid (same byte order as `txHashData`).
    ///   - directionRaw: FFI direction encoding (0=incoming, 1=outgoing,
    ///     2=internal, 3=coinjoin).
    ///   - contextRaw: 0=mempool, 1=instantSend, 2=inBlock, 3=chainLocked.
    init(syntheticTxid txid: Data, directionRaw: UInt32, netAmount: Int64,
         fee: UInt64?, contextRaw: UInt32, date: Date,
         externalSentAddresses: [String] = []) {
        self.snapshot = SDKSnapshot(
            syntheticTxid: txid,
            direction: directionRaw,
            netAmount: netAmount,
            fee: fee,
            context: contextRaw,
            externalSentAddresses: externalSentAddresses)
        self.date = date
    }
}

extension Transaction {
    var feeUsed: UInt64 { snapshot.fee ?? 0 }

    var dashAmountTintColor: UIColor {
        direction.dashAmountTintColor
    }

    var txHashHexString: String { Self.displayHex(snapshot.txid) }

    var txHashData: Data { snapshot.txid }

    /// True for any masternode special transaction: provider registration
    /// (proRegTx), update registrar/service, or revocation. Drives the
    /// "Masternode" home filter category.
    var isMasternodeTransaction: Bool {
        switch transactionType {
        case .masternodeRegistration, .masternodeUpdate, .masternodeRevoke:
            return true
        default:
            return false
        }
    }

    var isCoinbaseTransaction: Bool {
        TransactionTypeKind(rawValue: snapshot.typeKind) == .coinbase
    }
}

extension Transaction: Hashable {
    // MARK: - Equatable
    static func == (lhs: Transaction, rhs: Transaction) -> Bool {
        return lhs.txHashData == rhs.txHashData
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(dashAmount)
        hasher.combine(direction)
        hasher.combine(transactionType)
        hasher.combine(date)
    }
}
