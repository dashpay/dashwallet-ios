//
//  WalletsViewModel.swift
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
//  ViewModel for the "Wallets" screen (Security menu → Wallets). Owns the
//  list of on-device SwiftDashSDK wallets for the current network and the
//  switch / rename / remove flows. All SDK, SwiftData, and mnemonic work
//  lives here — the SwiftUI `WalletsScreen` only renders `rows` and calls
//  these intents (SwiftUI-first guardrail).
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

/// One on-device wallet as rendered by the Wallets screen.
struct WalletRow: Identifiable, Equatable {
    /// Raw 32-byte walletId — also the switch/rename/remove key.
    let walletId: Data
    /// Display name: `PersistentWallet.name` when set, else "Wallet <prefix>…".
    let displayName: String
    /// House-formatted DASH balance (e.g. "DASH 1.2345"), or nil when the SDK
    /// could not report a balance for this wallet.
    let balanceText: String?
    /// DPNS username of this wallet's identity, when it has one.
    let username: String?
    /// True for the wallet currently bound as active on this network.
    let isActive: Bool

    var id: Data { walletId }
}

@MainActor
final class WalletsViewModel: ObservableObject {
    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "wallets-screen")

    @Published private(set) var rows: [WalletRow] = []
    /// Non-nil while a switch (or an auto-switch before removing the active
    /// wallet) is in flight — the screen shows a blocking progress overlay.
    @Published private(set) var switchInProgress = false
    /// True while an add-wallet (create or import) is in flight — the add sheet
    /// shows a progress state and disables its controls.
    @Published private(set) var addInProgress = false
    /// True for the complete remove transaction, including an active-wallet
    /// pre-switch. Prevents a second destructive operation from interleaving
    /// while the SDK deletion is suspended.
    @Published private(set) var removeInProgress = false
    /// Set to surface an error alert; the screen clears it on dismiss.
    @Published var errorMessage: String? = nil

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Rebuild the list whenever the active wallet changes (switch success)
        // or wallet material changes (a remove completed). Both post on main.
        NotificationCenter.default.publisher(
            for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    // MARK: - List sourcing

    /// Rebuild `rows` from ground truth: the manager's loaded wallets
    /// (`SwiftDashSDKHost.shared.manager?.wallets`) intersected with the
    /// walletIds that have a persisted mnemonic (a wallet without a mnemonic
    /// isn't switchable). Per-row name/username come from the SwiftData store
    /// scoped by walletId; the balance from the managed wallet.
    func reload() {
        let host = SwiftDashSDKHost.shared
        let activeId = activeWalletId()
        let context = host.modelContainer?.mainContext

        let built: [WalletRow] = Self.switchableWallets()
            .map { wallet in
                let walletId = wallet.walletId
                let persisted = context.flatMap { Self.fetchPersistentWallet(walletId: walletId, in: $0) }
                let name = persisted?.name?.nonEmpty
                let username = persisted.flatMap { Self.username(for: $0) }
                let balanceText = (try? wallet.balance().total).map { $0.formattedDashAmount }
                return WalletRow(
                    walletId: walletId,
                    displayName: name ?? Self.fallbackName(for: walletId),
                    balanceText: balanceText,
                    username: username,
                    isActive: walletId == activeId)
            }
            // Stable ordering: active first, then by display name.
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        rows = built
    }

    /// The wallets the current network can switch among: the running manager's
    /// wallets intersected with the walletIds that have a persisted mnemonic
    /// (a wallet without a mnemonic isn't switchable). Shared by `reload()`
    /// and the Switch Wallet shortcut's visibility gate.
    static func switchableWallets() -> [ManagedPlatformWallet] {
        guard let manager = SwiftDashSDKHost.shared.manager else { return [] }
        let switchableIds = Set(SwiftDashSDKHost.persistedMnemonics().map { $0.walletId })
        return manager.wallets.values.filter { switchableIds.contains($0.walletId) }
    }

    /// Cheap visibility gate for the Switch Wallet shortcut (offered while > 1).
    static var switchableWalletCount: Int { switchableWallets().count }

    var hasSingleWallet: Bool { rows.count <= 1 }

    // MARK: - Switch

    /// Switch the active wallet to `walletId`, showing a progress overlay while
    /// the runtime rebuilds. On success `activeWalletDidChangeNotification`
    /// fires and `reload()` refreshes the list; on failure the error surfaces
    /// and the list is left unchanged.
    func switchWallet(to walletId: Data) {
        guard !switchInProgress, !removeInProgress else { return }
        switchInProgress = true
        Task {
            defer { switchInProgress = false }
            do {
                try await SwiftDashSDKWalletRuntime.shared.switchWallet(to: walletId)
                // reload() also runs from the change notification, but call it
                // directly so the list is fresh even if delivery order lags.
                reload()
            } catch {
                Self.logger.error("switchWallet failed: \(String(describing: error), privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Add Wallet

    /// Outcome of an add-wallet attempt, surfaced to the sheet.
    enum AddOutcome: Equatable {
        /// The wallet was added and the app switched to it — dismiss the sheet.
        case switched
        /// A wallet with this recovery phrase is already on this device. Carries
        /// its walletId so the sheet can offer switching to it instead.
        case alreadyOnDevice(walletId: Data)
    }

    /// Generate a fresh 12-word BIP39 mnemonic via the SDK for the "Create New
    /// Wallet" flow. Returns nil (and surfaces an error) on FFI failure. Nothing
    /// is persisted here — creation happens in `addWallet` after the user
    /// confirms they wrote the phrase down.
    func generateMnemonic() -> String? {
        do {
            return try Mnemonic.generate(wordCount: 12)
        } catch {
            Self.logger.error("mnemonic generation failed: \(String(describing: error), privacy: .public)")
            errorMessage = NSLocalizedString("Could not generate a recovery phrase.", comment: "Wallets")
            return nil
        }
    }

    /// Whether `phrase` is a valid BIP39 mnemonic — the import field's gate,
    /// checked before enabling its confirm button.
    func isValidMnemonic(_ phrase: String) -> Bool {
        Mnemonic.validate(Self.normalize(phrase))
    }

    /// Add a wallet from `mnemonic` and switch to it. `origin` controls the
    /// scan/restore lifecycle and the new wallet's `walletNeedsBackup` flag:
    /// a created wallet still needs a backup (its phrase was only shown, not
    /// verified — matches onboarding); an imported wallet does not (the user
    /// already holds the phrase — matches the recover flow).
    ///
    /// Flow: `SwiftDashSDKHost.addWallet` (additive — no rebind) → on `.added`,
    /// `switchWallet(to:)` the new wallet (awaited, progress overlay) → set the
    /// per-wallet backup flag for the now-active new wallet → refresh. On
    /// `.alreadyExists` nothing is written and `.alreadyOnDevice` is returned so
    /// the sheet can offer switching instead.
    ///
    /// Returns the outcome; returns nil after surfacing an error (the sheet
    /// stays open on failure — never claims a success that didn't happen).
    func addWallet(mnemonic: String, origin: WalletMaterialOrigin) async -> AddOutcome? {
        guard !addInProgress, !switchInProgress, !removeInProgress else { return nil }
        let normalized = Self.normalize(mnemonic)

        addInProgress = true
        defer { addInProgress = false }

        let result: SwiftDashSDKHost.AddWalletResult
        do {
            result = try await SwiftDashSDKHost.shared.addWallet(
                mnemonic: normalized,
                origin: origin)
        } catch {
            Self.logger.error("addWallet failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
            return nil
        }

        switch result {
        case .alreadyExists(let walletId):
            return .alreadyOnDevice(walletId: walletId)
        case .added(let walletId):
            switchInProgress = true
            do {
                try await SwiftDashSDKWalletRuntime.shared.switchWallet(to: walletId)
            } catch {
                switchInProgress = false
                Self.logger.error("post-add switch failed: \(String(describing: error), privacy: .public)")
                // The wallet was added but the switch failed; leave it on device
                // and surface the error. The list still gains the new wallet.
                errorMessage = error.localizedDescription
                reload()
                return nil
            }
            switchInProgress = false

            // The new wallet is now the active wallet, so this per-wallet flag
            // targets it (DWGlobalOptions scopes by the active walletId).
            if case .fresh = origin {
                DWGlobalOptions.sharedInstance().walletNeedsBackup = true
            } else {
                DWGlobalOptions.sharedInstance().walletNeedsBackup = false
            }

            reload()
            return .switched
        }
    }

    // MARK: - Rename

    /// Write `name` to `PersistentWallet.name` for `walletId` (empty string
    /// clears it to nil). Persists via the host's `modelContainer` mainContext.
    func rename(walletId: Data, to name: String) {
        guard let context = SwiftDashSDKHost.shared.modelContainer?.mainContext,
              let persisted = Self.fetchPersistentWallet(walletId: walletId, in: context) else {
            Self.logger.error("rename: no PersistentWallet row for target")
            errorMessage = NSLocalizedString("Could not rename this wallet.", comment: "Wallets")
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persisted.name = trimmed.isEmpty ? nil : trimmed
        do {
            try context.save()
            reload()
        } catch {
            Self.logger.error("rename save failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Remove

    /// Whether removing `walletId` requires routing to the full reset flow —
    /// true only when it is the sole remaining wallet. The screen presents
    /// `DWResetWalletInfoViewController` in that case (preserving today's
    /// last-wallet reset semantics); otherwise it drives `removeWallet`.
    func removalRoutesToFullReset(walletId: Data) -> Bool {
        rows.count <= 1
    }

    /// Derive the walletId of `mnemonic` on the current network WITHOUT
    /// creating or persisting anything, and confirm it equals `expected`. Used
    /// by the remove sheet to verify the user typed the target wallet's own
    /// recovery phrase before deleting this device's copy of it. Returns false
    /// on an invalid mnemonic, an unsupported network, or a mismatch.
    func recoveryPhraseMatches(_ mnemonic: String, walletId expected: Data) -> Bool {
        let trimmed = Self.normalize(mnemonic)
        guard Mnemonic.validate(trimmed) else { return false }
        guard let network = WalletEnvironment.network else { return false }
        do {
            // `Wallet(mnemonic:network:)` derives keys locally in the key-wallet
            // FFI and persists nothing (same read-only surface `SwiftDashSDKHost
            // .derivationWallet` uses); its `id` is the deterministic walletId.
            let derivedId = try Wallet(mnemonic: trimmed, network: network).id
            return derivedId == expected
        } catch {
            Self.logger.error("walletId derivation from mnemonic failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Remove `walletId` from this device (this device's copy only — funds stay
    /// recoverable with the phrase). Precondition (enforced by the screen): the
    /// recovery phrase was verified, and this is NOT the last wallet.
    ///
    /// If `walletId` is the active wallet, auto-switch to any other wallet
    /// first (await the rebind) so the runtime never ends up bound to a
    /// deleted wallet, then delete. Deletion reuses the wiper's promoted
    /// per-wallet primitive (`SwiftDashSDKWalletWiper.deleteWalletFromSDK`) and
    /// clears the per-network registry entry if it still names this wallet.
    func removeWallet(walletId: Data) async {
        guard !addInProgress, !switchInProgress, !removeInProgress else { return }
        removeInProgress = true
        defer { removeInProgress = false }

        if walletId == activeWalletId() {
            guard let other = rows.first(where: { $0.walletId != walletId })?.walletId else {
                // No other wallet — the screen routes the last wallet to the
                // full reset flow instead of calling this. Bail defensively.
                Self.logger.error("removeWallet: refusing to remove the only wallet")
                errorMessage = NSLocalizedString("Cannot remove the last wallet here.", comment: "Wallets")
                return
            }
            switchInProgress = true
            do {
                try await SwiftDashSDKWalletRuntime.shared.switchWallet(to: other)
            } catch {
                switchInProgress = false
                Self.logger.error("pre-remove auto-switch failed: \(String(describing: error), privacy: .public)")
                errorMessage = error.localizedDescription
                return
            }
            switchInProgress = false
        }

        do {
            try SwiftDashSDKWalletWiper.deleteWalletFromSDK(walletId)
        } catch {
            Self.logger.error("removeWallet failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
            reload()
            return
        }

        // Keep the registry honest: if the removed wallet is still recorded as
        // active for either registry network, drop it so a stale id can't be
        // resolved. The removed wallet is gone from `wallets` now.
        for kind in [WalletEnvironment.NetworkKind.mainnet, .testnet] {
            if WalletEnvironment.activeWalletId(for: kind) == walletId {
                WalletEnvironment.setActiveWalletId(nil, for: kind)
            }
        }

        reload()
    }

    // MARK: - Helpers

    private func activeWalletId() -> Data? {
        WalletEnvironment.activeWalletId(for: WalletEnvironment.isTestnet ? .testnet : .mainnet)
    }

    /// Collapse a user-entered recovery phrase to canonical form: trim, then
    /// join words on single spaces (tolerates newlines / extra spacing from
    /// paste). Shared by import and the remove-sheet verification.
    static func normalize(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func fetchPersistentWallet(walletId: Data, in context: ModelContext) -> PersistentWallet? {
        var descriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The wallet's DPNS username via its pinned identity row, or nil.
    /// Reads `PersistentIdentity` directly (target-neutral SDK model), so it
    /// compiles in both the dashwallet and dashpay targets without a DASHPAY
    /// gate. Mirrors `DWCurrentUserIdentityInfo`'s wallet→identities lookup.
    private static func username(for wallet: PersistentWallet) -> String? {
        wallet.identities
            .first(where: { $0.identityIndex == 0 })?
            .dpnsName?
            .nonEmpty
    }

    private static func fallbackName(for walletId: Data) -> String {
        let prefix = walletId.prefix(4).map { String(format: "%02x", $0) }.joined()
        return String(
            format: NSLocalizedString("Wallet %@…", comment: "Wallets — placeholder name with short id"),
            prefix)
    }
}

private extension String {
    /// Self when non-empty, else nil.
    var nonEmpty: String? { isEmpty ? nil : self }
}
