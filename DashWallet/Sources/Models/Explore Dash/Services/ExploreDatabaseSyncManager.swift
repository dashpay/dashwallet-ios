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

import Foundation
import Firebase
import SSZipArchive

let gsFilePath = "gs://dash-wallet-firebase.appspot.com/explore/explore.db"

private let fileName = "explore"

private let timestampKey = "Data-Timestamp"
private let checksumKey = "Data-Checksum"

let bundleExploreDatabaseSyncTime: TimeInterval = 1647448290711/1000

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
    var lastServerUpdateDate: Date { Date(timeIntervalSince1970: bundleExploreDatabaseSyncTime) }
    
    init()
    {
        syncState = .inititialing
        storageRef = storage.reference(forURL: gsFilePath)
    }
    
    public func start() {
        syncIfNeeded()
        
        // Try to sync 24h later
        timer = Timer.scheduledTimer(withTimeInterval: 60*60*24, repeats: true) { [weak self] timer in
            self?.syncIfNeeded()
        }
    }
    
    private func syncIfNeeded() {
        syncState = .fetchingInfo
        weak var wSelf = self
        storageRef.getMetadata { metadata, error in
            guard let metadata = metadata else {
                wSelf?.syncState = .error(Date(), nil)
                return
            }
            
            guard let timestamp = metadata.customMetadata?[timestampKey],
                  let ts = TimeInterval(timestamp),
                  let savedTs = wSelf?.exploreDatabaseLastSyncTimestamp,
                  (ts/1000) > savedTs else {
                wSelf?.syncState = .synced(Date())
                return
            }
            
            wSelf?.downloadDatabase(metadata: metadata)
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
              let checksum = metadata.customMetadata?[checksumKey] else {
            syncState = .error(Date(), nil)
            return
        }
        
        syncState = .syncing
        let urlToSave = getDocumentsDirectory().appendingPathComponent("\(fileName)-\(timestamp).zip")
    
        storageRef.getData(maxSize: metadata.size) { [weak self] data, error in
            let date = Date()
            let timestamp = date.timeIntervalSince1970
            
            if let e = error {
                self?.syncState = .error(date, e)
            }else{
                try? data?.write(to: urlToSave)
                self?.exploreDatabaseLastSyncTimestamp = timestamp
                self?.syncState = .synced(date)
                self?.unzipFile(at: urlToSave.path, password: checksum)
            }
        }
    }
    
    private func unzipFile(at path: String, password: String) {
        var error: NSError?
        let urlToUnzip = getDocumentsDirectory()
        SSZipArchive.unzipFile(atPath: path, toDestination: urlToUnzip.path, preserveAttributes: true, overwrite: true, nestedZipLevel: 0, password: password, error: &error, delegate: nil, progressHandler: nil) { path, succeded, error in
            NotificationCenter.default.post(name: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification, object: nil)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}

private let kExploreDatabaseLastSyncTimestampKey = "kExploreDatabaseLastSyncTimestampKey"

extension ExploreDatabaseSyncManager {
    var exploreDatabaseLastSyncTimestamp: TimeInterval {
        set {
            UserDefaults.standard.setValue(newValue, forKey: kExploreDatabaseLastSyncTimestampKey)
        }
        get {
            let value = UserDefaults.standard.double(forKey: kExploreDatabaseLastSyncTimestampKey)
            return UserDefaults.standard.double(forKey: kExploreDatabaseLastSyncTimestampKey) == 0 ? bundleExploreDatabaseSyncTime : value
        }
    }
}
