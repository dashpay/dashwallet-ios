//
//  ConnectionExpiryChecker.swift
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
import OSLog
import SwiftDashSDK

/// The active identity's keys as Platform has them and as the wallet's store
/// holds them.
struct ConnectionIdentityKeys: Equatable {
    /// Base58.
    let identityId: String
    let keys: [ManagedIdentity.IdentityPublicKeyInfo]
    let bindings: [AppConnect.KeyBinding]

    /// The SDK's key type is not `Equatable`: this compares every stored
    /// field of `ManagedIdentity.IdentityPublicKeyInfo`, and has to follow
    /// it when it gains one.
    static func == (lhs: ConnectionIdentityKeys, rhs: ConnectionIdentityKeys) -> Bool {
        lhs.identityId == rhs.identityId && lhs.bindings == rhs.bindings
            && lhs.keys.count == rhs.keys.count
            && zip(lhs.keys, rhs.keys).allSatisfy { left, right in
                left.keyId == right.keyId && left.purpose == right.purpose
                    && left.securityLevel == right.securityLevel && left.keyType == right.keyType
                    && left.readOnly == right.readOnly && left.disabledAt == right.disabledAt
                    && left.data == right.data && left.totalBudget == right.totalBudget
                    && left.expiresAt == right.expiresAt
            }
    }
}

/// How a read of the active identity's keys ended, as the host tells it.
enum ConnectionExpiryReadResult: Equatable {
    case keys(ConnectionIdentityKeys)
    /// The runtime is not there yet, or is changing wallets.
    case notReady
    /// The wallet has no identity loaded yet.
    case noIdentity
    /// The runtime's network has no identity to read.
    case unavailable
    /// The read failed; the message says why.
    case failed(String)
}

/// When the expiry check reads the identity's keys, judges them, waits, and
/// what it publishes: a reducer over the events that can change any of it.
/// It holds no clock and runs nothing itself: `ConnectionExpiryChecker` hands
/// it the clocks with each event and runs the effects it returns.
struct ConnectionExpiryMachine {
    struct Policy {
        /// How long to wait before each read again after a read found the
        /// runtime or the identity not ready; after the last, the check fails.
        var notReadyWaits: [TimeInterval] = [2, 5, 15]
        /// How long a read stays fresh enough for the page appearing again
        /// to judge its keys instead of reading anew.
        var freshRead: TimeInterval = 30
        /// The longest a clock deadline is waited for in one go; it is
        /// judged again then, and waited for further.
        var longestWait: TimeInterval = 24 * 60 * 60

        static let standard = Policy()
    }

    /// What the event is handled with: the clocks, and the identity the app
    /// uses (Base58), read as it arrives.
    struct Clocks {
        let now: Date
        let chainTime: Date?
        let identityId: String?
    }

    /// What a read and its verdicts are for.
    struct Key: Equatable {
        var scope: String?
        var identity: String?
    }

    struct Attempt: Equatable {
        let id: Int
        let key: Key
        /// The active rows when it started.
        let rows: [DAppConnection.ExpiryGeneration]
        /// The runtime generation it started with.
        let runtime: Int
    }

    /// A read that ended with what to judge, kept for judging again.
    struct Held: Equatable {
        /// `nil` when there is no identity whose keys to judge.
        let keys: ConnectionIdentityKeys?
        /// When it was read, by the phone's clock.
        let at: Date
        let key: Key
        let rows: [DAppConnection.ExpiryGeneration]
        let runtime: Int
        /// The Core tip time from which a verdict can change.
        var nextChainThreshold: Int64? = nil
        /// The phone time from which a verdict can change.
        var phoneDeadline: Int64? = nil
    }

    enum Failure: Equatable {
        case notReady
        case noIdentity
        case unavailable
        case error
    }

    enum Phase: Equatable {
        case notStarted
        case checking(Attempt)
        /// The read found the runtime or the identity not ready, and is
        /// made again after a wait.
        case backingOff(Attempt)
        case read(Held)
        case failed(Failure)
    }

    /// What is owed once the page is on screen and no read runs; a later
    /// one includes an earlier.
    enum Pending: Int, Comparable {
        case none
        case judge
        case read
        case forcedRead

        static func < (lhs: Pending, rhs: Pending) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Timer: Hashable {
        case backoff
        case phoneDeadline
    }

