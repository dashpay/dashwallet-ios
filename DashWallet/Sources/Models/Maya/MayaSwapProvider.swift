//
//  MayaSwapProvider.swift
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

/// `SwapProvider` implementation that delegates to `MayaAPIService` — the direct Maya integration.
/// Maps Maya-specific DTOs (`MayaSwapQuote`, `MayaSwapTransactionInfo`) to the neutral result types.
final class MayaSwapProvider: SwapProvider {
    var displayName: String { "Maya" }

    func fetchPools() async throws -> [MayaPool] {
        try await MayaAPIService.shared.fetchPools()
    }

    func fetchInboundAddresses() async throws -> [MayaInboundAddress] {
        try await MayaAPIService.shared.fetchInboundAddresses()
    }

    func validateAddress(destination: String, toAsset: String) async -> String? {
        await MayaAPIService.shared.validateAddress(destination: destination, toAsset: toAsset)
    }

    func fetchQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        let quote = try await MayaAPIService.shared.fetchQuote(
            dashSatoshis: dashSatoshis,
            toAsset: toAsset,
            destination: destination
        )
        return SwapQuoteResult(
            error: quote.error,
            expectedAmountOut: quote.expectedAmountOut,
            fees: quote.fees.map { SwapFeeResult(total: $0.total, outbound: $0.outbound) },
            inboundAddress: quote.inboundAddress,
            memo: quote.memo,
            executionNetwork: quote.executionNetwork ?? displayName
        )
    }

    func fetchSwapStatus(txid: String) async throws -> SwapStatusResult {
        let info = try await MayaAPIService.shared.fetchSwapTransactionInfo(txid: txid)
        guard let observedTx = info.observedTx else {
            return SwapStatusResult(error: info.error, isObserved: false, observedStatus: nil, outHashes: nil)
        }
        return SwapStatusResult(
            error: info.error,
            isObserved: true,
            observedStatus: observedTx.status,
            outHashes: observedTx.outHashes
        )
    }
}
