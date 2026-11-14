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

/// Resumes a held asset lock on its existing outpoint.
@MainActor
protocol HeldAssetLockResuming {
    func resume(_ lock: HeldAssetLock) async throws -> AssetLockRecoveryService.Outcome
}

/// The resume the transaction details' Rebroadcast runs: `AssetLockRecoveryService.retry`, which authenticates before
/// it moves the lock and throws `DWIdentityAuthorizer.AuthError.cancelled` when the prompt is cancelled.
struct LiveHeldAssetLockResumer: HeldAssetLockResuming {
    func resume(_ lock: HeldAssetLock) async throws -> AssetLockRecoveryService.Outcome {
        try await AssetLockRecoveryService().retry(
            fundingTypeRaw: lock.fundingTypeRaw, txidWire: lock.txidWire, vout: lock.vout)
    }
}

/// The lock-held sheet after a `lockHeld` send: Finish resumes the lock, Close leaves it for the transaction details.
@MainActor
final class SendLockHeldViewModel: ObservableObject {
    enum State: Equatable {
        case ready
        case finishing
        /// The resume failed; the lock is still held and Finish can run again.
        case failed
    }

    /// What the flow shows once Finish is over.
    enum Result: Equatable {
        case completed
        /// An info Toast with this text.
        case info(String)
    }

    @Published private(set) var state: State = .ready
    var onFinished: ((Result) -> Void)?

    let lock: HeldAssetLock
    private let resumer: HeldAssetLockResuming

    /// `state` other than `.ready` is for previews.
    init(lock: HeldAssetLock, resumer: HeldAssetLockResuming, state: State = .ready) {
        self.lock = lock
        self.resumer = resumer
        self.state = state
    }

    var isFinishing: Bool { state == .finishing }

    var title: String {
        NSLocalizedString("Transfer not finished", comment: "External send")
    }

    var message: String {
        NSLocalizedString(
            "Your Dash is held for this transfer. Finish it now, or later from the transaction details.",
            comment: "External send")
    }

    var failureMessage: String? {
        guard state == .failed else { return nil }
        return NSLocalizedString(
            "The transfer could not be finished. Try again, or finish it later from the transaction details.",
            comment: "External send")
    }

    func finish() async {
        guard state != .finishing else { return }
        state = .finishing
        do {
            let outcome = try await resumer.resume(lock)
            log("\(outcome)")
            state = .ready
            onFinished?(Self.result(for: outcome))
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            log("cancelled")
            state = .ready
        } catch AssetLockRecoveryService.RecoveryError.inProgress(let message) {
            log("inProgress")
            state = .ready
            onFinished?(.info(message))
        } catch {
            log("failed(\(Self.errorType(error)))")
            state = .failed
        }
    }

    static func result(for outcome: AssetLockRecoveryService.Outcome) -> Result {
        switch outcome {
        case .completed:
            return .completed
        case .completionUnconfirmed:
            return .info(NSLocalizedString(
                "Already spent — nothing to transfer", comment: "Asset-lock retry found the lock already consumed"))
        case .submittedAwaitingSync:
            return .info(NSLocalizedString(
                "Submitted — waiting for the network to confirm",
                comment: "Asset-lock retry submitted but its result could not be read back"))
        }
    }

    /// The error's type only: a recovery failure's text can carry Platform's raw message.
    private static func errorType(_ error: Error) -> String {
        if case AssetLockRecoveryService.RecoveryError.failed(_, let underlying?) = error {
            return String(describing: type(of: underlying))
        }
        return String(describing: type(of: error))
    }

    private func log(_ outcome: String) {
        DWLogger.log("External send: finish held lock type=\(lock.fundingTypeRaw) outcome=\(outcome)")
    }
}
