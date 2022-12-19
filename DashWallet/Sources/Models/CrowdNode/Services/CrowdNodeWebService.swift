//  
//  Created by Andrei Ashikhmin
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

import Moya

// MARK: - CrowdNodeService

class CrowdNodeService {
    private var httpClient: CrowdNodeAPI {
        CrowdNodeAPI.shared
    }
}

extension CrowdNodeService {
    func getCrowdNodeBalance(address: String) async throws -> CrowdNodeBalance {
        let result: CrowdNodeBalance = try await httpClient.request(.getBalance(address))
        return result
        
//        httpClient.request(.getBalance(address)) { result in
//            switch result {
//            case let .success(moyaResponse):
//                let data = moyaResponse.data // Data, your JSON response is probably in here!
//                let statusCode = moyaResponse.statusCode // Int - 200, 401, 500, etc
//
//                do {
//                    let json = try moyaResponse.mapJSON() // type Any
//                    print("CrowdNode statusCode: \(json)")
//                } catch {
//                    print("CrowdNode error1: \(error)")
//                }
//
//            case let .failure(error):
//                print("CrowdNode error2: \(error)")
//            }
//        }
    }
}
