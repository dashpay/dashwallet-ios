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
    private let storageRef: StorageReference

    private var timer: Timer!

    private var databaseVersion: Double = 0
    private var lastSync: Double = 0

    var syncState: State
    var lastServerUpdateDate: Date { Date(timeIntervalSince1970: exploreDatabaseLastVersion) }

    init() {
        syncState = .inititialing

        // Initialize storageRef with computed database path
        let databasePath: String
        if DWEnvironment.sharedInstance().currentChain.isMainnet() {
            databasePath = "gs://dash-wallet-firebase.appspot.com/explore/explore-v4.db"
        } else {
            databasePath = "gs://dash-wallet-firebase.appspot.com/explore/explore-v4-testnet.db"
        }

        storageRef = storage.reference(forURL: databasePath)
    }

    public func start() {
        syncIfNeeded()

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
        let urlToSave = getDocumentsDirectory().appendingPathComponent("\(fileName)-\(timestamp).zip")

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
}

private let kExploreDatabaseLastSyncTimestampKey = "kExploreDatabaseLastSyncTimestampKey"
private let kExploreDatabaseLastVersion = "kExploreDatabaseLastVersion"

extension ExploreDatabaseSyncManager {
    var exploreDatabaseLastSyncTimestamp: TimeInterval {
        set {
            UserDefaults.standard.setValue(newValue, forKey: kExploreDatabaseLastSyncTimestampKey)
        }
        get {
            let value = UserDefaults.standard.double(forKey: kExploreDatabaseLastSyncTimestampKey)
            return value == 0 ? bundleExploreDatabaseSyncTime : value
        }
    }

    var exploreDatabaseLastVersion: TimeInterval {
        set {
            UserDefaults.standard.setValue(newValue, forKey: kExploreDatabaseLastVersion)
        }
        get {
            let value = UserDefaults.standard.double(forKey: kExploreDatabaseLastVersion)
            return value == 0 ? bundleExploreDatabaseSyncTime : value
        }
    }
}
