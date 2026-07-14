//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

// MARK: - ObjC bridge (called from AppDelegate.m at app launch)

@objc
class SwapTrackingServiceObjcWrapper: NSObject {
    @objc static func start() {
        SwapTrackingService.shared.start()
    }
}

// MARK: - SwapTrackingService

/// Background singleton that persists and polls all non-terminal swap orders.
///
/// Mirrors Android's `SwapTrackingService.kt`:
/// - `start()` at app launch resumes all non-terminal orders.
/// - Polls `/track` every 30 s for active orders.
/// - NEAR fallback by `depositAddress` when hash lookup errors.
/// - Material-change-only writes (unconditional writes turn the ticker into a tight loop).
/// - Ages out an order still unresolved after 24 h → `.failed`.
final class SwapTrackingService {
    static let shared = SwapTrackingService()

    private enum Constants {
        static let pollIntervalNs: UInt64 = 30_000_000_000  // 30 s
        static let ageOutSeconds: Int64 = 86_400             // 24 h
    }

    private enum TrackingRoute {
        case maya
        case near
        case swapKitHash
    }

    private let dao = SwapOrdersDAOImpl.shared
    private var trackingTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public

    /// Starts (or restarts) background polling for all non-terminal swap orders.
    /// Safe to call multiple times — cancels any previously running task.
    func start() {
        trackingTask?.cancel()
        trackingTask = Task { await pollLoop() }
        DSLogger.log("SwapTrackingService: started")
    }

    // MARK: - Private: Poll loop

    private func pollLoop() async {
        while !Task.isCancelled {
            let active = await dao.all().filter { $0.status.isActive }
            DSLogger.log("SwapTrackingService: polling \(active.count) active order(s)")

            await withTaskGroup(of: Void.self) { group in
                for order in active {
                    group.addTask { await self.pollOrder(order) }
                }
            }

            try? await Task.sleep(nanoseconds: Constants.pollIntervalNs)
        }
    }

    private func pollOrder(_ order: SwapOrder) async {
        let nowSeconds = Int64(Date().timeIntervalSince1970)

        // Always ask the API FIRST. The 24 h age-out must never pre-empt a real status:
        // an order can complete while the app is closed (polling only runs in-foreground), so an
        // order older than 24 h can already be `completed`/`refunded`. Aging out before checking
        // would mislabel a genuinely-completed swap as failed.
        let route = trackingRoute(for: order)

        var apiStatus: SwapOrderStatus?
        var firstOutHash: String?
        var newActualAmount: String?

        do {
            if order.direction == "buy" {
                if let walletTxHash = await completedWalletTxHash(for: order) {
                    apiStatus = .completed
                    firstOutHash = walletTxHash
                } else {
                    // Buy orders use the deposit address as the tracking key until the Dash tx
                    // lands in the wallet; the source-chain address must never be treated as a hash.
                    let depositAddress = order.depositAddress ?? order.id
                    let result = try await SwapKitSwapProvider().fetchSwapStatus(
                        txid: order.id,
                        depositAddress: depositAddress
                    )

                    // Only treat the response as authoritative when the provider has observed the tx,
                    // or returned cleanly. When isObserved = true, a non-nil error is often a non-critical
                    // warning alongside valid status data (e.g. Maya returns both fields on completion).
                    if result.isObserved || result.error == nil {
                        apiStatus = SwapOrderStatus.from(
                            trackStatus: result.observedStatus,
                            isObserved: result.isObserved
                        )
                        firstOutHash = result.outHashes?.first
                        newActualAmount = result.actualToAmount
                    }
                }
            } else {
                let result: SwapStatusResult
                switch route {
                case .maya:
                    result = try await MayaSwapProvider().fetchSwapStatus(
                        txid: order.id,
                        depositAddress: nil
                    )
                case .near:
                    // NEAR-Intents tracking uses the deposit address, not the Dash tx hash.
                    result = try await SwapKitSwapProvider().fetchSwapStatus(
                        txid: order.id,
                        depositAddress: order.depositAddress
                    )
                case .swapKitHash:
                    result = try await SwapKitSwapProvider().fetchSwapStatus(
                        txid: order.id,
                        depositAddress: nil
                    )
                }

                // Only treat the response as authoritative when the provider has observed the tx,
                // or returned cleanly. When isObserved = true, a non-nil error is often a non-critical
                // warning alongside valid status data (e.g. Maya returns both fields on completion).
                if result.isObserved || result.error == nil {
                    apiStatus = SwapOrderStatus.from(
                        trackStatus: result.observedStatus,
                        isObserved: result.isObserved
                    )
                    firstOutHash = result.outHashes?.first
                    newActualAmount = result.actualToAmount
                }
            }
        } catch {
            // Transient network error — no authoritative status this cycle; may still age out below.
            DSLogger.log("SwapTrackingService: poll error for \(order.id): \(error)")
        }

        // Decide the final status: prefer the API result; only fall back to the 24 h age-out when
        // the order is STILL non-terminal. Age-out lands on the neutral `.expired` (not `.failed`) —
        // funds may have arrived; we simply stopped tracking.
        var finalStatus = apiStatus ?? order.status
        if finalStatus.isActive {
            let orderAgeSeconds = nowSeconds - (order.timestamp / 1000)
            if orderAgeSeconds > Constants.ageOutSeconds {
                DSLogger.log("SwapTrackingService: order \(order.id) unresolved after 24 h → expired")
                finalStatus = .expired
            }
        }

        // Material-change-only writes — avoids tight-loop DB churn.
        let changed = finalStatus != order.status
            || (firstOutHash != nil && firstOutHash != order.outboundTxHash)
            || (newActualAmount != nil && newActualAmount != order.actualToAmount)

        guard changed else { return }

        var updated = order
        updated.status = finalStatus
        updated.outboundTxHash = firstOutHash ?? order.outboundTxHash
        updated.actualToAmount = newActualAmount ?? order.actualToAmount
        updated.lastChecked = nowSeconds
        if finalStatus.isTerminal { updated.finalisedAt = nowSeconds }

        DSLogger.log("SwapTrackingService: order \(order.id) → \(finalStatus.rawValue)")
        await dao.update(dto: updated)
    }

    // MARK: - Private: Route resolution

    private func trackingRoute(for order: SwapOrder) -> TrackingRoute {
        let provider = order.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if provider.contains("maya") {
            return .maya
        }

        if provider.contains("near") {
            return .near
        }

        if order.service == "maya" {
            return .maya
        }

        return .swapKitHash
    }

    @MainActor
    private func completedWalletTxHash(for order: SwapOrder) -> String? {
        let transactions = DWEnvironment.sharedInstance().currentWallet.allTransactions
        return SwapBuyTransactionMatcher.walletTxHashHexString(for: order, in: transactions)
    }
}
