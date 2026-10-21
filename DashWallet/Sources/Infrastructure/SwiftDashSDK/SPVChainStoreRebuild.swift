//
//  SPVChainStoreRebuild.swift
//  DashWallet
//

import Foundation

/// Durable "rebuild this network's SPV chain store before the next SPV start"
/// marker, armed whenever a wallet is imported from a recovery phrase or
/// recreated from the phrase kept in the Keychain (there on a best-effort
/// basis: a recovery whose marker cannot be written still opens the wallet).
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
/// dropped from the marker once that start succeeds.
///
/// One empty file per wallet, `<directory>/<scope>/<wallet id hex>`, flushed
/// to stable storage before the import writes its first row: the wallet's
/// rows are a synchronous database commit, and a marker that reached disk
/// after them could be lost by an interruption that keeps the rows. A start
/// on the other network, or one in a later launch, still rebuilds.
enum SPVChainStoreRebuild {

    /// Serializes the multi-step file operations: imports and the Keychain
    /// recovery arm on the main actor while the wallet wipe clears from its
    /// own queue.
    private static let lock = NSLock()

    /// The marker directory under the user's Documents directory.
    static func defaultDirectory() throws -> URL {
        try WalletLocalStoreRoots.inDocuments().chainStoreRebuilds
    }

    private static func name(for walletId: Data) -> String {
        walletId.map { String(format: "%02x", $0) }.joined()
    }

    private static func walletId(named name: String) -> Data? {
        guard !name.isEmpty, name.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = name.startIndex
        while index < name.endIndex {
            let next = name.index(index, offsetBy: 2)
            guard let byte = UInt8(name[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
    }

    /// Record that `walletId` was imported or recreated on `scope`, durably:
    /// it returns only once the marker and every directory entry naming it,
    /// up to the directory that holds `directory`, are flushed to stable
    /// storage — also when the marker was there already, which an earlier
    /// arm may have written without managing to flush. Throws when they
    /// could not be; a marker written but not flushed is left in place — a
    /// caller that goes on to create the wallet anyway is better served by
    /// it than by none, and one for a wallet that is never created rebuilds
    /// nothing. Returns false when the wallet was pending already.
    @discardableResult
    static func arm(
        walletId: Data,
        scope: String,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        let root = try directory ?? defaultDirectory()
        let scoped = root.appendingPathComponent(scope, isDirectory: true)
        let marker = scoped.appendingPathComponent(name(for: walletId), isDirectory: false)
        let wasPending = fileManager.fileExists(atPath: marker.path)
        try fileManager.createDirectory(at: scoped, withIntermediateDirectories: true)
        if wasPending {
            try DurableMarkerFile.flushToStableStorage(marker)
        } else {
            try DurableMarkerFile.write(at: marker)
        }
        try DurableMarkerFile.flushDirectories(from: scoped, through: root.deletingLastPathComponent())
        return !wasPending
    }

    /// The wallet ids pending on `scope`, in a stable order, or `nil` when no
    /// rebuild is pending.
    static func pendingWalletIds(
        scope: String,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [Data]? {
        guard let root = directory ?? (try? defaultDirectory()),
              let names = try? fileManager.contentsOfDirectory(
                atPath: root.appendingPathComponent(scope, isDirectory: true).path) else {
            return nil
        }
        let pending = names.sorted().compactMap(walletId(named:))
        return pending.isEmpty ? nil : pending
    }

    /// Drop `walletIds` from the wallets pending on `scope`: their rebuild
    /// ran, the wallet was removed, or its import failed before anything was
    /// created. Ids armed meanwhile stay pending. A marker that could not be
    /// removed stays pending, rebuilds again on the next start, and is
    /// logged.
    static func finish(
        walletIds: [Data],
        scope: String,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        lock.lock(); defer { lock.unlock() }
        guard let root = directory ?? (try? defaultDirectory()) else { return }
        let scoped = root.appendingPathComponent(scope, isDirectory: true)
        var removedAny = false
        for walletId in walletIds {
            do {
                try fileManager.removeItem(at: scoped.appendingPathComponent(name(for: walletId), isDirectory: false))
                removedAny = true
            } catch where isMissingFile(error) {
                continue
            } catch {
                DWLogger.log(
                    "SPVCOORD chain store rebuild marker not removed scope=\(scope) codes=\(WalletPreparationFailure(error: error).codes.joined(separator: ","))")
            }
        }
        // Best effort: a removal an interruption undoes only rebuilds once more.
        if removedAny {
            try? DurableMarkerFile.flushToStableStorage(scoped)
        }
    }

    /// Run `start` and, once it returns, drop `walletIds` from the wallets
    /// pending on `scope`. A start that throws leaves them pending, so the
    /// next start applies the rebuild again.
    static func finish(
        walletIds: [Data],
        scope: String,
        directory: URL? = nil,
        afterStarting start: () throws -> Void
    ) rethrows {
        try start()
        guard !walletIds.isEmpty else { return }
        finish(walletIds: walletIds, scope: scope, directory: directory)
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

    /// Clear every pending rebuild: the wallets they name are gone (wallet
    /// wipe or local-store reset).
    static func clearAll(directory: URL? = nil, fileManager: FileManager = .default) {
        lock.lock(); defer { lock.unlock() }
        guard let root = directory ?? (try? defaultDirectory()) else { return }
        do {
            try fileManager.removeItem(at: root)
        } catch where isMissingFile(error) {
            return
        } catch {
            DWLogger.log(
                "SPVCOORD chain store rebuild markers not cleared codes=\(WalletPreparationFailure(error: error).codes.joined(separator: ","))")
        }
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
        directory: URL? = nil,
        isLoaded: (Data) -> Bool,
        rewind: (Data) -> Bool,
        clearStore: () async -> Bool
    ) async -> [Data] {
        guard let pending = pendingWalletIds(scope: scope, directory: directory) else { return [] }
        let rewound = pending.filter { isLoaded($0) && rewind($0) }
        guard !rewound.isEmpty else { return [] }
        guard await clearStore() else { return [] }
        return rewound
    }

    /// The persistence scopes whose SPV stop failed in this process. A client
    /// that did not stop cleanly can keep its storage worker writing into its
    /// network's chain store, so that scope's store is not cleared until a
    /// later launch; the other scopes' stores are unaffected. Nothing takes a
    /// scope out again: the worker lives as long as the process does.
    ///
    /// Both store clears ahead of an SPV start go through it: this rebuild
    /// and the birth-height resync (`SPVChainResyncMarker`).
    struct StoreClearGate {
        private var stopFailedScopes: Set<String> = []

        mutating func recordFailedStop(scope: String) {
            stopFailedScopes.insert(scope)
        }

        func allowsClearing(scope: String) -> Bool {
            !stopFailedScopes.contains(scope)
        }

        /// Run `clear` for `scope`'s store and return true, or return false
        /// without running it when that scope's stop failed.
        @MainActor
        func clear(scope: String, _ clear: () async throws -> Void) async rethrows -> Bool {
            guard allowsClearing(scope: scope) else { return false }
            try await clear()
            return true
        }
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
