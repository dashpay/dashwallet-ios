//
//  Created by Andrei Ashikhmin
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

// Genuinely app-global keys: user-level UX-education flags shown once ever, and
// CrowdNode service parameters (withdrawal limits, fee) that are refreshed from
// the CrowdNode API and identical for every account. These describe the app/user
// or the service, not one wallet's CrowdNode relationship — they stay global.
private let kInfoShown = "crowdNodeInfoShownKey"
private let kWithdrawalLimitPerTx = "crowdNodeWithdrawalLimitPerTxKey"
private let kWithdrawalLimitPerHour = "crowdNodeWithdrawalLimitPerHourKey"
private let kWithdrawalLimitPerDay = "crowdNodeWithdrawalLimitPerDayKey"
private let kWithdrawalLimitsInfoShown = "crowdNodeWithdrawalLimitsInfoShownKey"
private let kFeePercentage = "feePercentageKey"

// Per-wallet keys: everything below describes ONE wallet's CrowdNode account
// (its funding/primary address, that account's signup/online state, its last
// known balance, its pending confirmation notification, its email-signing
// message id, its last withdrawal block). These are the LEGACY key names — kept
// as the migration source and as the fallback when no wallet is active — routed
// through `perWalletKey(_:)` so the effective key is `<legacy>_<walletIdHex>`.
private let kLastKnownBalance = "lastKnownCrowdNodeBalanceKey"
private let kOnlineAccountState = "сrowdNodeOnlineAccountStateKey"
private let kCrowdNodeAccountAddress = "crowdNodeAccountAddressKey"
private let kCrowdNodePrimaryAddress = "crowdNodePrimaryAddressKey"
private let kConfirmationDialogShown = "crowdNodeConfirmationDialogShownKey"
private let kOnlineInfoShown = "crowdNodeOnlineInfoShownKey"
private let kSignedEmailMessageId = "crowdNodeSignedEmailMessageId"
private let kShouldShowConfirmedNotification = "shouldShowConfirmedNotification"
private let kLastWithdrawalBlock = "lastWithdrawalBlockKey"
// Unlike the keys above this one is NOT legacy — it was introduced after the
// per-wallet scoping, so no pre-multi-wallet install ever wrote the bare key.
// It still routes through `perWalletKey(_:)` like the rest: the bare name is
// only the no-active-wallet fallback.
private let kFruitlessRestoreTxCount = "crowdNodeFruitlessRestoreTxCountKey"

/// The set of legacy keys that are scoped per wallet. Enumerated by `resetForWipe`
/// (which must clear the per-wallet variant for EVERY wallet) and used by
/// `CrowdNodeDefaults.perWalletKeysToClear(forWalletIdHex:)` to build the exact
/// per-wallet keys to remove when a single wallet is deleted.
private let kPerWalletKeys = [
    kLastKnownBalance,
    kOnlineAccountState,
    kCrowdNodeAccountAddress,
    kCrowdNodePrimaryAddress,
    kConfirmationDialogShown,
    kOnlineInfoShown,
    kSignedEmailMessageId,
    kShouldShowConfirmedNotification,
    kLastWithdrawalBlock,
    kFruitlessRestoreTxCount,
]

// MARK: - CrowdNodeDefaults

class CrowdNodeDefaults {
    public static let shared: CrowdNodeDefaults = .init()

    // MARK: - Per-wallet key scoping
    //
    // CrowdNode state describes ONE wallet's CrowdNode account (bound to a
    // funding address in a specific wallet). With multi-wallet switching, an
    // app-global key would show wallet A's CrowdNode balance/account under
    // wallet B. The per-wallet keys above are scoped by the active walletId,
    // mirroring the mechanism `DWGlobalOptions` established for its per-wallet
    // flags: effective key = `<legacyKey>_<activeWalletIdHex>`, resolved live on
    // every access; seeded once from the legacy key on first read for a wallet;
    // legacy key kept dormant and used as the fallback when no wallet is active
    // yet (e.g. before the SDK binds a wallet). The active id comes from
    // `WalletEnvironment.activeWalletIdHex`.

