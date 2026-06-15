//
//  SwapKitSwapProvider.swift
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

/// `SwapProvider` backed by `SwapKitAPIService`.
///
/// Strategy mirrors Android's `SwapKitApiAggregator`:
/// - Pool/price data comes from SwapKit `/price` (batch USD lookup) rather than Midgard
///   stable-pool arithmetic — AC#3 "improve price retrieval".
/// - Best route is RECOMMENDED → CHEAPEST → first from `/v3/quote` which aggregates
///   MAYACHAIN, NEAR, Chainflip, etc. — AC#4 "choose best price (Maya vs NEAR)".
/// - The DASH tx is still built locally from `vaultAddress + memo` — no PSBT parsing.
final class SwapKitSwapProvider: SwapProvider {
    var displayName: String { "SwapKit" }
    var usesGenericFeeLabel: Bool { true }
    var buildsSwapKitDeposit: Bool { true }

    // MARK: - Cache

    private var cachedPools: [MayaPool] = []
    private var poolsCachedAt: Date?
    // Asset identifier → USD price, seeded during fetchPools.
    private var usdPriceCache: [String: Double] = [:]
    private let cacheMaxAge: TimeInterval = 60

    private var isCacheValid: Bool {
        guard let cachedAt = poolsCachedAt else { return false }
        return Date().timeIntervalSince(cachedAt) < cacheMaxAge
    }

    // MARK: - SwapProvider