    enum Event: Equatable {
        /// The published rows, of the wallet `scope` names (`nil`: none).
        case listing(scope: String?, rows: [DAppConnection])
        /// The identity the app uses may have changed (another was picked,
        /// or a registration moved on).
        case identityMayHaveChanged
        /// The app came back to the foreground: the clocks may have moved on
        /// while the device slept.
        case foreground
        /// The page is on screen; `forcesRead` for Retry.
        case shown(forcesRead: Bool)
        case hidden
        /// The SDK runtime generation running now.
        case runtime(Int)
        case chainTip(Date)
        case readEnded(Attempt, ConnectionExpiryReadResult)
        case timerFired(Timer)
    }

    enum Effect: Equatable {
        case startRead(Attempt)
        case cancelRead
        case sleep(Timer, TimeInterval)
        case cancelTimer(Timer)
        case publish(ConnectionExpiries)
        case log(String)
    }

    /// Judges `apps` of the wallet `scope` on `keys` at the phone time and
    /// Core tip time given, in milliseconds; `nil` when it cannot judge for
    /// that wallet (it is no longer the active one).
    typealias Judge = (_ scope: String, _ apps: Set<String>, _ keys: ConnectionIdentityKeys,
                       _ nowMilliseconds: Int64, _ chainTimeMilliseconds: Int64?) -> [String: AppConnect.ExpiryJudgement]?

    let policy: Policy
    private let judgeKeys: Judge

    private(set) var phase = Phase.notStarted
    private(set) var shown = false
    private(set) var pending = Pending.none
    private(set) var key = Key()
    /// The key and runtime generation the last read started with.
    private(set) var keyOfLastAttempt: Key?
    private(set) var runtimeOfLastAttempt: Int?
    private(set) var runtime = 0
    private(set) var notReadyAttempts = 0
    /// The verdicts last told, by app; they hold for a published row of the
    /// same generation (`ConnectionExpiries.holding(for:)`).
    private(set) var verdicts: [String: ConnectionExpiry] = [:]
    /// The identity `verdicts` were told on.
    private var verdictsIdentity: String?
    /// The published rows.
    private(set) var rows: [DAppConnection] = []
    private var activeRows: [DAppConnection.ExpiryGeneration] = []
    /// The latest Core tip time seen for the wallet: the chain does not go
    /// back, so a judgement made without the tip (the SDK restarting) keeps
    /// what an earlier tip showed.
    private var latestChainTime: Date?
    private var nextAttemptId = 0

    init(policy: Policy = .standard, judge: @escaping Judge) {
        self.policy = policy
        self.judgeKeys = judge
    }

    /// The check as the page shows it.
    var expiries: ConnectionExpiries {
        let check: ConnectionExpiries.Check
        switch phase {
        case .checking: check = .checking
        case _ where pending >= .read: check = .checking
        case .notStarted, .backingOff: check = .notStarted
        case .read: check = .read
        case .failed(.unavailable): check = .unavailable
        case .failed: check = .failed
        }
        return ConnectionExpiries(identityId: verdictsIdentity, check: check, byApp: verdicts)
    }

    mutating func handle(_ event: Event, clocks: Clocks) -> [Effect] {
        let before = expiries
        var effects: [Effect] = []
        switch event {
        case .listing(let scope, let rows):
            listing(scope: scope, rows: rows, clocks: clocks, &effects)
        case .identityMayHaveChanged:
            if clocks.identityId != (keyOfLastAttempt ?? key).identity {
                key.identity = clocks.identityId
                restart(clocks, &effects)
            }
        case .foreground:
            guard shown else { break }
            switch phase {
            case .read(let held) where isFresh(held, clocks):
                judge(held, clocks, &effects)
            case .read:
                owe(.read, clocks, &effects)
                drive(clocks, &effects)
            case .failed(.notReady), .failed(.noIdentity):
                // The runtime or the identity may be ready by now.
                notReadyAttempts = 0
                owe(.read, clocks, &effects)
                drive(clocks, &effects)
            default:
                break
            }
        case .shown(let forcesRead):
            shown(forcesRead: forcesRead, clocks: clocks, &effects)
        case .hidden:
            shown = false
            effects += [.cancelTimer(.backoff), .cancelTimer(.phoneDeadline)]
            switch phase {
            case .checking:
                // The read is made again when the page is back.
                effects.append(.cancelRead)
                phase = .notStarted
                owe(.read, clocks, &effects)
            case .backingOff:
                phase = .notStarted
                owe(.read, clocks, &effects)
            default:
                break
            }
        case .runtime(let generation):
            runtime = generation
            if case .backingOff = phase {
                effects.append(.cancelTimer(.backoff))
                notReadyAttempts = 0
                owe(.read, clocks, &effects)
                drive(clocks, &effects)
            } else if generation != runtimeOfLastAttempt {
                owe(.read, clocks, &effects)
                drive(clocks, &effects)
            }
        case .chainTip(let tip):
            latestChainTime = max(latestChainTime ?? tip, tip)
            if case .read(let held) = phase, let threshold = held.nextChainThreshold,
               Self.milliseconds(tip) >= threshold {
                if shown { judge(held, clocks, &effects) } else { owe(.judge, clocks, &effects) }
            }
        case .timerFired(.phoneDeadline):
            if case .read(let held) = phase, shown { judge(held, clocks, &effects) }
        case .timerFired(.backoff):
            if case .backingOff = phase, shown { startRead(clocks, &effects) }
        case .readEnded(let attempt, let result):
            readEnded(attempt, result, clocks: clocks, &effects)
        }
        if expiries != before { effects.append(.publish(expiries)) }
        return effects
    }

