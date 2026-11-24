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
        .toast(message: String(localized: "Sent", comment: "External send"))
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
    /// The lock-held sheet: Finish resumes the lock, Close leaves it for the transaction details.
    case lockHeld(HeldAssetLock)
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
                title: String(localized: "Send in progress", comment: "External send"),
                message: String(
                    localized: "Don't send it again. It can take a few minutes to finish.", comment: "External send"))
        case .lockHeld(let lock):
            return .lockHeld(lock)
        case .notSent(let reason):
            return .sendFailed(SendFailedContent(
                title: String(localized: "Send failed", comment: "External send"),
                reason: reason.localizedMessage,
                info: String(localized: "Nothing was sent. Your money is still in your \(SendAmountViewModel.title(of: request.route.source)) balance.", comment: "External send")))
        }
    }
}
