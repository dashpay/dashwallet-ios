//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

import Firebase
import Foundation
import SSZipArchive

private let fileName = "explore"

private let timestampKey = "Data-Timestamp"
private let checksumKey = "Data-Checksum"

// TODO: Move it to plist and note in release process
let bundleExploreDatabaseSyncTime: TimeInterval = 1689686772332/1000

// MARK: - ExploreDatabaseSyncManager

public class ExploreDatabaseSyncManager {

    enum State {
        case inititialing
        case fetchingInfo
        case syncing
        case synced(Date)
        case error(Date, Error?)
    }

    static let databaseHasBeenUpdatedNotification = NSNotification.Name(rawValue: "databaseHasBeenUpdatedNotification")
    /// Posted right before `explore.db` is replaced on disk, so open connections can let go of the
    /// file first. Overwriting it underneath a live SQLite connection corrupts the database.
    static let databaseWillBeUpdatedNotification = NSNotification.Name(rawValue: "databaseWillBeUpdatedNotification")

    private let storage = Storage.storage()

    /// The archive for `network`. Never cached: the network can change inside a session, and a
    /// stale reference would download the previous network's archive while the bookkeeping below
    /// stamps it with the current network — leaving the wrong merchants installed and the marker
    /// claiming otherwise, so the mismatch check never fires again.
    ///
    /// Resolved once per sync attempt and then carried through metadata *and* download: resolving
    /// it twice would let a switch land between the two, pairing one network's size/checksum with
    /// the other network's bytes.
    private func storageReference(for network: String) -> StorageReference {
        let path = network == mainnetName
            ? "gs://dash-wallet-firebase.appspot.com/explore/explore-v4.db"
            : "gs://dash-wallet-firebase.appspot.com/explore/explore-v4-testnet.db"
        return storage.reference(forURL: path)
    }

    private var timer: Timer!
    private var networkObserver: NSObjectProtocol?
    /// A network change that arrived while an attempt was in flight. That attempt is pinned to
    /// the previous network, so dropping the request would leave its merchants installed until
    /// the next launch — the exact failure this observer exists to prevent.
    private var pendingResync = false

    private var databaseVersion: Double = 0
    private var lastSync: Double = 0

    var syncState: State
    var lastServerUpdateDate: Date { Date(timeIntervalSince1970: exploreDatabaseLastVersion) }

    private let mainnetName = "mainnet"

    /// Name of the downloaded archive for `network` — the database itself always unzips to the
    /// single `explore.db`, so see `installedDatabaseNetwork` for the mainnet/testnet conflict.
    private func archiveFileName(for network: String) -> String {
        network == mainnetName ? "explore-mainnet" : "explore-testnet"
    }

    private func versionKey(for network: String) -> String {
        network == mainnetName ? "kExploreDatabaseLastVersion_Mainnet" : "kExploreDatabaseLastVersion_Testnet"
    }

    private func syncTimestampKey(for network: String) -> String {
        network == mainnetName
            ? "kExploreDatabaseLastSyncTimestampKey_Mainnet"
            : "kExploreDatabaseLastSyncTimestampKey_Testnet"
    }

    private func installedVersion(for network: String) -> TimeInterval {
        let value = UserDefaults.standard.double(forKey: versionKey(for: network))
        return value == 0 ? bundleExploreDatabaseSyncTime : value
    }

    // Network the sync bookkeeping expects, from the SDK (DWEnvironment is frozen post-M6).
    private var currentNetworkName: String {
        WalletEnvironment.isMainnet ? mainnetName : "testnet"
    }

    // Network whose data currently sits in the shared explore.db (see comment on
    // networkSpecificFileName); lets a chain switch force a re-download.
    private var installedDatabaseNetwork: String? {
        get { UserDefaults.standard.string(forKey: kExploreDatabaseInstalledNetworkKey) }
        set { UserDefaults.standard.setValue(newValue, forKey: kExploreDatabaseInstalledNetworkKey) }
    }

    init() {
        syncState = .inititialing
    }

