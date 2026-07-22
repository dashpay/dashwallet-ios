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

    private let storage = Storage.storage()

    // Computed per access so a mainnet/testnet switch always targets the current network's archive.
    // Caching this in `init()` meant the singleton kept downloading the launch-network's database
    // after a chain switch, so the wrong network's merchants stayed on disk.
    private var storageRef: StorageReference {
        let databasePath = currentNetworkName == "mainnet"
            ? "gs://dash-wallet-firebase.appspot.com/explore/explore-v4.db"
            : "gs://dash-wallet-firebase.appspot.com/explore/explore-v4-testnet.db"
        return storage.reference(forURL: databasePath)
    }

    private var timer: Timer!

    private var databaseVersion: Double = 0
    private var lastSync: Double = 0

    var syncState: State
    var lastServerUpdateDate: Date { Date(timeIntervalSince1970: exploreDatabaseLastVersion) }

    // Network-specific name for the downloaded archive only — the database itself always unzips to
    // the single `explore.db`, so see `installedDatabaseNetwork` for the mainnet/testnet conflict.
    private var networkSpecificFileName: String {
        return currentNetworkName == "mainnet" ? "explore-mainnet" : "explore-testnet"
    }

    private var currentNetworkName: String {
        return DWEnvironment.sharedInstance().currentChain.isMainnet() ? "mainnet" : "testnet"
    }

    /// The network whose data currently sits in `explore.db`. Both networks share that one file
    /// while the sync bookkeeping (`versionKey`) is per-network, so after a chain switch the saved
    /// version reads as up to date while the file on disk still holds the other network's merchants.
    private var installedDatabaseNetwork: String? {
        get { UserDefaults.standard.string(forKey: kExploreDatabaseInstalledNetworkKey) }
        set { UserDefaults.standard.setValue(newValue, forKey: kExploreDatabaseInstalledNetworkKey) }
    }

    private var networkDidChangeObserver: NSObjectProtocol?

    init() {
        syncState = .inititialing
    }

    public func start() {
        syncIfNeeded()

        // A chain switch at runtime otherwise goes unnoticed until the next launch: the
        // version check only runs from here and the 24h timer. Re-run it on a network
        // change so the installedDatabaseNetwork mismatch forces a same-session re-download.
        networkDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.DWCurrentNetworkDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.syncIfNeeded()
        }

        // Try to sync every 24h
        timer = Timer.scheduledTimer(withTimeInterval: 60*60*24, repeats: true) { [weak self] _ in
            self?.syncIfNeeded()
        }
    }

    private func syncIfNeeded() {
        syncState = .fetchingInfo

        storageRef.getMetadata { [weak self] metadata, _ in
            guard let wSelf = self else { return }

            guard let metadata else {
                wSelf.syncState = .error(Date(), nil)
                return
            }

            guard let timestamp = metadata.customMetadata?[timestampKey],
                  let timeIntervalMillesecond = TimeInterval(timestamp) else {
                wSelf.syncState = .error(Date(), nil)
                return
            }

            let timeInterval = timeIntervalMillesecond/1000
            let installedVersion = wSelf.exploreDatabaseLastVersion
            let localDatabaseExists = wSelf.hasLocalExploreDatabase()

            // If local DB is missing (e.g. removed due to schema mismatch), force download
            // regardless of saved version timestamp to avoid falling back to in-memory DB.
            if !localDatabaseExists {
                DSLogger.log("ExploreDash: local explore.db missing, forcing cloud database download")
                wSelf.downloadDatabase(metadata: metadata)
                return
            }

            // The file on disk may belong to the other network (the chain was switched since it was
            // downloaded). Its version is tracked under that network's key, so the check below would
            // read as up to date and leave us serving the wrong network's merchants.
            if wSelf.installedDatabaseNetwork != wSelf.currentNetworkName {
                DSLogger.log("ExploreDash: explore.db belongs to \(wSelf.installedDatabaseNetwork ?? "an unknown network"), current network is \(wSelf.currentNetworkName) — forcing download")
                wSelf.downloadDatabase(metadata: metadata)
                return
            }

            guard timeInterval > installedVersion else {
                wSelf.syncState = .synced(Date())
                return
            }

            wSelf.downloadDatabase(metadata: metadata)
        }
    }

    deinit {
        timer.invalidate()
        timer = nil
        if let networkDidChangeObserver {
            NotificationCenter.default.removeObserver(networkDidChangeObserver)
        }
    }

    static let share = ExploreDatabaseSyncManager()
}

extension ExploreDatabaseSyncManager {
    private func downloadDatabase(metadata: StorageMetadata) {
        guard let timestamp = metadata.customMetadata?[timestampKey],
              let checksum = metadata.customMetadata?[checksumKey],
              let timeIntervalMillesecond = TimeInterval(timestamp) else {
            syncState = .error(Date(), nil)
            return
        }

        syncState = .syncing
        let urlToSave = getDocumentsDirectory().appendingPathComponent("\(networkSpecificFileName)-\(timestamp).zip")

        storageRef.getData(maxSize: metadata.size) { [weak self] data, error in
            let date = Date()
            let now = date.timeIntervalSince1970

            if let e = error {
                self?.syncState = .error(date, e)
            } else {
                try? data?.write(to: urlToSave)
                
                Task {
                    do {
                        try await self?.unzipFile(at: urlToSave.path, password: checksum)
                        self?.exploreDatabaseLastSyncTimestamp = now
                        self?.exploreDatabaseLastVersion = timeIntervalMillesecond / 1000
                        self?.installedDatabaseNetwork = self?.currentNetworkName
                        self?.syncState = .synced(date)

                        NotificationCenter.default.post(name: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification, object: nil)
                        try? FileManager.default.removeItem(at: URL(fileURLWithPath: urlToSave.path))
                    } catch {
                        DSLogger.log("ExploreDash: failed to open DB archive: \(String(describing: error))")
                        self?.syncState = .error(Date(), error)
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
}

private let kExploreDatabaseLastSyncTimestampKey = "kExploreDatabaseLastSyncTimestampKey"
private let kExploreDatabaseLastVersion = "kExploreDatabaseLastVersion"
private let kExploreDatabaseInstalledNetworkKey = "kExploreDatabaseInstalledNetwork"

extension ExploreDatabaseSyncManager {
    // Network-specific UserDefaults keys
    private var syncTimestampKey: String {
        let isMainnet = DWEnvironment.sharedInstance().currentChain.isMainnet()
        return isMainnet ? "kExploreDatabaseLastSyncTimestampKey_Mainnet" : "kExploreDatabaseLastSyncTimestampKey_Testnet"
    }

    private var versionKey: String {
        let isMainnet = DWEnvironment.sharedInstance().currentChain.isMainnet()
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
