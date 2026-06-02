//
//  SwapKitModels.swift
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

import Foundation

// MARK: - Request Models

struct SwapKitQuoteRequest: Encodable {
    let sellAsset: String
    let buyAsset: String
    /// Decimal amount as string, e.g. "0.1" — NOT base units.
    let sellAmount: String
    let slippage: Int?
    let sourceAddress: String?
    let destinationAddress: String?
    let providers: [String]?
    let affiliateFee: Int?
}

struct SwapKitSwapRequest: Encodable {
    let routeId: String
    let sourceAddress: String
    let destinationAddress: String
    let disableBalanceCheck: Bool?
    let disableBuildTx: Bool?
    let overrideSlippage: Bool?
}

struct SwapKitTrackRequest: Encodable {
    let hash: String?
    let chainId: String?
    let depositAddress: String?
}

struct SwapKitPriceRequest: Encodable {
    let tokens: [SwapKitPriceToken]
    let metadata: Bool
}

struct SwapKitPriceToken: Encodable {
    let identifier: String
}

// MARK: - Quote Response

struct SwapKitQuoteResponse: Decodable {
    let quoteId: String?
    let routes: [SwapKitRoute]?
    let providerErrors: [SwapKitProviderError]?
    let error: String?
}

struct SwapKitRoute: Decodable {
    let routeId: String
    let providers: [String]
    let sellAsset: String?
    let buyAsset: String?
    let sellAmount: String?
    let expectedBuyAmount: String
    let expectedBuyAmountMaxSlippage: String?
    let fees: [SwapKitFee]?
    let estimatedTime: SwapKitEstimatedTime?
    let totalSlippageBps: Double?
    let warnings: [String]?
    let meta: SwapKitMeta?
}

struct SwapKitFee: Decodable {
    let type: String?
    let asset: String?
    let chain: String?
    let amount: String?
}

struct SwapKitEstimatedTime: Decodable {
    let inbound: Double?
    let swap: Double?
    let outbound: Double?
    let total: Double?
}

/// Route metadata. `tags` carries RECOMMENDED / CHEAPEST / FASTEST labels.
struct SwapKitMeta: Decodable {
    let tags: [String]?
    let txType: String?
}

struct SwapKitProviderError: Decodable {
    let provider: String?
    let errorCode: String?
    let message: String?
}

// MARK: - Swap Response

/// Returned by POST /v3/swap. Extends the quote-route shape with execution fields.
/// The `tx` field is intentionally omitted — for DASH (UTXO via Maya) the wallet
/// uses `targetAddress` + `memo` directly, same as the existing Maya flow.
struct SwapKitSwapResponse: Decodable {
    let swapId: String?
    let providers: [String]?
    let sellAsset: String?
    let buyAsset: String?
    let sellAmount: String?
    let expectedBuyAmount: String?
    let expectedBuyAmountMaxSlippage: String?
    let fees: [SwapKitFee]?
    let targetAddress: String?
    let inboundAddress: String?
    let memo: String?
    let error: String?
    let message: String?
}

// MARK: - Price Response

struct SwapKitPriceResponse: Decodable {
    let identifier: String
    /// USD price. 0 means "unknown / not found" — never interpret as free.
    let priceUsd: Double
    let cg: SwapKitCoinGeckoData?

    enum CodingKeys: String, CodingKey {
        case identifier
        case priceUsd = "price_usd"
        case cg
    }
}

struct SwapKitCoinGeckoData: Decodable {
    let id: String?
    let name: String?
    let marketCap: Double?
    let totalVolume: Double?
    let priceChange24hUsd: Double?
    let priceChangePercentage24hUsd: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case marketCap = "market_cap"
        case totalVolume = "total_volume"
        case priceChange24hUsd = "price_change_24h_usd"
        case priceChangePercentage24hUsd = "price_change_percentage_24h_usd"
    }
}

// MARK: - Track Response

struct SwapKitTrackResponse: Decodable {
    let status: String?
    /// Transaction hash for this leg's chain (present when SwapKit has seen the tx).
    let hash: String?
    let chainId: String?
    let fromAsset: String?
    let toAsset: String?
    let toAmount: String?
    let finalisedAt: Double?
    /// Per-stage legs of a multi-chain swap; same shape as the top-level response.
    let legs: [SwapKitTrackResponse]?
}
