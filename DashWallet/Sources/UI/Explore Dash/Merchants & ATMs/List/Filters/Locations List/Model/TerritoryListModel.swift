//
//  Created by tkhp
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

typealias Territory = String

// MARK: - TerritoriesListModel

final class TerritoriesListModel {
    var territories: [Territory] = []

    var territoriesDidChange: (() -> ())?
    var territoriesDataSource: TerritoryDataSource? {
        didSet {
            fetchTerritories()
        }
    }

    init() {
        fetchTerritories()
    }

    private func fetchTerritories() {
        guard let dataSource = territoriesDataSource else { return }

        dataSource {
            [weak self] result in
            switch result {
            case .success(let r):
                self?.territories = r
                DispatchQueue.main.async {
                    self?.territoriesDidChange?()
                }
            case .failure:
                break
            }
        }
    }
}
