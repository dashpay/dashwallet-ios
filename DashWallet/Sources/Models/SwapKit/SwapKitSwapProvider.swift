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
///
/// @MainActor ensures all mutable caches (classification sets, routability cache, price cache,
/// etc.) are accessed from a single isolation domain, eliminating concurrent read/write races.
@MainActor
final class SwapKitSwapProvider: SwapProvider {
    private enum Constants {
        static let maxMemoBytes = 80
    }

    nonisolated var displayName: String { "SwapKit" }
    nonisolated var usesGenericFeeLabel: Bool { true }
    nonisolated var buildsSwapKitDeposit: Bool { true }
    var onBuyRoutabilityChanged: (() -> Void)?

    // MARK: - Cache

    private var cachedPools: [SwapPool] = []
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
    /// Cached NEAR→DASH buy routability decisions for buy-list pruning.
    private var buyRoutabilityCache: [String: (value: BuyRoutability, checkedAt: Date)] = [:]
    /// Prevents duplicate probes while a candidate is already being checked.
    private var buyRoutabilityInFlight: Set<String> = []
    /// Buy routability cache TTL, mirroring Android's preferred-route cache cadence.
    private let buyRoutabilityTTL: TimeInterval = 600
    /// Small batch size to keep verification bounded without spamming the quote endpoint.
    private let buyRoutabilityProbeBatchSize: Int = 8

    private enum BuyRoutability {
        case routable
        case notRoutable
    }

    private var isCacheValid: Bool {
        guard let cachedAt = poolsCachedAt else { return false }
        return Date().timeIntervalSince(cachedAt) < cacheMaxAge
    }

    // MARK: - SwapProvider

    func fetchPools() async throws -> [SwapPool] {
        try await fetchPools(direction: .sell)
    }

