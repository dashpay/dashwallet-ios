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

/**
 TODO:
 -[] Check file periodically
 -[]
 
 **/


import Foundation
import Firebase
import SSZipArchive

let gsFilePath = "gs://dash-wallet-firebase.appspot.com/explore/explore.db"

private let fileName = "explore"

private let timestampKey = "Data-Timestamp"
private let checksumKey = "Data-Checksum"

public class ExploreDatabaseSyncManager {
    
    private let storage = Storage.storage()
    private let storageRef: StorageReference
    
    private var timer: Timer!
    
    init()
    {
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
        storageRef.getMetadata { [weak self] metadata, error in
            guard let metadata = metadata else {
                return
            }
            
            guard let timestamp = metadata.customMetadata?[timestampKey],
                  let ts = TimeInterval(timestamp),
                  ts > GlobalOptions.shared.exploreDatabaseLastSync else {
                return
            }
            
            self?.downloadDatabase(metadata: metadata)
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
            return
        }
        
        let urlToSave = getDocumentsDirectory().appendingPathComponent("\(fileName)-\(timestamp).zip")
    
        storageRef.getData(maxSize: metadata.size) { [weak self] data, error in
            try? data?.write(to: urlToSave)
            //GlobalOptions.shared.exploreDatabaseLastSync = Date().timeIntervalSince1970
            self?.unzipFile(atPath: urlToSave.path, password: checksum)
        }
    }
    
    private func unzipFile(atPath: String, password: String) {
        var error: NSError?
        let urlToUnzip = getDocumentsDirectory()
        SSZipArchive.unzipFile(atPath: atPath, toDestination: urlToUnzip.path, preserveAttributes: true, overwrite: true, password: password, error: &error, delegate: nil)
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
