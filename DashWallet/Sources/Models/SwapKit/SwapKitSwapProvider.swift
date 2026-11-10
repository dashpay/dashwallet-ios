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

import Combine
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
/// Live per-provider availability (what the picker labels and halts on) lives in
/// `SwapRouteAvailability`; this type supplies it with the static classification and the probes.
///
/// @MainActor ensures all mutable caches (classification sets, price cache, etc.) are accessed
/// from a single isolation domain, eliminating concurrent read/write races.
@MainActor
final class SwapKitSwapProvider: SwapProvider {
    private enum Constants {
        static let maxMemoBytes = 80
    }

    nonisolated var displayName: String { "SwapKit" }
    nonisolated var usesGenericFeeLabel: Bool { true }
    nonisolated var buildsSwapKitDeposit: Bool { true }

    private let routeAvailability: SwapRouteAvailability
    /// The running live-availability refresh per direction, so leaving the picker can stop it.
    private var routeRefreshTasks: [SwapDirection: (id: UUID, task: Task<Void, Never>)] = [:]

    init(routeAvailability: SwapRouteAvailability = .shared) {
        self.routeAvailability = routeAvailability
    }

    /// One event per stored answer that changed something; subscribers batch them.
    var routeAvailabilityChanges: AnyPublisher<SwapDirection, Never> {
        routeAvailability.changes.eraseToAnyPublisher()
    }

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

