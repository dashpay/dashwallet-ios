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

    // MARK: - Pools and Prices (Midgard)

    func fetchPools() async throws -> [MayaPool] {
        try await request(.getPools)
    }

    // MARK: - Inbound Addresses (mayanode)

    func fetchInboundAddresses() async throws -> [MayaInboundAddress] {
        try await request(.getInboundAddresses)
    }

    // MARK: - Quote and Swap (mayanode)

    func fetchQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> MayaSwapQuote {
        try await request(
            .quoteSwap(
                fromAsset: "DASH.DASH",
                toAsset: toAsset,
                amount: dashSatoshis,
                destination: destination
            )
        )
    }

    func fetchSwapTransactionInfo(txid: String) async throws -> MayaSwapTransactionInfo {
        try await request(.getSwapTransactionInfo(txid: txid))
    }

    // MARK: - Address Validation

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
            // Non-200 responses may still carry a structured error body with the validation message.
            if case HTTPClientError.statusCode(let response) = error,
               let body = try? JSONDecoder().decode(MayaSwapQuote.self, from: response.data) {
                return body.error
            }
            DSLogger.log("Maya: Address validation request failed: \(error)")
            return NSLocalizedString("Address validation unavailable — please check your connection", comment: "Maya")
        }
    }
}

// MARK: - Inbound Address Model

struct MayaInboundAddress: Decodable {
    let chain: String
    let halted: Bool
    let address: String?
    let chainLpActionsPaused: Bool?
    let chainTradingPaused: Bool?
    let dustThreshold: String?
    let gasRate: String?
    let gasRateUnits: String?
    let globalTradingPaused: Bool?
    let outboundFee: String?
    let outboundTxSize: String?
    let pubKey: String?

    enum CodingKeys: String, CodingKey {
        case chain
        case halted
        case address
        case chainLpActionsPaused = "chain_lp_actions_paused"
        case chainTradingPaused = "chain_trading_paused"
        case dustThreshold = "dust_threshold"
        case gasRate = "gas_rate"
        case gasRateUnits = "gas_rate_units"
        case globalTradingPaused = "global_trading_paused"
        case outboundFee = "outbound_fee"
        case outboundTxSize = "outbound_tx_size"
        case pubKey = "pub_key"
    }
}

// MARK: - Quote Models

struct MayaSwapQuote: Decodable {
    let error: String?
    let expectedAmountOut: String?
    let dustThreshold: String?
    let expiry: Int64?
    let fees: MayaSwapFees?
    let inboundAddress: String?
    let inboundConfirmationBlocks: Int?
    let inboundConfirmationSeconds: Int?
    let memo: String?
    let notes: String?
    let outboundDelayBlocks: Int?
    let outboundDelaySeconds: Int?
    let recommendedMinAmountIn: String?
    let slippageBps: Int?
    let warning: String?
    let routeId: String?
    let routeProviders: [String]?
    let executionNetwork: String?

    enum CodingKeys: String, CodingKey {
        case error
        case expectedAmountOut = "expected_amount_out"
        case dustThreshold = "dust_threshold"
        case expiry
        case fees
        case inboundAddress = "inbound_address"
        case inboundConfirmationBlocks = "inbound_confirmation_blocks"
        case inboundConfirmationSeconds = "inbound_confirmation_seconds"
        case memo
        case notes
        case outboundDelayBlocks = "outbound_delay_blocks"
        case outboundDelaySeconds = "outbound_delay_seconds"
        case recommendedMinAmountIn = "recommended_min_amount_in"
        case slippageBps = "slippage_bps"
        case warning
        case routeId
        case routeProviders
        case executionNetwork
    }
}

struct MayaSwapFees: Decodable {
    let affiliate: String?
    let asset: String?
    let liquidity: String?
    let outbound: String?
    let slippageBps: Int?
    let total: String?
    let totalBps: Int?

    enum CodingKeys: String, CodingKey {
        case affiliate
        case asset
        case liquidity
        case outbound
        case slippageBps = "slippage_bps"
        case total
        case totalBps = "total_bps"
    }
}

// MARK: - Transaction Tracking Models

struct MayaSwapTransactionInfo: Decodable {
    let observedTx: MayaObservedTx?
    let keysignMetric: MayaKeysignMetric?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case observedTx = "observed_tx"
        case keysignMetric = "keysign_metric"
        case error
    }
}

struct MayaObservedTx: Decodable {
    let transaction: MayaObservedTransaction?
    let status: String?
    let outHashes: [String]?
    let blockHeight: Int?
    let signers: [String]?
    let observedPubKey: String?
    let finaliseHeight: Int?

    enum CodingKeys: String, CodingKey {
        case transaction = "tx"
        case status
        case outHashes = "out_hashes"
        case blockHeight = "block_height"
        case signers
        case observedPubKey = "observed_pub_key"
        case finaliseHeight = "finalise_height"
    }
}

struct MayaObservedTransaction: Decodable {
    let id: String?
    let chain: String?
    let fromAddress: String?
    let toAddress: String?
    let coins: [MayaCoinAmount]?
    let gas: [MayaCoinAmount]?
    let memo: String?

    enum CodingKeys: String, CodingKey {
        case id
        case chain
        case fromAddress = "from_address"
        case toAddress = "to_address"
        case coins
        case gas
        case memo
    }
}

struct MayaCoinAmount: Decodable {
    let asset: String?
    let amount: String?
}

struct MayaKeysignMetric: Decodable {
    let txId: String?
    // The API may return node TSS times as either Double or Int depending on the node version.
    let nodeTssTimes: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case txId = "tx_id"
        case nodeTssTimes = "node_tss_times"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        txId = try container.decodeIfPresent(String.self, forKey: .txId)

        if let asDouble = try? container.decodeIfPresent([String: Double].self, forKey: .nodeTssTimes) {
            nodeTssTimes = asDouble
        } else if let asInt = try? container.decodeIfPresent([String: Int].self, forKey: .nodeTssTimes) {
            nodeTssTimes = asInt.mapValues { Double($0) }
        } else {
            nodeTssTimes = nil
        }
    }
}
