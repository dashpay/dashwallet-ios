//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import SQLite
import Combine

#if !swift(>=5.9)
// Provide `withLock` helper for older Swift toolchains to use scoped locking.
extension NSLock {
    /// Executes `body` while holding the lock, ensuring the lock is always released.
    /// - Returns: The value returned by `body`.
    /// - Throws: Rethrows anything thrown by `body`.
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
#endif

// MARK: - IconBitmapDAO

protocol IconBitmapDAO {
    func addBitmap(bitmap: IconBitmap) async
    func getBitmap(id: Data) async -> IconBitmap?
    func observeBitmaps() -> AnyPublisher<[Data: IconBitmap], Never>
    func clear() async
}

// MARK: - IconBitmapDAOImpl

class IconBitmapDAOImpl: NSObject, IconBitmapDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [String: IconBitmap] = [:]
    /// Synchronizes access to `cache` to avoid data races when called from multiple threads/queues.
    private let cacheLock = NSLock()
    private var bitmapsSubject = CurrentValueSubject<[Data: IconBitmap], Never>([:])
    
    static let shared = IconBitmapDAOImpl()
    
    override init() {
        super.init()
        Task {
            await loadAllBitmaps()
        }
    }
    
    func addBitmap(bitmap: IconBitmap) async {
        do {
            let insert = IconBitmap.table.insert(or: .ignore,
                                                IconBitmap.id <- bitmap.id,
                                                IconBitmap.imageData <- bitmap.imageData,
                                                IconBitmap.originalUrl <- bitmap.originalUrl,
                                                IconBitmap.height <- bitmap.height,
                                                IconBitmap.width <- bitmap.width)
            try await execute(insert)
            let key = bitmap.id.hexEncodedString()
            cacheLock.withLock { cache[key] = bitmap }
            updateBitmapsSubject()
        } catch {
            print("IconBitmapDAO addBitmap error: \(error)")
        }
    }
    
    func getBitmap(id: Data) async -> IconBitmap? {
        let statement = IconBitmap.table.filter(IconBitmap.id == id)
        
        do {
            let results: [IconBitmap] = try await prepare(statement)
            let bitmap = results.first
            if let bitmap = bitmap {
                let key = id.hexEncodedString()
                cacheLock.withLock { cache[key] = bitmap }
            }
            return bitmap
        } catch {
            print("IconBitmapDAO getBitmap error: \(error)")
        }
        
        return nil
    }
    
    func observeBitmaps() -> AnyPublisher<[Data: IconBitmap], Never> {
        return bitmapsSubject.eraseToAnyPublisher()
    }
    
    func clear() async {
        do {
            let deleteQuery = IconBitmap.table.delete()
            try await execute(deleteQuery)
            cacheLock.withLock { cache.removeAll() }
            updateBitmapsSubject()
        } catch {
            print("IconBitmapDAO clear error: \(error)")
        }
    }
    
    private func loadAllBitmaps() async {
        do {
            let bitmaps: [IconBitmap] = try await prepare(IconBitmap.table)
            cacheLock.withLock {
                cache.removeAll()
                for bitmap in bitmaps {
                    let key = bitmap.id.hexEncodedString()
                    cache[key] = bitmap
                }
            }
            updateBitmapsSubject()
        } catch {
            print("IconBitmapDAO loadAllBitmaps error: \(error)")
        }
    }
    
    private func updateBitmapsSubject() {
        let cachedCopy = cacheLock.withLock { cache }

        let bitmapsDict = cachedCopy.reduce(into: [Data: IconBitmap]()) { result, item in
            if let data = Data(hex: item.key) {
                result[data] = item.value
            }
        }
        bitmapsSubject.send(bitmapsDict)
    }
}

// MARK: - async / await

extension IconBitmapDAOImpl {
    private func execute(_ query: Insert) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume() }
                
                do {
                    try db.run(query)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func execute(_ query: Delete) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume() }
                
                do {
                    try db.run(query)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func prepare<T: RowDecodable>(_ query: Table) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume(returning: []) }
                
                var result: [T] = []
                
                do {
                    for row in try db.prepare(query) {
                        let rowItem = T(row: row)
                        result.append(rowItem)
                    }
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func prepare<T: RowDecodable>(_ query: QueryType) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume(returning: []) }
                
                var result: [T] = []
                
                do {
                    for row in try db.prepare(query) {
                        let rowItem = T(row: row)
                        result.append(rowItem)
                    }
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
