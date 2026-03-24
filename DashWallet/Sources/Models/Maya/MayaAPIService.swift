//
//  MayaAPIService.swift
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

final class MayaAPIService: HTTPClient<MayaEndpoint> {
    static let shared = MayaAPIService()

    func fetchPools() async throws -> [MayaPool] {
        try await request(.getPools)
    }

    func fetchInboundAddresses() async throws -> [MayaInboundAddress] {
        try await request(.getInboundAddresses)
    }

    /// Validates a destination address by requesting a swap quote from the Maya API.
    /// Returns nil if the address is valid, or an error string if invalid.
    func validateAddress(destination: String, toAsset: String) async -> String? {
        do {
            let quote: MayaSwapQuote = try await request(
                .quoteSwap(
                    fromAsset: "DASH.DASH",
                    toAsset: toAsset,
                    amount: 100_000_000, // 1 DASH in base units
                    destination: destination
                )
            )
            return quote.error
        } catch {
            // Non-200 responses may contain an error body with the validation message
            if case HTTPClientError.statusCode(let response) = error {
                if let body = try? JSONDecoder().decode(MayaSwapQuote.self, from: response.data) {
                    return body.error
                }
            }
            DSLogger.log("Maya: Address validation request failed: \(error)")
            return NSLocalizedString("Address validation unavailable — please check your connection", comment: "Maya")
        }
    }
}

struct MayaInboundAddress: Decodable {
    let chain: String
    let halted: Bool
}

struct MayaSwapQuote: Decodable {
    let error: String?
}
