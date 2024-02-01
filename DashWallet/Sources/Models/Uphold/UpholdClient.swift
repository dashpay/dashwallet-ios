//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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
import Moya

public enum UpholdEndpoint {
    case getCapabilities(String)
}

// MARK: TargetType

extension UpholdEndpoint: TargetType, AccessTokenAuthorizable {
    public var authorizationType: Moya.AuthorizationType? {
        return .bearer
    }
    
    public var baseURL: URL {
        URL(string: DWUpholdConstants.baseURLString())!
    }

    public var path: String {
        switch self {
        case .getCapabilities(let operation): return "v0/me/capabilities/\(operation)"
        }
    }

    public var method: Moya.Method {
        .get
    }

    public var task: Moya.Task {
        .requestPlain
    }

    public var headers: [String : String]? {
        [:]
    }
}

class UpholdClient: HTTPClient<UpholdEndpoint> {
    private var accessToken: String? = nil
    private let kUpholdAccessToken = "DW_UPHOLD_ACCESS_TOKEN"
    
    init() {
        super.init()
        accessTokenProvider = {
            if self.accessToken == nil || self.accessToken!.isEmpty {
                self.accessToken = self.getToken()
            }
            
            return self.accessToken
        }
    }
    
    func getCapabilities(capability: String) async throws -> UpholdCapability? {
        try await request(.getCapabilities(capability))
    }
    
    private func getToken() -> String? {
        getKeychainString(kUpholdAccessToken, nil)
    }
}
