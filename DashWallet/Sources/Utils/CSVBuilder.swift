//
//  Created by tkhp
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

class CSVBuilder<HeaderIdentifierType: CustomStringConvertible, ItemIdentifierType> {
    private var columns: [HeaderIdentifierType] = []

    @discardableResult
    func add(column: HeaderIdentifierType) -> Self {
        columns.append(column)
        return self
    }

    @discardableResult
    func set(columns: [HeaderIdentifierType]) -> Self {
        self.columns = columns
        return self
    }

    func build(from items: [ItemIdentifierType], using cellValueProvider: (HeaderIdentifierType, ItemIdentifierType) -> String) -> String {
        var rows: [String] = []
        rows.reserveCapacity(items.count + 1) // Number of items + header row

        let headerRow = columns.map { String(describing: $0) }.joined(separator: ",")
        rows.append(headerRow)

        var rowValues: [String] = Array(repeating: "", count: columns.count)

        for item in items {
            for (i, column) in columns.enumerated() {
                rowValues[i] = cellValueProvider(column, item)
            }

            rows.append(rowValues.joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }
}
