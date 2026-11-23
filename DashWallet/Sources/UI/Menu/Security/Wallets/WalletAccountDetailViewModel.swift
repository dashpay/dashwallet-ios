//
//  WalletAccountDetailViewModel.swift
//  DashWallet
//
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
//  ViewModel for the account detail screen (Wallets → wallet → tap an
//  account). Projects one `PersistentAccount` — overview, live balance,
//  address-pool stats, per-pool address lists, and the extended public key
//  for provider key accounts — mirroring the SwiftExampleApp's
//  `AccountDetailView` data flow. All SDK and SwiftData work lives here —
//  the SwiftUI screen only renders `detail` (SwiftUI-first guardrail).
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

/// One address of an account's pool, as rendered by the detail screen.
struct AccountAddressItem: Identifiable, Equatable {
    /// Base58check (core pools) or bech32m (DIP-17 platform pool).
    let address: String
    let index: UInt32
    let isUsed: Bool
    /// Duffs for core addresses; credits for platform addresses.
    let balance: UInt64

    var id: String { address }
}

/// One pool section ("External", "Internal", …) of the address list.
struct AccountAddressSection: Identifiable, Equatable {
    let name: String
    let items: [AccountAddressItem]

    var id: String { name }
}

/// Everything the detail screen shows for one account — a pure value
/// projection of `PersistentAccount` + the manager's live `AccountBalance`.
struct WalletAccountDetail: Equatable {
    let typeName: String
    let accountIndex: UInt32
    let networkName: String

    let showsBalance: Bool
    let isPlatformPayment: Bool
    /// Provider operator (BLS, tag 10) / platform-node (EdDSA, tag 11)
    /// key-material accounts: no addresses or balance — show the xpub.
    let isProviderKeyAccount: Bool

    /// Live balances in duffs (funds accounts only).
    let confirmed: UInt64
    let unconfirmed: UInt64
    /// PlatformPayment only: total balance in credits.
    let platformCredits: UInt64

    /// Core pool stats (non-platform accounts).
    let externalPoolSize: Int
    let internalPoolSize: Int
    /// Highest used derivation index, or nil when the pool is unused.
    let externalHighestUsed: Int32?
    let internalHighestUsed: Int32?
    /// Distinct transactions this account participates in: the union of the
    /// TXO-derived set (each TXO's creating + spending tx) and the
    /// payload-only `involvedTransactions` join, de-duped by txid.
    let transactionCount: Int
    let txoCount: Int

    /// Platform pool stats (PlatformPayment accounts).
    let platformAddressesTotal: Int
    let platformAddressesUsed: Int
    let platformHighestUsed: UInt32?

    /// Address lists grouped by pool, in stable display order.
    let addressSections: [AccountAddressSection]

    /// Bincode-encoded extended public key hex (provider key accounts), or
    /// nil when the account has none persisted yet.
    let extendedPublicKeyHex: String?
}