    /// The active wallet's per-wallet key for `legacyKey`, or `nil` when no
    /// wallet is active yet (fresh install / post-wipe window) — callers fall
    /// back to the legacy global key in that case.
    private func perWalletKey(_ legacyKey: String) -> String? {
        guard let walletIdHex = WalletEnvironment.activeWalletIdHex as String?,
              !walletIdHex.isEmpty else {
            return nil
        }
        return "\(legacyKey)_\(walletIdHex)"
    }

    /// Resolve the effective UserDefaults key for a per-wallet `legacyKey`,
    /// seeding the per-wallet key once from the legacy value on first read so an
    /// existing single-wallet install keeps its CrowdNode state. Returns the
    /// legacy key itself when no wallet is active (fallback).
    private func resolvedKey(_ legacyKey: String) -> String {
        let defaults = UserDefaults.standard
        guard let key = perWalletKey(legacyKey) else { return legacyKey }
        if defaults.object(forKey: key) == nil,
           let legacyValue = defaults.object(forKey: legacyKey) {
            // First access for this wallet: seed from the legacy global value so
            // a pre-multi-wallet install's CrowdNode account carries over.
            defaults.set(legacyValue, forKey: key)
        }
        return key
    }

    /// Drop the in-memory caches so the next read resolves the now-active
    /// wallet's per-wallet keys. Called on `activeWalletDidChange` — the
    /// persisted per-wallet values are untouched.
    func invalidateCache() {
        _accountAddress = nil
        _infoShown = nil
        _lastKnownBalance = nil
        _crowdNodeWithdrawalLimitPerTx = nil
        _crowdNodeWithdrawalLimitPerHour = nil
        _crowdNodeWithdrawalLimitPerDay = nil
        _feePercentage = nil
        _withdrawalLimitsInfoShown = nil
        _savedOnlineAccountState = nil
        _crowdNodePrimaryAddress = nil
        _confirmationDialogShown = nil
        _onlineInfoShown = nil
        _shouldShowConfirmedNotification = nil
        _signedEmailMessageId = nil
        _lastWithdrawalBlock = nil
        _fruitlessRestoreTxCount = nil
    }

    private var _accountAddress: String? = nil
    var accountAddress: String? {
        get { _accountAddress ?? UserDefaults.standard.value(forKey: resolvedKey(kCrowdNodeAccountAddress)) as? String }
        set(value) {
            _accountAddress = value
            UserDefaults.standard.set(value, forKey: resolvedKey(kCrowdNodeAccountAddress))
        }
    }

    private var _infoShown: Bool? = nil
    var infoShown: Bool {
        get { _infoShown ?? UserDefaults.standard.bool(forKey: kInfoShown) }
        set(value) {
            _infoShown = value
            UserDefaults.standard.set(value, forKey: kInfoShown)
        }
    }

    private var _lastKnownBalance: UInt64? = nil
    var lastKnownBalance: UInt64 {
        get { _lastKnownBalance ?? UserDefaults.standard.value(forKey: resolvedKey(kLastKnownBalance)) as? UInt64 ?? 0 }
        set(value) {
            _lastKnownBalance = value
            UserDefaults.standard.set(value, forKey: resolvedKey(kLastKnownBalance))
        }
    }

    private var _crowdNodeWithdrawalLimitPerTx: UInt64? = nil
    var crowdNodeWithdrawalLimitPerTx: UInt64 {
        get { _crowdNodeWithdrawalLimitPerTx ?? UserDefaults.standard.value(forKey: kWithdrawalLimitPerTx) as? UInt64 ?? 15 * kOneDash }
        set(value) {
            _crowdNodeWithdrawalLimitPerTx = value
            UserDefaults.standard.set(value, forKey: kWithdrawalLimitPerTx)
        }
    }

    private var _crowdNodeWithdrawalLimitPerHour: UInt64? = nil
    var crowdNodeWithdrawalLimitPerHour: UInt64 {
        get { _crowdNodeWithdrawalLimitPerHour ?? UserDefaults.standard.value(forKey: kWithdrawalLimitPerHour) as? UInt64 ?? 30 * kOneDash }
        set(value) {
            _crowdNodeWithdrawalLimitPerHour = value
            UserDefaults.standard.set(value, forKey: kWithdrawalLimitPerHour)
        }
    }

