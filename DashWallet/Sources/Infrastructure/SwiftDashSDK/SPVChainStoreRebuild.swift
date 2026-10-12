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
/// coordinator consumes it before `startSpv`: it deletes the store, so the
/// client anchors at the lowest birth height now loaded, and rewinds the
/// recorded wallets' filter checkpoints to the import floor, in case the
/// running scan already walked them on the old store. Durable, so an
/// interrupted import or a start on the other network still rebuilds.
///
/// Foundation-only so the wallet-preparation harness can compile it.
enum SPVChainStoreRebuild {

    private static func key(scope: String) -> String {
        "spvChainStoreRebuild.v1.pending.\(scope)"
    }

    /// Record that `walletId` was imported on `scope`. Adds to the wallets
    /// already pending there.
    static func arm(walletId: Data, scope: String, defaults: UserDefaults = .standard) {
        var pending = defaults.stringArray(forKey: key(scope: scope)) ?? []
        let hex = walletId.map { String(format: "%02x", $0) }.joined()
        if !pending.contains(hex) {
            pending.append(hex)
        }
        defaults.set(pending, forKey: key(scope: scope))
    }

    /// The wallet ids pending on `scope`, or `nil` when no rebuild is pending.
    static func pendingWalletIds(scope: String, defaults: UserDefaults = .standard) -> [Data]? {
        guard let pending = defaults.stringArray(forKey: key(scope: scope)), !pending.isEmpty else {
            return nil
        }
        return pending.compactMap(walletId(hex:))
    }

    static func clear(scope: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(scope: scope))
    }

    private static func walletId(hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
