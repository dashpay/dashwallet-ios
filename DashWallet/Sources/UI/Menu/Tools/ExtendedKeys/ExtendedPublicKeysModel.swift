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
import SwiftData
import SwiftDashSDK

// MARK: - ExtendedPublicKeysModel

@MainActor
final class ExtendedPublicKeysModel {
    /// The SDK wallet's BIP44 account-0 extended public key (xpub/tpub
    /// base58check), rendered from the account bytes the wallet persisted. It
    /// is `nil` when the wallet runtime isn't up or the bytes are missing. The
    /// sheet then shows "Not available".
    let bip44AccountXpub: String?

    /// The `standardTag` of a Standard account's BIP44 variant.
    private static let bip44StandardTag: UInt8 = 0

    init() {
        let host = SwiftDashSDKHost.shared
        guard let walletId = host.wallet?.walletId,
              let context = host.modelContainer?.mainContext else {
            bip44AccountXpub = nil
            return
        }
        bip44AccountXpub = Self.loadBIP44AccountXpub(context: context, walletId: walletId)
    }

    /// Renders the xpub from the persisted BIP-44 account 0 bytes of
    /// `walletId`, or nil when the row or its bytes are missing.
    static func loadBIP44AccountXpub(context: ModelContext, walletId: Data) -> String? {
        let standardType = PersistentAccount.standardAccountType
        let bip44Tag = bip44StandardTag
        let accountIndex: UInt32 = 0
        var descriptor = FetchDescriptor<PersistentAccount>(
            predicate: #Predicate {
                $0.wallet.walletId == walletId &&
                    $0.accountType == standardType &&
                    $0.standardTag == bip44Tag &&
                    $0.accountIndex == accountIndex
            })
        descriptor.fetchLimit = 1
        guard let bytes = (try? context.fetch(descriptor))?.first?.accountExtendedPubKeyBytes else {
            return nil
        }
        return PlatformWalletManager.accountExtendedPubKeyString(bytes: bytes)
    }
}
