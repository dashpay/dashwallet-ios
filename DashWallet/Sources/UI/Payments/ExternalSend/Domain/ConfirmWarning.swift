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

/// A note Confirm lists for a source and destination pair.
enum ConfirmWarning: Equatable, Hashable {
    /// Shielded to a non-Shielded destination makes the amount and the destination public.
    case shieldedMadePublic
    /// Shielded to Core is not instant: it takes the place of "Processing time" on that pair.
    case shieldedNotInstant
    /// "Double-check the address": the default note of the current Send.
    case wrongAddressReminder
    /// "Processing time": Platform to Core.
    case processingTime
    /// Platform to Core for the whole Platform balance.
    case fullPlatformWithdrawal
    /// Core to Shielded for the whole Core balance.
    case emptyingCoreBalance
}

/// The wording of the warnings the current Send already shows (AC-18), shared by its confirm sheet and Confirm.
enum SendWarningText {
    static var coreDrainTitle: String {
        NSLocalizedString("Sends all eligible Transparent funds", comment: "Send confirm sheet: Core drain")
    }

    static var coreDrainBody: String {
        // swiftlint:disable line_length
        NSLocalizedString(
            "All eligible funds in your Transparent balance will be sent to this address when you confirm. Nothing is kept as change. The amount and fees are estimates. CoinJoin funds are excluded. Dash sent to a wrong address can't be recovered.",
            comment: "Send confirm sheet: Core drain")
        // swiftlint:enable line_length
    }

    static var processingTimeTitle: String { NSLocalizedString("Processing time", comment: "") }

    static var doubleCheckTitle: String {
        NSLocalizedString("Double-check the address", comment: "Send confirm sheet")
    }

    static var doubleCheckBody: String {
        // swiftlint:disable line_length
        NSLocalizedString(
            "Dash sent to a wrong address can't be recovered. Make sure the address is exactly the one you intend to pay.",
            comment: "Send confirm sheet")
        // swiftlint:enable line_length
    }

    static var shieldedWithdrawalBody: String {
        // swiftlint:disable line_length
        NSLocalizedString(
            "The Dash arrives at the recipient's address after the network processes the withdrawal — this can take up to 10 minutes.",
            comment: "Send confirm sheet")
        // swiftlint:enable line_length
    }

    static var fullPlatformWithdrawalBody: String {
        // swiftlint:disable line_length
        NSLocalizedString(
            "This withdraws your entire Platform balance in one transfer. The Dash arrives at the recipient's address once the network processes the withdrawal.",
            comment: "Send confirm sheet")
        // swiftlint:enable line_length
    }

    static var platformWithdrawalBody: String {
        NSLocalizedString(
            "The Dash arrives at the recipient's address once the network processes the withdrawal.",
            comment: "Send confirm sheet")
    }
}
