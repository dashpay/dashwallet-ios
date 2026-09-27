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
/// A screen an operation shows (its amount step) is bound to the operation;
/// input from a screen bound to an obsolete operation — one left on a
/// navigation stack, or reached by going back — is refused the same way.
///
/// Pure, so the admission rule is unit-tested without the processor.
struct PaymentOperationGate {
    typealias Token = Int

    private(set) var current: Token?
    private var next: Token = 0
    private var screens: [ObjectIdentifier: Token] = [:]

    /// Starts a new operation; every earlier one is obsolete from here on,
    /// and so is every screen bound to one.
    mutating func begin() -> Token {
        next += 1
        current = next
        screens = [:]
        return next
    }

    /// Binds `screen` to the operation `token`; refused — and nothing
    /// changes — unless `token` is current.
    mutating func bind(_ screen: ObjectIdentifier, to token: Token) {
        guard admits(token) else { return }
        screens[screen] = token
    }

    /// Whether input from `screen` belongs to the current operation: the
    /// screen is bound, and to the operation that is current.
    func admits(screen: ObjectIdentifier) -> Bool {
        guard let token = screens[screen] else { return false }
        return admits(token)
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
        screens = [:]
        return true
    }
}
