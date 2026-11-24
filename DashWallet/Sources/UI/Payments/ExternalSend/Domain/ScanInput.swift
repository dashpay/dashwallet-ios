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

/// A scanned code or a dash: link, read once into what it pays. The scanner and the link entry build it, the host
/// presents nothing for text that builds none, and the flow opens it as it is.
struct ScanInput {
    let destination: Destination
    /// The payment request the scanner already fetched and verified with the code; it is not fetched again.
    let prefetched: PaymentRequestDetails?
    /// The scanner's fetch of the code's `r=` request failed and it fell back to the code's own Core address: the
    /// destination has no request to fetch.
    let requestCleared: Bool
    /// Another app opened the link, so its `sender=` callback scheme is kept.
    let openedByApp: Bool

    /// nil when `text` is not valid on `network`. A `dashwallet://pay=` link is read as the deep-link router reads it,
    /// and a payment-request URL scanned whole (BIP73) is a merchant request. With `requestCleared` a code's optional
    /// request is dropped: the destination is the code's own Core address, with its amount, label and message, and a
    /// code with no address is not valid. A required request (`req-r`) is kept, so the flow fetches it again and
    /// reports its failure instead of paying the address.
    init?(text: String, network: WalletEnvironment.NetworkKind, prefetched: PaymentRequestDetails? = nil,
          openedByApp: Bool = false, requestCleared: Bool = false) {
        guard let destination = Self.destination(
            of: text, network: network, openedByApp: openedByApp, requestCleared: requestCleared) else { return nil }
        self.destination = destination
        self.prefetched = prefetched
        self.requestCleared = requestCleared
        self.openedByApp = openedByApp
    }

    private static func destination(of text: String, network: WalletEnvironment.NetworkKind, openedByApp: Bool,
                                    requestCleared: Bool) -> Destination? {
        let paymentString = ParsedPaymentURI.paymentString(for: text)
        if case .success(let parsed) = DestinationParser.parse(paymentString, network: network,
                                                               openedByApp: openedByApp) {
            guard requestCleared, parsed.paymentRequestURL != nil, !parsed.isPaymentRequestRequired else {
                return parsed
            }
            guard parsed.type != .paymentRequest else { return nil }
            return parsed.droppingPaymentRequest()
        }
        guard !requestCleared else { return nil }
        let trimmed = paymentString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let requestURL = DestinationParser.paymentRequestURL(url) else {
            return nil
        }
        return Destination(type: .paymentRequest, text: "", paymentRequestURL: requestURL)
    }
}
