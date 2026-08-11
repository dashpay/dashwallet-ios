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

/// Immutable projection of one `PersistentPublicKey`, captured at reload
/// time (same no-live-`@Model` contract as `IdentityRowModel`). Feeds the
/// identity detail's Public Keys page.
struct IdentityKeyRowModel: Identifiable {
    let keyId: Int32
    /// Human name of the DPP purpose/level/type, or the raw stored value
    /// when it doesn't map to a known enum case (future variants render
    /// honestly instead of being hidden).
    let purposeText: String
    let securityLevelText: String
    let keyTypeText: String
    let readOnly: Bool
    let isDisabled: Bool
    /// The key material as stored (33-byte compressed point, 48-byte BLS
    /// pubkey, or a 20-byte hash for the *Hash160 types).
    let publicKeyHex: String
    /// Base58 contract ids this key is bound to; empty when unbounded.
    let contractBoundIds: [String]
    /// Document-type name for a `.singleContractDocumentType` bound.
    let contractBoundDocumentType: String?
    /// DIP-9 derivation path breadcrumb, when persisted.
    let derivationPath: String?

    var id: Int32 { keyId }
}

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
    /// The identity's public keys, ordered by key id (detail page list;
    /// its count drives the summary row).
    let publicKeys: [IdentityKeyRowModel]
    /// Every DPNS label owned by this identity (detail sheet list).
    let dpnsNames: [String]
    /// The label the identity currently displays: the stored
    /// `mainDpnsName` pick when set, else the same fallback the title
    /// uses (`dpnsName` → first owned label). Drives the selection
    /// indicator on the detail page's Usernames card. Nil when the
    /// identity owns no names.
    let displayedDpnsName: String?
    /// Contested label submitted by this wallet but not owned yet.
    /// Kept separate from `dpnsNames` so every identities surface can
    /// render it explicitly as voting rather than as a confirmed name.
    let pendingContestedName: String?
    /// Best-known close time of that contest — the submission-time estimate
    /// until Platform's `ContestVoteState.endTime` replaces it. nil only when
    /// there is no pending submission for this identity.
    let pendingVotingEndTime: Date?
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
        _ = DWCurrentUserIdentityInfo.shared.reconcileRecoveredIdentity()
        reload()
    }

    /// Persist `name` as the identity's main DPNS name — the label every
    /// display surface prefers (`alias → mainDpnsName → dpnsName → first
    /// owned label`). When the identity is the wallet's main identity,
    /// drive the same reconcile cascade `setMainIdentity` uses so the
    /// app-wide username mirror and live DashPay surfaces re-render with
    /// the new pick immediately.
    func setMainName(_ name: String, for row: IdentityRowModel) {
        guard let container = SwiftDashSDKHost.shared.modelContainer else {
            errorMessage = NSLocalizedString("Wallet is not ready", comment: "Identities")
            return
        }
        // Only an owned (non-pending) label can be displayed.
        guard row.dpnsNames.contains(where: { DWContestedNameStatusService.labelsMatch($0, name) }) else {
            return
        }
        PersistentIdentity.updateMainDpnsName(
            in: container.mainContext,
            identityId: row.identityId,
            mainDpnsName: name)
        try? container.mainContext.save()
        if row.isMainIdentity {
            _ = DWCurrentUserIdentityInfo.shared.reconcileRecoveredIdentity()
        }
        reload()
    }

    /// One-shot Platform refresh, pull-to-refresh style: re-fetch each
    /// identity's balance, and backfill a DPNS name for rows that have
    /// none (silent — not every identity has a name). Mirrors the example
    /// app's `IdentityRow.refreshBalance`, batched over the whole list.
    /// Re-fetch one wallet-owned identity from Platform — public keys
    /// included — via the Rust load pipeline, then rebuild the rows. The
    /// persisted key rows lag keys added on another device; this is the
    /// user-facing "refresh my identity's keys" action (Identities →
    /// detail → Public keys). Only identities of the ACTIVE wallet can be
    /// reloaded: `loadIdentity(atIndex:)` probes the active wallet's DIP-9
    /// tree. The wallet linkage is the gate — deliberately NOT `isLocal`,
    /// which persisted rows have been observed to carry as false for the
    /// wallet's own identity. Returns false for other wallets' rows.
    @discardableResult
    func refreshIdentityKeys(for row: IdentityRowModel) async -> Bool {
        guard let activeWalletId = SwiftDashSDKHost.shared.wallet?.walletId,
              row.walletId == activeWalletId else {
            DWLogger.log("IdentitiesViewModel: key refresh skipped — identity \(row.idBase58) is not the active wallet's (walletId=\(row.walletId?.hexEncodedString() ?? "nil"))")
            return false
        }
        #if DASHPAY
        await DWIdentityReloader.reload(identityIndex: row.identityIndex)
        reload()
        return true
        #else
        return false
        #endif
    }

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
            }
            // Backfill balances / usernames, THEN adopt. Run this even when
            // the scan found no new row: an earlier discovery may already be
            // persisted while the app-level DashPay mirror/UI is stale.
            reload()
            await refreshFromNetwork()
            adoptActiveWalletIdentityIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reconcile an identity found by the explicit scan through the same
    /// recovery path startup uses. In particular this posts the canonical
    /// registration notification directly — there is no active registration
    /// bridge username in a seed-recovery session.
    private func adoptActiveWalletIdentityIfNeeded() {
        _ = DWCurrentUserIdentityInfo.shared.reconcileRecoveredIdentity()
    }

    // MARK: - Mapping

    private static func rowModel(for identity: PersistentIdentity, mainIdentityId: Data?) -> IdentityRowModel {
        let pendingLabel = DWContestedNameStatusService.shared.pendingLabel
        let isPending: (String?) -> Bool = { candidate in
            guard let candidate, let pendingLabel else { return false }
            return DWContestedNameStatusService.labelsMatch(candidate, pendingLabel)
        }
        // Sold / transferred-away labels stay in the cache as rows with
        // `isOwned == false` (their trade history remains browsable) —
        // they are no longer this identity's names and must not appear
        // in the picker or count toward "has a name".
        let allNames = identity.dpnsNames.filter(\.isOwned).map(\.label)
        let departedLabels = identity.dpnsNames.filter { !$0.isOwned }.map(\.label)
        let isSoldAway: (String?) -> Bool = { candidate in
            guard let candidate else { return false }
            return departedLabels.contains { DWContestedNameStatusService.labelsMatch($0, candidate) }
        }
        let pendingBelongsToIdentity = pendingLabel != nil && (
            isPending(identity.mainDpnsName)
                || isPending(identity.dpnsName)
                || allNames.contains(where: { isPending($0) })
        )
        let ownedNames = allNames.filter { !isPending($0) }
        let alias = identity.alias?.nonEmptyString
        // The display-pick scalars can outlive a sale of the picked name;
        // a KNOWN-departed label falls through to the next candidate.
        // (Scalars are still trusted while the label cache is empty —
        // they double as the hydration fallback.)
        let mainName = isPending(identity.mainDpnsName) || isSoldAway(identity.mainDpnsName)
            ? nil
            : identity.mainDpnsName?.nonEmptyString
        let preferredName = isPending(identity.dpnsName) || isSoldAway(identity.dpnsName)
            ? nil
            : identity.dpnsName?.nonEmptyString
        let displayedName = mainName ?? preferredName ?? ownedNames.first
        let title = alias
            ?? displayedName
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
            publicKeys: identity.publicKeys
                .sorted { $0.keyId < $1.keyId }
                .map(keyRowModel(for:)),
            dpnsNames: ownedNames,
            displayedDpnsName: displayedName,
            pendingContestedName: pendingBelongsToIdentity ? pendingLabel : nil,
            pendingVotingEndTime: pendingBelongsToIdentity
                ? DWContestedNameStatusService.shared.pendingVotingEndTime
                : nil,
            isMainIdentity: mainIdentityId != nil && identity.identityId == mainIdentityId)
    }

    /// Project one persisted identity key for display. The stored
    /// purpose/level/type are raw-value strings; unmapped values (future
    /// DPP variants) render as the raw value rather than being hidden.
    private static func keyRowModel(for key: PersistentPublicKey) -> IdentityKeyRowModel {
        IdentityKeyRowModel(
            keyId: key.keyId,
            purposeText: key.purposeEnum?.description ?? key.purpose,
            securityLevelText: key.securityLevelEnum?.description ?? key.securityLevel,
            keyTypeText: key.keyTypeEnum?.name ?? key.keyType,
            readOnly: key.readOnly,
            isDisabled: key.isDisabled,
            publicKeyHex: key.publicKeyData.map { String(format: "%02x", $0) }.joined(),
            contractBoundIds: (key.contractBounds ?? []).map { $0.toBase58String() },
            contractBoundDocumentType: key.contractBoundsDocumentTypeName,
            derivationPath: key.identityDerivationPath)
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
