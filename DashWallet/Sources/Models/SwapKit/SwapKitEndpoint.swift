//
//  SwapKitEndpoint.swift
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

enum SwapKitEndpoint {
    case getSwapTo(sellAsset: String)
    case getPrices(identifiers: [String])
    case quote(_ request: SwapKitQuoteRequest)
    case swap(_ request: SwapKitSwapRequest)
    case track(_ request: SwapKitTrackRequest)
}

extension SwapKitEndpoint: TargetType {
    var baseURL: URL {
        URL(string: "https://api.swapkit.dev/")!
    }

    var path: String {
        switch self {
        case .getSwapTo:
            return "swapTo"
        case .getPrices:
            return "price"
        case .quote:
            return "v3/quote"
        case .swap:
            return "v3/swap"
        case .track:
            return "track"
        }
    }

    var method: Moya.Method {
        switch self {
        case .getSwapTo:
            return .get
        case .getPrices, .quote, .swap, .track:
            return .post
        }
    }

    var task: Moya.Task {
        switch self {
        case .getSwapTo(let sellAsset):
            return .requestParameters(
                parameters: ["sellAsset": sellAsset],
                encoding: URLEncoding.queryString
            )
        case .getPrices(let identifiers):
            let body = SwapKitPriceRequest(
                tokens: identifiers.map { SwapKitPriceToken(identifier: $0) },
                metadata: false
            )
            return .requestJSONEncodable(body)
        case .quote(let request):
            return .requestJSONEncodable(request)
        case .swap(let request):
            return .requestJSONEncodable(request)
        case .track(let request):
            return .requestJSONEncodable(request)
        }
    }

    var headers: [String: String]? {
        [
            "x-api-key": SwapKitConstants.apiKey,
            "Content-Type": "application/json",
        ]
    }
}
