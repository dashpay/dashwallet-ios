//
//  IdentitiesViewModel.swift
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
//  Backs the "Identities" screen (main menu, under Wallets). Reads the
//  SwiftDashSDK `PersistentIdentity` rows for the current network — the
//  same store the SwiftExampleApp's Identities tab renders — and refreshes
//  balance/DPNS from Platform on pull. All SDK access lives here
//  (SwiftUI-first guardrail); the screen only renders row models.
//

import Combine
import Foundation
import SwiftData
import SwiftDashSDK

/// Immutable per-row projection of a `PersistentIdentity`, captured at
/// reload time so the view never holds live `@Model` references.
struct IdentityRowModel: Identifiable {
    let identityId: Data
    /// `alias → mainDpnsName → dpnsName → truncated id` (the SDK model's
    /// `displayName` priority).
    let title: String
    /// True when the title is a DPNS name / alias rather than the id.
    let hasName: Bool
    /// True when the user pinned a main DPNS name (star affordance,
    /// mirrors the example app's row).
    let isMainName: Bool
    /// Alias shown as subtitle when the title is a DPNS name.
    let subtitle: String?
    let idBase58: String
    /// Balance formatted as a plain DASH decimal (no symbol).
    let balanceText: String
    /// Full-precision balance line for the detail sheet.
    let balanceDetailText: String
    let type: IdentityType
    let isLocal: Bool
    let walletName: String?
    let identityIndex: UInt32
    let publicKeyCount: Int
    /// Every DPNS label owned by this identity (detail sheet list).
    let dpnsNames: [String]

    var id: Data { identityId }
}

@MainActor
final class IdentitiesViewModel: ObservableObject {

    @Published private(set) var rows: [IdentityRowModel] = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    /// Reload the row models from SwiftData. Cheap; called on appear and
    /// after every network refresh.
    func reload() {
        guard let container = SwiftDashSDKHost.shared.modelContainer,
              let network = SwiftDashSDKHost.shared.runningNetwork else {
            rows = []
            return
        }
        let descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: PersistentIdentity.predicate(network: network),
            sortBy: [SortDescriptor(\.identityIndex, order: .forward)])
        let identities = (try? container.mainContext.fetch(descriptor)) ?? []
        rows = identities.map(Self.rowModel(for:))
    }

    /// One-shot Platform refresh, pull-to-refresh style: re-fetch each
    /// identity's balance, and backfill a DPNS name for rows that have
    /// none (silent — not every identity has a name). Mirrors the example
    /// app's `IdentityRow.refreshBalance`, batched over the whole list.
    func refreshFromNetwork() async {
        guard !isRefreshing else { return }
        guard let sdk = SwiftDashSDKHost.shared.sdk,
              let container = SwiftDashSDKHost.shared.modelContainer else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            reload()
        }

        var failures = 0
        for row in rows where !row.isLocal {
            do {
                let fetched = try await sdk.identityGet(identityId: row.idBase58)
                if let balance = Self.uint64(from: fetched["balance"]) {
                    PersistentIdentity.updateBalance(
                        in: container.mainContext,
                        identityId: row.identityId,
                        balance: balance)
                }
                if !row.hasName,
                   let usernames = try? await sdk.dpnsGetUsername(identityId: row.idBase58, limit: 1),
                   let label = usernames.first?["label"] as? String {
                    PersistentIdentity.updateDpnsName(
                        in: container.mainContext,
                        identityId: row.identityId,
                        dpnsName: label)
                }
            } catch {
                failures += 1
            }
        }
        try? container.mainContext.save()

        if failures > 0 {
            errorMessage = String(
                format: NSLocalizedString("Could not refresh %d identities", comment: "Identities"),
                failures)
        }
    }

    // MARK: - Mapping

    private static func rowModel(for identity: PersistentIdentity) -> IdentityRowModel {
        let hasName = (identity.alias?.isEmpty == false)
            || (identity.mainDpnsName?.isEmpty == false)
            || (identity.dpnsName?.isEmpty == false)
        // Balance is stored as Int64 bit-pattern of the UInt64 credits.
        let credits = UInt64(bitPattern: identity.balance)
        return IdentityRowModel(
            identityId: identity.identityId,
            title: identity.displayName,
            hasName: hasName,
            isMainName: identity.mainDpnsName?.isEmpty == false,
            subtitle: hasName ? identity.alias?.nonEmptyString : nil,
            idBase58: identity.identityIdBase58,
            balanceText: InternalTransferViewModel.cardBalanceString(duffs: credits / 1000),
            balanceDetailText: identity.formattedBalance,
            type: identity.identityTypeEnum,
            isLocal: identity.isLocal,
            walletName: identity.wallet?.label.nonEmptyString,
            identityIndex: identity.identityIndex,
            publicKeyCount: identity.publicKeys.count,
            dpnsNames: identity.dpnsNames.map(\.label))
    }

    private static func uint64(from value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let string = value as? String, let parsed = UInt64(string) {
            return parsed
        }
        return nil
    }
}

private extension String {
    /// Self when non-empty, else nil.
    var nonEmptyString: String? { isEmpty ? nil : self }
}
