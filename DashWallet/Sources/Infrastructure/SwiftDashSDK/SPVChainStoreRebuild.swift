//
//  SPVChainStoreRebuild.swift
//  DashWallet
//

import Foundation

/// Durable "rebuild this network's SPV chain store before the next SPV start"
/// marker, armed whenever a wallet is imported from a recovery phrase or
/// recreated from the phrase kept in the Keychain.
///
/// The chain store (`Documents/SPV/<scope>/`) is shared by every wallet on a
/// network and dash-spv anchors it once, at the birth height of the wallets
/// present on its first start; an existing store is never re-anchored. On an
/// install whose first wallet was freshly generated the store therefore starts
/// near the tip, and a wallet imported later — after a wallet reset or beside
/// the first one — was scanned only from that anchor: sync completed in
/// seconds with every older transaction missing.
///
/// The marker records those wallet ids per network scope. The SPV
/// coordinator applies it before `startSpv`: it rewinds the recorded
/// wallets' filter checkpoints to the import floor, in case the running scan
/// already walked them on the old store, and deletes the store, so the client
/// anchors at the lowest birth height now loaded. The applied wallets are
/// dropped from the marker once that start succeeds. Kept in UserDefaults, so a
/// start on the other network, or one in a later launch, still rebuilds.
///
/// Foundation-only so the wallet-preparation harness can compile it.
enum SPVChainStoreRebuild {

    /// Serializes the read-modify-write of a scope's pending list: imports
    /// and the Keychain recovery arm on the main actor while the wallet wipe
    /// clears from its own queue.
    private static let lock = NSLock()

    private static func key(scope: String) -> String {
        "spvChainStoreRebuild.v1.pending.\(scope)"
    }

    /// Record that `walletId` was imported or recreated on `scope`. Adds to the wallets
    /// already pending there; returns false when it was pending already.
    @discardableResult
    static func arm(walletId: Data, scope: String, defaults: UserDefaults = .standard) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var pending = pendingWalletIds(scope: scope, defaults: defaults) ?? []
        guard !pending.contains(walletId) else { return false }
        pending.append(walletId)
        defaults.set(pending, forKey: key(scope: scope))
        return true
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
        lock.lock(); defer { lock.unlock() }
        let remaining = (pendingWalletIds(scope: scope, defaults: defaults) ?? [])
            .filter { !walletIds.contains($0) }
        if remaining.isEmpty {
            defaults.removeObject(forKey: key(scope: scope))
        } else {
            defaults.set(remaining, forKey: key(scope: scope))
        }
    }

    /// Run `start` and, once it returns, drop `walletIds` from the wallets
    /// pending on `scope`. A start that throws leaves them pending, so the
    /// next start applies the rebuild again.
    static func finish(
        walletIds: [Data],
        scope: String,
        defaults: UserDefaults = .standard,
        afterStarting start: () throws -> Void
    ) rethrows {
        try start()
        guard !walletIds.isEmpty else { return }
        finish(walletIds: walletIds, scope: scope, defaults: defaults)
    }

    /// Lower each row's `checkpoint` to `floor`, never raising it, and
    /// `save`. When the save throws the rows are put back, so a later save
    /// on the same context cannot write a checkpoint this call reported as
    /// not lowered.
    static func lowerCheckpoints<Row: AnyObject>(
        of rows: [Row],
        to floor: UInt32,
        checkpoint: ReferenceWritableKeyPath<Row, UInt32>,
        save: () throws -> Void
    ) throws {
        var lowered: [(row: Row, from: UInt32)] = []
        for row in rows where row[keyPath: checkpoint] > floor {
            lowered.append((row, row[keyPath: checkpoint]))
            row[keyPath: checkpoint] = floor
        }
        do {
            try save()
        } catch {
            for (row, from) in lowered {
                row[keyPath: checkpoint] = from
            }
            throw error
        }
    }

    static func clear(scope: String, defaults: UserDefaults = .standard) {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key(scope: scope))
    }

    /// Apply `scope`'s pending rebuild ahead of an SPV start and return the
    /// wallet ids it was applied for; the caller drops those from the marker
    /// once the start succeeds. Nothing is consumed here, so a rebuild that
    /// stops at any step is tried again by the next start.
    ///
    /// Only a wallet this start loads can be rescanned. One that is not
    /// loaded stays pending and deletes nothing: the import may have armed it
    /// for a start that has not seen the wallet yet.
    ///
    /// `rewind` runs per wallet, before `clearStore`, and returns whether it
    /// succeeded. A wallet whose rewind failed stays
    /// pending without holding back the others; when none was rewound the
    /// store is left as it was. When the clear is refused instead, the
    /// rewound wallets are only rescanned on the old store.
    @MainActor
    static func apply(
        scope: String,
        defaults: UserDefaults = .standard,
        isLoaded: (Data) -> Bool,
        rewind: (Data) -> Bool,
        clearStore: () async -> Bool
    ) async -> [Data] {
        guard let pending = pendingWalletIds(scope: scope, defaults: defaults) else { return [] }
        let rewound = pending.filter { isLoaded($0) && rewind($0) }
        guard !rewound.isEmpty else { return [] }
        guard await clearStore() else { return [] }
        return rewound
    }

    /// Empty the SPV store at `store`: the directory is renamed into `trash`
    /// and only then deleted. The caller passes a `trash` on the store's
    /// volume, where the rename is atomic, so a failure never leaves the
    /// store half removed — it throws with the store untouched, or the store
    /// is gone. Deleting the moved copy and recreating the empty directory
    /// are best effort: `trash` holds nothing but moved stores, so a copy
    /// left behind is removed by the next clear (or purged by the system),
    /// and `startSpv` creates the data directory itself.
    static func emptyStore(at store: URL, movingInto trash: URL, fileManager: FileManager = FileManager()) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: trash.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            try? fileManager.removeItem(at: trash)
        }
        // Copies an earlier clear moved away but was interrupted deleting.
        // Entry by entry, so the directory another clear is moving into stays.
        for leftover in (try? fileManager.contentsOfDirectory(atPath: trash.path)) ?? [] {
            try? fileManager.removeItem(at: trash.appendingPathComponent(leftover))
        }
        if fileManager.fileExists(atPath: store.path) {
            try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
            let removed = trash.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.moveItem(at: store, to: removed)
            try? fileManager.removeItem(at: removed)
        }
        try? fileManager.createDirectory(at: store, withIntermediateDirectories: true)
    }
}
