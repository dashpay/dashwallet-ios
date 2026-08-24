//
//  Created by Claude Code
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation
import SwiftDashSDK

// MARK: - AddMasternodeViewModel

/// Tools → Masternodes → Add: find any masternode / evonode on the network
/// by IP, proTxHash or one of its private keys (SDK locator), track it
/// independently of every wallet, and optionally attach keys.
///
/// All lookup / matching / verification logic is in the SDK
/// (`locateMasternode`, `verifyMasternodeKey`, `trackMasternode`); this model
/// only sequences the flow and holds screen state. Keys the user attaches are
/// stored in the app's keychain vault — the SDK never retains them.
@MainActor
final class AddMasternodeViewModel: ObservableObject {
    // MARK: Find step

    /// The locator text: IP (`1.2.3.4`, `1.2.3.4:9999`), proTxHash (explorer
    /// hex), or a private key (owner / voting / payout WIF or hex, operator
    /// BLS hex, Tenderdash node key).
    @Published var query = ""
    /// Also ask Platform for the owner / payout role of a pasted key. Owner
    /// and payout keys are not on the masternode list, so without this they
    /// can't be located — but the lookup reveals the key's public hash to a
    /// DAPI node, so it stays opt-in (owner decision 2026-08-24).
    @Published var searchPlatform = false
    @Published private(set) var searching = false
    /// `nil` = no search ran yet; empty = ran and found nothing.
    @Published private(set) var matches: [MasternodeLocateMatch]?
    @Published private(set) var searchError: String?
    /// One-line outcome of the opt-in Platform step (unavailable / off),
    /// shown under the results so "no match" is never mistaken for "checked
    /// everywhere".
    @Published private(set) var platformLookupNote: String?

    // MARK: Track + keys step

    /// The match being tracked (single-select; owner decision 2026-08-24).
    @Published private(set) var selected: MasternodeLocateMatch?
    @Published var label = ""
    /// Key text per form role. Pre-filled with the query when the search
    /// matched by that key, so it never has to be typed twice.
    @Published var keyInputs: [MasternodeKeyRole: String] = [:]
    @Published private(set) var keyStates: [MasternodeKeyRole: KeyFieldState] = [:]
    @Published private(set) var tracking = false
    @Published private(set) var trackError: String?
    /// Set once the node is in the registry; the screen switches to the
    /// keys step and the list behind it refreshes on dismiss.
    @Published private(set) var trackedRecord: PlatformMasternode?
    /// Background enrichment (Platform identities + ProRegTx) outcome —
    /// owner / payout verification stays "can't verify yet" until it lands.
    @Published private(set) var refreshing = false
    @Published private(set) var refreshNote: String?

    enum KeyFieldState: Equatable {
        case empty
        case matches
        case doesNotMatch
        /// The reference for this role isn't known yet (owner / payout
        /// before enrichment) — stored, but never claimed verified.
        case unverifiable
        case invalid(String)
    }

    /// The four key roles the form offers (owner decision 2026-08-24; the
    /// platform node key identifies a node but no app action uses it, and
    /// operator payout is deferred with operator-identity withdrawals).
    static let formRoles: [MasternodeKeyRole] = TrackedMasternodeKeyVault.managedRoles

    private let vault: TrackedMasternodeKeyVaulting

    init(vault: TrackedMasternodeKeyVaulting = TrackedMasternodeKeyVault()) {
        self.vault = vault
    }

    // MARK: - Find

