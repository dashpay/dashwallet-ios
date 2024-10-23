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
    func get(byRequestId id: String) async -> UsernameRequest?
    func get(byUsername name: String) async -> UsernameRequest?
    func update(dto: UsernameRequest) async
    func delete(by requestId: String) async
    func vote(for requestIds: [String], voteIncrement: Int) async
    func deleteAll()
}

// MARK: - UsernameRequestsDAOImpl

class UsernameRequestsDAOImpl: NSObject, UsernameRequestsDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [String: UsernameRequest] = [:]

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

    func get(byRequestId id: String) async -> UsernameRequest? {
        let statement = UsernameRequest.table.filter(UsernameRequest.requestId == id)

        do {
            let results: [UsernameRequest] = try await prepare(statement)
            self.cache[id] = results.first
            return results.first
        } catch {
            print(error)
        }

        return nil
    }
    
    func get(byUsername name: String) async -> UsernameRequest? {
        let statement = UsernameRequest.table.filter(UsernameRequest.username == name)

        do {
            let results: [UsernameRequest] = try await prepare(statement)
            
            if let request = results.first {
                self.cache[request.requestId] = request
            }
            
            return results.first
        } catch {
            print(error)
        }

        return nil
    }
    
    func update(dto: UsernameRequest) async {
        await create(dto: dto)
    }

    func deleteAll() {
        do {
            try db.run(UsernameRequest.table.delete())
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
    
    func vote(for requestIds: [String], voteIncrement: Int) async {
        let idsPlaceholder = requestIds.map { _ in "?" }.joined(separator: ", ")
        let query = """
            UPDATE username_requests
            SET isApproved = 1, votes = votes + ?
                WHERE requestId IN (\(idsPlaceholder))
        """

        do {
            let binding: [Binding?] = [voteIncrement] + requestIds
            let _: [UsernameRequest] = try await self.execute(query: query, bindings: binding)
        } catch {
            print(error)
        }
    }

    func delete(by requestId: String) async {
        self.cache[requestId] = nil
        
        do {
            let deleteQuery = UsernameRequest.table.filter(UsernameRequest.requestId == requestId).delete()
            try await self.execute(deleteQuery)
        } catch {
            print(error)
        }
    }
}

// MARK: - async / await

extension UsernameRequestsDAOImpl {
    private func execute<Item: RowDecodable>(query: String, bindings: [Binding?] = []) async throws -> [Item] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume(returning: []) }
                    
                do {
                    let results = try self.db.prepareRowIterator(query, bindings: bindings).map { Item(row: $0) }
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
    
    private func prepare<T: RowDecodable>(_ statement: QueryType) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return continuation.resume(returning: []) }
                
                var result: [T] = []
                
                do {
                    for row in try db.prepare(statement) {
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
