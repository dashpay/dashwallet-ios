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

import Combine
import Foundation
import UserNotifications

/// Posts a notification when a swap order transitions into a terminal
/// state (completed / refunded / failed / expired).
///
/// Signal: the swap orders DAO publisher (`SwapOrdersDAOImpl.observeAll`),
/// which re-emits the full order set on every write —
/// `SwapTrackingService`'s 30 s poll loop is the writer that lands terminal
/// statuses. The store dedup on the order-scoped id ("swap.<orderId>") is
/// the transition-edge detector: a terminal order re-emitted by N refreshes
/// posts once.
///
/// Known limitation: the poll loop only runs while the app process is
/// scheduled, so a swap that completes while the app is suspended or killed
/// is only observed on the next poll after relaunch/return. If the user is
/// back on the live swap-status screen by then, the transition is consumed
/// silently (that screen already shows the outcome); anywhere else it posts
/// as a foreground banner.
final class SwapNotificationProducer {
    /// A terminal order must have been finalised at most this long ago to
    /// notify — the replay guard: the DAO publisher replays the whole
    /// table on every launch, and month-old outcomes are not news.
    static let freshnessWindow: TimeInterval = 10 * 60

    private let dispatcher: NotificationDispatcher
    private let store: NotifiedEventStoring
    /// The order-set publisher; deferred so subscribing at bootstrap does
    /// not touch the DAO singleton before `start()`.
    private let ordersPublisher: () -> AnyPublisher<[SwapOrder], Never>
    private let appState: AppStateProvider
    /// True while the user is watching a live swap-status screen; deferred
    /// closure for the same reason as `ordersPublisher` (and for tests).
    private let swapUIVisible: () -> Bool
    private let now: () -> Date
    private var cancellables = Set<AnyCancellable>()

    init(dispatcher: NotificationDispatcher,
         store: NotifiedEventStoring,
         ordersPublisher: @escaping () -> AnyPublisher<[SwapOrder], Never> = { SwapOrdersDAOImpl.shared.observeAll() },
         appState: AppStateProvider = UIApplicationStateProvider(),
         swapUIVisible: @escaping () -> Bool = { SwapTrackingService.shared.isStatusUIVisible },
         now: @escaping () -> Date = Date.init) {
        self.dispatcher = dispatcher
        self.store = store
        self.ordersPublisher = ordersPublisher
        self.appState = appState
        self.swapUIVisible = swapUIVisible
        self.now = now
    }

    /// Subscribes to the order stream. Idempotent; called once by
    /// `NotificationsBootstrap`.
    func start() {
        guard cancellables.isEmpty else { return }
        ordersPublisher()
            .sink { [weak self] orders in
                Task { await self?.process(orders) }
            }
            .store(in: &cancellables)
    }

    /// One pass over an emitted order set. Overlapping passes posting the
    /// same order are resolved by the store's `markIfNew` (an actor), so
    /// exactly one post happens per order.
    func process(_ orders: [SwapOrder]) async {
        for order in orders where order.status.isTerminal {
            await processTerminal(order)
        }
    }

    // MARK: Private

    private func processTerminal(_ order: SwapOrder) async {
        guard let body = Self.terminalBody(for: order) else { return }
        let id = "swap.\(order.id)"

        // Replay guard: `finalisedAt` is stamped by the tracking service
        // when it writes the terminal status, so a fresh stamp means the
        // transition just happened. A stale stamp — or an unknown one (-1),
        // which cannot prove freshness — is recorded as known without
        // posting, so the launch replay of the whole table stays silent.
        let finalisedRecently = order.finalisedAt > 0
            && Date(timeIntervalSince1970: TimeInterval(order.finalisedAt)) >= now().addingTimeInterval(-Self.freshnessWindow)
        guard finalisedRecently else {
            await store.consume(id: id, topic: .swap)
            return
        }

        // App-state policy: consume only a transition the user is
        // actually watching happen — foregrounded AND on the live
        // swap-status screen — so a later emission (relaunch, next poll)
        // cannot resurrect it. Anywhere else in the foreground the post
        // below surfaces as a banner (`foregroundBehavior: .banner` is
        // obeyed by `NotificationLifecycle.willPresent`).
        if appState.isApplicationActive && swapUIVisible() {
            await store.consume(id: id, topic: .swap)
            return
        }

        await dispatcher.post(AppNotification(
            id: id,
            topic: .swap,
            title: nil,
            body: body,
            sound: .default,
            route: .swapOrder(id: order.id),
            foregroundBehavior: .banner))
    }

    /// Outcome copy naming the pair; nil for non-terminal statuses (the
    /// caller filters those out — nil keeps that contract honest instead
    /// of fabricating a message).
    static func terminalBody(for order: SwapOrder) -> String? {
        let pair = "\(SwapOrderMetadataProvider.shortSymbol(from: order.fromAsset))/\(SwapOrderMetadataProvider.shortSymbol(from: order.toAsset))"
        switch order.status {
        case .completed:
            return String(format: NSLocalizedString("Your %@ swap is complete", comment: "Dash DEX"), pair)
        case .refunded:
            return String(format: NSLocalizedString("Your %@ swap was refunded", comment: "Dash DEX"), pair)
        case .failed:
            return String(format: NSLocalizedString("Your %@ swap failed", comment: "Dash DEX"), pair)
        case .expired:
            // Neutral by design: the 24 h age-out is "we stopped tracking",
            // not a failure — funds may well have arrived.
            return String(format: NSLocalizedString("The status of your %@ swap could not be confirmed", comment: "Dash DEX"), pair)
        case .notStarted, .pending, .swapping, .unknown:
            return nil
        }
    }
}
