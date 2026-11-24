//
//  MasternodeClaimableBalance.swift
//  DashWallet
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
import SwiftDashSDK

/// The credits a masternode's Platform identity holds, or the fact that it
/// has no Platform identity. A failed read is neither: `fetch` throws it.
enum MasternodeClaimableBalance: Equatable {
    case credits(UInt64)
    case noIdentity

    /// Reads the balance of the identity `identityId` (a masternode's
    /// ProTxHash in identity byte order). The batch read answers a missing
    /// identity with no balance rather than with an error, so "no identity"
    /// is told from a failed read without looking at an error's text.
    static func fetch(sdk: SDK, identityId: Data) throws -> MasternodeClaimableBalance {
        try fetch(identityId: identityId) { try sdk.identities.fetchBalances(ids: $0) }
    }

    /// `fetch(sdk:identityId:)` with the batch read passed in: asks
    /// `fetchBalances` for `identityId` alone and lets its failure through.
    static func fetch(
        identityId: Data,
        fetchBalances: ([Data]) throws -> [Data: UInt64?]
    ) throws -> MasternodeClaimableBalance {
        resolve(try fetchBalances([identityId]), identityId: identityId)
    }

    /// The balance `balances` holds for `identityId`; an identity with no
    /// entry, or an entry with no balance, has no Platform identity.
    static func resolve(_ balances: [Data: UInt64?], identityId: Data) -> MasternodeClaimableBalance {
        guard let credits = balances[identityId] ?? nil else { return .noIdentity }
        return .credits(credits)
    }
}
