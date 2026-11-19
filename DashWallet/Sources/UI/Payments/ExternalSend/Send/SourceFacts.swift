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

/// What Send knows about the source it pays from. One source operation owns it: a source change replaces it whole,
/// so nothing read for an earlier source lands on a later one, and a value that could not be read stays unknown.
struct SourceFacts: Equatable {
    enum Balance: Equatable {
        case loading
        /// The balance could not be read: it is neither 0 nor too little.
        case unknown
        /// In the source's own unit: credits for an Identity, duffs otherwise.
        case known(UInt64)
    }

    /// The route's fee estimate, in the source's own unit.
    enum Fee: Equatable {
        case pending
        case known(UInt64)
        case failed
    }

    /// Whether the route's funding step can pay the amount (`SendMaxPlanning.canFund`).
    enum Funding: Equatable {
        case pending
        case ok
        case refused
        /// What the funding step draws on could not be read.
        case unknown

        init(_ check: SendFundingCheck) {
            switch check {
            case .notChecked, .fundable: self = .ok
            case .notFundable: self = .refused
            case .unknown: self = .unknown
            }
        }
    }

    /// The amount is the route's Max: being planned after a Max tap, being planned again for a new source or balance
    /// (the amount already was a Max), or planned, with the Shielded sweep plan's exact credits.
    enum Max: Equatable {
        case planning
        case replanning
        case planned(sweepCredits: UInt64?)
    }

    let source: SendSource
    /// nil while no source is picked yet.
    let route: SendRoute?
    var balance: Balance = .loading
    var fee: Fee = .pending
    var funding: Funding = .pending
    /// nil while the amount is typed.
    var max: Max?
    /// Confirm refused the typed amount on its binding fee, which can be above Send's estimate. Holds until the
    /// amount or the source changes.
    var confirmRefusedAmount = false

    var knownBalance: UInt64? {
        if case .known(let value) = balance { return value }
        return nil
    }

    var knownFee: UInt64? {
        if case .known(let value) = fee { return value }
        return nil
    }
}
