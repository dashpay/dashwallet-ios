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

/// What a fetched and verified payment request tells Send: where to pay and how much. `confirmation` is the
/// verified request itself, which the send builds and signs; it serves one send attempt, and a Retry fetches the
/// request again.
struct PaymentRequestDetails: Equatable {
    let address: String
    let confirmation: BIP70ConfirmationBox

    var amountDuffs: UInt64 { confirmation.amount }
    var merchantName: String? { confirmation.merchantName }
    var memo: String? { confirmation.memo }
    /// The request's signature verified against a trusted certificate (the old Send's 🔒).
    var isSecure: Bool { confirmation.isSecure }
}

extension PaymentRequestDetails {
    /// The details of a request the BIP70 fetch verified; nil when it names no address.
    init?(box: BIP70ConfirmationBox) {
        guard let address = box.primaryAddress else { return nil }
        self.init(address: address, confirmation: box)
    }
}

/// Fetches and verifies a BIP70 payment request. It does not build or spend anything.
@MainActor
protocol PaymentRequestFetching {
    func fetch(url: URL, callbackScheme: String?) async throws -> PaymentRequestDetails
}

/// The existing BIP70 fetch of the interactive coordinator, awaited. A cancelled fetch ends at once with
/// `CancellationError`; the coordinator's answer that arrives afterwards is dropped.
struct LivePaymentRequestFetcher: PaymentRequestFetching {
    /// Starts fetching and verifying the request at `url`; `completion` runs once, on the main thread.
    typealias Start = (_ url: URL, _ callbackScheme: String?,
                       _ completion: @escaping (BIP70ConfirmationBox?, Error?) -> Void) -> Void

    private struct MissingAddress: LocalizedError {
        var errorDescription: String? {
            NSLocalizedString("The payment request has no address", comment: "External send")
        }
    }

    private let start: Start

    init(start: @escaping Start = Self.coordinatorFetch) {
        self.start = start
    }

    private static func coordinatorFetch(url: URL, callbackScheme: String?,
                                         completion: @escaping (BIP70ConfirmationBox?, Error?) -> Void) {
        let coordinator = BIP70InteractiveCoordinator()
        coordinator.fetchAndVerify(requestURL: url, scheme: "dash", callbackScheme: callbackScheme) { box, error in
            withExtendedLifetime(coordinator) {}
            completion(box, error)
        }
    }

    func fetch(url: URL, callbackScheme: String?) async throws -> PaymentRequestDetails {
        let pending = PendingFetch()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard pending.wait(continuation) else { return }
                start(url, callbackScheme) { box, error in
                    guard let box else { return pending.resume(.failure(error ?? MissingAddress())) }
                    pending.resume(PaymentRequestDetails(box: box).map { .success($0) } ?? .failure(MissingAddress()))
                }
            }
        } onCancel: {
            pending.cancel()
        }
    }
}

/// One fetch's continuation, resumed once: by the fetch's answer or by its task's cancellation, whichever comes
/// first. The cancellation can arrive on any thread, so the state is locked.
private final class PendingFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PaymentRequestDetails, Error>?
    private var isCancelled = false

    /// Keeps `continuation` for the answer; false when the task was already cancelled and it was resumed instead.
    func wait(_ continuation: CheckedContinuation<PaymentRequestDetails, Error>) -> Bool {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func resume(_ result: Result<PaymentRequestDetails, Error>) {
        take()?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
        take()?.resume(throwing: CancellationError())
    }

    private func take() -> CheckedContinuation<PaymentRequestDetails, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let taken = continuation
        continuation = nil
        return taken
    }
}
