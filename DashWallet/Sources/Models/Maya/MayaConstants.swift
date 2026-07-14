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

/// Centralized constants for the Maya feature.
enum MayaConstants {
    private static let mayaScanHomeURL = URL(string: "https://www.mayascan.org") ?? URL(fileURLWithPath: "/")

    /// Maya's official support/community channel — used as the fallback on the failed-conversion
    /// screen when there is no on-chain transaction to show (failure before broadcast).
    static let supportURL = URL(string: "https://discord.com/invite/mayaprotocol") ?? URL(fileURLWithPath: "/")

    /// Maya fee documentation, opened from the "Learn more" action on the fee-info sheet.
    static let feesDocsURL = URL(string: "https://docs.mayaprotocol.com/deep-dive/how-it-works/fees") ?? URL(fileURLWithPath: "/")

    /// Deep link to an inbound transaction on the MayaScan block explorer.
    /// Used on the failed-conversion screen so the user can see what happened to their swap
    /// (including the automatic refund Maya issues on failure).
    static func mayaScanTransactionURL(txHash: String) -> URL {
        let encoded = txHash.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? txHash
        return URL(string: "https://www.mayascan.org/tx/\(encoded)") ?? mayaScanHomeURL
    }
}

enum NearConstants {
    private static let fallbackURL = URL(fileURLWithPath: "/")
    static let explorerHomeURL = URL(string: "https://explorer.near-intents.org/") ?? fallbackURL

    static func explorerTransactionURL(depositAddress: String) -> URL {
        let encoded = depositAddress.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? depositAddress
        return URL(string: "https://explorer.near-intents.org/transactions/\(encoded)") ?? explorerHomeURL
    }
}