    public func start() {
        // Both networks share one `explore.db`, so a chain switch leaves the other network's
        // merchants on screen. Without this the mismatch is only noticed at the next launch (or
        // 24 h later), which is how a testnet wallet ended up browsing the mainnet catalogue.
        // Registered before the first sync so a switch during startup is queued, not missed.
        networkObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.DWCurrentNetworkDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncIfNeeded()
        }

        syncIfNeeded()

        // Try to sync every 24h
        timer = Timer.scheduledTimer(withTimeInterval: 60*60*24, repeats: true) { [weak self] _ in
            self?.syncIfNeeded()
        }
    }

    /// End an attempt: publish its outcome and run the sync that was requested while it was busy.
    private func settle(_ state: State) {
        syncState = state

        guard pendingResync else { return }
        pendingResync = false
        syncIfNeeded()
    }

    private func syncIfNeeded() {
        // An attempt already owns the file on disk and is pinned to the network it started on.
        // Queue the request rather than racing it — `settle` runs it once this one finishes.
        switch syncState {
        case .fetchingInfo, .syncing:
            pendingResync = true
            return
        default:
            break
        }

        // Pinned for the whole attempt: metadata, bytes and bookkeeping must all describe the
        // same network even if the user switches chains halfway through.
        let network = currentNetworkName
        let reference = storageReference(for: network)

        syncState = .fetchingInfo

        reference.getMetadata { [weak self] metadata, _ in
            guard let wSelf = self else { return }

            guard let metadata else {
                wSelf.settle(.error(Date(), nil))
                return
            }

            guard let timestamp = metadata.customMetadata?[timestampKey],
                  let timeIntervalMillesecond = TimeInterval(timestamp) else {
                wSelf.settle(.error(Date(), nil))
                return
            }

            let timeInterval = timeIntervalMillesecond/1000
            let installedVersion = wSelf.installedVersion(for: network)
            let localDatabaseExists = wSelf.hasLocalExploreDatabase()

            // If local DB is missing (e.g. removed due to schema mismatch), force download
            // regardless of saved version timestamp to avoid falling back to in-memory DB.
            if !localDatabaseExists {
                DWLogger.log("ExploreDash: local explore.db missing, forcing cloud database download")
                wSelf.downloadDatabase(metadata: metadata, from: reference, network: network)
                return
            }

            // The file on disk may belong to the other network (the chain was switched since it was
            // downloaded). Its version is tracked under that network's key, so the check below would
            // read as up to date and leave us serving the wrong network's merchants.
            if wSelf.installedDatabaseNetwork != network {
                DWLogger.log("ExploreDash: explore.db belongs to \(wSelf.installedDatabaseNetwork ?? "an unknown network"), current network is \(network) — forcing download")
                wSelf.downloadDatabase(metadata: metadata, from: reference, network: network)
                return
            }

            guard timeInterval > installedVersion else {
                wSelf.settle(.synced(Date()))
                return
            }

            wSelf.downloadDatabase(metadata: metadata, from: reference, network: network)
        }
    }

    deinit {
        timer.invalidate()
        timer = nil

        if let networkObserver {
            NotificationCenter.default.removeObserver(networkObserver)
        }
    }

    static let share = ExploreDatabaseSyncManager()
}

