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
import SQLite

private let pageLimit = 30

class MerchantDAO
{
    private let connection: ExploreDatabaseConnection
    
    init(dbConnection: ExploreDatabaseConnection) {
        self.connection = dbConnection
    }
    
    func allOnlineMerchants(offset: Int = 0) -> PaginationResult<Merchant> {
        let name = Expression<String>("name")
        let type = Expression<String>("type")
        
        let merchants = Table("merchant")
        let query = merchants.select(merchants[*])
            .filter(type == "online")
            .order(name)
            .limit(pageLimit, offset: offset)
        
        do {
            let items: [Merchant] = try connection.find(query: query)
            return PaginationResult(items: items, offset: offset + pageLimit)
        }catch{
            print(error)
            return PaginationResult(items: [], offset: 0)
        }
    }
    
    func searchOnlineMerchants(query: String, offset: Int = 0) -> PaginationResult<Merchant> {
        let name = Expression<String>("name")
        let type = Expression<String>("type")
        
        let merchants = Table("merchant")
        let query = merchants.select(merchants[*])
            .filter(type == "online" && name.like("\(query)%"))
            .order(name)
            .limit(pageLimit, offset: offset)
        
        do {
            let items: [Merchant] = try connection.find(query: query)
            return PaginationResult(items: items, offset: offset + pageLimit)
        }catch{
            print(error)
            return PaginationResult(items: [], offset: 0)
        }
    }
//    func nearby(location:offset: Int = 1) -> PaginationResult<Merchant> {
//        let name = Expression<String>("name")
//        let type = Expression<String>("type")
//        
//        let merchants = Table("merchant")
//        let query = merchants.select(merchants[*])
//            .filter(type == "physical" || type == "both")
//            .order(name)
//            .limit(pageLimit, offset: offset)
//        
//        do {
//            let items: [Merchant] = try connection.find(query: query)
//            return PaginationResult(items: items, offset: offset + pageLimit)
//        }catch{
//            print(error)
//            return PaginationResult(items: [], offset: 0)
//        }
//    }
}

struct PaginationResult<Item> {
    var items: [Item]
    var offset: Int
}
