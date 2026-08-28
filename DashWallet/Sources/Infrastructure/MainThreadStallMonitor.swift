//
//  Created by Dash Core Group.
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

/// DEBUG-only main-runloop stall detector backing the wallet-lifecycle
/// performance work: it turns "the spinner froze" into a `DWLogger` line with
/// a duration, in the same rolling file the stage timings go to, so stalls
/// can be attributed to a bootstrap stage by timestamp.
///
/// Design: a single ping-pong. The monitor thread posts ONE block to the main
/// queue and parks on a semaphore until the main thread runs it; the measured
/// round-trip IS the stall duration (a healthy runloop answers in
/// microseconds). The next ping is only posted after the previous one was
/// answered, plus a fixed pause — so at most one ping is ever pending, a
/// single long stall produces a single log line after it resolves (never a
/// burst of queued-up reports), and the log line can only underestimate a
/// stall by at most the inter-ping pause.
///
/// Thresholds follow the Instruments/MetricKit hang convention: report from
/// 250 ms (microhang); the etap-C acceptance gate reads ≥500 ms as a hang.
@objc(DWMainThreadStallMonitor)
final class MainThreadStallMonitor: NSObject {
    /// Latencies below this are a healthy runloop; from here up they are
    /// logged. Matches the Instruments "microhang" floor.
    static let reportThreshold: TimeInterval = 0.25
    /// Pause between an answered ping and the next one. Bounds both the
    /// sampling overhead and the maximum underestimate of a stall.
    static let interPingPause: TimeInterval = 0.1

    /// Pure classification, unit-testable without threads: milliseconds to
    /// report for a measured ping round-trip, or nil when the latency is
    /// below the reporting threshold.
    static func stallMilliseconds(forLatency latency: TimeInterval) -> Int? {
        guard latency >= reportThreshold else { return nil }
        return Int(latency * 1000)
    }

    private static var started = false

    /// Idempotent; a no-op outside DEBUG builds. Called once from
    /// `application(_:didFinishLaunchingWithOptions:)`.
    @objc static func start() {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(.main))
        guard !started else { return }
        started = true

        let thread = Thread {
            while true {
                let semaphore = DispatchSemaphore(value: 0)
                let pinged = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async {
                    semaphore.signal()
                }
                semaphore.wait()
                let latency = CFAbsoluteTimeGetCurrent() - pinged
                if let ms = stallMilliseconds(forLatency: latency) {
                    DWLogger.log("⏱️ MAINSTALL ~\(ms)ms")
                }
                Thread.sleep(forTimeInterval: interPingPause)
            }
        }
        thread.name = "org.dashfoundation.dash.main-stall-monitor"
        thread.qualityOfService = .utility
        thread.start()
        #endif
    }
}
