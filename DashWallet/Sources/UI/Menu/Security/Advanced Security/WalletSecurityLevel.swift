//
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

/// How strongly the wallet is protected, from the auto-logout and the
/// spending-confirmation settings together. Shown at the top of Advanced
/// Security.
enum WalletSecurityLevel: Equatable {
    case none
    case low
    case medium
    case high
    case veryHigh

    /// - Parameters:
    ///   - lockTime: Seconds before the app locks, or `nil` when auto logout
    ///     is off.
    ///   - spendingLimit: Duffs that can be spent with biometrics instead of
    ///     the PIN, or `nil` when spending confirmation is off.
    static func level(lockTime: Int?, spendingLimit: UInt64?) -> WalletSecurityLevel {
        switch (lockTime, spendingLimit) {
        case (nil, nil):
            return .none
        case (0, 0):
            // Locks immediately and always asks for the PIN.
            return .veryHigh
        case (.some, .some):
            return .high
        case (.some(let lockTime), nil) where lockTime >= 60 * 60:
            return .low
        default:
            // Auto logout under an hour with spending confirmation off, or
            // spending confirmation on with auto logout off.
            return .medium
        }
    }
}