@MainActor
final class WalletAccountDetailViewModel: ObservableObject {
    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "wallet-account-detail")

    /// Nil until `reload()` finds the account; the screen shows an
    /// unavailable state then.
    @Published private(set) var detail: WalletAccountDetail? = nil

    private let walletId: Data
    private let account: WalletAccountRow

    init(walletId: Data, account: WalletAccountRow) {
        self.walletId = walletId
        self.account = account
    }

    func reload() {
        guard let context = SwiftDashSDKHost.shared.modelContainer?.mainContext else {
            Self.logger.error("reload: no model container")
            detail = nil
            return
        }

        // The displayed accounts exclude the DashPay friendship tags, so
        // (wallet, type, index, standardTag, registrationIndex, keyClass)
        // is unique per the persister's match logic.
        let targetId = walletId
        let type = account.accountType
        let index = account.accountIndex
        let standardTag = account.standardTag
        let registrationIndex = account.registrationIndex
        let keyClass = account.keyClass
        var descriptor = FetchDescriptor<PersistentAccount>(
            predicate: #Predicate {
                $0.wallet.walletId == targetId &&
                    $0.accountType == type &&
                    $0.accountIndex == index &&
                    $0.standardTag == standardTag &&
                    $0.registrationIndex == registrationIndex &&
                    $0.keyClass == keyClass
            })
        descriptor.fetchLimit = 1

        guard let persisted = (try? context.fetch(descriptor))?.first else {
            Self.logger.error("reload: account row not found")
            detail = nil
            return
        }

        let live = (SwiftDashSDKHost.shared.manager?.accountBalances(for: walletId) ?? [])
            .first { entry in
                UInt32(entry.typeTag) == type &&
                    entry.standardTag == standardTag &&
                    entry.index == index
            }

        detail = Self.project(persisted, live: live)
    }

    private static func project(
        _ account: PersistentAccount,
        live: PlatformWalletManager.AccountBalance?
    ) -> WalletAccountDetail {
        let showsBalance = account.accountType == 0 || account.accountType == 1 || account.accountType == 14
        let isPlatformPayment = account.accountType == 14

        // Distinct transactions: TXO walk (creating + spending tx per TXO)
        // unioned with the payload-only involvement join, de-duped by txid —
        // same derivation as the SwiftExampleApp's AccountDetailView.
        var txids = Set<Data>()
        var txoCount = 0
        for address in account.coreAddresses {
            for txo in address.txos {
                txoCount += 1
                if let tx = txo.transaction { txids.insert(tx.txid) }
                if let spending = txo.spendingTransaction { txids.insert(spending.txid) }
            }
        }
        for tx in account.involvedTransactions { txids.insert(tx.txid) }

        // Address lists grouped by pool tag, in stable display order (pool
        // names via `PersistentCoreAddress.poolTypeName` — the shared
        // taxonomy; tags 2/3 are the on-demand "Additional" pools).
        let grouped = Dictionary(grouping: account.coreAddresses) { $0.poolTypeTag }
        let sections: [AccountAddressSection]
        if isPlatformPayment {
            let items = account.platformAddresses
                .sorted { $0.addressIndex < $1.addressIndex }
                .map { AccountAddressItem(address: $0.address, index: $0.addressIndex, isUsed: $0.isUsed, balance: $0.balance) }
            sections = items.isEmpty
                ? []
                : [AccountAddressSection(
                    name: NSLocalizedString("Platform Addresses", comment: "Wallet accounts"),
                    items: items)]
        } else {
            sections = [UInt8(0), 1, 2, 3].compactMap { tag in
                guard let bucket = grouped[tag], !bucket.isEmpty else { return nil }
                let items = bucket
                    .sorted { $0.addressIndex < $1.addressIndex }
                    .map { AccountAddressItem(address: $0.address, index: $0.addressIndex, isUsed: $0.isUsed, balance: $0.balance) }
                return AccountAddressSection(name: bucket[0].poolTypeName, items: items)
            }
        }

        let platformUsed = account.platformAddresses.filter { $0.isUsed }
        return WalletAccountDetail(
            typeName: account.accountTypeName,
            accountIndex: account.accountIndex,
            networkName: account.wallet.network?.displayName
                ?? NSLocalizedString("Unknown", comment: ""),
            showsBalance: showsBalance,
            isPlatformPayment: isPlatformPayment,
            isProviderKeyAccount: account.accountType == 10 || account.accountType == 11,
            confirmed: live?.confirmed ?? account.balanceConfirmed,
            unconfirmed: live?.unconfirmed ?? account.balanceUnconfirmed,
            platformCredits: account.platformAddresses.reduce(0) { $0 + $1.balance },
            externalPoolSize: account.coreAddresses.filter { $0.poolTypeTag == 0 }.count,
            internalPoolSize: account.coreAddresses.filter { $0.poolTypeTag == 1 }.count,
            externalHighestUsed: account.externalHighestUsed >= 0 ? account.externalHighestUsed : nil,
            internalHighestUsed: account.internalHighestUsed >= 0 ? account.internalHighestUsed : nil,
            transactionCount: txids.count,
            txoCount: txoCount,
            platformAddressesTotal: account.platformAddresses.count,
            platformAddressesUsed: platformUsed.count,
            platformHighestUsed: platformUsed.map { $0.addressIndex }.max(),
            addressSections: sections,
            extendedPublicKeyHex: account.accountExtendedPubKeyBytes.map {
                $0.map { String(format: "%02x", $0) }.joined()
            })
    }
}
