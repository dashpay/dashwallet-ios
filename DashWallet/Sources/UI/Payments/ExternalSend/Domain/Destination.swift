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

/// What a typed, pasted, scanned or linked text turned out to be, for the selected network.
/// A pure value: no SDK types.
struct Destination: Equatable {
    enum Kind: Equatable {
        case coreAddress
        case shieldedAddress
        case platformAddress
        case identityID
        /// An address-less `dash:?r=…` link: the address and amount come from the merchant's request.
        case paymentRequest
    }

    let type: Kind
    /// The trimmed address itself, without any `dash:` scheme or query. Empty for `.paymentRequest`.
    let text: String
    /// P2SH (Core) or 0x80 (Platform) rather than P2PKH / 0xb0.
    let isScriptForm: Bool
    /// The `dash:` link's amount in duffs.
    let amountDuffs: UInt64?
    let label: String?
    let message: String?
    /// The `dash:` link's payment-request (`r=`) URL. Fetching it stays in the existing BIP70 path.
    let paymentRequestURL: URL?
    /// The link's `sender=` scheme, which the merchant's callback URL is built for.
    let callbackScheme: String?
    /// `label` is the name of a payment request's merchant whose signature verified.
    let isVerifiedMerchant: Bool
    /// The payment request fetched and verified when the link was opened: Confirm shows it and the send builds and
    /// signs it, without fetching it again. It serves one send attempt; a Retry fetches the request again.
    let verifiedRequest: BIP70ConfirmationBox?

    init(type: Kind, text: String, isScriptForm: Bool = false, amountDuffs: UInt64? = nil,
         label: String? = nil, message: String? = nil, paymentRequestURL: URL? = nil,
         callbackScheme: String? = nil, isVerifiedMerchant: Bool = false,
         verifiedRequest: BIP70ConfirmationBox? = nil) {
        self.type = type
        self.text = text
        self.isScriptForm = isScriptForm
        self.amountDuffs = amountDuffs
        self.label = label
        self.message = message
        self.paymentRequestURL = paymentRequestURL
        self.callbackScheme = callbackScheme
        self.isVerifiedMerchant = isVerifiedMerchant
        self.verifiedRequest = verifiedRequest
    }
}

enum DestinationParseError: Error, Equatable {
    /// A valid address (checksum holds) that belongs to another network.
    case wrongNetwork
    case invalid
}
