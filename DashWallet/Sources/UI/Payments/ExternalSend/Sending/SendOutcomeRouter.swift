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

/// The existing success view a `sent` outcome shows.
enum SendSuccessView: Equatable {
    /// A send with a Core transaction: the transaction success screen of the old Send.
    case transactionDetails
    /// A send with no Core transaction to show: the sheet closes and a success Toast shows over Home.
    case toast(message: String)

    static var sentToast: SendSuccessView {
        .toast(message: NSLocalizedString("Sent", comment: "External send"))
    }
}

/// What Send failed (SCR-10) shows, all of it already localized text.
struct SendFailedContent: Equatable {
    let title: String
    let reason: String
    /// "Nothing was sent. Your money is still in your <source> balance."
    let info: String
}

/// Where a send outcome goes after Confirm (SCR-09, SCR-10).
enum SendOutcomeDestination: Equatable {
    case success(SendSuccessView)
    /// The sheet closes and an info Toast shows over Home; no Retry.
    case infoToast(title: String, message: String)
    /// The only destination with Retry (ADR-0040).
    case sendFailed(SendFailedContent)
}

/// Maps the outcome of a send to its destination (ADR-0040). Pure: the flow shows the destination.
struct SendOutcomeRouter {
    func destination(for outcome: SendOutcome, request: SendAmountRequest) -> SendOutcomeDestination {
        switch outcome {
        case .sent:
            return .success(request.route.source == .core ? .transactionDetails : .sentToast)
        case .inFlight:
            return .infoToast(
                title: NSLocalizedString("Send in progress", comment: "External send"),
                message: NSLocalizedString(
                    "It will finish on its own. You don't need to send it again.", comment: "External send"))
        case .notSent(let reason):
            return .sendFailed(SendFailedContent(
                title: NSLocalizedString("Send failed", comment: "External send"),
                reason: reason.localizedMessage,
                info: String(
                    format: NSLocalizedString(
                        "Nothing was sent. Your money is still in your %@ balance.", comment: "External send"),
                    SendAmountViewModel.title(of: request.route.source))))
        }
    }
}