extension ExploreDatabaseSyncManager {
    private func downloadDatabase(metadata: StorageMetadata, from reference: StorageReference, network: String) {
        guard let timestamp = metadata.customMetadata?[timestampKey],
              let checksum = metadata.customMetadata?[checksumKey],
              let timeIntervalMillesecond = TimeInterval(timestamp) else {
            settle(.error(Date(), nil))
            return
        }

        syncState = .syncing
        let urlToSave = getDocumentsDirectory().appendingPathComponent("\(archiveFileName(for: network))-\(timestamp).zip")

        reference.getData(maxSize: metadata.size) { [weak self] data, error in
            let date = Date()
            let now = date.timeIntervalSince1970

            if let e = error {
                self?.settle(.error(date, e))
            } else {
                try? data?.write(to: urlToSave)
                
                Task {
                    do {
                        // The archive unzips straight over the live `explore.db`. Let the open
                        // connection go first, and drop the -wal/-shm sidecars: they describe the
                        // *old* file, and SQLite replaying that WAL against the new one is what
                        // produces "database disk image is malformed".
                        await MainActor.run {
                            NotificationCenter.default.post(name: ExploreDatabaseSyncManager.databaseWillBeUpdatedNotification, object: nil)
                        }
                        self?.removeDatabaseSidecars()

                        try await self?.unzipFile(at: urlToSave.path, password: checksum)
                        // Stamped with the network this attempt downloaded, never the one the
                        // user may have switched to meanwhile — otherwise the marker certifies
                        // the wrong archive and the mismatch check agrees with itself forever.
                        if let wSelf = self {
                            UserDefaults.standard.setValue(now, forKey: wSelf.syncTimestampKey(for: network))
                            UserDefaults.standard.setValue(timeIntervalMillesecond / 1000,
                                                           forKey: wSelf.versionKey(for: network))
                            wSelf.installedDatabaseNetwork = network
                        }
                        await MainActor.run { [weak self] in self?.settle(.synced(date)) }

                        NotificationCenter.default.post(name: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification, object: nil)
                        try? FileManager.default.removeItem(at: URL(fileURLWithPath: urlToSave.path))
                    } catch {
                        DWLogger.log("ExploreDash: failed to open DB archive: \(String(describing: error))")
                        await MainActor.run { [weak self] in self?.settle(.error(Date(), error)) }
                    }
                }
            }
        }
    }

    private func unzipFile(at path: String, password: String) async throws {
        let urlToUnzip = self.getDocumentsDirectory()
        
        return try await withCheckedThrowingContinuation { continuation in
            SSZipArchive.unzipFile(atPath: path, toDestination: urlToUnzip.path, preserveAttributes: true, overwrite: true,
                                    nestedZipLevel: 0, password: password, error: nil, delegate: nil,
                                    progressHandler: nil) { path, success, error in
                if success {
                    continuation.resume()
                } else {
                    let errorToThrow = error ?? NSError(domain: "ExploreDatabaseSyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to unzip archive"])
                    continuation.resume(throwing: errorToThrow)
                }
            }
        }
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    private func hasLocalExploreDatabase() -> Bool {
        let localDbPath = getDocumentsDirectory().appendingPathComponent(kExploreDashDatabaseName).path
        return FileManager.default.fileExists(atPath: localDbPath)
    }

    /// Deletes the write-ahead log and shared-memory files left behind by the database we are about
    /// to replace. They are only valid for the file they were written against.
    private func removeDatabaseSidecars() {
        let dbPath = getDocumentsDirectory().appendingPathComponent(kExploreDashDatabaseName).path

        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbPath + suffix)
        }
    }
}

private let kExploreDatabaseLastSyncTimestampKey = "kExploreDatabaseLastSyncTimestampKey"
private let kExploreDatabaseLastVersion = "kExploreDatabaseLastVersion"
private let kExploreDatabaseInstalledNetworkKey = "kExploreDatabaseInstalledNetwork"

extension ExploreDatabaseSyncManager {
    // Network-specific UserDefaults keys
    private var syncTimestampKey: String {
        let isMainnet = WalletEnvironment.isMainnet
        return isMainnet ? "kExploreDatabaseLastSyncTimestampKey_Mainnet" : "kExploreDatabaseLastSyncTimestampKey_Testnet"
    }

    private var versionKey: String {
        let isMainnet = WalletEnvironment.isMainnet
        return isMainnet ? "kExploreDatabaseLastVersion_Mainnet" : "kExploreDatabaseLastVersion_Testnet"
    }

    var exploreDatabaseLastSyncTimestamp: TimeInterval {
        set {
            UserDefaults.standard.setValue(newValue, forKey: syncTimestampKey)
        }
        get {
            let value = UserDefaults.standard.double(forKey: syncTimestampKey)
            return value == 0 ? bundleExploreDatabaseSyncTime : value
        }
    }

    var exploreDatabaseLastVersion: TimeInterval {
        set {
            UserDefaults.standard.setValue(newValue, forKey: versionKey)
        }
        get {
            let value = UserDefaults.standard.double(forKey: versionKey)
            return value == 0 ? bundleExploreDatabaseSyncTime : value
        }
    }
}