        // Only assets the classification says NEAR can carry: Buy routes through NEAR alone.
        // Whether NEAR carries them right now is live state — a coin it cannot carry is shown
        // halted (`haltedAssets`), not dropped.
        return pools.filter { !capableProviders(for: $0.asset, direction: .buy).isEmpty }
    }

    /// The label is the set of providers that can carry the coin *now* (live probes over the static
    /// classification): both → "Multiple", one → that provider. A coin no provider can carry gets
    /// no label; `haltedAssets` reports it instead.
    func networkLabels(for pools: [SwapPool], direction: SwapDirection) async -> [String: String] {
        if !classificationBuilt { await buildClassification() }
        var result: [String: String] = [:]
        for pool in pools {
            if let label = RouteProvider.label(forUsable: usableProviders(for: pool.asset, direction: direction)) {
                result[pool.asset.uppercased()] = label.shortLabel
            }
        }
        return result
    }

    /// Coins some provider can ever carry but none can carry now — a halt, or no route at all.
    /// `fetchInboundAddresses` reports no halted chains for SwapKit, so this is its only halt source.
    func haltedAssets(from inboundAddresses: [SwapInboundAddress], pools: [SwapPool], direction: SwapDirection) async -> Set<String> {
        if !classificationBuilt { await buildClassification() }
        var halted = Set<String>()
        for pool in pools {
            let capable = capableProviders(for: pool.asset, direction: direction)
            guard !capable.isEmpty else { continue }
            if routeAvailability.usableProviders(for: pool.asset, capable: capable, direction: direction).isEmpty {
                halted.insert(pool.asset.uppercased())
            }
        }
        return halted
    }

    /// Starts the live probes for the coins the picker shows, in its display order. Returns at once;
    /// answers arrive through `routeAvailabilityChanges`.
    ///
    /// Assets are passed in their original case: an uppercased contract address is not what the
    /// quote endpoint accepts.
    func refreshRouteAvailability(for pools: [SwapPool], direction: SwapDirection) {
        guard classificationUsable, routeRefreshTasks[direction] == nil else { return }
        let assets = pools.map { $0.asset }
        let capability = Dictionary(
            assets.map { ($0.uppercased(), capableProviders(for: $0, direction: direction)) },
            uniquingKeysWith: { first, _ in first }
        )
        let id = UUID()
        let task = Task { [weak self, routeAvailability] in
            await routeAvailability.refresh(
                assets: assets,
                direction: direction,
                capable: { capability[$0.uppercased()] ?? [] },
                probe: { asset, provider, direction in
                    guard let self else { return .unknown }
                    return await self.probeRoute(asset: asset, provider: provider, direction: direction)
                }
            )
            // A newer refresh may have replaced this one after a stop; leave its handle alone.
            if self?.routeRefreshTasks[direction]?.id == id {
                self?.routeRefreshTasks[direction] = nil
            }
        }
        routeRefreshTasks[direction] = (id, task)
    }

    /// Stops the live-availability refresh for `direction`: queued probes are dropped, the one or
    /// two in flight finish. Answers already in keep counting.
    func stopRouteAvailabilityRefresh(direction: SwapDirection) {
        routeRefreshTasks[direction]?.task.cancel()
        routeRefreshTasks[direction] = nil
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

    /// What the address screen does with the nominal quote to the user's address.
    enum AddressCheck: Equatable {
        /// Let the user through; the amount screen quotes the real amount.
        case pass
        /// The request itself was refused (`validation_error`, `invalidDestinationAddress`, …);
        /// the associated value is SwapKit's code for `SwapKitErrorCopy.message(for:coin:)`.
        case refused(String)
        /// No asked provider can carry the coin, and these said no-route — which, to the user's own
        /// address, may be about the address: re-ask them without it before deciding.
        case confirmNoRoute(Set<RouteProvider>)
        /// No asked provider can carry the coin, and none blamed a missing route (all halted).
        case unavailable
    }

    /// Codes that are about the request or the address, not about the route.
    private static let requestCodes: Set<String> = [
        "validation_error", "invalidrequest", "invaliddestinationaddress", "issanctionedaddress",
    ]
    /// Codes SwapKit uses to refuse the coin itself, whatever the provider.
    private static let refusedCoinCodes: Set<String> = ["blacklistasset", "invalidasset"]

    /// Pure decision for `validateAddress`, internal for the tests. `requested` is the providers
    /// the quote named (`addressCheckRequest`), never empty: `sellQuoteProviders` always names NEAR
    /// or Maya.
    static func addressCheck(_ response: SwapKitQuoteResponse, requested: Set<RouteProvider>) -> AddressCheck {
        // Only a route an asked provider carries counts: the swap would not use another one.
        let routed = Set((response.routes ?? []).flatMap { $0.providers }
            .compactMap { RouteProvider(swapKitProvider: $0) })
        if !routed.isDisjoint(with: requested) {
            return .pass
        }

        func code(_ raw: String?) -> String? {
            raw?.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A top-level refusal is about the whole request.
        if let top = code(response.error),
           requestCodes.contains(top.lowercased()) || refusedCoinCodes.contains(top.lowercased()) {
            return .refused(top)
        }

        // A refusal only counts for the SwapKit provider (a Maya flavour, say) that gave it: another
        // one may still accept the request. A refusal from a provider the quote did not ask, from any
        // other provider, or from none named, is ignored. When several refuse, the first in
        // SwapKit's order is shown.
        let errors = response.providerErrors ?? []
        var refusedBy: Set<String> = []
        var firstRefusal: String?
        for error in errors {
            guard let raw = code(error.errorCode),
                  requestCodes.contains(raw.lowercased()) || refusedCoinCodes.contains(raw.lowercased()) else { continue }
            guard let name = error.provider,
                  let provider = RouteProvider(swapKitProvider: name),
                  requested.contains(provider) else { continue }
            refusedBy.insert(name.uppercased())
            firstRefusal = firstRefusal ?? raw
        }

        // The quote asked every usable provider at once; each one is judged on its own answer.
        let states = judgedWithoutRefusals(LiveRouteState.classifyPerProvider(response, requested: requested),
                                           errors: errors, refusedBy: refusedBy)
        if states.values.contains(where: { $0.isUsable }) {
            return .pass
        }
        if let refusal = firstRefusal {
            return .refused(refusal)
        }
        let noRoute = Set(states.filter { $0.value == .noRoute }.map { $0.key })
        return noRoute.isEmpty ? .unavailable : .confirmNoRoute(noRoute)
    }

    /// `states` with each provider whose flavours (SwapKit provider names) are partly in
    /// `refusedBy` judged on the other flavours' errors alone, and left out when every flavour
    /// that spoke refused.
    private static func judgedWithoutRefusals(
        _ states: [RouteProvider: LiveRouteState],
        errors: [SwapKitProviderError],
        refusedBy: Set<String>
    ) -> [RouteProvider: LiveRouteState] {
        var judged = states
        for provider in states.keys {
            let spoke = errors.filter { $0.provider.flatMap { RouteProvider(swapKitProvider: $0) } == provider }
            let rest = spoke.filter { !refusedBy.contains($0.provider?.uppercased() ?? "") }
            guard rest.count < spoke.count else { continue }
            judged[provider] = rest.isEmpty
                ? nil
                : LiveRouteState.classify(SwapKitQuoteResponse(quoteId: nil, routes: nil, providerErrors: rest,
                                                               error: nil, message: nil))
        }
        return judged
    }

    /// A nominal Sell quote to the entered address. Its real use is the last check before the
    /// amount screen that the coin can be swapped right now (`addressCheck` decides).
    ///
    /// The user is stopped when SwapKit refuses the request or the address, or when no asked
    /// provider can carry the coin. Anything inconclusive (an upstream failure, a below-minimum for
    /// the nominal amount) lets them through to the amount screen, which quotes the real amount
    /// and reports what is wrong with it.
    func validateAddress(destination: String, toAsset: String) async -> String? {
        if !classificationBuilt { await buildClassification() }
        let request = addressCheckRequest(destination: destination, toAsset: toAsset)

        let response: SwapKitQuoteResponse
        do {
            response = try await SwapKitAPIService.shared.quote(request)
        } catch {
            // A non-2xx carrying a SwapKit body (404 `noRoutesFound`, 400 `validation_error`) is an
            // answer, not a connection problem.
            guard let decoded = Self.decodedQuoteResponse(from: error) else {
                DWLogger.log("SwapKit: address validation request failed: \(error)")
                return Self.addressCheckFailureMessage(for: error)
            }
            response = decoded
        }

        let requested = Set((request.providers ?? []).compactMap { RouteProvider(swapKitProvider: $0) })
        Self.recordQuoteOutcome(
            response, requested: requested, asset: toAsset, direction: .sell, store: routeAvailability
        )

        let check = Self.addressCheck(response, requested: requested)
        if check != .pass {
            DWLogger.log("SwapKit: address check for \(toAsset) → \(check) — \(response.error ?? SwapKitErrorCopy.providerErrorMessage(response.providerErrors?.first) ?? "no code")")
        }
        let coin = SwapCryptoCurrency.knownCoin(for: toAsset)

        switch check {
        case .pass:
            return nil
        case .refused(let code):
            guard let coin else { return code }
            // On this screen the address is the thing to check; the generic deposit copy for
            // `invalidDestinationAddress` would only say "try again".
            if code.lowercased() == "invaliddestinationaddress" {
                return SwapKitErrorCopy.message(for: "validation_error", coin: coin)
            }
            return SwapKitErrorCopy.message(for: code, coin: coin)
        case .unavailable:
            guard let coin else { return NSLocalizedString("No route available", comment: "SwapKit") }
            return SwapKitErrorCopy.unavailableNowMessage(coin: coin)
        case .confirmNoRoute(let noRouteProviders):
            let reAsked = await Self.reCheckNoRoute(noRouteProviders, asset: toAsset, store: routeAvailability)
            return Self.addressReCheckMessage(reAsked, coin: coin)
        }
    }

    /// The amount of the address quote, and of its re-check without the address.
    nonisolated static let addressCheckAmount = "1"  // one DASH is far above every route floor

    /// The re-check of a no-route on the address screen: the address quote's amount, forced to
    /// `provider`, with no address — so only the address differs from the quote it confirms.
    nonisolated static func addressReCheckRequest(asset: String, provider: RouteProvider) -> SwapKitQuoteRequest {
        probeRequest(asset: asset, provider: provider, direction: .sell, amount: addressCheckAmount)
    }

    /// Asks each of `noRouteProviders` (NEAR, then Maya) again through `quote` at the address
    /// quote's amount without the address: if a provider routes there, the address is what to fix.
    /// Returns each answer as read for the address (`addressReCheckState`); `store` records the
    /// usual classification (`LiveRouteState.classify`). When an answer recorded while the re-check
    /// was asking is newer, the store keeps it and the re-check returns it instead.
    static func reCheckNoRoute(
        _ noRouteProviders: Set<RouteProvider>,
        asset: String,
        store: SwapRouteAvailability,
        quote: (SwapKitQuoteRequest) async -> SwapKitQuoteResponse? = addressReCheckResponse
    ) async -> [LiveRouteState] {
        var reAsked: [LiveRouteState] = []
        for provider in [RouteProvider.near, .maya] where noRouteProviders.contains(provider) {
            var reCheck = LiveRouteState.unknown
            var asked = LiveRouteState.unknown
            let kept = await store.probeNow(asset: asset, provider: provider, direction: .sell) { asset, provider, _ in
                let response = await quote(addressReCheckRequest(asset: asset, provider: provider))
                reCheck = addressReCheckState(response)
                asked = response.map(LiveRouteState.classify) ?? .unknown
                return asked
            }
            // A different state back means a newer answer recorded meanwhile won over this one.
            reAsked.append(kept == asked ? reCheck : kept)
        }
        return reAsked
    }

    /// Sends a re-check request; nil when no SwapKit answer came back.
    private static func addressReCheckResponse(_ request: SwapKitQuoteRequest) async -> SwapKitQuoteResponse? {
        do {
            return try await SwapKitAPIService.shared.quote(request)
        } catch {
            return decodedQuoteResponse(from: error)
        }
    }

    /// What a re-check answer says about the address: a route → `.available`; a below-minimum is
    /// about the amount, so `.unknown` here (the amount screen quotes the real amount); otherwise
    /// as `LiveRouteState.classify`. No answer → `.unknown`.
    nonisolated static func addressReCheckState(_ response: SwapKitQuoteResponse?) -> LiveRouteState {
        guard let response else { return .unknown }
        if response.routes?.isEmpty == false { return .available }
        let state = LiveRouteState.classify(response)
        return state == .available ? .unknown : state
    }

    /// The nominal quote `validateAddress` sends: the providers the real Sell quote would ask
    /// (`sellQuoteProviders`), so no provider the swap can't use decides the address.
    func addressCheckRequest(destination: String, toAsset: String) -> SwapKitQuoteRequest {
        SwapKitQuoteRequest(
            sellAsset: SwapKitConstants.dashAsset,
            buyAsset: toAsset,
            sellAmount: Self.addressCheckAmount,
            slippage: SwapKitConstants.defaultSlippagePercent,
            sourceAddress: nil,
            destinationAddress: destination,
            providers: sellQuoteProviders(for: toAsset),
            affiliateFee: nil
        )
    }

    /// What the address screen says after the providers that answered "no route" were asked again
    /// without the address: a route → the address is what to fix; nothing conclusive → nil, the
    /// amount screen gets to quote the coin; no route confirmed → the coin can't be swapped now.
    nonisolated static func addressReCheckMessage(_ reAsked: [LiveRouteState], coin: SwapCryptoCurrency?) -> String? {
        if reAsked.contains(.available) {
            guard let coin else { return "validation_error" }
            return SwapKitErrorCopy.message(for: "validation_error", coin: coin)
        }
        if reAsked.contains(.unknown) {
            return nil
        }
        guard let coin else { return NSLocalizedString("No route available", comment: "SwapKit") }
        return SwapKitErrorCopy.unavailableNowMessage(coin: coin)
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
        let depositDeadline = swapResponse.meta?.depositDeadline()
        // A response that describes a deposit channel gives this order an address of its
        // own. Without one the address may be a shared router or vault.
        let hasDepositChannel = swapResponse.meta?.depositChannelExpiration != nil
        DWLogger.log("SwapKit: buy order deposit=\(depositAddress) deadline=\(depositDeadline.map { "\(Int($0.timeIntervalSince1970))" } ?? "none")")
        // An empty memo is no memo.
        let memo = swapResponse.memo.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return BuyOrder(
            depositAddress: depositAddress,
            memo: memo,
            expectedDashAmount: expectedDashAmount,
            sellAsset: sellAsset,
            sellAmount: sellAmount,
            depositDeadline: depositDeadline,
            hasDepositChannel: hasDepositChannel
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
            // 404 for a deposit address is the tracker answering: it knows no such deposit
            // channel (never funded, or aged out of its storage). That is "nothing observed",
            // not a failed request.
            if let depositAddress, !depositAddress.isEmpty,
               case HTTPClientError.statusCode(let response) = error, response.statusCode == 404 {
                return SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil)
            }
            // Non-fatal; return not-yet-observed so polling continues — flagged, so a caller
            // that draws conclusions from "not observed" can tell it from a real answer.
            DWLogger.log("SwapKit: track request failed (deposit=\(depositAddress ?? "nil")): \(error)")
            return SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil, requestFailed: true)
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
            if let apiError = Self.decodeQuoteError(from: error) {
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
            if let apiError = Self.decodeQuoteError(from: error) {
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

    // MARK: - Private: Live Route Availability

    /// The providers the `/tokens` classification says can ever carry `asset` in `direction`.
    /// Buy routes only through NEAR (the counterparty builds the deposit, and Maya needs an
    /// OP_RETURN memo an external wallet will not add), so Maya never counts for Buy.
    private func capableProviders(for asset: String, direction: SwapDirection) -> Set<RouteProvider> {
        Self.capableProviders(
            for: asset,
            direction: direction,
            nearOnly: nearOnlyAssets,
            mayaOnly: mayaOnlyAssets,
            both: bothAssets
        )
    }

    /// The providers the published lists say can carry `asset`. Buy routes through NEAR only,
    /// so Maya never counts on Buy.
    nonisolated static func capableProviders(
        for asset: String,
        direction: SwapDirection,
        nearOnly: Set<String>,
        mayaOnly: Set<String>,
        both: Set<String>
    ) -> Set<RouteProvider> {
        let key = asset.uppercased()
        var providers = Set<RouteProvider>()
        if nearOnly.contains(key) || both.contains(key) {
            providers.insert(.near)
        }
        if direction == .sell, mayaOnly.contains(key) || both.contains(key) {
            providers.insert(.maya)
        }
        return providers
    }

    /// The providers that can carry `asset` now: capable ones the live probes have not ruled out.
    private func usableProviders(for asset: String, direction: SwapDirection) -> Set<RouteProvider> {
        routeAvailability.usableProviders(
            for: asset,
            capable: capableProviders(for: asset, direction: direction),
            direction: direction
        )
    }

    /// The amount a probe sells: about $50 of the sold asset, so a top-level `noRoutesFound` can be
    /// read as a real no-route (see `LiveRouteState.classify`). `nil` when that size is unknown —
    /// a Buy coin with no cached USD price — and the probe must not run.
    private func probeAmount(for asset: String, direction: SwapDirection) -> String? {
        let soldAsset = direction == .sell ? SwapKitConstants.dashAsset : asset
        if let priceUSD = usdPriceCache[soldAsset.uppercased()], priceUSD > 0 {
            return Self.plainDecimalString(Decimal(50) / Decimal(priceUSD), scale: 8)
        }
        // One DASH is worth tens of dollars, far above any route floor, so Sell can still probe
        // without a DASH price. One unit of an arbitrary Buy coin can be worth a fraction of a cent.
        return direction == .sell ? "1" : nil
    }

    /// The quote a probe sends: forced to `provider`'s SwapKit providers and carrying no address,
    /// so a probe reveals nothing about the wallet.
    nonisolated static func probeRequest(
        asset: String,
        provider: RouteProvider,
        direction: SwapDirection,
        amount: String
    ) -> SwapKitQuoteRequest {
        SwapKitQuoteRequest(
            sellAsset: direction == .sell ? SwapKitConstants.dashAsset : asset,
            buyAsset: direction == .sell ? asset : SwapKitConstants.dashAsset,
            sellAmount: amount,
            slippage: SwapKitConstants.defaultSlippagePercent,
            sourceAddress: nil,
            destinationAddress: nil,
            providers: provider.swapKitProviders,
            affiliateFee: nil
        )
    }

    /// One quote forced to `provider`'s SwapKit providers, classified.
    private func probeRoute(asset: String, provider: RouteProvider, direction: SwapDirection) async -> LiveRouteState {
        guard let amount = probeAmount(for: asset, direction: direction) else {
            return .unknown
        }
        let request = Self.probeRequest(asset: asset, provider: provider, direction: direction, amount: amount)

        do {
            return LiveRouteState.classify(try await SwapKitAPIService.shared.quote(request))
        } catch {
            let state = Self.decodedQuoteResponse(from: error).map(LiveRouteState.classify) ?? .unknown
            // Every field of a quote response is optional, so any JSON error body decodes. Only a
            // conclusive answer is not a failure; a 401, a 429 or a gateway error is logged.
            if state == .unknown {
                let detail = SwapKitFailureDetail.describe(error)
                DWLogger.log("SwapKit: route check \(asset) \(provider) \(direction) failed — \(detail)")
            }
            return state
        }
    }

    /// Feeds what a quote to the user's address said about `asset` into the live store. Only what
    /// cannot depend on the address is recorded: a route names the providers that carry it, and a
    /// provider's halt names the provider that is halted. A no-route is left to the address-free
    /// re-probe in `validateAddress`. Internal rather than private so the tests can feed it an answer.
    static func recordQuoteOutcome(
        _ response: SwapKitQuoteResponse,
        requested: Set<RouteProvider>,
        asset: String,
        direction: SwapDirection,
        store: SwapRouteAvailability
    ) {
        let carrying = Set(
            (response.routes ?? []).flatMap { $0.providers }.compactMap { RouteProvider(swapKitProvider: $0) }
        )
        for provider in carrying.intersection(requested) {
            store.record(.available, provider: provider, asset: asset, direction: direction)
        }

        // Both Maya flavours answer for `.maya`: it is halted only when no flavour says otherwise,
        // and a route from either flavour says otherwise.
        var halted = Set<RouteProvider>()
        var notHalted = Set<RouteProvider>()
        for error in response.providerErrors ?? [] {
            guard let name = error.provider, let provider = RouteProvider(swapKitProvider: name),
                  requested.contains(provider) else { continue }
            if SwapKitErrorCopy.isHalted(error.errorCode) {
                halted.insert(provider)
            } else {
                notHalted.insert(provider)
            }
        }
        for provider in halted.subtracting(notHalted).subtracting(carrying) {
            store.record(.halted, provider: provider, asset: asset, direction: direction)
        }
    }

    /// The address screen's copy for a check that got no SwapKit answer to read. A response that came
    /// back but could not be read (a gateway's error page, a broken body) means the swap service
    /// failed, so the user is not sent to check a connection that works; anything else never got a
    /// response — no connection, a timeout, a DNS failure.
    static func addressCheckFailureMessage(for error: Error) -> String {
        switch error {
        case HTTPClientError.statusCode, HTTPClientError.mapping, HTTPClientError.decoder:
            return NSLocalizedString("The swap service isn't responding. Please try again later.", comment: "SwapKit")
        default:
            return NSLocalizedString("Address validation unavailable — please check your connection", comment: "SwapKit")
        }
    }

    private static func decodedQuoteResponse(from error: Error) -> SwapKitQuoteResponse? {
        guard case HTTPClientError.statusCode(let response) = error else { return nil }
        return try? JSONDecoder().decode(SwapKitQuoteResponse.self, from: response.data)
    }

    /// Internal rather than private so the tests can feed it a recorded non-2xx body and pin the
    /// code-first ordering; nothing outside this type calls it.
    static func decodeQuoteError(from error: Error) -> String? {
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
    ///
    /// Providers the live probes have ruled out for this coin are left out, so a halted Maya leg
    /// cannot crowd the answer of a working NEAR one. When the probes ruled out every provider, the
    /// static set is sent anyway and SwapKit's own answer reaches the user.
    private func sellQuoteProviders(for toAsset: String) -> [String] {
        guard classificationUsable else {
            return [SwapKitConstants.providerNear]
        }

        let capable = capableProviders(for: toAsset, direction: .sell)
        guard !capable.isEmpty else {
            return [SwapKitConstants.providerNear]
        }
        let usable = routeAvailability.usableProviders(for: toAsset, capable: capable, direction: .sell, freshOnly: true)
        let chosen = usable.isEmpty ? capable : usable
        // NEAR first, then Maya — the order the request has always used.
        return [RouteProvider.near, .maya].filter { chosen.contains($0) }.flatMap { $0.swapKitProviders }
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

    /// Internal for tests: what each `/track` answer means to the tracker.
    func mapTrackResponse(_ response: SwapKitTrackResponse) -> SwapStatusResult {
        switch response.status?.lowercased() {
        case nil:
            // A body without a status carries no information — not the provider saying
            // "not started". Keep polling, flagged like a failed request.
            return SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil, requestFailed: true)

        case "not_started":
            // SwapKit hasn't seen the inbound DASH tx yet — keep polling.
            return SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil)

        case "pending":
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "pending", outHashes: nil, depositProven: true)

        case "swapping":
            // SwapKit is actively routing the swap; surface as "swapping" for per-order status tracking.
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "swapping", outHashes: nil, depositProven: true)

        case "completed":
            let outHashes = extractOutHashes(from: response)
            return SwapStatusResult(
                error: nil, isObserved: true, observedStatus: "done", outHashes: outHashes, depositProven: true,
                dashPayoutHash: dashPayoutHash(from: response))

        case "refunded":
            return SwapStatusResult(error: nil, isObserved: true, observedStatus: "refunded", outHashes: nil, depositProven: true)

        case "failed", "unknown":
            // Map to "refunded" so the polling loop drives swapStatus = .failed(reason:)
            // via the existing .refunded path. Conservative: no new state machine needed.
            // `providerStatus` keeps the real word for callers that must tell them apart.
            return SwapStatusResult(
                error: nil, isObserved: true, observedStatus: "refunded", outHashes: nil,
                providerStatus: response.status?.lowercased())

        default:
            // Prefer "still pending" over a wrong terminal state for any future statuses.
            return SwapStatusResult(
                error: nil, isObserved: true, observedStatus: "pending", outHashes: nil,
                providerStatus: response.status?.lowercased())
        }
    }

    /// The payout of a swap into DASH: the hash of its leg on the Dash chain, the one
    /// transaction of the swap the wallet holds. Nil unless the answer says the swap ends
    /// in DASH and has such a leg — any other hash in it is the deposit's or the router's.
    private func dashPayoutHash(from response: SwapKitTrackResponse) -> String? {
        guard response.toAsset?.uppercased() == "DASH.DASH" else { return nil }
        return (response.legs ?? []).first { leg in
            leg.chainId?.lowercased() == "dash" && leg.hash?.isEmpty == false
        }?.hash
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
