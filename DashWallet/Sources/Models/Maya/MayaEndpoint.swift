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

// Pool/price data comes from Midgard (analytics layer).
// All swap operations — inbound addresses, quotes, tx lookup — go to mayanode (protocol layer).
private enum MayaHost {
    static let midgard = "https://midgard.mayachain.info/v2/"
    static let mayanode = "https://mayanode.mayachain.info/mayachain/"
}

enum MayaEndpoint {
    case getPools
    case getInboundAddresses
    case quoteSwap(fromAsset: String, toAsset: String, amount: Int64, destination: String)
    case getSwapTransactionInfo(txid: String)
}

extension MayaEndpoint: TargetType {
    var baseURL: URL {
        switch self {
        case .getPools:
            return URL(string: MayaHost.midgard)!
        case .getInboundAddresses, .quoteSwap, .getSwapTransactionInfo:
            return URL(string: MayaHost.mayanode)!
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
        case .getSwapTransactionInfo(let txid):
            return "tx/\(txid)"
        }
    }

    var method: Moya.Method {
        .get
    }

    var task: Moya.Task {
        switch self {
        case let .quoteSwap(fromAsset, toAsset, amount, destination):
            return .requestParameters(
                parameters: [
                    "from_asset": fromAsset,
                    "to_asset": toAsset,
                    "amount": amount,
                    "destination": destination,
                ],
                encoding: URLEncoding.queryString
            )
        case .getPools, .getInboundAddresses, .getSwapTransactionInfo:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        nil
    }
}