    // MARK: - Transitions

    private mutating func listing(scope: String?, rows: [DAppConnection], clocks: Clocks, _ effects: inout [Effect]) {
        let active = DAppConnection.activeExpiryGenerations(rows)
        self.rows = rows
        guard scope == key.scope else {
            key.scope = scope
            activeRows = active
            latestChainTime = nil
            guard scope != nil else {
                reset(to: .notStarted, &effects)
                return
            }
            restart(clocks, &effects)
            return
        }
        guard active != activeRows else { return }
        activeRows = active
        owe(.read, clocks, &effects)
        drive(clocks, &effects)
    }

    private mutating func shown(forcesRead: Bool, clocks: Clocks, _ effects: inout [Effect]) {
        shown = true
        notReadyAttempts = 0
        effects.append(.cancelTimer(.backoff))
        if forcesRead { pending = .forcedRead }
        if case .checking = phase { return }
        if case .read(let held) = phase, !forcesRead, pending <= .judge,
           held.key == Key(scope: key.scope, identity: clocks.identityId), held.rows == activeRows {
            if isFresh(held, clocks) {
                pending = .none
                judge(held, clocks, &effects)
                return
            }
        }
        owe(.read, clocks, &effects)
        drive(clocks, &effects)
    }

    private mutating func readEnded(
        _ attempt: Attempt, _ result: ConnectionExpiryReadResult, clocks: Clocks, _ effects: inout [Effect]
    ) {
        guard case .checking(let running) = phase, running.id == attempt.id else { return }
        // What was read is of the wallet and the identity active now.
        var readIdentity: String? = attempt.key.identity
        if case .keys(let keys) = result { readIdentity = keys.identityId }
        guard attempt.key.scope == key.scope, attempt.key.identity == clocks.identityId,
              readIdentity == clocks.identityId else {
            phase = .notStarted
            key.identity = clocks.identityId
            restart(clocks, &effects)
            return
        }
        switch result {
        case .keys(let keys):
            notReadyAttempts = 0
            let held = Held(keys: keys, at: clocks.now, key: attempt.key, rows: attempt.rows, runtime: attempt.runtime)
            if !judge(held, clocks, &effects) {
                // Not this wallet's to judge any more: read again, as for a
                // read of another wallet; its listing restarts the check.
                phase = .notStarted
                owe(.read, clocks, &effects)
            }
        case .notReady:
            notReady(attempt, failure: .notReady, clocks, &effects)
        case .noIdentity:
            notReady(attempt, failure: .noIdentity, clocks, &effects)
        case .unavailable:
            keepExpired()
            phase = .failed(.unavailable)
        case .failed(let message):
            keepExpired()
            phase = .failed(.error)
            effects.append(.log(message))
        }
        drive(clocks, &effects)
    }

    /// No read could be made: made again after a wait while the page is on
    /// screen, failed once the waits are used up, and owed while it is not.
    private mutating func notReady(_ attempt: Attempt, failure: Failure, _ clocks: Clocks, _ effects: inout [Effect]) {
        keepExpired()
        guard shown else {
            phase = .notStarted
            owe(.read, clocks, &effects)
            return
        }
        guard notReadyAttempts < policy.notReadyWaits.count else {
            phase = .failed(failure)
            return
        }
        notReadyAttempts += 1
        phase = .backingOff(attempt)
        effects.append(.sleep(.backoff, policy.notReadyWaits[notReadyAttempts - 1]))
    }

    // MARK: - Helpers

    /// Nothing told holds any more: another wallet or identity is active.
    private mutating func restart(_ clocks: Clocks, _ effects: inout [Effect]) {
        reset(to: .notStarted, &effects)
        owe(.read, clocks, &effects)
        drive(clocks, &effects)
    }