    private var _crowdNodeWithdrawalLimitPerDay: UInt64? = nil
    var crowdNodeWithdrawalLimitPerDay: UInt64 {
        get { _crowdNodeWithdrawalLimitPerDay ?? UserDefaults.standard.value(forKey: kWithdrawalLimitPerDay) as? UInt64 ?? 60 * kOneDash }
        set(value) {
            _crowdNodeWithdrawalLimitPerDay = value
            UserDefaults.standard.set(value, forKey: kWithdrawalLimitPerDay)
        }
    }
    
    private var _feePercentage: Double? = nil
    var feePercentage: Double {
        get { _feePercentage ?? UserDefaults.standard.value(forKey: kFeePercentage) as? Double ?? CrowdNode.defaultFee }
        set(value) {
            _feePercentage = value
            UserDefaults.standard.set(value, forKey: kFeePercentage)
        }
    }

    private var _withdrawalLimitsInfoShown: Bool? = nil
    var withdrawalLimitsInfoShown: Bool {
        get { _withdrawalLimitsInfoShown ?? UserDefaults.standard.bool(forKey: kWithdrawalLimitsInfoShown) }
        set(value) {
            _withdrawalLimitsInfoShown = value
            UserDefaults.standard.set(value, forKey: kWithdrawalLimitsInfoShown)
        }
    }

    private var _savedOnlineAccountState: CrowdNode.OnlineAccountState? = nil
    var savedOnlineAccountState: CrowdNode.OnlineAccountState {
        get { _savedOnlineAccountState ?? CrowdNode.OnlineAccountState(rawValue: UserDefaults.standard.integer(forKey: resolvedKey(kOnlineAccountState))) ?? .none }
        set(value) {
            _savedOnlineAccountState = value
            UserDefaults.standard.set(value.rawValue, forKey: resolvedKey(kOnlineAccountState))
        }
    }

    private var _crowdNodePrimaryAddress: String? = nil
    var crowdNodePrimaryAddress: String? {
        get { _crowdNodePrimaryAddress ?? UserDefaults.standard.value(forKey: resolvedKey(kCrowdNodePrimaryAddress)) as? String }
        set(value) {
            _crowdNodePrimaryAddress = value
            UserDefaults.standard.set(value, forKey: resolvedKey(kCrowdNodePrimaryAddress))
        }
    }

    private var _confirmationDialogShown: Bool? = nil
    var confirmationDialogShown: Bool {
        get { _confirmationDialogShown ?? UserDefaults.standard.bool(forKey: resolvedKey(kConfirmationDialogShown)) }
        set(value) {
            _confirmationDialogShown = value
            UserDefaults.standard.set(value, forKey: resolvedKey(kConfirmationDialogShown))
        }
    }

    private var _onlineInfoShown: Bool? = nil
    var onlineInfoShown: Bool {
        get { _onlineInfoShown ?? UserDefaults.standard.bool(forKey: resolvedKey(kOnlineInfoShown)) }
        set(value) {
            _onlineInfoShown = value
            UserDefaults.standard.set(value, forKey: resolvedKey(kOnlineInfoShown))
        }
    }

    private var _shouldShowConfirmedNotification: Bool? = nil
    var shouldShowConfirmedNotification: Bool {
        get { _shouldShowConfirmedNotification ?? UserDefaults.standard.bool(forKey: resolvedKey(kShouldShowConfirmedNotification)) }
        set(value) {
            _shouldShowConfirmedNotification = value
            UserDefaults.standard.set(value, forKey: resolvedKey(kShouldShowConfirmedNotification))
        }
    }

    private var _signedEmailMessageId: Int? = nil
    var signedEmailMessageId: Int {
        get { _signedEmailMessageId ?? UserDefaults.standard.value(forKey: resolvedKey(kSignedEmailMessageId)) as? Int ?? -1 }
        set(value) {
            _signedEmailMessageId = value
            UserDefaults.standard.set(value, forKey: resolvedKey(kSignedEmailMessageId))
        }
    }

