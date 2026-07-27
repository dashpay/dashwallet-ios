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
    /// Owning wallet id — main-identity selection is scoped to the
    /// active wallet, so the detail page needs this to offer it.
    let walletId: Data?
    let identityIndex: UInt32
    let publicKeyCount: Int
    /// Every DPNS label owned by this identity (detail sheet list).
    let dpnsNames: [String]
    /// Contested label submitted by this wallet but not owned yet.
    /// Kept separate from `dpnsNames` so every identities surface can
    /// render it explicitly as voting rather than as a confirmed name.
    let pendingContestedName: String?
    /// True when this identity is the wallet's resolved MAIN identity —
    /// the one `DWCurrentUserIdentityInfo` reads, i.e. the owner of
    /// DashPay mode (username, avatar, contacts). Resolution = stored
    /// pick → index 0 → lowest index.
    let isMainIdentity: Bool

    var id: Data { identityId }
}

@MainActor
final class IdentitiesViewModel: ObservableObject {

    @Published private(set) var rows: [IdentityRowModel] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isDiscovering = false
    @Published var errorMessage: String?
    /// Outcome of the explicit Find-identities scan ("Found 2 new
    /// identities" / none found) — presented as an informational alert.
    @Published var infoMessage: String?

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
        // The RESOLVED main identity (stored pick → index 0 → lowest) —
        // read from the same source every DashPay surface reads, so the
        // star can't disagree with actual behavior.
        let mainIdentityId = DWCurrentUserIdentityInfo.shared.identityId
        rows = identities.map { Self.rowModel(for: $0, mainIdentityId: mainIdentityId) }
    }

    /// Make `row` the wallet's main identity: the one every DashPay
    /// surface keys on (username, avatar, contacts owner). Stores the
    /// per-wallet pick, then drives the same refresh cascade a
    /// registration completion does so the app re-keys live: identity
    /// snapshot, DWGlobalOptions username mirror (the new main's name,
    /// or cleared when it has none — the Join banner then honestly
    /// returns), the registration-status notification chain, and the
    /// contacts snapshots.
    func setMainIdentity(_ row: IdentityRowModel) {
        guard let activeWalletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            errorMessage = NSLocalizedString("Wallet is not ready", comment: "Identities")
            return
        }
        guard row.walletId == activeWalletId else {
            errorMessage = NSLocalizedString(
                "The main identity can only be chosen from the active wallet",
                comment: "Identities")
            return
        }

        DWCurrentUserIdentityInfo.setMainIdentityId(row.identityId, walletId: activeWalletId)
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()

        let options = DWGlobalOptions.sharedInstance()
        let username = DWCurrentUserIdentityInfo.shared.username
        options.dashpayUsername = username
        options.dashpayRegistrationCompleted = username?.isEmpty == false

        NotificationCenter.default.post(
            name: DWIdentityRegistrationBridge.stateChangedNotification,
            object: nil)
        SwiftDashSDKContactsService.shared.refresh()
        reload()
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

    /// Explicit "Find identities" command — the example app's
    /// "Re-scan for Identities": a DIP-9 gap-limit scan of the ACTIVE
    /// wallet's identity-authentication derivation tree against Platform
    /// (`ManagedPlatformWallet.discoverIdentities`). Unlike the refresh,
    /// this DISCOVERS identities the local store has never seen — after a
    /// reinstall, an imported recovery phrase, or a registration made on
    /// another device with the same seed. Discoveries are persisted by
    /// the SDK's identity persister; `startIndex: 0` forces a full
    /// re-walk rather than resuming from the cached scan watermark.
    /// Scans only the loaded (active) wallet — other on-device wallets
    /// would each need their own loaded handle.
    func discoverIdentities() async {
        guard !isDiscovering else { return }
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            errorMessage = NSLocalizedString("Wallet is not ready", comment: "Identities")
            return
        }
        isDiscovering = true
        defer {
            isDiscovering = false
            reload()
        }
        do {
            let found = try await wallet.discoverIdentities(startIndex: 0)
            if found.isEmpty {
                infoMessage = NSLocalizedString(
                    "No new identities were found for this wallet",
                    comment: "Identities")
            } else {
                infoMessage = found.count == 1
                    ? NSLocalizedString("Found 1 new identity", comment: "Identities")
                    : String(
                        format: NSLocalizedString("Found %d new identities", comment: "Identities"),
                        found.count)
                // Backfill balances / usernames for the fresh rows, THEN
                // adopt — the discovered row usually arrives nameless and
                // the DPNS backfill supplies the username adoption needs.
                reload()
                await refreshFromNetwork()
                adoptActiveWalletIdentityIfNeeded()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A discovery that surfaced the ACTIVE wallet's pinned identity
    /// (index 0) flips the app into DashPay mode — the same
    /// `DWGlobalOptions` mirror + notification chain a fresh registration
    /// performs on `.completed` — provided the identity already owns a
    /// DPNS username. A nameless identity stays list-only: Join DashPay
    /// later completes the name (the coordinator skips IdentityCreate for
    /// an existing identity at the pinned slot). No-op when the mirror is
    /// already set, so re-running Find can't clobber live state.
    private func adoptActiveWalletIdentityIfNeeded() {
        let options = DWGlobalOptions.sharedInstance()
        guard options.dashpayUsername?.isEmpty != false else { return }
        guard let container = SwiftDashSDKHost.shared.modelContainer,
              let activeWalletId = SwiftDashSDKHost.shared.wallet?.walletId else { return }

        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { identity in
                identity.wallet?.walletId == activeWalletId && identity.identityIndex == 0
            })
        descriptor.fetchLimit = 1
        guard let identity = try? container.mainContext.fetch(descriptor).first else { return }
        let username = [identity.mainDpnsName, identity.dpnsName]
            .compactMap { $0?.nonEmptyString }
            .first
        guard let username else { return }

        options.dashpayUsername = username
        options.dashpayRegistrationCompleted = true
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
        // Internal bridge notification: DWDashPayModel observes it, rebuilds
        // its state, and posts the canonical
        // DWDashPayRegistrationStatusUpdatedNotification for the wider UI —
        // same ordering as a registration completion.
        NotificationCenter.default.post(
            name: DWIdentityRegistrationBridge.stateChangedNotification,
            object: nil)
    }

    // MARK: - Mapping

    private static func rowModel(for identity: PersistentIdentity, mainIdentityId: Data?) -> IdentityRowModel {
        let pendingLabel = DWContestedNameStatusService.shared.pendingLabel
        let isPending: (String?) -> Bool = { candidate in
            guard let candidate, let pendingLabel else { return false }
            return DWContestedNameStatusService.labelsMatch(candidate, pendingLabel)
        }
        let allNames = identity.dpnsNames.map(\.label)
        let pendingBelongsToIdentity = pendingLabel != nil && (
            isPending(identity.mainDpnsName)
                || isPending(identity.dpnsName)
                || allNames.contains(where: { isPending($0) })
        )
        let ownedNames = allNames.filter { !isPending($0) }
        let alias = identity.alias?.nonEmptyString
        let mainName = isPending(identity.mainDpnsName)
            ? nil
            : identity.mainDpnsName?.nonEmptyString
        let preferredName = isPending(identity.dpnsName)
            ? nil
            : identity.dpnsName?.nonEmptyString
        let title = alias
            ?? mainName
            ?? preferredName
            ?? ownedNames.first
            ?? (pendingBelongsToIdentity ? pendingLabel : nil)
            ?? (String(identity.identityIdString.prefix(12)) + "...")
        let hasName = alias != nil || mainName != nil || preferredName != nil || !ownedNames.isEmpty
        // Balance is stored as Int64 bit-pattern of the UInt64 credits.
        let credits = UInt64(bitPattern: identity.balance)
        return IdentityRowModel(
            identityId: identity.identityId,
            title: title,
            hasName: hasName,
            isMainName: mainName != nil,
            subtitle: hasName ? alias : nil,
            idBase58: identity.identityIdBase58,
            balanceText: InternalTransferViewModel.cardBalanceString(duffs: credits / 1000),
            balanceDetailText: identity.formattedBalance,
            type: identity.identityTypeEnum,
            isLocal: identity.isLocal,
            walletName: identity.wallet?.label.nonEmptyString,
            walletId: identity.wallet?.walletId,
            identityIndex: identity.identityIndex,
            publicKeyCount: identity.publicKeys.count,
            dpnsNames: ownedNames,
            pendingContestedName: pendingBelongsToIdentity ? pendingLabel : nil,
            isMainIdentity: mainIdentityId != nil && identity.identityId == mainIdentityId)
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
