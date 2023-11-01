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

// MARK: - UsernameRequest

struct UsernameRequest {
    var requestId: String
    var username: String
    var createdAt: Int64
    var identity: String
    var link: String?
    var votes: Int
    var isApproved: Bool

    init(requestId: String, username: String, createdAt: Int64, identity: String, link: String?, votes: Int, isApproved: Bool) {
        self.requestId = requestId
        self.username = username
        self.createdAt = createdAt
        self.identity = identity
        self.link = link
        self.votes = votes
        self.isApproved = isApproved
    }

    init(row: Row) {
        self.requestId = row[UsernameRequest.requestId]
        self.username = row[UsernameRequest.username]
        self.createdAt = row[UsernameRequest.createdAt]
        self.identity = row[UsernameRequest.identity]
        self.link = row[UsernameRequest.link]
        self.votes = row[UsernameRequest.votes]
        self.isApproved = row[UsernameRequest.isApproved]
    }
}

extension UsernameRequest {
    static var table: Table { Table("username_requests") }
    
    static var requestId: Expression<String> { Expression<String>("requestId") }
    static var username: Expression<String> { Expression<String>("username") }
    static var createdAt: Expression<Int64> { Expression<Int64>("createdAt") }
    static var identity: Expression<String> { Expression<String>("identity") }
    static var votes: Expression<Int> { Expression<Int>("votes") }
    static var isApproved: Expression<Bool> { Expression<Bool>("isApproved") }
    static var link: Expression<String?> { .init("link") }
}