    func fetchPools() async throws -> [MayaPool] {
        if isCacheValid && !cachedPools.isEmpty {
            return cachedPools
        }

        // 1. Discover reachable buy-assets from DASH.
        let reachable = try await SwapKitAPIService.shared.swapTo(sellAsset: SwapKitConstants.dashAsset)

        // Add DASH itself so the convert screen can look up DASH's USD price for DASH↔fiat ratio.
        var seenIdentifiers = Set<String>()
        let identifiers = (reachable + [SwapKitConstants.dashAsset]).filter {
            seenIdentifiers.insert($0.uppercased()).inserted
        }

        // 2. Batch price fetch — one call for all assets (AC#3).
        let priceItems = (try? await SwapKitAPIService.shared.prices(identifiers: identifiers)) ?? []
        let priceMap = Dictionary(
            priceItems.compactMap { item -> (String, Double)? in
                guard let price = item.priceUsd, price > 0 else { return nil }
                return (item.identifier.uppercased(), price)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // 3. Seed the USD price cache for currency-switch re-conversion without re-fetching.
        usdPriceCache = priceMap

        // 4. Map to MayaPool — `status = "available"` (lowercase) because `isAvailable` checks that.
        let pools = identifiers.map { identifier -> MayaPool in
            let priceUsd = priceMap[identifier.uppercased()] ?? 0.0
            return MayaPool(
                asset: identifier,
                status: "available",
                assetPriceUSD: priceUsd > 0 ? String(priceUsd) : "0"
            )
        }

        cachedPools = pools
        poolsCachedAt = Date()
        return pools
    }

    func fetchInboundAddresses() async throws -> [MayaInboundAddress] {
        // SwapKit returns vault address inline per-swap; no vault-list endpoint.
        // Synthesise one MayaInboundAddress(chain:, halted: false) per reachable chain
        // so SelectCoinViewModel's "halted?" filter works without modification.
        let identifiers: [String]
        if !cachedPools.isEmpty {
            identifiers = cachedPools.map { $0.asset }
        } else {
            identifiers = (try? await SwapKitAPIService.shared.swapTo(sellAsset: SwapKitConstants.dashAsset)) ?? []
        }

        let chains = Set(identifiers.compactMap { $0.components(separatedBy: ".").first })
        return chains.map { chain in
            MayaInboundAddress(
                chain: chain,
                halted: false,
                address: nil,
                chainLpActionsPaused: nil,
                chainTradingPaused: nil,
                dustThreshold: nil,
                gasRate: nil,
                gasRateUnits: nil,
                globalTradingPaused: nil,
                outboundFee: nil,
                outboundTxSize: nil,
                pubKey: nil
            )
        }
    }

    func validateAddress(destination: String, toAsset: String) async -> String? {
        let request = SwapKitQuoteRequest(
            sellAsset: SwapKitConstants.dashAsset,
            buyAsset: toAsset,
            sellAmount: "1",  // nominal — only the address format is being validated
            slippage: SwapKitConstants.defaultSlippagePercent,
            sourceAddress: nil,
            destinationAddress: destination,
            providers: nil,
            affiliateFee: nil
        )
        do {
            let response = try await SwapKitAPIService.shared.quote(request)
            return response.error
        } catch {
            DSLogger.log("SwapKit: address validation request failed: \(error)")
            return NSLocalizedString("Address validation unavailable — please check your connection", comment: "SwapKit")
        }
    }

    func fetchIndicativeQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        let quoteResponse = try await fetchQuoteResponse(
            dashSatoshis: dashSatoshis,
            toAsset: toAsset,
            destination: destination
        )

        if let err = quoteResponse.error {
            return errorResult(err)
        }

        guard let best = bestRoute(from: quoteResponse.routes ?? []) else {
            let msg = quoteResponse.providerErrors?.first?.message
                ?? NSLocalizedString("No route available", comment: "SwapKit")
            return errorResult(msg)
        }

        return SwapQuoteResult(
            error: nil,
            expectedAmountOut: humanToBaseUnits(best.expectedBuyAmount),
            fees: nil,
            inboundAddress: nil,
            memo: nil,
            executionNetwork: prettifyProviders(best.providers)
        )
    }

    /// Pick the best SwapKit route and build the swap.
    func fetchQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        let quoteResponse = try await fetchQuoteResponse(
            dashSatoshis: dashSatoshis,
            toAsset: toAsset,
            destination: destination
        )

        if let err = quoteResponse.error {
            return errorResult(err)
        }

        // Step 2: pick RECOMMENDED → CHEAPEST → first (mirrors Android bestRoute()).
        guard let best = bestRoute(from: quoteResponse.routes ?? []) else {
            let msg = quoteResponse.providerErrors?.first?.message
                ?? NSLocalizedString("No route available", comment: "SwapKit")
            return errorResult(msg)
        }

        // Step 3: build swap — get vault address + memo.
        // sourceAddress must be a real wallet address for SwapKit's format check and
        // so any SwapKit refund is returned to this wallet.
        let sourceAddress = walletSourceAddress()
        let swapRequest = SwapKitSwapRequest(
            routeId: best.routeId,
            sourceAddress: sourceAddress,
            destinationAddress: destination,
            disableBalanceCheck: true,  // required on UTXO chains
            disableBuildTx: true,       // we build the DASH tx locally from vault+memo
            overrideSlippage: nil
        )
        let swapResponse: SwapKitSwapResponse
        do {
            swapResponse = try await SwapKitAPIService.shared.swap(swapRequest)
        } catch {
            if let apiError = decodeSwapError(from: error) {
                return errorResult(apiError)
            }
            throw error
        }

        if let err = swapResponse.error {
            let detail = swapResponse.message.map { ": \($0)" } ?? ""
            return errorResult("\(err)\(detail)")
        }

        guard let vaultAddress = swapResponse.targetAddress ?? swapResponse.inboundAddress else {
            return errorResult(NSLocalizedString("No vault address returned by SwapKit", comment: "SwapKit"))
        }

        // Step 4: map to neutral result.
        let expectedOut = humanToBaseUnits(swapResponse.expectedBuyAmount ?? best.expectedBuyAmount)
        let fees = swapResponse.fees ?? best.fees ?? []
        let expectedOutTarget = Decimal(string: swapResponse.expectedBuyAmount ?? best.expectedBuyAmount) ?? 0
        let sellDash = Decimal(dashSatoshis) / Decimal(100_000_000)
        let targetPerDash = sellDash > 0 ? expectedOutTarget / sellDash : 0
        let feeTarget = totalFeeInTargetUnits(fees: fees, targetAsset: toAsset, targetPerDash: targetPerDash)
        let feeBaseUnits = decimalToBaseUnits(feeTarget)
        // AC#5: executionNetwork surfaces the winning provider(s).
        let executionNetwork = prettifyProviders(best.providers)

        return SwapQuoteResult(
            error: nil,
            expectedAmountOut: expectedOut,
            fees: SwapFeeResult(total: feeBaseUnits, outbound: feeBaseUnits),
            inboundAddress: vaultAddress,
            memo: swapResponse.memo,
            executionNetwork: executionNetwork
        )
    }

