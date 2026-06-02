//
//  SwapKitAPIService.swift
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

final class SwapKitAPIService: HTTPClient<SwapKitEndpoint> {
    static let shared = SwapKitAPIService()

    // MARK: - Asset Discovery

    func swapTo(sellAsset: String) async throws -> [String] {
        try await request(.getSwapTo(sellAsset: sellAsset))
    }

    // MARK: - Prices

    func prices(identifiers: [String]) async throws -> [SwapKitPriceResponse] {
        try await request(.getPrices(identifiers: identifiers))
    }

    // MARK: - Quote and Swap

    func quote(_ request: SwapKitQuoteRequest) async throws -> SwapKitQuoteResponse {
        try await self.request(.quote(request))
    }

    func swap(_ request: SwapKitSwapRequest) async throws -> SwapKitSwapResponse {
        try await self.request(.swap(request))
    }

    // MARK: - Transaction Tracking

    func track(_ request: SwapKitTrackRequest) async throws -> SwapKitTrackResponse {
        try await self.request(.track(request))
    }
}
