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

struct SupportedTopperAssets: Codable {
    let assets: TopperAssets
}

struct TopperAssets: Codable {
    let source: [SourceCurrency]
    let target: [TargetCurrency]
}

struct SourceCurrency: Codable {
    let code: String
    let name: String
    let symbol: String
}

struct TargetCurrency: Codable {
    let code: String
    let name: String
    let networks: [TargetNetwork]
    let symbol: String?
}

struct TargetNetwork: Codable {
    let code: String
    let name: String
    let priorities: [String]
    let tagTypes: [String]
}