    func search() async {
        guard !searching else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let manager = SwiftDashSDKHost.shared.manager else {
            searchError = NSLocalizedString("Wallet is not ready. Try again in a moment.", comment: "Evonode withdrawal")
            return
        }
        searching = true
        searchError = nil
        matches = nil
        platformLookupNote = nil
        defer { searching = false }
        do {
            let result = try await manager.locateMasternode(text, searchPlatform: searchPlatform)
            matches = result.matches
            switch result.platformLookup {
            case .notRequested:
                platformLookupNote = NSLocalizedString(
                    "That could also be an owner or payout key — turn on “Search Platform too” to check.",
                    comment: "Add masternode")
            case .unavailable:
                platformLookupNote = NSLocalizedString(
                    "Platform could not be reached, so owner and payout keys were not checked.",
                    comment: "Add masternode")
            case .notNeeded, .done:
                platformLookupNote = nil
            }
        } catch {
            matches = nil
            searchError = (error as? PlatformWalletError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Track

    /// Track `match` and move to the keys step. Pre-fills every key field
    /// the search already proved (`matchedKeys` ∋ role ⇒ the query text IS
    /// that key), then starts the background enrichment that lets owner /
    /// payout keys verify.
    func track(_ match: MasternodeLocateMatch) async {
        guard !tracking, trackedRecord == nil else { return }
        guard let manager = SwiftDashSDKHost.shared.manager else {
            trackError = NSLocalizedString("Wallet is not ready. Try again in a moment.", comment: "Evonode withdrawal")
            return
        }
        tracking = true
        trackError = nil
        defer { tracking = false }
        do {
            let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = try manager.trackMasternode(
                proTxHash: match.proTxHash,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel)
            selected = match
            trackedRecord = record

            let keyText = query.trimmingCharacters(in: .whitespacesAndNewlines)
            for role in match.matchedKeys where Self.formRoles.contains(role) {
                keyInputs[role] = keyText
            }
            revalidateKeys()
            await refreshDetails()
        } catch {
            trackError = (error as? PlatformWalletError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Fetch the node's Platform identities + registration transaction so
    /// the owner / payout references become verifiable. Best-effort: a
    /// failure leaves those fields "can't verify yet" and says so.
    func refreshDetails() async {
        guard let manager = SwiftDashSDKHost.shared.manager,
              let record = trackedRecord else { return }
        refreshing = true
        refreshNote = nil
        defer { refreshing = false }
        do {
            trackedRecord = try await manager.refreshTrackedMasternode(proTxHash: record.proTxHash)
        } catch {
            refreshNote = NSLocalizedString(
                "Could not load the node's registration details — owner and payout keys will verify later.",
                comment: "Add masternode")
        }
        revalidateKeys()
    }

    /// Persist the label field if it changed since tracking (SDK call —
    /// kept out of the View per the repo guardrails).
    func saveLabelIfChanged() {
        guard let record = trackedRecord,
              let manager = SwiftDashSDKHost.shared.manager else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (record.label ?? "") else { return }
        try? manager.setTrackedMasternodeLabel(
            proTxHash: record.proTxHash,
            label: trimmed.isEmpty ? nil : trimmed)
    }

    /// Seed the model directly at the keys step for an already-tracked
    /// node (the detail screen's key-management sheet).
    func adoptTrackedRecord(_ record: PlatformMasternode) {
        trackedRecord = record
        revalidateKeys()
        Task { await refreshDetails() }
    }

    // MARK: - Keys

    /// Re-verify every non-empty key field against the SDK's references
    /// (masternode list + tracked snapshot). Local; no network.
    func revalidateKeys() {
        guard let manager = SwiftDashSDKHost.shared.manager,
              let record = trackedRecord else { return }
        var states: [MasternodeKeyRole: KeyFieldState] = [:]
        for role in Self.formRoles {
            let text = (keyInputs[role] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                states[role] = .empty
                continue
            }
            do {
                switch try manager.verifyMasternodeKey(
                    proTxHash: record.proTxHash, role: role, key: text) {
                case .matches: states[role] = .matches
                case .doesNotMatch: states[role] = .doesNotMatch
                case .unverifiable: states[role] = .unverifiable
                }
            } catch {
                states[role] = .invalid(
                    (error as? PlatformWalletError)?.errorDescription ?? error.localizedDescription)
            }
        }
        keyStates = states
    }

    /// Whether the keys step can complete: no field holds a key that is
    /// invalid or provably wrong. Empty fields are fine (track-only), and
    /// `unverifiable` saves with its caveat shown.
    var canSaveKeys: Bool {
        !keyStates.values.contains { state in
            switch state {
            case .doesNotMatch, .invalid: return true
            case .empty, .matches, .unverifiable: return false
            }
        }
    }

    /// Store every non-empty field in the keychain vault. Returns false
    /// when a keychain write fails (the screen stays put and says so).
    func saveKeys() -> Bool {
        guard canSaveKeys, let record = trackedRecord else { return false }
        for role in Self.formRoles {
            let text = (keyInputs[role] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard vault.store(text, for: record.proTxHash, role: role) else {
                trackError = NSLocalizedString(
                    "Could not save a key to the keychain. Nothing was lost — try again.",
                    comment: "Add masternode")
                return false
            }
        }
        return true
    }
}