    func fetchPools(direction: SwapDirection) async throws -> [SwapPool] {
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

        // 4. Map to SwapPool — `status = "available"` (lowercase) because `isAvailable` checks that.
        let pools = identifiers.map { identifier -> SwapPool in
            let priceUsd = priceMap[identifier.uppercased()] ?? 0.0
            return SwapPool(
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
    private func filteredPools(_ pools: [SwapPool], for direction: SwapDirection) async throws -> [SwapPool] {
        guard direction == .buy else {
            if !classificationBuilt { await buildClassification() }
            return pools
        }

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

        // Cheap pre-filter: only assets that classification says can reach NEAR.
        let candidates = pools.filter {
            let key = $0.asset.uppercased()
            return nearOnlyAssets.contains(key) || bothAssets.contains(key)
        }

        // Pass original-case identifiers — uppercased contract addresses differ from what
        // the quote endpoint accepts, causing all contract-token probes to error → never pruned.
        // Uppercasing is kept only for the Set-membership keys (nearOnlyAssets / bothAssets above).
        scheduleBuyRoutabilityVerification(for: candidates.map { $0.asset })

        // Optimistic filter: show until a probe conclusively proves the asset cannot route
        // NEAR→DASH — which now means NEAR itself reporting a no-route in `providerErrors`, the
        // only unambiguous negative (see `routability(from:)`). This keeps first-open responsive
        // while background verification prunes.
        return candidates.filter { pool in
            cachedBuyRoutability(for: pool.asset) != .notRoutable
        }
    }

    func networkLabels(for pools: [SwapPool]) async -> [String: String] {
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

    func haltedAssets(from inboundAddresses: [SwapInboundAddress], pools: [SwapPool]) async -> Set<String> {
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

    func fetchInboundAddresses() async throws -> [SwapInboundAddress] {
        // SwapKit returns vault address inline per-swap; no vault-list endpoint.
        // Synthesise one SwapInboundAddress(chain:, halted: false) per reachable chain
        // so SelectCoinViewModel's "halted?" filter works without modification.
        let identifiers: [String]
        if !cachedPools.isEmpty {
            identifiers = cachedPools.map { $0.asset }
        } else {
            identifiers = (try? await SwapKitAPIService.shared.swapTo(sellAsset: SwapKitConstants.dashAsset)) ?? []
        }

        let chains = Set(identifiers.compactMap { $0.components(separatedBy: ".").first })
        return chains.map { chain in
            SwapInboundAddress(
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
            DWLogger.log("SwapKit: address validation request failed: \(error)")
            return NSLocalizedString("Address validation unavailable — please check your connection", comment: "SwapKit")
        }
    }

    func createBuyOrder(
        sellAsset: String,
        sellAmount: String,
        destination: String,
        refundAddress: String
    ) async throws -> BuyOrder {
        let route = try await requestBuyRoute(
            sellAsset: sellAsset,
            sellAmount: sellAmount,
            destination: destination,
            refundAddress: refundAddress
        )

        let swapRequest = SwapKitSwapRequest(
            routeId: route.routeId,
            sourceAddress: refundAddress,
            destinationAddress: destination,
            disableBalanceCheck: true,
            disableBuildTx: true,
            overrideSlippage: nil
        )

        let swapResponse: SwapKitSwapResponse
        do {
            swapResponse = try await SwapKitAPIService.shared.swap(swapRequest)
        } catch {
            if let apiError = decodeSwapError(from: error) {
                throw NSError(domain: "SwapKit", code: 1, userInfo: [NSLocalizedDescriptionKey: apiError])
            }
            throw error
        }

        if let err = swapResponse.error {
            let detail = swapResponse.message.map { ": \($0)" } ?? ""
            throw NSError(domain: "SwapKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(err)\(detail)"])
        }

        guard let depositAddress = swapResponse.inboundAddress ?? swapResponse.targetAddress, !depositAddress.isEmpty else {
            throw NSError(
                domain: "SwapKit",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("No deposit address returned by SwapKit", comment: "SwapKit")]
            )
        }

        let expectedDashAmount = Decimal(string: swapResponse.expectedBuyAmount ?? route.expectedBuyAmount) ?? 0
        return BuyOrder(
            depositAddress: depositAddress,
            memo: swapResponse.memo,
            expectedDashAmount: expectedDashAmount,
            sellAsset: sellAsset,
            sellAmount: sellAmount
        )
    }

    func validateBuyOrder(
        sellAsset: String,
        sellAmount: String,
        refundAddress: String
    ) async throws {
        guard let destination = walletSourceAddress() else {
            throw Self.walletUnavailableError()
        }
        _ = try await requestBuyRoute(
            sellAsset: sellAsset,
            sellAmount: sellAmount,
            destination: destination,
            refundAddress: refundAddress
        )
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
            let providerError = quoteResponse.providerErrors?.first
            let msg = SwapKitErrorCopy.providerErrorMessage(providerError)
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
            let providerError = quoteResponse.providerErrors?.first
            let msg = SwapKitErrorCopy.providerErrorMessage(providerError)
                ?? NSLocalizedString("No route available", comment: "SwapKit")
            return errorResult(msg)
        }

        // Step 3: build swap — get vault address + memo.
        // sourceAddress must be a real wallet address for SwapKit's format check and
        // so any SwapKit refund is returned to this wallet.
        guard let sourceAddress = walletSourceAddress() else {
            return errorResult(Self.walletUnavailableMessage)
        }
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

        let memo = swapResponse.memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let memo, !memo.isEmpty, memo.utf8.count > Constants.maxMemoBytes {
            DWLogger.log("SwapKit: rejecting over-length memo for \(toAsset) — \(memo.utf8.count) bytes")
            return errorResult(SwapKitErrorCopy.mayaMemoTooLongErrorCode)
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
            memo: memo?.isEmpty == false ? memo : nil,
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
            DWLogger.log("SwapKit: track request failed (deposit=\(depositAddress ?? "nil")): \(error)")
            return SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil)
        }
    }

    nonisolated func trackerURL(for _: String, depositAddress _: String?) -> URL? {
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
            // Union both Maya providers: their token lists differ, and an asset routable only
            // via non-streaming MAYACHAIN would otherwise be classified as un-routable and
            // quoted against NEAR, which cannot route it either.
            async let mayaChainRequest = SwapKitAPIService.shared.tokens(provider: SwapKitConstants.providerMayaChain)
            async let mayaStreamingRequest = SwapKitAPIService.shared.tokens(provider: SwapKitConstants.providerMayaStreaming)
            async let nearRequest = SwapKitAPIService.shared.tokens(provider: SwapKitConstants.providerNear)
            let (mayaChainTokens, mayaStreamingTokens, nearTokens) =
                (try await mayaChainRequest, try await mayaStreamingRequest, try await nearRequest)

            let mayaIds = Set(mayaChainTokens.map { $0.identifier.uppercased() })
                .union(mayaStreamingTokens.map { $0.identifier.uppercased() })
            let nearIds = Set(nearTokens.map { $0.identifier.uppercased() })

            let newMayaOnly = mayaIds.subtracting(nearIds)
            let newNearOnly = nearIds.subtracting(mayaIds)
            let newBoth = mayaIds.intersection(nearIds)

            // Only trust classification when it produces a non-trivial split.
            // An empty result (network error, bad decode, empty response) is indistinguishable
            // from "everything is both", which would wrongly pass all coins through Buy filter.
            guard !mayaIds.isEmpty || !nearIds.isEmpty else {
                DWLogger.log("SwapKit: classification produced empty token lists — marking unusable")
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
            for token in mayaChainTokens + mayaStreamingTokens {
                if let uri = token.logoURI { logos[token.identifier.uppercased()] = uri }
            }
            for token in nearTokens {
                let key = token.identifier.uppercased()
                if logos[key] == nil, let uri = token.logoURI { logos[key] = uri }
            }
            logoURIByIdentifier = logos

            DWLogger.log("SwapKit: classification built — mayaOnly=\(mayaOnlyAssets.count) nearOnly=\(nearOnlyAssets.count) both=\(bothAssets.count)")
        } catch {
            classificationUsable = false
            clearClassification()
            DWLogger.log("SwapKit: classification fetch failed: \(error) — Buy will show error state")
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
        if !classificationBuilt { await buildClassification() }

        let sellAmount = baseUnitsToHuman(dashSatoshis)
        let quoteRequest = SwapKitQuoteRequest(
            sellAsset: SwapKitConstants.dashAsset,
            buyAsset: toAsset,
            sellAmount: sellAmount,
            slippage: SwapKitConstants.defaultSlippagePercent,
            sourceAddress: nil,
            destinationAddress: destination,
            providers: sellQuoteProviders(for: toAsset),
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

    private func requestBuyRoute(
        sellAsset: String,
        sellAmount: String,
        destination: String,
        refundAddress: String
    ) async throws -> SwapKitRoute {
        let quoteRequest = SwapKitQuoteRequest(
            sellAsset: sellAsset,
            buyAsset: SwapKitConstants.dashAsset,
            sellAmount: sellAmount,
            slippage: SwapKitConstants.defaultSlippagePercent,
            sourceAddress: refundAddress,
            destinationAddress: destination,
            // Buy deposits are built by the counterparty, so OP_RETURN support in the app does
            // not change Buy routing; keep the existing NEAR-only request shape.
            providers: [SwapKitConstants.providerNear],
            affiliateFee: nil
        )

        let quoteResponse: SwapKitQuoteResponse
        do {
            quoteResponse = try await SwapKitAPIService.shared.quote(quoteRequest)
        } catch {
            if let apiError = decodeQuoteError(from: error) {
                throw NSError(domain: "SwapKit", code: 1, userInfo: [NSLocalizedDescriptionKey: apiError])
            }
            throw error
        }

        if let err = quoteResponse.error {
            let detail = quoteResponse.message.map { ": \($0)" } ?? ""
            throw NSError(domain: "SwapKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(err)\(detail)"])
        }

        guard let best = bestRoute(from: quoteResponse.routes ?? []) else {
            let providerError = quoteResponse.providerErrors?.first
            let message = SwapKitErrorCopy.providerErrorMessage(providerError)
                ?? quoteResponse.message
                ?? quoteResponse.error
                ?? NSLocalizedString("No route available", comment: "SwapKit")
            throw NSError(domain: "SwapKit", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        return best
    }

    // MARK: - Private: Buy Routability

    private func scheduleBuyRoutabilityVerification(for assets: [String]) {
        let pending = assets.filter { shouldProbeBuyRoutability(for: $0) }
        guard !pending.isEmpty else { return }

        pending.forEach { buyRoutabilityInFlight.insert($0) }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.verifyBuyRoutability(for: pending)
        }
    }

    private func verifyBuyRoutability(for assets: [String]) async {
        var updatedAny = false

        for chunk in assets.chunked(into: buyRoutabilityProbeBatchSize) {
            let probeResults = await withTaskGroup(of: (String, BuyRoutability?).self) { group -> [(String, BuyRoutability?)] in
                for asset in chunk {
                    let sellAmount = buyProbeSellAmount(for: asset)
                    group.addTask { [sellAmount] in
                        (asset, await Self.probeBuyRoutability(for: asset, sellAmount: sellAmount))
                    }
                }

                var results: [(String, BuyRoutability?)] = []
                results.reserveCapacity(chunk.count)
                for await result in group {
                    results.append(result)
                }
                return results
            }

            // @MainActor class — caches are already on the main actor; no MainActor.run hop needed.
            let now = Date()
            var changed = false
            for (asset, result) in probeResults {
                buyRoutabilityInFlight.remove(asset)
                guard let result else { continue }

                let previous = buyRoutabilityCache[asset]?.value
                buyRoutabilityCache[asset] = (value: result, checkedAt: now)
                if previous != result {
                    changed = true
                }
            }
            updatedAny = updatedAny || changed
        }

        guard updatedAny else { return }
        onBuyRoutabilityChanged?()
    }

    private func shouldProbeBuyRoutability(for asset: String) -> Bool {
        guard cachedBuyRoutability(for: asset) == nil else { return false }
        return !buyRoutabilityInFlight.contains(asset)
    }

    private func cachedBuyRoutability(for asset: String) -> BuyRoutability? {
        guard let entry = buyRoutabilityCache[asset] else { return nil }
        guard Date().timeIntervalSince(entry.checkedAt) < buyRoutabilityTTL else { return nil }
        return entry.value
    }

    private func buyProbeSellAmount(for asset: String) -> String {
        guard let priceUSD = usdPriceCache[asset.uppercased()], priceUSD > 0 else {
            return "1"
        }

        let nominal = Decimal(50) / Decimal(priceUSD)
        return Self.plainDecimalString(nominal, scale: 8)
    }

    private static func probeBuyRoutability(for asset: String, sellAmount: String) async -> BuyRoutability? {
        let request = SwapKitQuoteRequest(
            sellAsset: asset,
            buyAsset: SwapKitConstants.dashAsset,
            sellAmount: sellAmount,
            slippage: SwapKitConstants.defaultSlippagePercent,
            sourceAddress: nil,
            destinationAddress: nil,
            // Buy routability is still about counterparty-built deposits, so keep probing NEAR.
            providers: [SwapKitConstants.providerNear],
            affiliateFee: nil
        )

        do {
            let response = try await SwapKitAPIService.shared.quote(request)
            return routability(from: response)
        } catch {
            if let response = decodedQuoteResponse(from: error) {
                return routability(from: response)
            }
            return nil
        }
    }

    private static func routability(from response: SwapKitQuoteResponse) -> BuyRoutability? {
        if response.routes?.isEmpty == false {
            return .routable
        }

        // Classify on the codes, not the prose: a provider reports its reason in
        // `providerErrors[].errorCode`, and only the code is a stable identifier.
        let providerCode = SwapKitErrorCopy.providerErrorMessage(response.providerErrors?.first)

        guard let providerCode else {
            // A top-level `noRoutesFound` is deliberately NOT treated as proof of unroutability.
            // SwapKit answers with it for an amount far below a route's floor as well as for a
            // pair it cannot carry — measured 2026-08-28, DASH → BTC returned it at 0.01 DASH
            // and quoted a route at 0.3 — and the probe amount is a $50 estimate that falls back
            // to one whole unit when no USD price is cached. Pruning on it would drop a routable
            // asset out of the picker for the whole cache window.
            return nil
        }

        if SwapKitErrorCopy.isBelowMinimum(providerCode) {
            // The probe amount was under this route's floor, which says nothing about whether
            // the asset is routable — the picker must not hide it on this evidence.
            return .routable
        }

        // A provider naming its own no-route is the one conclusive negative: it is answering for
        // the single provider the probe asked about. Anything else it reports (an upstream
        // `apiRequestFailed`, say) leaves the question open.
        return SwapKitErrorCopy.isNoRoute(providerCode) ? .notRoutable : nil
    }

    private static func decodedQuoteResponse(from error: Error) -> SwapKitQuoteResponse? {
        guard case HTTPClientError.statusCode(let response) = error else { return nil }
        return try? JSONDecoder().decode(SwapKitQuoteResponse.self, from: response.data)
    }

    private func decodeQuoteError(from error: Error) -> String? {
        guard case HTTPClientError.statusCode(let response) = error,
              let body = try? JSONDecoder().decode(SwapKitQuoteResponse.self, from: response.data)
        else {
            return nil
        }

        if let code = body.error, !code.isEmpty {
            if let message = body.message, !message.isEmpty {
                return "\(code): \(message)"
            }
            return code
        }

        return SwapKitErrorCopy.providerErrorMessage(body.providerErrors?.first) ?? body.message
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

    /// Best-route selection across the two protocols the classification covers: whatever a
    /// coin is actually routable by is offered, and SwapKit picks. A dual-routable coin is
    /// therefore quoted against NEAR *and* MAYACHAIN, which is what the picker's "Multiple
    /// networks" label promises.
    ///
    /// The list is always explicit — never `nil` — so routing stays confined to NEAR and
    /// MAYACHAIN. Passing no filter would also admit THORChain, Chainflip and every other
    /// SwapKit provider, none of which this classification or the deposit path accounts for.
    ///
    /// Both Maya providers are named because MAYACHAIN and MAYACHAIN_STREAMING are distinct
    /// providers with different token lists.
    ///
    /// Consequence to keep in mind: a MAYACHAIN route can now win for a coin that previously
    /// always deposited memo-less, so the 80-byte memo ceiling and Maya's dust floor apply to
    /// dual-routable coins too. Both guards already run on the fresh pre-commit quote.
    private func sellQuoteProviders(for toAsset: String) -> [String]? {
        guard classificationUsable else {
            return [SwapKitConstants.providerNear]
        }

        let key = toAsset.uppercased()
        if mayaOnlyAssets.contains(key) {
            return SwapKitConstants.mayaProviders
        }
        if bothAssets.contains(key) {
            return [SwapKitConstants.providerNear] + SwapKitConstants.mayaProviders
        }

        return [SwapKitConstants.providerNear]
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

    private static func plainDecimalString(_ value: Decimal, scale: Int) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, scale, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
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
                DWLogger.log("SwapKit fee skipped: type=\(fee.type ?? "?") asset=\(fee.asset ?? "?") chain=\(fee.chain ?? "?")")
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
            // SwapKit is actively routing the swap; surface as "swapping" for per-order status tracking.
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "swapping", outHashes: nil)

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

    /// Current receive address, used for SwapKit's source-address format check and refund
    /// routing. Read from SwiftDashSDK (the frozen DashSync account's receiveAddress is stale
    /// post-migration). Returns `nil` when the wallet isn't bound yet (or FFI failure) — callers
    /// must fail fast rather than send an empty address into the swap request, which would
    /// surface as an opaque provider error.
    private func walletSourceAddress() -> String? {
        guard let address = SwiftDashSDKReceiveAddressReader.receiveAddress(), !address.isEmpty else {
            return nil
        }
        return address
    }

    private static var walletUnavailableMessage: String {
        NSLocalizedString("Your wallet isn’t ready yet. Please try again in a moment.", comment: "SwapKit")
    }

    private static func walletUnavailableError() -> Error {
        NSError(domain: "SwapKit", code: 1, userInfo: [NSLocalizedDescriptionKey: walletUnavailableMessage])
    }

    // MARK: - Private: Helpers

private func errorResult(_ message: String) -> SwapQuoteResult {
        // Every quote/swap failure funnels through here on its way to the UI, which renders a
        // mapped (often generic) string. Log the raw message at the source so a failure is
        // diagnosable from an exported log instead of only from a screenshot.
        DWLogger.log("SwapKit: quote/swap failed — raw: \(message)")
        return SwapQuoteResult(error: message, expectedAmountOut: nil, fees: nil, inboundAddress: nil, memo: nil, executionNetwork: nil)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)

        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }

        return result
    }
}
