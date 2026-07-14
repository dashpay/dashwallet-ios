//
//  NetworkStatusService.swift
//  DashWallet
//
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

// FUTURE MIGRATION PATH (do not implement now):
//  • Re-back `NetworkReachabilityMonitor` (SwiftUI) by subscribing to
//    `NetworkStatusService.shared.statusPublisher` so the whole app shares a single
//    NWPathMonitor, then retire the DSReachabilityManager dependency from app-side code.
//  • Re-back `NetworkReachabilityHandling` (UIKit protocol) the same way.
//  • Optionally expose `isExpensive` / `interfaceType` from `NWPath` when a consumer
//    needs it (extend `NetworkStatusProviding` with these optional properties).

import Combine
import Foundation
import Network

// MARK: - NetworkStatusProviding

public protocol NetworkStatusProviding: AnyObject {
    var currentStatus: NetworkStatus { get }
    /// Convenience: `currentStatus == .online`.
    var isOnline: Bool { get }
    /// Emits the current status immediately on subscribe (CurrentValueSubject semantics),
    /// then on every path change. Delivered on `DispatchQueue.main`.
    var statusPublisher: AnyPublisher<NetworkStatus, Never> { get }
}

// MARK: - NetworkStatusService

/// App-wide, NWPathMonitor-backed connectivity service.
///
/// DashDEX ViewModels are the first consumers; non-DEX code (`NetworkReachabilityMonitor`,
/// `NetworkReachabilityHandling`) still uses `DSReachabilityManager` and can be migrated
/// in a follow-up without a vocabulary change (both speak `NetworkStatus`).
public final class NetworkStatusService: NetworkStatusProviding {
    public static let shared = NetworkStatusService()

    public var currentStatus: NetworkStatus { subject.value }
    public var isOnline: Bool { currentStatus == .online }
    public var statusPublisher: AnyPublisher<NetworkStatus, Never> {
        subject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    private let subject: CurrentValueSubject<NetworkStatus, Never>
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "dash.network-status-service", qos: .utility)

    public init() {
        subject = CurrentValueSubject(monitor.currentPath.status == .satisfied ? .online : .offline)

        monitor.pathUpdateHandler = { [weak self] path in
            let status: NetworkStatus = path.status == .satisfied ? .online : .offline
            self?.subject.send(status)
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }
}
