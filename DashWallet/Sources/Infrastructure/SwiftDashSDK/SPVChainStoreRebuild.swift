//
//  SPVChainStoreRebuild.swift
//  DashWallet
//

import Foundation

/// Durable "rebuild this network's SPV chain store before the next SPV start"
/// marker, armed whenever a wallet is imported from a recovery phrase.
///
/// The chain store (`Documents/SPV/<scope>/`) is shared by every wallet on a
/// network and dash-spv anchors it once, at the birth height of the wallets
/// present on its first start; an existing store is never re-anchored. On an
/// install whose first wallet was freshly generated the store therefore starts
/// near the tip, and a wallet imported later — after a wallet reset or beside
/// the first one — was scanned only from that anchor: sync completed in
/// seconds with every older transaction missing.
///
/// The marker records the imported wallet ids per network scope. The SPV
/// coordinator consumes it before `startSpv`: it rewinds the recorded
/// wallets' filter checkpoints to the import floor, in case the running scan
/// already walked them on the old store, and deletes the store, so the client
/// anchors at the lowest birth height now loaded. Durable, so a start on the
/// other network, or one in a later launch, still rebuilds.
///
/// Foundation-only so the wallet-preparation harness can compile it.
enum SPVChainStoreRebuild {

    private static func key(scope: String) -> String {
        "spvChainStoreRebuild.v1.pending.\(scope)"
    }

    /// Record that `walletId` was imported on `scope`. Adds to the wallets
    /// already pending there.
    static func arm(walletId: Data, scope: String, defaults: UserDefaults = .standard) {
        var pending = pendingWalletIds(scope: scope, defaults: defaults) ?? []
        if !pending.contains(walletId) {
            pending.append(walletId)
        }
        defaults.set(pending, forKey: key(scope: scope))
    }

    /// The wallet ids pending on `scope`, or `nil` when no rebuild is pending.
    static func pendingWalletIds(scope: String, defaults: UserDefaults = .standard) -> [Data]? {
        guard let pending = defaults.array(forKey: key(scope: scope)) as? [Data], !pending.isEmpty else {
            return nil
        }
        return pending
    }

    /// Drop `walletIds` from the wallets pending on `scope`: their rebuild
    /// ran, their import failed, or the wallet was removed. Ids armed
    /// meanwhile stay pending.
    static func finish(walletIds: [Data], scope: String, defaults: UserDefaults = .standard) {
        let remaining = (pendingWalletIds(scope: scope, defaults: defaults) ?? [])
            .filter { !walletIds.contains($0) }
        if remaining.isEmpty {
            clear(scope: scope, defaults: defaults)
        } else {
            defaults.set(remaining, forKey: key(scope: scope))
        }
    }

    static func clear(scope: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(scope: scope))
    }
}
