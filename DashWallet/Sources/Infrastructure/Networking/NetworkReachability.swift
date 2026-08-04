//
//  Created by Bartosz Rozwarski
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
import Network

@objc(DWNetworkReachability)
final class NetworkReachability: NSObject {
    @objc static let shared = NetworkReachability()

    @objc static let didChangeNotification =
        Notification.Name("org.dash.networking.reachability.change")

    private let queue = DispatchQueue(label: "org.dash.reachability", qos: .utility)
    private var monitor: NWPathMonitor?
    private let lock = NSLock()

    private var _isReachable: Bool = false
    private var _isReachableViaWiFi: Bool = false
    private var hasReceivedFirstPath: Bool = false

    @objc var isMonitoring: Bool {
        lock.lock(); defer { lock.unlock() }
        return monitor != nil
    }

    @objc var isReachable: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isReachable
    }

    @objc var isReachableViaWiFi: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isReachableViaWiFi
    }

    @objc func startMonitoring() {
        lock.lock()
        if monitor != nil {
            lock.unlock()
            return
        }
        let m = NWPathMonitor()
        monitor = m
        hasReceivedFirstPath = false
        lock.unlock()

        m.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        m.start(queue: queue)

        // Callers read `isReachable` the moment this returns, so the state is
        // seeded from the path the monitor already holds instead of parking the
        // caller until the utility-QoS queue delivers its first callback.
        handlePathUpdate(m.currentPath)
    }

    @objc func stopMonitoring() {
        lock.lock()
        let m = monitor
        monitor = nil
        lock.unlock()
        m?.cancel()
    }

    /// Updates the shared reachability snapshot from the latest path and marks
    /// whether the monitor has observed at least one path since it started.
    private func handlePathUpdate(_ path: NWPath) {
        let reachable = path.status == .satisfied
        let wifi = reachable && path.usesInterfaceType(.wifi)

        lock.lock()
        _isReachable = reachable
        _isReachableViaWiFi = wifi
        hasReceivedFirstPath = true
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NetworkReachability.didChangeNotification,
                object: self
            )
        }
    }
}
