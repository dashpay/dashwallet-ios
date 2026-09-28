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

    /// A token for an operation that never becomes current (a newcomer
    /// refused while another one owns the screen): nothing it reports is
    /// admitted, and the current operation and its screens are untouched.
    mutating func issue() -> Token {
        next += 1
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

/// Replacement and link settlement of the operations a link handler runs
/// one after another, over `PaymentOperationGate`: `PaymentController`'s
/// payments and `ConnectionsViewModel`'s DashConnect requests.
///
/// An operation started by a deep link carries the link queue's completion
/// (`settled`) and its abandonment check; one started by hand carries
/// neither. Every operation's completion runs exactly once:
/// when the operation settles itself, or when a later operation replaces it
/// — whoever replaces it. Replacement is reentrancy-safe:
///
/// - the new operation is current before any predecessor is notified, so
///   nothing a notification triggers can be overwritten by the caller that
///   started the replacement;
/// - a completion is detached at once but delivered through `deliver` —
///   the next main-queue turn in the app — so the queue's next hand-over,
///   which can start another operation on this same handler, never runs
///   inside the call that settled the previous one;
/// - a caller that did get re-entered finds its token no longer admitted
///   (`admits(_:)`) and stops; its operation was settled by the one that
///   replaced it.
///
/// Pure apart from `deliver`, so the ordering is unit-tested.
final class LinkOperationSequence {
    typealias Token = PaymentOperationGate.Token

    private struct Settlement {
        let settled: () -> Void
        let isAbandoned: (() -> Bool)?
    }

    private var gate = PaymentOperationGate()
    private var settlements: [Token: Settlement] = [:]
    private let deliver: (@escaping () -> Void) -> Void

    init(deliver: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.deliver = deliver
    }

    var current: Token? { gate.current }

    /// Starts an operation and makes it current, then settles every
    /// operation it replaces — except those in `kept`, whose settlement
    /// still waits for something of theirs (a published alert) to appear.
    /// `settled` (nil for an operation that no link waits on) runs once,
    /// later, on the delivery queue.
    func begin(settled: (() -> Void)?, isAbandoned: (() -> Bool)?, keeping kept: Set<Token> = []) -> Token {
        let token = gate.begin()
        if let settled {
            settlements[token] = Settlement(settled: settled, isAbandoned: isAbandoned)
        }
        for replaced in settlements.keys.filter({ $0 != token && !kept.contains($0) }).sorted() {
            settle(replaced)
        }
        return token
    }

    /// Takes a newcomer that is refused, without starting it: the current
    /// operation stays current and nothing already pending is settled.
    /// The returned token carries only the newcomer's own `settled`, for
    /// `settle(_:)` once its refusal is shown; it is never admitted.
    func refuse(settled: (() -> Void)?) -> Token {
        let token = gate.issue()
        if let settled {
            settlements[token] = Settlement(settled: settled, isAbandoned: nil)
        }
        return token
    }

    /// Whether a callback tagged `token` belongs to the current operation.
    func admits(_ token: Token) -> Bool {
        gate.admits(token)
    }

    func bind(_ screen: ObjectIdentifier, to token: Token) {
        gate.bind(screen, to: token)
    }

    func admits(screen: ObjectIdentifier) -> Bool {
        gate.admits(screen: screen)
    }

    /// Whether `token`'s link still waits for its completion.
    func awaitsSettlement(_ token: Token) -> Bool {
        settlements[token] != nil
    }

    /// Whether the link queue has given `token`'s payment up. False once
    /// the payment is settled: a settled link is no longer the queue's
    /// concern, and the payment's later screens (a confirmation after its
    /// amount step) are its own.
    func isAbandoned(_ token: Token) -> Bool {
        settlements[token]?.isAbandoned?() == true
    }

    /// Detaches `token`'s completion and delivers it; a no-op when it has
    /// already been settled (or never had one).
    func settle(_ token: Token) {
        guard let settlement = settlements.removeValue(forKey: token) else { return }
        deliver(settlement.settled)
    }
}
