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
import SwiftDashSDK

// MARK: - ExtendedPublicKeysModel

@MainActor
final class ExtendedPublicKeysModel {
    /// The running SDK wallet's BIP44 account-0 extended public key
    /// (xpub/tpub base58check). It is `nil` when the wallet runtime isn't up
    /// or the wallet has no BIP44 account 0. The sheet then shows
    /// "Not available".
    let bip44AccountXpub: String?

    init() {
        bip44AccountXpub = try? SwiftDashSDKHost.shared.wallet?.bip44AccountXpub()
    }
}
