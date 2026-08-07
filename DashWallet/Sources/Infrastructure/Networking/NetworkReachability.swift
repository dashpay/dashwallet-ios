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

    /// Path updates are background work and stay at `.utility`. Raising the
    /// QoS here was an attempt to hide a priority inversion, but the inversion
    /// came from `startMonitoring` blocking the main thread — and
    /// `.userInitiated` still sits below the main thread's `.userInteractive`,
    /// so it only narrowed the window. The wait itself is gone instead.
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

        let firstUpdate = DispatchSemaphore(value: 0)
        m.pathUpdateHandler = { [weak self] path in
            if self?.handlePathUpdate(path) == true {
                firstUpdate.signal()
            }
        }
        m.start(queue: queue)

        // Off the main thread, keep the synchronous contract the old
        // `SCNetworkReachability`-based manager offered: wait briefly so the
        // caller observes real state on return.
        //
        // On the main thread, never wait. `NWPathMonitor` delivers on a
        // background queue, so the wait made a user-interactive thread block on
        // lower-QoS work for up to 200 ms at launch — the priority inversion
        // the Thread Performance Checker flags. Every caller already observes
        // `didChangeNotification`, which carries the first real path a few
        // milliseconds later.
        guard !Thread.isMainThread else { return }
        _ = firstUpdate.wait(timeout: .now() + .milliseconds(200))
    }

    @objc func stopMonitoring() {
        lock.lock()
        let m = monitor
        monitor = nil
        lock.unlock()
        m?.cancel()
    }

    /// Returns `true` on the first path update after `startMonitoring()`.
    @discardableResult
    private func handlePathUpdate(_ path: NWPath) -> Bool {
        let reachable = path.status == .satisfied
        let wifi = reachable && path.usesInterfaceType(.wifi)

        lock.lock()
        _isReachable = reachable
        _isReachableViaWiFi = wifi
        let wasFirst = !hasReceivedFirstPath
        hasReceivedFirstPath = true
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NetworkReachability.didChangeNotification,
                object: self
            )
        }
        return wasFirst
    }
}
