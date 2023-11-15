//  
//  Created by Andrei Ashikhmin
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - UsernameRequestsDAO

protocol UsernameRequestsDAO {
    func create(dto: UsernameRequest) async
    func all(onlyWithLinks: Bool) async -> [UsernameRequest]
    func duplicates(onlyWithLinks: Bool) async -> [UsernameRequest]
    func get(by requestId: String) -> UsernameRequest?
    func update(dto: UsernameRequest) async
    func delete(dto: UsernameRequest)
    func deleteAll()
}

// MARK: - UsernameRequestsDAOImpl

class UsernameRequestsDAOImpl: NSObject, UsernameRequestsDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [String: UsernameRequest] = [:]

    private let queue = DispatchQueue(label: "org.dash.infrastructure.queue.username-requests-dao", attributes: .concurrent)

    func create(dto: UsernameRequest) async {
        
        do {
            let usernameRequest = UsernameRequest.table.insert(or: .replace,
                                                          UsernameRequest.requestId <- dto.requestId,
                                                          UsernameRequest.username <- dto.username,
                                                          UsernameRequest.createdAt <- dto.createdAt,
                                                          UsernameRequest.identity <- dto.identity,
                                                          UsernameRequest.link <- dto.link,
                                                          UsernameRequest.votes <- dto.votes,
                                                          UsernameRequest.isApproved <- dto.isApproved)
            try await execute(usernameRequest)
            self.cache[dto.requestId] = dto
        } catch {
            print(error)
        }
    }

    func get(by requestId: String) -> UsernameRequest? {
        if let cached = cachedValue(by: requestId) {
            return cached
        }

        let statement = UsernameRequest.table.filter(UsernameRequest.requestId == requestId)

        do {
            for row in try db.prepare(statement) {
                let userInfo = UsernameRequest(row: row)
                queue.async(flags: .barrier) { [weak self] in
                    self?.cache[requestId] = userInfo
                }
                return userInfo
            }
        } catch {
            print(error)
        }

        return nil
    }

    private func cachedValue(by key: String) -> UsernameRequest? {
        var v: UsernameRequest?

        queue.sync {
            v = cache[key]
        }

        return v
    }

    func update(dto: UsernameRequest) async {
        await create(dto: dto)
    }

    func delete(dto: UsernameRequest) {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache[dto.requestId] = nil
        }
    }

    func deleteAll() {
        do {
            try db.run(UsernameRequest.table.delete())
            queue.async(flags: .barrier) { [weak self] in
                self?.cache = [:]
            }
        } catch {
            print(error)
        }
    }

    static let shared = UsernameRequestsDAOImpl()
}

// MARK: - Queries

extension UsernameRequestsDAOImpl {
    func all(onlyWithLinks: Bool) async -> [UsernameRequest] {
        let linksParam = onlyWithLinks ? 1 : 0
        let query = """
            SELECT * FROM username_requests 
                WHERE (\(linksParam) = 0) OR (\(linksParam) = 1 AND link IS NOT NULL)
            ORDER BY username
            COLLATE NOCASE ASC
        """
        
        do {
            return try await self.execute(query: query)
        } catch {
            print(error)
        }
        
        return []
    }
    
    func duplicates(onlyWithLinks: Bool) async -> [UsernameRequest] {
        let linksParam = onlyWithLinks ? 1 : 0
        let query = """
            SELECT * FROM username_requests
                WHERE username IN 
                    (SELECT username FROM username_requests GROUP BY username HAVING COUNT(username) > 1)
                AND ((\(linksParam) = 0) OR (\(linksParam) = 1 AND link IS NOT NULL))
            ORDER BY username
            COLLATE NOCASE ASC
        """
        
        do {
            return try await self.execute(query: query)
        } catch {
            print(error)
        }
        
        return []
    }
}

// MARK: - async / await

extension UsernameRequestsDAOImpl {
    private func execute<Item: RowDecodable>(query: String) async throws -> [Item] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume(returning: []) }
                    
                do {
                    let results = try self.db.prepare(query).prepareRowIterator().map { Item(row: $0) }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
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
}
