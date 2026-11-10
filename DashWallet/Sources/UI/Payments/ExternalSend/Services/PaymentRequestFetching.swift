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

/// What a fetched and verified payment request tells Send: where to pay and how much.
struct PaymentRequestDetails: Equatable {
    let address: String
    let amountDuffs: UInt64
    let merchantName: String?
    let memo: String?
    /// The request's signature verified against a trusted certificate (the old Send's 🔒).
    let isSecure: Bool
}

extension PaymentRequestDetails {
    /// The details of a request the BIP70 fetch verified; nil when it names no address.
    init?(box: BIP70ConfirmationBox) {
        guard let address = box.primaryAddress else { return nil }
        self.init(address: address, amountDuffs: box.amount, merchantName: box.merchantName, memo: box.memo,
                  isSecure: box.isSecure)
    }
}

/// Fetches and verifies a BIP70 payment request. It does not build or spend anything.
@MainActor
protocol PaymentRequestFetching {
    func fetch(url: URL, callbackScheme: String?) async throws -> PaymentRequestDetails
}

/// The existing BIP70 fetch of the interactive coordinator, awaited.
struct LivePaymentRequestFetcher: PaymentRequestFetching {
    private struct MissingAddress: LocalizedError {
        var errorDescription: String? {
            NSLocalizedString("The payment request has no address", comment: "External send")
        }
    }

    func fetch(url: URL, callbackScheme: String?) async throws -> PaymentRequestDetails {
        try await withCheckedThrowingContinuation { continuation in
            let coordinator = BIP70InteractiveCoordinator()
            coordinator.fetchAndVerify(requestURL: url, scheme: "dash", callbackScheme: callbackScheme) { box, error in
                withExtendedLifetime(coordinator) {}
                guard let box else {
                    continuation.resume(throwing: error ?? MissingAddress())
                    return
                }
                guard let details = PaymentRequestDetails(box: box) else {
                    continuation.resume(throwing: MissingAddress())
                    return
                }
                continuation.resume(returning: details)
            }
        }
    }
}