    /// Stops the read and the waits, drops every verdict, and leaves
    /// `phase` with nothing owed.
    private mutating func reset(to phase: Phase, _ effects: inout [Effect]) {
        if case .checking = self.phase { effects.append(.cancelRead) }
        effects += [.cancelTimer(.backoff), .cancelTimer(.phoneDeadline)]
        verdicts = [:]
        verdictsIdentity = nil
        notReadyAttempts = 0
        pending = .none
        self.phase = phase
    }

    /// Owes `work`. With no active row there is nothing to read: the check
    /// is `.read` with no verdicts at once.
    private mutating func owe(_ work: Pending, _ clocks: Clocks, _ effects: inout [Effect]) {
        guard key.scope != nil else { return }
        guard work < .read || !activeRows.isEmpty else {
            reset(to: .read(Held(keys: nil, at: clocks.now, key: key, rows: [], runtime: runtime)), &effects)
            return
        }
        pending = max(pending, work)
    }

    /// Does what is owed, while the page is on screen and no read runs.
    private mutating func drive(_ clocks: Clocks, _ effects: inout [Effect]) {
        guard shown, key.scope != nil else { return }
        if case .checking = phase { return }
        if pending >= .read {
            startRead(clocks, &effects)
        } else if pending == .judge, case .read(let held) = phase {
            pending = .none
            judge(held, clocks, &effects)
        }
    }

    private mutating func startRead(_ clocks: Clocks, _ effects: inout [Effect]) {
        nextAttemptId += 1
        key.identity = clocks.identityId
        let attempt = Attempt(id: nextAttemptId, key: key, rows: activeRows, runtime: runtime)
        keyOfLastAttempt = attempt.key
        runtimeOfLastAttempt = runtime
        pending = .none
        phase = .checking(attempt)
        effects += [.cancelTimer(.backoff), .cancelTimer(.phoneDeadline), .startRead(attempt)]
    }

    /// Judges the active rows `held` was read for on its keys with the
    /// clocks as they are, and waits for the earliest phone time a clock can
    /// change a verdict. A row that changed since owes a read. A judge that
    /// cannot judge for the wallet changes nothing, and this returns false.
    @discardableResult
    private mutating func judge(_ held: Held, _ clocks: Clocks, _ effects: inout [Effect]) -> Bool {
        let nowMilliseconds = Self.milliseconds(clocks.now)
        if let chainTime = clocks.chainTime { latestChainTime = max(latestChainTime ?? chainTime, chainTime) }
        let readFor = Set(held.rows)
        let active = rows.filter { $0.status == .active && readFor.contains($0.expiryGeneration) }
        var judgements: [String: AppConnect.ExpiryJudgement] = [:]
        if let keys = held.keys, let scope = held.key.scope {
            guard let judged = judgeKeys(
                scope, Set(active.map(\.id)), keys, nowMilliseconds, latestChainTime.map(Self.milliseconds))
            else { return false }
            judgements = judged
        }
        // Every active row the read was made for gets a verdict; one with
        // nothing of this identity's to judge is `.notJudged`.
        verdicts = Dictionary(active.map {
            ($0.id, ConnectionExpiry(verdict: judgements[$0.id]?.verdict ?? .notJudged, row: $0))
        }, uniquingKeysWith: { first, _ in first })
        verdictsIdentity = held.keys?.identityId
        var judged = held
        judged.nextChainThreshold = judgements.values.compactMap(\.rejudgeAtChainTime).min()
        judged.phoneDeadline = judgements.values.compactMap(\.rejudgeAtPhoneTime).min()
        phase = .read(judged)
        effects.append(.cancelTimer(.phoneDeadline))
        if shown, let deadline = judged.phoneDeadline {
            let (difference, overflow) = deadline.subtractingReportingOverflow(nowMilliseconds)
            let wait = overflow ? policy.longestWait
                : min(max(0, TimeInterval(difference) / 1000), policy.longestWait)
            effects.append(.sleep(.phoneDeadline, wait))
        }
        if activeRows.contains(where: { !readFor.contains($0) }) { owe(.read, clocks, &effects) }
        return true
    }

    /// `held` was read less than `Policy.freshRead` ago; a read from the
    /// phone's future (its clock was set back) is not fresh.
    private func isFresh(_ held: Held, _ clocks: Clocks) -> Bool {
        let age = clocks.now.timeIntervalSince(held.at)
        return age >= 0 && age < policy.freshRead
    }

