//
//  MayaEndpoint.swift
//  DashWallet
//
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

import Moya

enum MayaEndpoint {
    case getPools
    case getInboundAddresses
    case quoteSwap(fromAsset: String, toAsset: String, amount: Int64, destination: String)
}

extension MayaEndpoint: TargetType {

    var baseURL: URL {
        switch self {
        case .getPools:
            return URL(string: "https://midgard.mayachain.info/v2/")!
        case .getInboundAddresses, .quoteSwap:
            return URL(string: "https://mayanode.mayachain.info/mayachain/")!
        }
    }

    var path: String {
        switch self {
        case .getPools:
            return "pools"
        case .getInboundAddresses:
            return "inbound_addresses"
        case .quoteSwap:
            return "quote/swap"
        }
    }

    var method: Moya.Method {
        .get
    }

    var task: Moya.Task {
        switch self {
        case .quoteSwap(let fromAsset, let toAsset, let amount, let destination):
            return .requestParameters(
                parameters: [
                    "from_asset": fromAsset,
                    "to_asset": toAsset,
                    "amount": amount,
                    "destination": destination,
                ],
                encoding: URLEncoding.queryString
            )
        default:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        [:]
    }
}
