//
//  IdentityCreditsWatcher.swift
//  DashWallet
//
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
import SwiftDashSDK

/// Watches the Current identity's credits while the Identity option is open
/// and decides when they rose enough for a Receipt.
///
/// Platform reports a balance, not incoming transfers, so the watch compares
/// balances: the Starting balance is the first successful fresh read of the
/// session (never a stored value), a lower balance replaces it, an own top-up
/// (`IdentityTopUpDidComplete`) raises it by the credits added, and a rise of
/// at least 1 duff over it is one Receipt for the whole rise, which ends the
/// session. Reads run on the Platform option's cadence and only while the gate
/// is open (card visible, not covered, app in the foreground): closing the gate
/// cancels the timer and keeps the session, opening it checks at once. Created
/// and owned by `PaymentsLandingViewModel`; not shared.
@MainActor
final class IdentityCreditsWatcher {
    struct Session: Equatable {
        let walletId: Data
        let network: Network
        let identityId: Data
    }

    enum State: Equatable {
        /// No successful read yet, the last read failed, or no session.
        case notWatching
        case watching
        /// The rise over the Starting balance, in whole duffs.
        case received(duffs: UInt64)
    }

    typealias Read = @MainActor (Session) async -> Result<UInt64, Error>
    typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor () async -> Void) -> Task<Void, Never>

    /// Runs `tick` now and then every `interval` until cancelled.
    static let repeating: Schedule = { interval, tick in
        Task { @MainActor in
            while !Task.isCancelled {
                await tick()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private(set) var state: State = .notWatching {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    var onStateChange: ((State) -> Void)?

    private let read: Read
    private let schedule: Schedule
    private let center: NotificationCenter
    private var session: Session?
    private var startingBalance: UInt64?
    private var isGateOpen = false
    private var timer: Task<Void, Never>?
    private var topUpObserver: NSObjectProtocol?
    /// Bumped by every start, stop, gate close and own top-up: a read answered under an
    /// older token is dropped.
    private var readToken: UInt64 = 0
    private var isReading = false

    init(read: @escaping Read,
         schedule: @escaping Schedule = IdentityCreditsWatcher.repeating,
         center: NotificationCenter = .default) {
        self.read = read
        self.schedule = schedule
        self.center = center
        #if DASHPAY
        // Always posted on the main actor (see `IdentityTopUpDidComplete`).
        topUpObserver = center.addObserver(
            forName: IdentityTopUpDidComplete.name, object: nil, queue: nil
        ) { [weak self] note in
            guard let event = IdentityTopUpDidComplete(notification: note) else { return }
            MainActor.assumeIsolated { self?.apply(event) }
        }
        #endif
    }

    deinit {
        timer?.cancel()
        if let topUpObserver { center.removeObserver(topUpObserver) }
    }

    func start(_ session: Session) {
        stop()
        self.session = session
        if isGateOpen { startTimer() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        session = nil
        startingBalance = nil
        readToken &+= 1
        isReading = false
        state = .notWatching
    }

    /// Open while the card is visible, not covered and the app is active.
    /// Own top-ups count whatever the gate.
    func setGateOpen(_ open: Bool) {
        guard open != isGateOpen else { return }
        isGateOpen = open
        if open {
            if session != nil { startTimer() }
        } else {
            // Cancelling the timer cancels the read it runs; drop its answer.
            timer?.cancel()
            timer = nil
            readToken &+= 1
            isReading = false
        }
    }

    private func startTimer() {
        timer?.cancel()
        timer = schedule(AttendedReceiveRefreshPolicy.platformInterval) { [weak self] in
            await self?.check()
        }
    }

    private func check() async {
        guard let session, isGateOpen, !isReading else { return }
        let token = readToken
        isReading = true
        let result = await read(session)
        guard token == readToken, self.session == session else { return }
        isReading = false

        guard case .success(let balance) = result else {
            state = .notWatching
            return
        }
        guard let starting = startingBalance, balance >= starting else {
            startingBalance = balance
            state = .watching
            return
        }
        let rise = balance - starting
        let creditsPerDuff = PlatformCreditsFormatter.creditsPerDuff
        guard rise >= creditsPerDuff else {
            state = .watching
            return
        }
        timer?.cancel()
        timer = nil
        self.session = nil
        state = .received(duffs: rise / creditsPerDuff)
    }

    #if DASHPAY
    private func apply(_ event: IdentityTopUpDidComplete) {
        guard let session,
              event.identityId == session.identityId,
              event.walletId == session.walletId,
              event.network == session.network
        else { return }
        // A read in flight may answer with the balance before the top-up.
        readToken &+= 1
        isReading = false
        if let startingBalance {
            self.startingBalance = startingBalance + event.creditsAdded
        }
    }
    #endif
}
