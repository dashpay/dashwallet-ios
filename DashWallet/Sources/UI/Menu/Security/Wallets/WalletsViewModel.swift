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
    /// True while a switch (or an auto-switch before removing the active
    /// wallet) is in flight — guards reentry and disables this screen's
    /// controls. The blocking progress UI itself is the app-wide lifecycle
    /// overlay (`WalletLifecycleOverlayPresenter`), not a screen-local view.
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
                let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lhs.walletId.lexicographicallyPrecedes(rhs.walletId)
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

    // MARK: - Switch

    /// Switch the active wallet to `walletId` behind the app-wide lifecycle
    /// overlay. On success `activeWalletDidChangeNotification` fires and
    /// `reload()` refreshes the list; on failure the overlay's blocking card
    /// owns recovery (Retry / Switch Back) — this screen may already be gone
    /// by then (the DASHPAY tab rebuild on the wallet change destroys its
    /// nav stack), so no local error alert is raised.
    func switchWallet(to walletId: Data) {
        guard !switchInProgress, !removeInProgress else { return }
        switchInProgress = true
        Task {
            defer { switchInProgress = false }
            do {
                try await Self.gatedSwitchWallet(
                    targetId: walletId,
                    targetName: Self.displayName(for: walletId))
                // reload() also runs from the change notification, but call it
                // directly so the list is fresh even if delivery order lags.
                reload()
            } catch {
                Self.logger.error("switchWallet failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Overlay-gated wallet switch shared by every interactive entry point:
    /// the row switch above, the post-add switch, the pre-remove auto-switch,
    /// and the overlay failure card's Retry / Switch Back
    /// (`WalletLifecycleOverlayViewModel`). Owns the transition-state
    /// bookkeeping around `SwiftDashSDKWalletRuntime.switchWallet`:
    /// tryBegin → run → finish (or stay busy) / fail.
    ///
    /// `thenFinish: false` keeps the operation busy on success so a composite
    /// flow (removing the active wallet) can `advance(to: .removingWallet)`
    /// without the overlay flickering through idle — that caller then owns
    /// the eventual `finish()`/`fail(_:)`.
    ///
    /// Throws `SwitchError.switchInProgress` when another interactive
    /// operation holds the admission gate (no failure phase is set then);
    /// rethrows the runtime's error after setting `.failedWalletSwitch`,
    /// whose card carries `previousId` — captured HERE, before the runtime
    /// repoints the active-wallet registry.
    static func gatedSwitchWallet(
        targetId: Data,
        targetName: String?,
        thenFinish: Bool = true
    ) async throws {
        let state = WalletLifecycleTransitionState.shared
        // A Retry begins from `.failedWalletSwitch`, where the host may hold
        // no wallet at all (runtime torn down) or an arbitrary fallback — so
        // carry the failure phase's previousId forward instead of re-sampling
        // the host: it is the wallet that was really active when this switch
        // saga began, and re-sampling would silently drop Switch Back.
        let previousId: Data?
        if case let .failedWalletSwitch(_, _, savedPrevious, _) = state.phase {
            previousId = savedPrevious
        } else {
            previousId = SwiftDashSDKHost.shared.wallet?.walletId
        }
        WalletLifecycleOverlayPresenter.shared.ensureActive()
        guard state.tryBegin(.switchingWallet(targetName: targetName)) else {
            throw SwiftDashSDKWalletRuntime.SwitchError.switchInProgress
        }
        let opID = String(UUID().uuidString.prefix(8))
        let started = CFAbsoluteTimeGetCurrent()
        DWLogger.log("🔁 WALLETOP [\(opID)] switch begin target=\(shortId(targetId)) prev=\(previousId.map(shortId) ?? "none")")
        do {
            try await SwiftDashSDKWalletRuntime.shared.switchWallet(to: targetId)
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            state.fail(.failedWalletSwitch(
                targetId: targetId,
                targetName: targetName,
                previousId: previousId,
                message: error.localizedDescription))
            DWLogger.log("🔁 WALLETOP [\(opID)] switch FAILED after \(ms)ms: \(error.localizedDescription)")
            throw error
        }
        if thenFinish {
            state.finish()
        }
        let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        DWLogger.log("🔁 WALLETOP [\(opID)] switch ready in \(ms)ms\(thenFinish ? "" : " (operation continues)")")
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

    /// Generate a fresh BIP39 mnemonic of `length` words (12 or 24) via the SDK
    /// for the "Create New Wallet" flow. Returns nil (and surfaces an error) on
    /// FFI failure. Nothing is persisted here — creation happens in `addWallet`
    /// after the user confirms they wrote the phrase down.
    func generateMnemonic(length: RecoveryPhraseLength) -> String? {
        do {
            return try Mnemonic.generate(wordCount: length.wordCount)
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

    /// Add a wallet from `mnemonic`, persist its optional display `name`, and
    /// switch to it. `isImported` distinguishes the two entry paths and sets
    /// the new wallet's `walletNeedsBackup` flag: a created wallet still needs
    /// a backup (its phrase was only shown, not verified — matches onboarding);
    /// an imported wallet does not (the user already holds the phrase — matches
    /// the recover flow).
    ///
    /// Flow: `SwiftDashSDKHost.addWallet` (additive — no rebind) → on `.added`,
    /// `switchWallet(to:)` the new wallet (awaited, progress overlay) → set the
    /// per-wallet backup flag for the now-active new wallet → refresh. On
    /// `.alreadyExists`, an entered name is applied to the existing current-
    /// network row and `.alreadyOnDevice` lets the sheet offer switching.
    ///
    /// Returns the outcome; returns nil after surfacing an error (the sheet
    /// stays open on failure — never claims a success that didn't happen).
    func addWallet(mnemonic: String, isImported: Bool, name: String? = nil) async -> AddOutcome? {
        guard !addInProgress, !switchInProgress, !removeInProgress else { return nil }
        let normalized = Self.normalize(mnemonic)
        let enteredName = Self.normalizedWalletName(name)
        let creationName = enteredName ?? SwiftDashSDKHost.defaultWalletName

        addInProgress = true
        defer { addInProgress = false }

        // Blocking overlay from the FIRST moment: without this phase the app
        // looked frozen until the post-add switch finally raised the window.
        // No paint-a-frame sleep needed anymore: on EVERY add path the first
        // provisioning work after the cheap duplicate guard is an await into
        // off-main work (the async create, or the mirror leg's off-main SDK
        // build), so the overlay window commits during that suspension —
        // confirmed by the stall monitor showing no >=250ms gap between the
        // add beginning and its first suspension.
        WalletLifecycleOverlayPresenter.shared.ensureActive()
        let state = WalletLifecycleTransitionState.shared
        guard state.tryBegin(.addingWallet(isImport: isImported)) else {
            errorMessage = SwiftDashSDKWalletRuntime.SwitchError.switchInProgress.localizedDescription
            return nil
        }

        let opID = String(UUID().uuidString.prefix(8))
        let started = CFAbsoluteTimeGetCurrent()
        DWLogger.log("🔁 WALLETOP [\(opID)] add begin import=\(isImported)")

        let result: SwiftDashSDKHost.AddWalletResult
        do {
            // Through the runtime's serial lifecycle chain: a queued
            // refresh/fullReset can no longer interleave with the
            // multi-network provisioning. The post-add switch below stays
            // OUTSIDE the chain (its own sequential op — nesting it here
            // would self-await-deadlock the queue).
            result = try await SwiftDashSDKWalletRuntime.shared.performAddWallet(
                mnemonic: normalized,
                isImported: isImported,
                name: creationName)
        } catch {
            // The ONE exit where a forgotten finish() would strand the
            // blocking overlay with no owner.
            state.finish()
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            DWLogger.log("🔁 WALLETOP [\(opID)] add FAILED after \(ms)ms: \(error.localizedDescription)")
            Self.logger.error("addWallet failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
            return nil
        }
        let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        DWLogger.log("🔁 WALLETOP [\(opID)] add done in \(ms)ms")

        switch result {
        case .alreadyExists(let walletId):
            state.finish()
            // The phrase may already exist on the current network while the
            // host has just repaired its missing sibling-network copy. Honor
            // the name the user entered instead of silently discarding it.
            if enteredName != nil,
               !persistWalletName(enteredName, walletId: walletId) {
                return nil
            }
            return .alreadyOnDevice(walletId: walletId)
        case .added(let walletId):
            switchInProgress = true
            do {
                // Admitted from `.addingWallet` by the composite rule — the
                // window advances Creating → Switching without dropping
                // through idle; from here the helper owns finish/fail.
                try await Self.gatedSwitchWallet(
                    targetId: walletId,
                    targetName: Self.displayName(for: walletId))
            } catch {
                switchInProgress = false
                // Defense in depth: a rejected admission (throws BEFORE any
                // fail-phase is set) must not strand `.addingWallet`; a real
                // switch failure has already moved to `.failedWalletSwitch`,
                // which this deliberately leaves alone.
                if case .addingWallet = state.phase {
                    state.finish()
                }
                Self.logger.error("post-add switch failed: \(String(describing: error), privacy: .public)")
                // The wallet was added but the switch failed; leave it on
                // device — the overlay's blocking card owns recovery (Retry /
                // Switch Back). The list still gains the new wallet, and the
                // sheet stays open (never claims a success that didn't happen).
                reload()
                return nil
            }
            switchInProgress = false

            // The new wallet is now the active wallet, so this per-wallet flag
            // targets it (DWGlobalOptions scopes by the active walletId).
            DWGlobalOptions.sharedInstance().walletNeedsBackup = !isImported

            reload()
            return .switched
        }
    }

    // MARK: - Rename

    /// Write `name` to `PersistentWallet.name` for `walletId` (empty input
    /// restores the default name). Persists through the host's model context.
    func rename(walletId: Data, to name: String) {
        let effectiveName = Self.normalizedWalletName(name)
            ?? SwiftDashSDKHost.defaultWalletName
        _ = persistWalletName(effectiveName, walletId: walletId)
    }

    @discardableResult
    private func persistWalletName(_ name: String?, walletId: Data) -> Bool {
        guard let context = SwiftDashSDKHost.shared.modelContainer?.mainContext,
              let persisted = Self.fetchPersistentWallet(walletId: walletId, in: context) else {
            Self.logger.error("rename: no PersistentWallet row for target")
            errorMessage = NSLocalizedString("Could not rename this wallet.", comment: "Wallets")
            return false
        }
        persisted.name = Self.normalizedWalletName(name)
        do {
            try context.save()
            reload()
            return true
        } catch {
            Self.logger.error("rename save failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Remove

    /// Whether removing `walletId` may route to the GLOBAL reset flow. The
    /// reset deletes every SDK mnemonic, including wallets that are not
    /// loaded/rendered on the current network, so `rows.count` is not a safe
    /// last-wallet test. Prove from Keychain ground truth that every stored
    /// wallet id resolves to the same recovery phrase as the target. Any
    /// enumeration/read failure returns false (fail closed).
    func removalRoutesToFullReset(walletId: Data) -> Bool {
        do {
            let entries = try SwiftDashSDKHost.strictlyPersistedMnemonics()
            guard let target = entries.first(where: { $0.walletId == walletId }) else { return false }
            return SwiftDashSDKHost.allMnemonicsMatch(phrase: target.mnemonic, in: entries)
        } catch {
            Self.logger.error("last-wallet proof failed; refusing global reset: \(String(describing: error), privacy: .public)")
            return false
        }
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

    /// Remove the logical wallet represented by `walletId` from this device on
    /// both supported networks. Precondition (enforced by the screen): the
    /// recovery phrase was verified, and another wallet exists on this network
    /// to switch to — also re-checked here, independent of the registry's
    /// active id, so a stale registry can never let the only rendered wallet
    /// be hard-deleted outside the reset flow.
    ///
    /// If `walletId` is the active wallet, auto-switch to any other wallet
    /// first (await the rebind) so the runtime never ends up bound to a
    /// deleted wallet, then delete both deterministic network ids plus any
    /// matching legacy DashSync mnemonic account.
    func removeWallet(walletId: Data) async {
        guard !addInProgress, !switchInProgress, !removeInProgress else { return }
        removeInProgress = true
        defer { removeInProgress = false }

        guard let other = rows.first(where: { $0.walletId != walletId })?.walletId else {
            // No other wallet on this network — per-wallet removal must leave
            // a wallet to switch to. The screen refuses this case up front
            // (`beginRemove`); this bail is defense in depth.
            Self.logger.error("removeWallet: refusing to remove the only wallet on this network")
            errorMessage = NSLocalizedString("Cannot remove the last wallet here.", comment: "Wallets")
            return
        }

        let mnemonic: String
        do {
            mnemonic = try SwiftDashSDKHost.strictlyPersistedMnemonic(for: walletId)
        } catch {
            Self.logger.error("removeWallet mnemonic read failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
            return
        }

        let state = WalletLifecycleTransitionState.shared
        if walletId == activeWalletId() {
            switchInProgress = true
            do {
                // `thenFinish: false`: the overlay advances straight from
                // "Switching wallet…" to "Removing wallet…" below without
                // dropping through idle.
                try await Self.gatedSwitchWallet(
                    targetId: other,
                    targetName: Self.displayName(for: other),
                    thenFinish: false)
            } catch {
                switchInProgress = false
                Self.logger.error("pre-remove auto-switch failed: \(String(describing: error), privacy: .public)")
                // The overlay's blocking card owns recovery, and its Retry
                // resumes ONLY the switch — the removal never started and is
                // re-initiated by the user from the Wallets screen.
                return
            }
            switchInProgress = false
            state.advance(to: .removingWallet)
        } else {
            WalletLifecycleOverlayPresenter.shared.ensureActive()
            guard state.tryBegin(.removingWallet) else {
                errorMessage = SwiftDashSDKWalletRuntime.SwitchError.switchInProgress.localizedDescription
                return
            }
        }

        let opID = String(UUID().uuidString.prefix(8))
        let started = CFAbsoluteTimeGetCurrent()
        DWLogger.log("🔁 WALLETOP [\(opID)] remove begin wallet=\(Self.shortId(walletId))")
        do {
            try await SwiftDashSDKWalletWiper.deleteLogicalWallet(
                mnemonic: mnemonic)
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            Self.logger.error("removeWallet failed: \(String(describing: error), privacy: .public)")
            // Dismissable overlay card, not a local alert: after an
            // active-wallet removal the tab rebuild has already destroyed
            // this screen, so only the overlay window can still surface the
            // failure. The wiper leaves wallet state retryable by design.
            state.fail(.failedWalletRemoval(message: error.localizedDescription))
            DWLogger.log("🔁 WALLETOP [\(opID)] remove FAILED after \(ms)ms: \(error.localizedDescription)")
            reload()
            return
        }
        state.finish()
        let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        DWLogger.log("🔁 WALLETOP [\(opID)] remove done in \(ms)ms")

        reload()
    }

    // MARK: - Helpers

    private func activeWalletId() -> Data? {
        SwiftDashSDKHost.shared.wallet?.walletId
            ?? WalletEnvironment.activeWalletId(
                for: WalletEnvironment.isTestnet ? .testnet : .mainnet)
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

    /// Trim an optional user-entered wallet name. Blank input becomes nil so
    /// callers can distinguish "use the default name" from an explicit name.
    nonisolated static func normalizedWalletName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
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

    /// Best available name for a wallet id in the current network's store.
    /// Recovery-phrase inventory also uses this for Keychain entries that are
    /// not loaded into the current manager; those safely fall back to a short
    /// id rather than being omitted from the chooser.
    static func displayName(for walletId: Data) -> String {
        let context = SwiftDashSDKHost.shared.modelContainer?.mainContext
        let persisted = context.flatMap { fetchPersistentWallet(walletId: walletId, in: $0) }
        let name = persisted?.name?.nonEmpty
        return name ?? fallbackName(for: walletId)
    }

    nonisolated static func fallbackName(for walletId: Data) -> String {
        String(
            format: NSLocalizedString("Wallet %@…", comment: "Wallets — placeholder name with short id"),
            shortId(walletId))
    }

    /// First-4-bytes hex label of a walletId — display fallbacks and log
    /// lines only, never a key.
    nonisolated static func shortId(_ walletId: Data) -> String {
        walletId.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    /// Self when non-empty, else nil.
    var nonEmpty: String? { isEmpty ? nil : self }
}
