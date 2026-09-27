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

/// Which payment a `PaymentController` is running. One controller serves a
/// screen for its lifetime, and a payment's preparation can outlive the
/// next payment's start (a BIP70 fetch, a BIP73 hop); every payment is an
/// operation with its own token, and a callback is admitted only for the
/// operation that is current — an obsolete operation's callback must not
/// mutate state, present anything or settle a later operation's link.
///
/// Pure, so the admission rule is unit-tested without the processor.
struct PaymentOperationGate {
    typealias Token = Int

    private(set) var current: Token?
    private var next: Token = 0

    /// Starts a new operation; every earlier one is obsolete from here on.
    mutating func begin() -> Token {
        next += 1
        current = next
        return next
    }

    /// Whether a callback tagged `token` belongs to the current operation.
    func admits(_ token: Token) -> Bool {
        current == token
    }

    /// Ends the current operation when `token` is it; false — and nothing
    /// changes — for an obsolete or already-ended operation.
    @discardableResult
    mutating func end(_ token: Token) -> Bool {
        guard admits(token) else { return false }
        current = nil
        return true
    }
}