    func fetchSwapStatus(txid: String, depositAddress: String?) async throws -> SwapStatusResult {
        do {
            let request: SwapKitTrackRequest
            if let depositAddress, !depositAddress.isEmpty {
                request = SwapKitTrackRequest(hash: nil, chainId: nil, depositAddress: depositAddress)
            } else {
                request = SwapKitTrackRequest(hash: txid, chainId: "dash", depositAddress: nil)
            }
            let response = try await SwapKitAPIService.shared.track(request)
            return mapTrackResponse(response)
        } catch {
            // Non-fatal; return not-yet-observed so polling continues.
            DSLogger.log("SwapKit: track request failed (deposit=\(depositAddress ?? "nil")): \(error)")
            return SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil)
        }
    }

    func trackerURL(for _: String, depositAddress _: String?) -> URL? {
        // The hosted tracker URL verified for `?hash=` 500s on NEAR-routed swaps, and this
        // change intentionally does not guess a `depositAddress` query form without proof.
        // Hide the link until a working hosted tracker format is confirmed.
        nil
    }

    // MARK: - Private: Route Selection

    private func bestRoute(from routes: [SwapKitRoute]) -> SwapKitRoute? {
        if routes.isEmpty { return nil }
        return routes.first { $0.meta?.tags?.contains("RECOMMENDED") == true }
            ?? routes.first { $0.meta?.tags?.contains("CHEAPEST") == true }
            ?? routes.first
    }

    private func fetchQuoteResponse(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapKitQuoteResponse {
        let sellAmount = baseUnitsToHuman(dashSatoshis)
        let quoteRequest = SwapKitQuoteRequest(
            sellAsset: SwapKitConstants.dashAsset,
            buyAsset: toAsset,
            sellAmount: sellAmount,
            slippage: SwapKitConstants.defaultSlippagePercent,
            sourceAddress: nil,
            destinationAddress: destination,
            providers: nil,
            affiliateFee: nil
        )

        do {
            return try await SwapKitAPIService.shared.quote(quoteRequest)
        } catch {
            if let apiError = decodeQuoteError(from: error) {
                return SwapKitQuoteResponse(
                    quoteId: nil,
                    routes: nil,
                    providerErrors: nil,
                    error: apiError,
                    message: nil
                )
            }
            throw error
        }
    }

    private func decodeQuoteError(from error: Error) -> String? {
        guard case HTTPClientError.statusCode(let response) = error,
              let body = try? JSONDecoder().decode(SwapKitQuoteResponse.self, from: response.data)
        else {
            return nil
        }

        return body.message ?? body.error ?? body.providerErrors?.first?.message
    }

    private func decodeSwapError(from error: Error) -> String? {
        guard case HTTPClientError.statusCode(let response) = error,
              let body = try? JSONDecoder().decode(SwapKitSwapResponse.self, from: response.data)
        else {
            return nil
        }

        guard let code = body.error, !code.isEmpty else {
            return body.message
        }

        if let message = body.message, !message.isEmpty {
            return "\(code): \(message)"
        }

        return code
    }

    // MARK: - Private: Amount Conversion

    private func baseUnitsToHuman(_ satoshis: Int64) -> String {
        // Divide by 1e8 with 8 decimal places, plain string — e.g. 10_000_000 → "0.10000000"
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 8,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let result = NSDecimalNumber(value: satoshis)
            .dividing(by: NSDecimalNumber(value: 100_000_000), withBehavior: handler)
        return result.stringValue
    }

    private func humanToBaseUnits(_ human: String?) -> String {
        guard let human, var value = Decimal(string: human), value > 0 else { return "0" }
        value *= Decimal(100_000_000)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value.description
    }

    private func decimalToBaseUnits(_ value: Decimal) -> String {
        guard value > 0 else { return "0" }
        var scaled = value * Decimal(100_000_000)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value.description
    }

    /// Total SwapKit fee, summed across categories, expressed in the target asset.
    /// Mirrors Android's total fee summation, but converts DASH legs into target units
    /// because the iOS order preview renders fees in the purchased asset.
    private func totalFeeInTargetUnits(
        fees: [SwapKitFee],
        targetAsset: String,
        targetPerDash: Decimal
    ) -> Decimal {
        let targetUpper = targetAsset.uppercased()
        let targetChain = targetUpper.components(separatedBy: ".").first ?? ""
        var total: Decimal = 0

        for fee in fees {
            guard let amountString = fee.amount,
                  let amount = Decimal(string: amountString),
                  amount > 0
            else {
                continue
            }

            let chain = fee.chain?.uppercased()
            let asset = fee.asset?.uppercased()

            if chain == targetChain || asset == targetUpper {
                total += amount
            } else if chain == "DASH" || (asset?.contains("DASH") ?? false) {
                total += amount * targetPerDash
            } else {
                DSLogger.log("SwapKit fee skipped: type=\(fee.type ?? "?") asset=\(fee.asset ?? "?") chain=\(fee.chain ?? "?")")
            }
        }

        return total
    }

    // MARK: - Private: Provider Display

    private func prettifyProviders(_ providers: [String]) -> String {
        let labels = providers.map { p -> String in
            switch p.uppercased() {
            case "MAYACHAIN", "MAYACHAIN_STREAMING": return "Maya"
            case "THORCHAIN", "THORCHAIN_STREAMING": return "THORChain"
            case "NEAR", "NEAR_INTENTS", "NEAR-INTENTS": return "NEAR"
            case "CHAINFLIP", "CHAINFLIP_STREAMING": return "Chainflip"
            default: return p
            }
        }
        var uniqueLabels = [String]()
        for label in labels where !uniqueLabels.contains(label) {
            uniqueLabels.append(label)
        }
        return uniqueLabels.joined(separator: ", ")
    }

    // MARK: - Private: Track Status Mapping

    private func mapTrackResponse(_ response: SwapKitTrackResponse) -> SwapStatusResult {
        switch response.status?.lowercased() {
        case "not_started", nil:
            // SwapKit hasn't seen the inbound DASH tx yet — keep polling.
            return SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil)

        case "pending":
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "pending", outHashes: nil)

        case "swapping":
            // SwapKit is actively routing the swap (intermediate state between pending and completed).
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "pending", outHashes: nil)

        case "completed":
            let outHashes = extractOutHashes(from: response)
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "done", outHashes: outHashes)

        case "refunded":
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "refunded", outHashes: nil)

        case "failed", "unknown":
            // Map to "refunded" so the polling loop drives swapStatus = .failed(reason:)
            // via the existing .refunded path. Conservative: no new state machine needed.
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "refunded", outHashes: nil)

        default:
            // Prefer "still pending" over a wrong terminal state for any future statuses.
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "pending", outHashes: nil)
        }
    }

    private func extractOutHashes(from response: SwapKitTrackResponse) -> [String] {
        // Prefer outbound leg hashes. Deposit-address tracking can include the inbound DASH
        // leg alongside the destination chain leg(s); filter DASH out first.
        let legs = response.legs ?? []
        let outboundHashes = legs.compactMap { leg -> String? in
            guard let hash = leg.hash, !hash.isEmpty else { return nil }
            if leg.chainId?.lowercased() == "dash" { return nil }
            return hash
        }
        if !outboundHashes.isEmpty { return outboundHashes }

        let legHashes = legs.compactMap(\.hash)
        if !legHashes.isEmpty { return legHashes }
        // No legs — fall back to the top-level response hash (single-hop DASH source).
        return response.hash.map { [$0] } ?? []
    }

    // MARK: - Private: Wallet

    private func walletSourceAddress() -> String {
        // Current receive address is always valid for SwapKit's format check.
        // Any SwapKit refund will be returned here.
        DWEnvironment.sharedInstance().currentAccount.receiveAddress ?? ""
    }

    // MARK: - Private: Helpers

    private func errorResult(_ message: String) -> SwapQuoteResult {
        SwapQuoteResult(error: message, expectedAmountOut: nil, fees: nil, inboundAddress: nil, memo: nil, executionNetwork: nil)
    }
}
