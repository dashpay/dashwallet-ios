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
    func create(dto: UsernameRequest)
    func all(onlyWithLinks: Bool) -> [UsernameRequest]
    func get(by requestId: String) -> UsernameRequest?
    func update(dto: UsernameRequest)
    func delete(dto: UsernameRequest)
    func deleteAll()
}

// MARK: - UsernameRequestsDAOImpl

class UsernameRequestsDAOImpl: NSObject, UsernameRequestsDAO {
    private var db: Connection { DatabaseConnection.shared.db }
    private var cache: [String: UsernameRequest] = [:]

    private let queue = DispatchQueue(label: "org.dash.infrastructure.queue.username-requests-dao", attributes: .concurrent)

    func create(dto: UsernameRequest) {
        do {
            let usernameRequest = UsernameRequest.table.insert(or: .replace,
                                                          UsernameRequest.requestId <- dto.requestId,
                                                          UsernameRequest.username <- dto.username,
                                                          UsernameRequest.createdAt <- dto.createdAt,
                                                          UsernameRequest.identity <- dto.identity,
                                                          UsernameRequest.link <- dto.link,
                                                          UsernameRequest.votes <- dto.votes,
                                                          UsernameRequest.isApproved <- dto.isApproved)
            try db.run(usernameRequest)

        } catch {
            print(error)
        }

        queue.async(flags: .barrier) { [weak self] in
            self?.cache[dto.requestId] = dto
        }
    }

    func all() -> [UsernameRequest] {
        let statement = UsernameRequest.table
        var userInfos: [UsernameRequest] = []

        do {
            for requestRow in try db.prepare(statement) {
                let userInfo = UsernameRequest(row: requestRow)
                userInfos.append(userInfo)
            }
        } catch {
            print(error)
        }

        return userInfos
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

    func update(dto: UsernameRequest) {
        create(dto: dto)
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
    
    func dictionaryOfAllItems() -> [String: UsernameRequest] {
        _ = all()
        return cache
    }

    static let shared = UsernameRequestsDAOImpl()
}

extension UsernameRequestsDAOImpl {
    func all(onlyWithLinks: Bool) -> [UsernameRequest] {
        let linksParam = onlyWithLinks ? 1 : 0
        let query = "SELECT * FROM username_requests WHERE (\(linksParam) = 0) OR (\(linksParam) = 1 AND link IS NOT NULL) ORDER BY username COLLATE NOCASE ASC"
        
        do {
            return try self.execute(query: query)
        } catch {
            print(error)
        }
        
        return []
    }
    
    private func execute<Item: RowDecodable>(query: String) throws -> [Item] {
        try db.prepare(query).prepareRowIterator().map { Item(row: $0) }
    }
}
