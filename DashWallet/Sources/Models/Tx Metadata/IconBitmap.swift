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

// MARK: - IconBitmap

struct IconBitmap: RowDecodable {
    let id: Data
    let imageData: Data
    let originalUrl: String
    let height: Int
    let width: Int
    
    static let table = Table("icon_bitmaps")
    static let id = SQLite.Expression<Data>("id")
    static let imageData = SQLite.Expression<Data>("imageData")
    static let originalUrl = SQLite.Expression<String>("originalUrl")
    static let height = SQLite.Expression<Int>("height")
    static let width = SQLite.Expression<Int>("width")
    
    init(row: Row) {
        self.id = row[IconBitmap.id]
        self.imageData = row[IconBitmap.imageData]
        self.originalUrl = row[IconBitmap.originalUrl]
        self.height = row[IconBitmap.height]
        self.width = row[IconBitmap.width]
    }
    
    init(id: Data, imageData: Data, originalUrl: String, height: Int, width: Int) {
        self.id = id
        self.imageData = imageData
        self.originalUrl = originalUrl
        self.height = height
        self.width = width
    }
} 