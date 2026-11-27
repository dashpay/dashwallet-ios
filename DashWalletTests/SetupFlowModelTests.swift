//
//  Created by Dash Core Group
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

@MainActor
final class SetupFlowModelTests: XCTestCase {
    private var hasPin = false
    private var offersBiometrics = false
    private var walletNeedsBackup: Bool?
    private var recoveries = 0

    private func makeFlow() -> SetupFlowModel {
        SetupFlowModel(environment: .init(
            needsPin: { [unowned self] in !self.hasPin },
            offersBiometrics: { [unowned self] in self.offersBiometrics },
            needsBackup: { [unowned self] in self.walletNeedsBackup ?? false },
            setWalletNeedsBackup: { [unowned self] in self.walletNeedsBackup = $0 }
        ))
    }

    private func recover() {
        recoveries += 1
    }

    // MARK: Create

    func testCreateAsksForPinThenBiometricsThenBackup() {
        offersBiometrics = true
        let flow = makeFlow()

        XCTAssertEqual(flow.createWallet(), .setPin)
        XCTAssertEqual(walletNeedsBackup, true)

        hasPin = true
        XCTAssertEqual(flow.didSetPin(), .biometrics)

        offersBiometrics = false
        XCTAssertEqual(flow.nextStep(), .backup)
    }

    // MARK: Recover

    func testRecoverWaitsForThePinBeforeRestoring() {
        let flow = makeFlow()
        flow.startRecovering()

        XCTAssertEqual(flow.didEnterRecoveryPhrase(recover: recover), .setPin)
        XCTAssertEqual(recoveries, 0, "The wallet is restored only once a PIN protects it")
        XCTAssertEqual(walletNeedsBackup, false)

        hasPin = true
        XCTAssertNil(flow.didSetPin())
        XCTAssertEqual(recoveries, 1)
    }

    func testRecoverWithAPinAlreadySetRestoresAtOnce() {
        // Setup was left after Set PIN: there is no PIN step to wait for.
        hasPin = true
        let flow = makeFlow()
        flow.startRecovering()

        XCTAssertNil(flow.didEnterRecoveryPhrase(recover: recover))
        XCTAssertEqual(recoveries, 1)
    }

    func testCancellingThePinDropsThePendingRecovery() {
        let flow = makeFlow()
        flow.startRecovering()
        _ = flow.didEnterRecoveryPhrase(recover: recover)

        flow.didCancelPin()
        hasPin = true
        _ = flow.didSetPin()

        XCTAssertEqual(recoveries, 0)
    }

    func testCreatingAfterRecoveringDropsThePendingRecovery() {
        let flow = makeFlow()
        flow.startRecovering()
        _ = flow.didEnterRecoveryPhrase(recover: recover)

        XCTAssertEqual(flow.createWallet(), .setPin)
        XCTAssertEqual(walletNeedsBackup, true)
        hasPin = true
        _ = flow.didSetPin()

        XCTAssertEqual(recoveries, 0)
    }

    func testTheRecoveryRunsOnlyOnce() {
        let flow = makeFlow()
        _ = flow.didEnterRecoveryPhrase(recover: recover)
        hasPin = true

        _ = flow.didSetPin()
        _ = flow.didSetPin()

        XCTAssertEqual(recoveries, 1)
    }
}