    /// An app shown expired stays so while its row is unchanged; an earlier
    /// `.current` is not kept, since time may have passed its keys' expiry.
    private mutating func keepExpired() {
        verdicts = ConnectionExpiries(identityId: verdictsIdentity, check: .read, byApp: verdicts)
            .holding(for: rows, onlyExpired: true).byApp
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64(AppConnect.milliseconds(date))
    }
}

/// Runs `ConnectionExpiryMachine`: hands it each event with the clocks read
/// as it arrives, reads the identity's keys, waits, and reports what the
/// page shows (`onChange`) when it changes.
@MainActor
final class ConnectionExpiryChecker {
    struct Dependencies {
        /// Reads the active identity's keys for the wallet scope given.
        var readKeys: (_ scope: String) async -> ConnectionExpiryReadResult
        var judge: ConnectionExpiryMachine.Judge
        var now: () -> Date
        /// The time of the last Core block this phone has synced.
        var chainTime: @MainActor () -> Date?
        /// The identity the app uses (Base58).
        var identityId: @MainActor () -> String?
        /// Waits the given seconds; throws when cancelled.
        var sleep: (TimeInterval) async throws -> Void
    }

    private static let logger = Logger(subsystem: "org.dashfoundation.dash", category: "dashconnect.expiry-check")

    private var machine: ConnectionExpiryMachine
    private let dependencies: Dependencies
    private let onChange: @MainActor (ConnectionExpiries) -> Void
    /// The check as last reported.
    private(set) var expiries: ConnectionExpiries
    private var readTask: Task<Void, Never>?
    private var timers: [ConnectionExpiryMachine.Timer: Task<Void, Never>] = [:]

    nonisolated init(
        dependencies: Dependencies,
        policy: ConnectionExpiryMachine.Policy = .standard,
        onChange: @escaping @MainActor (ConnectionExpiries) -> Void
    ) {
        let machine = ConnectionExpiryMachine(policy: policy, judge: dependencies.judge)
        self.machine = machine
        self.dependencies = dependencies
        self.onChange = onChange
        self.expiries = machine.expiries
    }

    deinit {
        readTask?.cancel()
        timers.values.forEach { $0.cancel() }
    }

    func listingChanged(scope: String?, rows: [DAppConnection]) { send(.listing(scope: scope, rows: rows)) }
    func identityMayHaveChanged() { send(.identityMayHaveChanged) }
    func foreground() { send(.foreground) }
    func pageShown(forcesRead: Bool) { send(.shown(forcesRead: forcesRead)) }
    func pageHidden() { send(.hidden) }
    func runtimeChanged(generation: Int) { send(.runtime(generation)) }
    func chainTipChanged(_ tip: Date) { send(.chainTip(tip)) }

    func send(_ event: ConnectionExpiryMachine.Event) {
        let clocks = ConnectionExpiryMachine.Clocks(
            now: dependencies.now(), chainTime: dependencies.chainTime(), identityId: dependencies.identityId())
        let effects = machine.handle(event, clocks: clocks)
        effects.forEach(run)
        if case .checking = machine.phase {
            assert(readTask != nil, "the check is checking with no read running")
        }
    }

    private func run(_ effect: ConnectionExpiryMachine.Effect) {
        switch effect {
        case .startRead(let attempt):
            readTask?.cancel()
            guard let scope = attempt.key.scope else { return }
            readTask = Task { [weak self, readKeys = dependencies.readKeys] in
                let result = await readKeys(scope)
                guard !Task.isCancelled, let self else { return }
                self.readTask = nil
                self.send(.readEnded(attempt, result))
            }
        case .cancelRead:
            readTask?.cancel()
            readTask = nil
        case .sleep(let timer, let seconds):
            timers[timer]?.cancel()
            timers[timer] = Task { [weak self, sleep = dependencies.sleep] in
                guard (try? await sleep(seconds)) != nil, !Task.isCancelled else { return }
                self?.send(.timerFired(timer))
            }
        case .cancelTimer(let timer):
            timers[timer]?.cancel()
            timers[timer] = nil
        case .publish(let expiries):
            guard expiries != self.expiries else { return }
            self.expiries = expiries
            onChange(expiries)
        case .log(let message):
            Self.logger.error("🔗 DASHCONNECT :: connection expiries not read — \(message, privacy: .public)")
        }
    }
}

/// Numbers the SDK managers as they come: the same manager keeps its
/// number, another one gets the next.
@MainActor
final class ManagerGenerations {
    private weak var last: AnyObject?
    private(set) var generation = 0

    nonisolated init() {}

    /// The number of `manager`; `nil` (none running) keeps the number.
    func generation(of manager: AnyObject?) -> Int {
        guard let manager, manager !== last else { return generation }
        last = manager
        generation += 1
        return generation
    }
}
