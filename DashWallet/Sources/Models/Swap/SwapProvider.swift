//
//  SwapProvider.swift
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

// MARK: - Result types

/// Neutral fee summary from a swap quote — only the fields the UI renders.
struct SwapFeeResult {
    let total: String?
    let outbound: String?
}

/// Neutral quote result carrying only the fields the UI reads.
/// `MayaSwapProvider` maps `MayaSwapQuote` into this. Future providers map their own types.
struct SwapQuoteResult {
    let error: String?
    /// Expected output in 1e8 base units (same normalisation the Maya flow uses throughout).
    let expectedAmountOut: String?
    let fees: SwapFeeResult?
    /// Vault / deposit address to send DASH to.
    let inboundAddress: String?
    /// OP_RETURN memo for the Dash tx.
    let memo: String?
    /// Human-readable label surfaced in the order-preview as the execution network (AC#5).
    let executionNetwork: String?
}

/// Neutral status result for swap tracking.
/// `isObserved` is true once the provider has seen the inbound DASH tx.
struct SwapStatusResult {
    let error: String?
    /// Whether the provider has observed the swap (Maya: observedTx != nil; SwapKit: status != not_started).
    let isObserved: Bool
    /// Normalised status string: "done" / "refunded" / "aborted" / "pending" or nil.
    let observedStatus: String?
    let outHashes: [String]?
}

// MARK: - Protocol

// MARK: - Protocol extension helpers

extension SwapProvider {
    /// Optional deep-link to a hosted transaction tracker for this provider.
    /// Returns `nil` for providers without a public tracker (Maya uses its own explorer).
    func trackerURL(for txid: String, depositAddress: String?) -> URL? { nil }

    /// Controls whether the order-preview fee row uses a backend-specific label
    /// (`"Maya fee"`) or a generic one (`"Fee"`).
    var usesGenericFeeLabel: Bool { false }

    /// True when the provider expects the client to build and submit the DASH deposit
    /// transaction locally for SwapKit-style routes.
    var buildsSwapKitDeposit: Bool { false }

    /// Indicative quote used by the amount screen. Providers that do not have a cheaper
    /// quote-only path can fall back to the full quote implementation.
    func fetchIndicativeQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        try await fetchQuote(dashSatoshis: dashSatoshis, toAsset: toAsset, destination: destination)
    }
}

// MARK: - Protocol

/// Backend-agnostic surface for cross-chain DASH swaps.
///
/// The Maya integration and the SwapKit aggregator both conform to this protocol so that
/// view models (SelectCoinViewModel, MayaConvertViewModel, OrderPreviewViewModel) can be
/// wired to either backend without modification.
protocol SwapProvider {
    /// Human-readable label shown as the execution network (e.g. "Maya", "MAYACHAIN").
    var displayName: String { get }
    var usesGenericFeeLabel: Bool { get }
    var buildsSwapKitDeposit: Bool { get }

    func fetchPools() async throws -> [MayaPool]
    func fetchInboundAddresses() async throws -> [MayaInboundAddress]

    /// Returns `nil` if the destination address is valid, otherwise an error string.
    func validateAddress(destination: String, toAsset: String) async -> String?

    /// Quote for a DASH→toAsset swap. `dashSatoshis` is in 1e8 base units.
    func fetchQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult

    /// Indicative quote for the amount screen: expected output + execution network only.
    /// Must not perform heavy swap-build work because it runs on every keystroke.
    func fetchIndicativeQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult

    /// Status lookup for a submitted swap.
    /// Maya: queries by Dash txid via `/tx/{txid}`.
    /// SwapKit: queries via `/track`.
    func fetchSwapStatus(txid: String, depositAddress: String?) async throws -> SwapStatusResult
}
