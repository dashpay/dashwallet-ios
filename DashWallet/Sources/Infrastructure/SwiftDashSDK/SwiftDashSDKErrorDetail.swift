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

/// The codes an error summary writes for the SDK's errors. Which errors carry
/// a consensus rejection is decided by `PlatformRefusal.consensusError(in:)`.
enum SwiftDashSDKErrorDetail {
    fileprivate static func logDetail(of consensus: PlatformConsensusError?) -> String? {
        consensus.map { "consensus code=\($0.code) kind=\($0.kind)" }
    }
}

extension SDKError: AppLogErrorDetail {
    var logDetail: String? { SwiftDashSDKErrorDetail.logDetail(of: PlatformRefusal.consensusError(in: self)) }
}

extension PlatformWalletError: AppLogErrorDetail {
    var logDetail: String? { SwiftDashSDKErrorDetail.logDetail(of: PlatformRefusal.consensusError(in: self)) }
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
