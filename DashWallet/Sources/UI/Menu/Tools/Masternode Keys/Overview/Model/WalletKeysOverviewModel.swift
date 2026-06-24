//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - MNKey

// Only Owner and Voting keys are supported. Operator (BLS) and HPMN/Platform
// (EdDSA) keys were removed: SwiftDashSDK can derive their private keys but the
// FFI does not export per-index BLS/EdDSA *public* keys, which the masternode
// setup requires, so those families can't be shown DashSync-free.
enum MNKey: CaseIterable {
    case owner
    case voting
}

extension MNKey {
    var title: String {
        switch self {
        case .owner:
            return NSLocalizedString("Owner keys", comment: "")
        case .voting:
            return NSLocalizedString("Voting keys", comment: "")
        }
    }
}