    private var _lastWithdrawalBlock: UInt32? = nil
    var lastWithdrawalBlock: UInt32 {
        get { _lastWithdrawalBlock ?? UserDefaults.standard.value(forKey: resolvedKey(kLastWithdrawalBlock)) as? UInt32 ?? 0 }
        set(value) {
            _lastWithdrawalBlock = value
            UserDefaults.standard.set(value, forKey: resolvedKey(kLastWithdrawalBlock))
        }
    }

    private var _fruitlessRestoreTxCount: Int? = nil
    /// Persisted-row count as of the last `restoreState()` pass that scanned
    /// this wallet's full post-2022 history and found no CrowdNode account at
    /// all, or nil when no such pass is on record. Lets a later launch skip
    /// the full history scan when nothing was persisted since — the memo is
    /// keyed to the row count rather than latching permanently precisely so a
    /// restored seed whose history syncs in later (count changes) rescans.
    /// Written ONLY by the account-not-found branch; setting nil clears it.
    ///
    /// Resolution deliberately bypasses `resolvedKey`'s seed-from-legacy step:
    /// the bare key can only hold a memo written while no wallet was active,
    /// i.e. from a pass whose wallet-scoped scan was vacuous — seeding it into
    /// a wallet's key would let that wallet skip a scan it never ran.
    var fruitlessRestoreTxCount: Int? {
        get {
            let key = perWalletKey(kFruitlessRestoreTxCount) ?? kFruitlessRestoreTxCount
            return _fruitlessRestoreTxCount ?? UserDefaults.standard.value(forKey: key) as? Int
        }
        set(value) {
            _fruitlessRestoreTxCount = value
            let key = perWalletKey(kFruitlessRestoreTxCount) ?? kFruitlessRestoreTxCount
            UserDefaults.standard.set(value, forKey: key)
        }
    }


    /// Reset the ACTIVE wallet's CrowdNode state (plus the two global education
    /// flags). Writes through the per-wallet-scoped properties, so it clears the
    /// active wallet's keys only — used by `CrowdNode.reset()` on
    /// network-change / alien-address detection, where only the current wallet's
    /// relationship is being torn down.
    func resetUserDefaults() {
        infoShown = false
        lastKnownBalance = 0
        withdrawalLimitsInfoShown = false
        savedOnlineAccountState = .none
        accountAddress = nil
        crowdNodePrimaryAddress = nil
        confirmationDialogShown = false
        onlineInfoShown = false
        signedEmailMessageId = -1
        lastWithdrawalBlock = 0
        fruitlessRestoreTxCount = nil
    }

    /// Clear a SINGLE wallet's per-wallet CrowdNode keys (the removed wallet may
    /// not be the active one, so this addresses keys by explicit `walletIdHex`
    /// rather than through the active-wallet-scoped properties). Invoked from the
    /// shared per-wallet deletion primitive when a wallet is removed. Leaves the
    /// legacy keys and the global education/limit flags intact.
    func clearPerWalletKeys(forWalletIdHex walletIdHex: String) {
        guard !walletIdHex.isEmpty else { return }
        let defaults = UserDefaults.standard
        for legacyKey in kPerWalletKeys {
            defaults.removeObject(forKey: "\(legacyKey)_\(walletIdHex)")
        }
    }

    /// Clear CrowdNode state for a full wallet wipe (which destroys EVERY
    /// wallet). Removes the per-wallet variant of each per-wallet key for every
    /// wallet — enumerated by prefix over UserDefaults, since the walletIds are
    /// gone by wipe time — plus the dormant legacy keys, plus the global
    /// education flags. Also drops the in-memory cache on the long-lived
    /// `shared` singleton so stale values don't linger until the next launch.
    func resetForWipe() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            if kPerWalletKeys.contains(where: { key.hasPrefix("\($0)_") }) {
                defaults.removeObject(forKey: key)
            }
        }
        // Dormant legacy (pre-multi-wallet) per-wallet keys.
        for legacyKey in kPerWalletKeys {
            defaults.removeObject(forKey: legacyKey)
        }
        // Global education flags (limits/fee are re-fetched from the API, so
        // they're left to refresh on next use).
        defaults.removeObject(forKey: kInfoShown)
        defaults.removeObject(forKey: kWithdrawalLimitsInfoShown)
        invalidateCache()
    }
}
