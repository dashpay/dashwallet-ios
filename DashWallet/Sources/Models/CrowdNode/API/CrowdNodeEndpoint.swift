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


// MARK: - CrowdNodeEndpoint

public enum CrowdNodeEndpoint {
    case getTransactions(String)
    case getBalance(String)
    case getWithdrawalLimits(String)
    case isAddressInUse(String)
    case addressStatus(String)
    case hasDefaultEmail(String)
    case sendSignedMessage(address: String, message: String, signature: String)
    case getMessages(String)
}

// MARK: TargetType

extension CrowdNodeEndpoint: TargetType {
    
    public var baseURL: URL {
        URL(string: CrowdNode.baseUrl)!
    }

    public var path: String {
        switch self {
        case .getTransactions(let address): return "odata/apifundings/GetFunds(address='\(address)')"
        case .getBalance(let address): return "odata/apifundings/GetBalance(address='\(address)')"
        case .getWithdrawalLimits(let address): return "odata/apifundings/GetWithdrawalLimits(address='\(address)')"
        case .isAddressInUse(let address): return "odata/apiaddresses/IsApiAddressInUse(address='\(address)')"
        case .addressStatus(let address): return "odata/apiaddresses/AddressStatus(address='\(address)')"
        case .hasDefaultEmail(let address): return "odata/apiaddresses/UsingDefaultApiEmail(address='\(address)')"
        case .sendSignedMessage(let address, let message, let signature): return "odata/apimessages/SendMessage(address='\(address)',message='\(message)',signature='\(signature)',messagetype=1)"
        case .getMessages(let address): return "odata/apimessages/GetMessages(address='\(address)')"
        }
    }

    public var method: Moya.Method {
        return .get
    }

    public var task: Moya.Task {
        return .requestPlain
    }
    
    public var headers: [String : String]? {
        return [:]
    }
}
