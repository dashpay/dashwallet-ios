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

    // MARK: - Classification Cache (Prompt 03)

    /// Maya-only asset identifiers (uppercased): routed by MAYACHAIN but not by NEAR.
    private var mayaOnlyAssets: Set<String> = []
    /// NEAR-only asset identifiers (uppercased): routed by NEAR but not by MAYACHAIN.
    private var nearOnlyAssets: Set<String> = []
    /// "both" identifiers: routed by both MAYACHAIN and NEAR.
    private var bothAssets: Set<String> = []
    /// Whether the classification has been attempted for this session (built or failed).
    private var classificationBuilt = false
    /// Whether the last classification attempt succeeded and produced a non-empty split.
    /// Only true when `buildClassification()` ran without errors AND emitted non-empty sets.
    /// The Buy filter is gated on this — not on `classificationBuilt` — so a failed or
    /// empty classification causes Buy to surface an error rather than silently showing everything.
    private var classificationUsable = false
    /// Identifier (uppercased) → logoURI, populated from both Maya and NEAR token lists.
    private var logoURIByIdentifier: [String: String] = [:]

    private var isCacheValid: Bool {
        guard let cachedAt = poolsCachedAt else { return false }
        return Date().timeIntervalSince(cachedAt) < cacheMaxAge
    }

    // MARK: - SwapProvider

    func fetchPools() async throws -> [MayaPool] {
        try await fetchPools(direction: .sell)
    }

    func fetchPools(direction: SwapDirection) async throws -> [MayaPool] {
        if isCacheValid && !cachedPools.isEmpty {
            if !classificationBuilt { await buildClassification() }
            return try await filteredPools(cachedPools, for: direction)
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

        // 5. Build Maya/NEAR classification alongside the pool fetch.
        await buildClassification()

        return try await filteredPools(pools, for: direction)
    }

    /// Filters pools by direction.
    /// Buy is **fail-closed**: if classification is not usable after one retry, throws an error
    /// so `SelectCoinViewModel` shows its error/retry state rather than an unfiltered list.
    /// Sell is always unaffected — all pools are returned regardless of classification state.
    private func filteredPools(_ pools: [MayaPool], for direction: SwapDirection) async throws -> [MayaPool] {
        guard direction == .buy else { return pools }

        if !classificationUsable {
            await buildClassification()
        }

        guard classificationUsable else {
            throw NSError(
                domain: "SwapKit",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(
                    "Could not load Buy Dash options — please check your connection and try again",
                    comment: "SwapKit"
                )]
            )
        }

        // Fail closed: include only assets explicitly buyable via NEAR ("nearOnly" or "both").
        // An asset missing from both token lists has no buy route and must not leak into Buy.
        return pools.filter {
            let key = $0.asset.uppercased()
            return nearOnlyAssets.contains(key) || bothAssets.contains(key)
        }
    }

    func networkLabels(for pools: [MayaPool]) async -> [String: String] {
        if !classificationBuilt { await buildClassification() }
        var result: [String: String] = [:]
        for pool in pools {
            let key = pool.asset.uppercased()
            if mayaOnlyAssets.contains(key) {
                result[key] = RouteProvider.maya.shortLabel
            } else if nearOnlyAssets.contains(key) {
                result[key] = RouteProvider.near.shortLabel
            } else if bothAssets.contains(key) {
                result[key] = RouteProvider.multiple.shortLabel
            }
        }
        return result
    }

    func haltedAssets(from inboundAddresses: [MayaInboundAddress], pools: [MayaPool]) async -> Set<String> {
        if !classificationBuilt { await buildClassification() }
        let haltedChains = Set(inboundAddresses.filter { $0.halted }.map { $0.chain.uppercased() })
        guard !haltedChains.isEmpty else { return [] }
        // Only mayaOnly assets are halted when the Maya chain is halted.
        // Assets routed via NEAR ("both" or "nearOnly") remain available.
        var halted = Set<String>()
        for asset in mayaOnlyAssets {
            let chain = asset.components(separatedBy: ".").first ?? ""
            if haltedChains.contains(chain) {
                halted.insert(asset)
            }
        }
        return halted
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

    // MARK: - Private: Classification

    /// Builds Maya/NEAR asset classification.
    /// `classificationBuilt` is set to true after the first attempt (success or failure) to
    /// prevent redundant retries in Sell/label flows. `classificationUsable` is only set true
    /// when the fetch succeeded AND produced non-empty sets — the Buy filter is gated on this.
    private func buildClassification() async {
        classificationBuilt = true
        do {
            async let mayaRequest = SwapKitAPIService.shared.tokens(provider: SwapKitConstants.providerMaya)
            async let nearRequest = SwapKitAPIService.shared.tokens(provider: SwapKitConstants.providerNear)
            let (mayaTokens, nearTokens) = (try await mayaRequest, try await nearRequest)

            let mayaIds = Set(mayaTokens.map { $0.identifier.uppercased() })
            let nearIds = Set(nearTokens.map { $0.identifier.uppercased() })

            let newMayaOnly = mayaIds.subtracting(nearIds)
            let newNearOnly = nearIds.subtracting(mayaIds)
            let newBoth = mayaIds.intersection(nearIds)

            // Only trust classification when it produces a non-trivial split.
            // An empty result (network error, bad decode, empty response) is indistinguishable
            // from "everything is both", which would wrongly pass all coins through Buy filter.
            guard !mayaIds.isEmpty || !nearIds.isEmpty else {
                DSLogger.log("SwapKit: classification produced empty token lists — marking unusable")
                classificationUsable = false
                // Drop any prior (now-stale) classification so networkLabels/haltedAssets,
                // which skip rebuilding while classificationBuilt is true, can't render stale state.
                clearClassification()
                return
            }

            mayaOnlyAssets = newMayaOnly
            nearOnlyAssets = newNearOnly
            bothAssets = newBoth
            classificationUsable = true

            // Build identifier → logoURI lookup. Maya takes priority; NEAR fills gaps.
            var logos: [String: String] = [:]
            for token in mayaTokens {
                if let uri = token.logoURI { logos[token.identifier.uppercased()] = uri }
            }
            for token in nearTokens {
                let key = token.identifier.uppercased()
                if logos[key] == nil, let uri = token.logoURI { logos[key] = uri }
            }
            logoURIByIdentifier = logos

            DSLogger.log("SwapKit: classification built — mayaOnly=\(mayaOnlyAssets.count) nearOnly=\(nearOnlyAssets.count) both=\(bothAssets.count)")
        } catch {
            classificationUsable = false
            clearClassification()
            DSLogger.log("SwapKit: classification fetch failed: \(error) — Buy will show error state")
        }
    }

    /// Drops the cached Maya/NEAR classification so stale labels/halted state aren't rendered
    /// after a failed or empty refresh (callers gate on `classificationBuilt`, which stays true).
    private func clearClassification() {
        mayaOnlyAssets = []
        nearOnlyAssets = []
        bothAssets = []
    }

    func logoURL(for mayaAsset: String) -> URL? {
        guard let s = logoURIByIdentifier[mayaAsset.uppercased()], let url = URL(string: s) else { return nil }
        return url
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
