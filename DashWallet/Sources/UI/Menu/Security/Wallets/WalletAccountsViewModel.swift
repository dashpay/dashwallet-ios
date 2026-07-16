//
//  WalletAccountsViewModel.swift
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
//  ViewModel for the per-wallet Accounts screen (Wallets → tap a wallet).
//  Sources the wallet's persisted accounts (SwiftData `PersistentAccount`)
//  joined with the live per-account balances from the Rust wallet manager,
//  mirroring the SwiftExampleApp's `AccountListView` data flow. All SDK and
//  SwiftData work lives here — the SwiftUI screen only renders `rows`
//  (SwiftUI-first guardrail).
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

/// One account of a wallet as rendered by the Accounts screen. A pure value
/// projection of `PersistentAccount` + the manager's live `AccountBalance`.
struct WalletAccountRow: Identifiable, Equatable {
    /// `AccountTypeTagFFI` discriminant (0 = Standard, 1 = CoinJoin,
    /// 14 = PlatformPayment, …).
    let accountType: UInt32
    /// BIP44 (0) vs BIP32 (1) within Standard; meaningless otherwise.
    let standardTag: UInt8
    let accountIndex: UInt32
    /// Human-readable type name persisted by the SDK ("Standard (BIP44)", …).
    let typeName: String
    /// Confirmed balance in duffs (funds accounts only).
    let confirmed: UInt64
    /// Unconfirmed balance in duffs (funds accounts only).
    let unconfirmed: UInt64
    /// Derived-and-used receive / change address counts for the footer.
    let receiveAddressCount: Int
    let changeAddressCount: Int
    /// PlatformPayment only: total balance in credits and the flat DIP-17
    /// pool's used/total counts. Zero elsewhere.
    let platformCredits: UInt64
    let platformAddressesUsed: Int
    let platformAddressesTotal: Int

    /// Full account-identity tuple minus the identity ids (hidden DashPay
    /// friendship accounts are filtered out before rows are built, so the
    /// remaining fields are unique per the persister's match logic).
    var id: String { "\(accountType)-\(standardTag)-\(accountIndex)-\(registrationIndex)-\(keyClass)" }
    let registrationIndex: UInt32
    let keyClass: UInt32

    /// Whether this is a funds account whose balance is worth showing
    /// (Standard / CoinJoin / PlatformPayment) — mirrors the example app.
    var showsBalance: Bool { accountType == 0 || accountType == 1 || accountType == 14 }
    var isPlatformPayment: Bool { accountType == 14 }
}

@MainActor
final class WalletAccountsViewModel: ObservableObject {
    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "wallet-accounts-screen")

    @Published private(set) var rows: [WalletAccountRow] = []

    let walletName: String
    private let walletId: Data

    init(walletId: Data, walletName: String) {
        self.walletId = walletId
        self.walletName = walletName
    }

    /// Rebuild `rows` from the wallet's persisted accounts joined with the
    /// manager's live in-memory balances. DashPay friendship accounts (tags
    /// 12 receiving / 13 external) are hidden: they're per-contact protocol
    /// plumbing, one pair per friendship, and would crowd the list as
    /// contacts grow (same rationale as the SwiftExampleApp).
    func reload() {
        guard let context = SwiftDashSDKHost.shared.modelContainer?.mainContext else {
            Self.logger.error("reload: no model container")
            rows = []
            return
        }

        let targetId = walletId
        let descriptor = FetchDescriptor<PersistentAccount>(
            predicate: #Predicate { $0.wallet.walletId == targetId })
        let accounts: [PersistentAccount]
        do {
            accounts = try context.fetch(descriptor)
        } catch {
            Self.logger.error("account fetch failed: \(String(describing: error), privacy: .public)")
            rows = []
            return
        }

        let liveBalances = SwiftDashSDKHost.shared.manager?.accountBalances(for: walletId) ?? []

        rows = accounts
            .filter { $0.accountType != 12 && $0.accountType != 13 }
            .map { account in
                // Live in-memory balance when the manager tracks this account,
                // else the persisted snapshot (kept current by the SDK's
                // persistence handler).
                let live = liveBalances.first { entry in
                    UInt32(entry.typeTag) == account.accountType &&
                        entry.standardTag == account.standardTag &&
                        entry.index == account.accountIndex
                }
                return WalletAccountRow(
                    accountType: account.accountType,
                    standardTag: account.standardTag,
                    accountIndex: account.accountIndex,
                    typeName: account.accountTypeName,
                    confirmed: live?.confirmed ?? account.balanceConfirmed,
                    unconfirmed: live?.unconfirmed ?? account.balanceUnconfirmed,
                    receiveAddressCount: max(Int(account.externalHighestUsed) + 1, 0),
                    changeAddressCount: max(Int(account.internalHighestUsed) + 1, 0),
                    platformCredits: account.platformAddresses.reduce(0) { $0 + $1.balance },
                    platformAddressesUsed: account.platformAddresses.filter { $0.isUsed }.count,
                    platformAddressesTotal: account.platformAddresses.count,
                    registrationIndex: account.registrationIndex,
                    keyClass: account.keyClass)
            }
            .sorted { Self.sortKey(for: $0) < Self.sortKey(for: $1) }
    }

    /// Stable display order — grouped by logical priority rather than by raw
    /// type tag, so BIP44 leads, PlatformPayment sits next, BIP32 follows,
    /// CoinJoin after, and every special-purpose account tails off in tag
    /// order (same ordering as the SwiftExampleApp's account list).
    private static func sortKey(for row: WalletAccountRow) -> (UInt8, UInt32, UInt8, UInt32) {
        let group: UInt8
        switch row.accountType {
        case 0:
            group = row.standardTag == 0 ? 0 : 2
        case 14:
            group = 1
        case 1:
            group = 3
        default:
            group = 4
        }
        return (group, row.accountType, row.standardTag, row.accountIndex)
    }
}
