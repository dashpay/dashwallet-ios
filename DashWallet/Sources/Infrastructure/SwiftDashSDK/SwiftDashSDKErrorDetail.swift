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
import SwiftDashSDK

/// What the SDK's errors carry beyond their case: the consensus rejection a
/// write decision reads, and the codes an error summary writes.
enum SwiftDashSDKErrorDetail {
    /// The consensus rejection `error` itself carries, from the SDK or from
    /// the wallet layer; `nil` for any other error. Not the errors it wraps:
    /// a caller that decides on a write reads the top level only, and
    /// `AppLogMessage.errorSummary` walks wrapped errors level by level.
    static func consensusRejection(in error: Error) -> PlatformConsensusError? {
        switch error {
        case let error as SDKError: error.consensusError
        case let error as PlatformWalletError: error.consensusError
        default: nil
        }
    }

    fileprivate static func logDetail(of consensus: PlatformConsensusError?) -> String? {
        consensus.map { "consensus code=\($0.code) kind=\($0.kind)" }
    }
}

extension SDKError: AppLogErrorDetail {
    var logDetail: String? { SwiftDashSDKErrorDetail.logDetail(of: consensusError) }
}

extension PlatformWalletError: AppLogErrorDetail {
    var logDetail: String? { SwiftDashSDKErrorDetail.logDetail(of: consensusError) }
}

/// The keychain status a recovery-phrase keychain failure carries; the
/// bridged error drops it.
extension WalletStorageError: AppLogErrorDetail {
    var logDetail: String? {
        guard case .keychainError(let status) = self else { return nil }
        return "status=\(status)"
    }
}

extension SwiftDashSDKKeyMigrator.LegacyMnemonicCleanupError: AppLogErrorDetail {
    var logDetail: String? {
        guard case .keychainRead(let status) = self else { return nil }
        return "status=\(status)"
    }
}
