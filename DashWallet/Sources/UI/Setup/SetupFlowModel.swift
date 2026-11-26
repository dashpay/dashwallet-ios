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

import Foundation

/// What follows Create a New Wallet or Recover Wallet in setup: Set PIN, then
/// Face ID or Touch ID, then backing up the recovery phrase, each only when
/// still needed. `SetupViewController` shows the steps; this decides them.
@MainActor
final class SetupFlowModel {
    enum Step: Equatable {
        case setPin
        case biometrics
        case backup
    }

    /// The checks and settings setup depends on.
    struct Environment {
        var needsPin: @MainActor () -> Bool
        var offersBiometrics: @MainActor () -> Bool
        var needsBackup: @MainActor () -> Bool
        var setWalletNeedsBackup: @MainActor (Bool) -> Void

        static var live: Environment {
            Environment(
                needsPin: { SetPinViewModel.shouldSetPin },
                offersBiometrics: { BiometricAuthViewModel.shouldOffer },
                needsBackup: { DWPreviewSeedPhraseModel.shouldVerifyPassphrase },
                setWalletNeedsBackup: { DWGlobalOptions.sharedInstance().walletNeedsBackup = $0 }
            )
        }
    }

    private let environment: Environment

    /// Restores the wallet from the entered phrase. It waits for the PIN, so
    /// the wallet is only created once a PIN protects it.
    private var pendingRecovery: (() -> Void)?

    init(environment: Environment = .live) {
        self.environment = environment
    }

    /// Create a New Wallet: the first step.
    func createWallet() -> Step? {
        pendingRecovery = nil
        environment.setWalletNeedsBackup(true)
        return nextStep()
    }

    /// Recover Wallet: the phrase is entered next, outside this flow.
    func startRecovering() {
        pendingRecovery = nil
    }

    /// The phrase was entered. With a PIN already set (setup was left after
    /// Set PIN), there is no Set PIN step to wait for: the wallet is restored
    /// now. The phrase was just entered, so there is nothing to back up.
    func didEnterRecoveryPhrase(recover: @escaping () -> Void) -> Step? {
        environment.setWalletNeedsBackup(false)
        if environment.needsPin() {
            pendingRecovery = recover
        }
        else {
            pendingRecovery = nil
            recover()
        }
        return nextStep()
    }

    /// The PIN was set: a wallet being recovered is restored now.
    func didSetPin() -> Step? {
        let recover = pendingRecovery
        pendingRecovery = nil
        recover?()
        return nextStep()
    }

    func didCancelPin() {
        pendingRecovery = nil
    }

    /// The step after the current one, or nil when setup is complete.
    func nextStep() -> Step? {
        if environment.needsPin() {
            return .setPin
        }
        if environment.offersBiometrics() {
            return .biometrics
        }
        if environment.needsBackup() {
            return .backup
        }
        return nil
    }
}
