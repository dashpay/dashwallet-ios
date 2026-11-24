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
import SwiftDashSDK

/// Builds the Shielded prover's Halo 2 proving key ahead of the first Shielded spend of the session, which otherwise
/// spends about 30 s of CPU building it inside the send. `ExternalSendFlow` starts it when it opens with Shielded
/// money; app launch does not, the build being CPU-heavy.
///
/// One shared instance (`shared`): the key is process-global on the Rust side, so one build serves every flow, and a
/// flow opened while a build runs must see that build to not start a second one.
@MainActor
final class ShieldedProverWarmUp {
    static let shared = ShieldedProverWarmUp()

    private let isHostReady: @MainActor () -> Bool
    private let shieldedCredits: @MainActor () -> UInt64?
    private let isProverReady: @MainActor () -> Bool
    private let build: @MainActor () async -> Void
    private let log: (String) -> Void
    /// The running build; nil before the first one and once it finished.
    private var running: Task<Void, Never>?

    init(
        isHostReady: @escaping @MainActor () -> Bool = { SwiftDashSDKHost.shared.wallet != nil },
        shieldedCredits: @escaping @MainActor () -> UInt64? = {
            PlatformAddressSyncCoordinator.shared.shieldedBalanceState.credits
        },
        isProverReady: @escaping @MainActor () -> Bool = { PlatformWalletManager.isShieldedProverReady },
        build: @escaping @MainActor () async -> Void = { await PlatformWalletManager.warmUpShieldedProver() },
        log: @escaping (String) -> Void = { DWLogger.log($0) }
    ) {
        self.isHostReady = isHostReady
        self.shieldedCredits = shieldedCredits
        self.isProverReady = isProverReady
        self.build = build
        self.log = log
    }

    /// Starts the build while Shielded holds money (the Shielded source can pay every destination), unless the SDK
    /// host has no wallet yet, the key is built, or a build runs. It never waits for the build: the SDK runs it on a
    /// background-priority task. Returns the started build.
    @discardableResult
    func startIfNeeded() -> Task<Void, Never>? {
        guard running == nil, isHostReady(), let credits = shieldedCredits(), credits > 0, !isProverReady() else {
            return nil
        }
        log("Shielded prover warm-up: started")
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task { [build] in
            await build()
            let elapsed = started.duration(to: clock.now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            log("Shielded prover warm-up: finished in \(String(format: "%.1f", seconds)) s")
            running = nil
        }
        running = task
        return task
    }
}
