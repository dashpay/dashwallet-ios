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

@testable import dashpay
import XCTest

/// The Halo 2 key build External Send starts ahead of the first Shielded spend: once, never when the key is built,
/// Shielded is empty or the SDK host has no wallet.
@MainActor
final class ShieldedProverWarmUpTests: XCTestCase {
    /// Stands for `PlatformWalletManager.warmUpShieldedProver` / `isShieldedProverReady` and the host's wallet.
    @MainActor
    final class FakeProver {
        var hostReady = true
        var shieldedCredits: UInt64? = 3_000_000
        var ready = false
        private(set) var builds = 0
        private(set) var lines: [String] = []
        /// Awaited inside the build, so a test can hold it running.
        var suspension: (() async -> Void)?

        func warmUp() -> ShieldedProverWarmUp {
            ShieldedProverWarmUp(
                isHostReady: { [unowned self] in hostReady },
                shieldedCredits: { [unowned self] in shieldedCredits },
                isProverReady: { [unowned self] in ready },
                build: { [unowned self] in
                    builds += 1
                    await suspension?()
                    ready = true
                },
                log: { [unowned self] in lines.append($0) })
        }
    }

    private let prover = FakeProver()

    func testItBuildsOnceAndLogsTheStartAndTheDuration() async {
        let warmUp = prover.warmUp()

        await warmUp.startIfNeeded()?.value
        XCTAssertNil(warmUp.startIfNeeded(), "the key is built")

        XCTAssertEqual(prover.builds, 1)
        XCTAssertEqual(prover.lines.count, 2)
        XCTAssertEqual(prover.lines.first, "Shielded prover warm-up: started")
        let finished = prover.lines.last ?? ""
        XCTAssertTrue(finished.hasPrefix("Shielded prover warm-up: finished in ") && finished.hasSuffix(" s"), finished)
    }

    func testASecondStartWhileTheBuildRunsStartsNothing() async {
        var release: CheckedContinuation<Void, Never>?
        prover.suspension = { await withCheckedContinuation { release = $0 } }
        let warmUp = prover.warmUp()

        let build = warmUp.startIfNeeded()
        await Task.yield()
        XCTAssertNil(warmUp.startIfNeeded(), "a build runs")
        while release == nil { await Task.yield() }
        release?.resume()
        await build?.value

        XCTAssertEqual(prover.builds, 1)
    }

    func testItStartsNothingWhenTheKeyIsBuilt() {
        prover.ready = true
        XCTAssertNil(prover.warmUp().startIfNeeded())
        XCTAssertEqual(prover.builds, 0)
        XCTAssertTrue(prover.lines.isEmpty)
    }

    func testItStartsNothingWhileShieldedIsEmptyOrUnread() {
        let warmUp = prover.warmUp()
        for credits in [UInt64(0), nil] {
            prover.shieldedCredits = credits
            XCTAssertNil(warmUp.startIfNeeded(), "\(String(describing: credits))")
        }
        XCTAssertEqual(prover.builds, 0)
    }

    func testItStartsNothingBeforeTheSDKHostHasAWallet() {
        prover.hostReady = false
        XCTAssertNil(prover.warmUp().startIfNeeded())
        XCTAssertEqual(prover.builds, 0)
    }
}
