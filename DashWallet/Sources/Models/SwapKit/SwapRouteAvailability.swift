//
//  SwapRouteAvailability.swift
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

import Combine
import Foundation

// MARK: - LiveRouteState

/// What one routing provider answered, right now, for one asset in one direction.
///
/// The `/tokens` classification says which provider *can ever* carry an asset; this says whether it
/// carries it at the moment. The two disagree whenever a chain is halted on Maya, or NEAR's DASH leg
/// is down, or SwapKit's own leg to a provider fails for a chain the provider itself still quotes.
enum LiveRouteState: Equatable {
    /// The provider returned a route (or only complained that the probe amount was too small).
    case available
    /// The provider reported a trading halt for this pair.
    case halted
    /// The provider has no route for this pair.
    case noRoute
    /// The answer said nothing conclusive: a transport failure, an upstream error, an empty reply.
    case unknown

    /// Whether the provider may be offered for the asset. An inconclusive answer keeps the
    /// provider: a flaky request must not halt a coin that may well be routable.
    var isUsable: Bool {
        switch self {
        case .available, .unknown: return true
        case .halted, .noRoute: return false
        }
    }

    /// Classifies a quote that was forced to the SwapKit providers of ONE `RouteProvider` (both
    /// Maya flavours count as one).
    ///
    /// Each provider error is read on its own and the most favourable reading wins: a flavour that
    /// routes (or only found the amount too small) means the provider can carry the coin, and a
    /// flavour that failed inconclusively leaves the question open. Only when every flavour that
    /// spoke said halt or no-route is the answer conclusive. A flavour that is not listed has no
    /// opinion; one listed without a code failed without saying why, which is inconclusive.
    ///
    /// A top-level `noRoutesFound` with no provider errors counts as a conclusive no-route here,
    /// unlike on the amount screens: SwapKit also answers it for an amount far below a route's
    /// floor, but the probes this classifies are sized at ~$50 (`SwapKitSwapProvider.probeAmount`)
    /// and the address screen's no-route re-check at 1 DASH (`addressCheckAmount`), both well above
    /// every floor measured (the DASH → BTC minimum was 0.175 DASH on 2026-08-28).
    static func classify(_ response: SwapKitQuoteResponse) -> LiveRouteState {
        if response.routes?.isEmpty == false {
            return .available
        }

        let states = (response.providerErrors ?? []).map { error -> LiveRouteState in
            guard let code = error.errorCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
                return .unknown
            }
            if SwapKitErrorCopy.isBelowMinimum(code) { return .available }
            if SwapKitErrorCopy.isHalted(code) { return .halted }
            if SwapKitErrorCopy.isNoRoute(code) { return .noRoute }
            return .unknown
        }

        guard !states.isEmpty else {
            return SwapKitErrorCopy.isNoRoute(response.error) ? .noRoute : .unknown
        }
        if states.contains(.available) { return .available }
        if states.contains(.unknown) { return .unknown }
        if states.contains(.halted) { return .halted }
        return .noRoute
    }

    /// The answer of each of `requested` in a quote that asked several route providers at once:
    /// every provider's own errors are classified on their own. A provider with no error and no
    /// route is `.unknown`, except under a bare top-level no-route, which covers everyone asked.
    static func classifyPerProvider(_ response: SwapKitQuoteResponse, requested: Set<RouteProvider>) -> [RouteProvider: LiveRouteState] {
        var result: [RouteProvider: LiveRouteState] = [:]
        let routed = Set((response.routes ?? []).flatMap { $0.providers }.compactMap { RouteProvider(swapKitProvider: $0) })
        let errors = response.providerErrors ?? []
        let bareNoRoute = errors.isEmpty && SwapKitErrorCopy.isNoRoute(response.error)
        for provider in requested {
            if routed.contains(provider) {
                result[provider] = .available
                continue
            }
            let own = errors.filter { $0.provider.flatMap { RouteProvider(swapKitProvider: $0) } == provider }
            if own.isEmpty {
                result[provider] = bareNoRoute ? .noRoute : .unknown
            } else {
                result[provider] = classify(SwapKitQuoteResponse(quoteId: nil, routes: nil, providerErrors: own, error: nil, message: nil))
            }
        }
        return result
    }
}

// MARK: - RouteProvider live label

extension RouteProvider {
    /// The provider label for the set of providers that can carry an asset right now:
    /// both → `.multiple`, one → that one, none → `nil` (the coin is shown halted instead).
    static func label(forUsable usable: Set<RouteProvider>) -> RouteProvider? {
        let near = usable.contains(.near)
        let maya = usable.contains(.maya)
        switch (near, maya) {
        case (true, true): return .multiple
        case (true, false): return .near
        case (false, true): return .maya
        case (false, false): return nil
        }
    }

    /// SwapKit provider names this route provider stands for in a quote's `providers` filter.
    var swapKitProviders: [String] {
        switch self {
        case .near: return [SwapKitConstants.providerNear]
        case .maya: return SwapKitConstants.mayaProviders
        case .multiple: return [SwapKitConstants.providerNear] + SwapKitConstants.mayaProviders
        }
    }

    /// The route provider a SwapKit provider name belongs to, or `nil` for one this wallet does not route through.
    init?(swapKitProvider name: String) {
        let upper = name.uppercased()
        if upper == SwapKitConstants.providerNear {
            self = .near
        } else if SwapKitConstants.mayaProviders.contains(upper) {
            self = .maya
        } else {
            return nil
        }
    }
}

// MARK: - SwapRouteAvailability

/// Live per-provider route availability for the swap coin pickers, probed with forced quotes.
///
/// Shared (`shared`) because every swap flow builds its own `SwapKitSwapProvider`
/// (`SwapBackend.makeProvider()`), while availability is a fact about SwapKit, not about one flow:
/// a second opening of a picker reuses the answers instead of re-probing every coin. Tests build
/// their own instance.
///
/// Probing rules:
/// - At most `maxInFlight` quotes are in flight across all directions, so opening a picker never
///   fires a burst of ~200 requests.
/// - NEAR is checked on a couple of liquid sentinel coins first. If two of them have no route and
///   none routes, NEAR is treated as down for every coin of that direction and no per-coin NEAR
///   probes run; if one routes, every NEAR-capable coin is probed on its own. A halted or
///   inconclusive sentinel counts toward neither, and a round that settles neither keeps the
///   previous verdict.
/// - Maya is probed per coin: its halts are per chain, so one coin says nothing about the next.
///
/// Answers age in two steps: after `probeAfter` (`nearDownProbeAfter` for a NEAR outage) a refresh
/// asks again, but the last conclusive answer keeps being read until the new one arrives or
/// `forgetAfter` passes — so a label does not flip back to the static guess between the two.
/// A refresh drops what passed `forgetAfter` in its direction and reports it on `changes`, so a
/// row halted by a forgotten answer comes back even when the re-check stores nothing.
/// Inconclusive answers (`.unknown`) are never stored: they would only block the next attempt.
@MainActor
final class SwapRouteAvailability {
    static let shared = SwapRouteAvailability()

    /// Runs one forced quote for `asset` against `provider` in `direction` and classifies it.
    typealias Probe = @MainActor (_ asset: String, _ provider: RouteProvider, _ direction: SwapDirection) async -> LiveRouteState

    enum NearVerdict: Equatable {
        case up
        case down
    }

    /// Liquid NEAR-capable coins on different chains. The third is asked only when the first two
    /// settled neither outcome: neither routes and they are not both a no-route.
    static let nearSentinels = ["BTC.BTC", "ETH.ETH", "SOL.SOL"]

    /// Emits the direction whose availability changed.
    let changes = PassthroughSubject<SwapDirection, Never>()

    private struct Key: Hashable {
        let direction: SwapDirection
        let provider: RouteProvider
        let asset: String

        init(_ direction: SwapDirection, _ provider: RouteProvider, _ asset: String) {
            self.direction = direction
            self.provider = provider
            self.asset = asset.uppercased()
        }
    }

    private struct Entry {
        let state: LiveRouteState
        let checkedAt: Date
    }

    private struct Verdict {
        let verdict: NearVerdict
        /// When this verdict was last confirmed — what makes it due for a re-check.
        let checkedAt: Date
        /// The sequence at the start of the round that last changed the verdict to this value. A
        /// coin's own answer asked or recorded after it wins over an outage, even after the outage
        /// was re-confirmed — also one recorded while that round was still asking.
        let sinceSequence: Int
    }

    private let probeAfter: TimeInterval
    private let nearDownProbeAfter: TimeInterval
    private let forgetAfter: TimeInterval
    private let now: () -> Date

    private var entries: [Key: Entry] = [:]
    /// Orders the answers: each stored answer carries the sequence number taken when it was asked
    /// (a probe) or learned (`record`), so an older probe that returns late does not overwrite it.
    private var sequence = 0
    private var storedSequence: [Key: Int] = [:]
    /// When a key last got an inconclusive answer, which is not stored as an answer. It is not
    /// asked again before `nearDownProbeAfter`, so an upstream outage is not polled every tick.
    private var inconclusiveAt: [Key: Date] = [:]
    /// When a sentinel round last ended without a verdict, per direction; same back-off.
    private var inconclusiveRoundAt: [SwapDirection: Date] = [:]
    private var nearVerdicts: [SwapDirection: Verdict] = [:]
    private var refreshing: Set<SwapDirection> = []
    private var refreshWaiters: [SwapDirection: [CheckedContinuation<Void, Never>]] = [:]
    private var freePermits: Int
    private let workerCount: Int
    private var permitWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        probeAfter: TimeInterval = 600,
        nearDownProbeAfter: TimeInterval = 120,
        forgetAfter: TimeInterval = 1800,
        maxInFlight: Int = 2,
        now: @escaping () -> Date = Date.init
    ) {
        self.probeAfter = probeAfter
        self.nearDownProbeAfter = nearDownProbeAfter
        self.forgetAfter = forgetAfter
        self.freePermits = maxInFlight
        self.workerCount = maxInFlight
        self.now = now
    }

    // MARK: Reading

    /// The last conclusive state of `provider` for `asset`, or `nil` when nothing usable is known.
    /// A NEAR outage applies to every coin, except one whose own answer was asked or recorded after
    /// the round that first found the outage started (`Verdict.sinceSequence`).
    ///
    /// `freshOnly` ignores answers that are due for a re-probe — for building a real quote, which
    /// must not leave out a provider on an answer the picker has not refreshed for a while.
    func state(of provider: RouteProvider, for asset: String, direction: SwapDirection, freshOnly: Bool = false) -> LiveRouteState? {
        let key = Key(direction, provider, asset)
        let entry = readableEntry(key).flatMap { freshOnly && now().timeIntervalSince($0.checkedAt) >= probeAfter ? nil : $0 }
        let verdict = readableVerdict(direction).flatMap { freshOnly && isDue($0) ? nil : $0 }
        if provider == .near, let verdict, verdict.verdict == .down {
            if let entry, storedSequence[key, default: 0] > verdict.sinceSequence {
                return entry.state
            }
            return .noRoute
        }
        return entry?.state
    }

    /// The providers of `capable` that can carry `asset` now. A provider with no known answer stays in.
    func usableProviders(
        for asset: String,
        capable: Set<RouteProvider>,
        direction: SwapDirection,
        freshOnly: Bool = false
    ) -> Set<RouteProvider> {
        capable.filter { state(of: $0, for: asset, direction: direction, freshOnly: freshOnly)?.isUsable ?? true }
    }

    /// The last NEAR verdict for `direction` the sentinels gave, while it is still readable.
    func nearVerdict(for direction: SwapDirection) -> NearVerdict? {
        readableVerdict(direction)?.verdict
    }

    // MARK: Writing

    /// Records a conclusive answer learned outside the probes (a quote on the address screen, say).
    /// An inconclusive one is dropped.
    func record(_ state: LiveRouteState, provider: RouteProvider, asset: String, direction: SwapDirection) {
        guard state != .unknown else { return }
        store(state, for: Key(direction, provider, asset), asked: nextSequence())
    }

    // MARK: Probing

    /// Probes what is due for `assets` (in the given order) and reports changes on `changes`.
    /// One refresh runs per direction: a second one waits for the first to finish (a cancelled
    /// one finishes once its one or two in-flight requests return) and then probes what is still
    /// due. Cancelling the calling task stops it: queued probes are dropped without a request.
    func refresh(
        assets: [String],
        direction: SwapDirection,
        capable: (String) -> Set<RouteProvider>,
        probe: @escaping Probe
    ) async {
        while refreshing.contains(direction) {
            await withCheckedContinuation { refreshWaiters[direction, default: []].append($0) }
        }
        guard !Task.isCancelled else { return }
        refreshing.insert(direction)
        defer {
            refreshing.remove(direction)
            refreshWaiters.removeValue(forKey: direction)?.forEach { $0.resume() }
        }
        forgetExpired(direction)

        var probeNearPerCoin = false
        if assets.contains(where: { capable($0).contains(.near) }) {
            probeNearPerCoin = await resolveNearVerdict(direction: direction, probe: probe) == .up
        }

        var jobs: [(key: Key, asset: String)] = []
        for asset in assets {
            let providers = capable(asset)
            for provider in [RouteProvider.maya, .near] where providers.contains(provider) {
                if provider == .near, !probeNearPerCoin { continue }
                let key = Key(direction, provider, asset)
                guard isDue(key) else { continue }
                jobs.append((key, asset))
            }
        }
        guard !jobs.isEmpty, !Task.isCancelled else { return }

        // As many workers as in-flight permits pull jobs in order, so a long list does not park a
        // waiting task per coin.
        let queue = JobQueue(jobs)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask { @MainActor [self] in
                    while !Task.isCancelled, let job = queue.next() {
                        _ = await self.probeOne(job.key, asset: job.asset, force: false, probe: probe)
                    }
                }
            }
        }
    }

    @MainActor
    private final class JobQueue {
        private var jobs: [(key: Key, asset: String)]
        private var index = 0

        init(_ jobs: [(key: Key, asset: String)]) {
            self.jobs = jobs
        }

        func next() -> (key: Key, asset: String)? {
            guard index < jobs.count else { return nil }
            defer { index += 1 }
            return jobs[index]
        }
    }

    /// Asks `provider` about `asset` now, whatever is cached — for confirming an answer that came
    /// from a quote the probes cannot vouch for (one to a user-typed address).
    /// Returns the probe's answer, or the newer stored one when the coin got an answer asked after
    /// this probe (`probeOne`).
    @discardableResult
    func probeNow(asset: String, provider: RouteProvider, direction: SwapDirection, probe: Probe) async -> LiveRouteState {
        await probeOne(Key(direction, provider, asset), asset: asset, force: true, probe: probe)
    }

    /// Re-asks the sentinels once the last verdict is due (2 minutes after an outage, 10 after
    /// "up"), bypassing their cached answers. They are asked until one routes or two give a
    /// conclusive no, so the third stands in for a halted or an inconclusive one. Two conclusive
    /// no-routes and none routing → NEAR is down. Fewer keeps the previous verdict. A route after
    /// a "down" verdict also drops the other sentinels' no-routes stored before this round, so
    /// their coins are asked again. Counting reads the sentinels' answers stored since the round
    /// started, so an answer recorded meanwhile replaces the one asked.
    private func resolveNearVerdict(direction: SwapDirection, probe: @escaping Probe) async -> NearVerdict? {
        if let verdict = readableVerdict(direction), !isDue(verdict) {
            return verdict.verdict
        }
        if let last = inconclusiveRoundAt[direction], now().timeIntervalSince(last) < nearDownProbeAfter {
            return readableVerdict(direction)?.verdict
        }

        let roundStart = sequence
        // An answer recorded for a sentinel while the round is asking (an address quote) replaces
        // the one asked, so the round reads the sentinels' answers stored since it started.
        // Only a no-route says something about NEAR as a whole; a halt is about that chain.
        func thisRound() -> [LiveRouteState] {
            Self.nearSentinels.compactMap { sentinel in
                let key = Key(direction, .near, sentinel)
                guard storedSequence[key, default: 0] > roundStart else { return nil }
                return readableEntry(key)?.state
            }
        }
        func noRoutes() -> Int { thisRound().filter { $0 == .noRoute }.count }

        for sentinel in Self.nearSentinels where noRoutes() < 2 {
            if Task.isCancelled {
                return readableVerdict(direction)?.verdict
            }
            _ = await probeOne(Key(direction, .near, sentinel), asset: sentinel, force: true, probe: probe)
            if thisRound().contains(.available) {
                return nearIsUp(direction: direction, roundStart: roundStart)
            }
        }

        guard noRoutes() >= 2 else {
            let kept = readableVerdict(direction).map { "\($0.verdict)" } ?? "none"
            DWLogger.log("SwapKit: NEAR sentinel round (\(direction)) settled nothing; keeping \(kept)")
            inconclusiveRoundAt[direction] = now()
            return readableVerdict(direction)?.verdict
        }
        inconclusiveRoundAt[direction] = nil
        setNearVerdict(.down, direction: direction, roundStart: roundStart)
        return .down
    }

    /// A sentinel routes: NEAR is up. After a "down" verdict, the other sentinels' outage-era
    /// no-routes are dropped (`forgetSentinelNoRoutes`).
    private func nearIsUp(direction: SwapDirection, roundStart: Int) -> NearVerdict {
        inconclusiveRoundAt[direction] = nil
        if readableVerdict(direction)?.verdict == .down {
            forgetSentinelNoRoutes(direction: direction, storedBefore: roundStart)
        }
        setNearVerdict(.up, direction: direction, roundStart: roundStart)
        return .up
    }

    /// When NEAR recovers, the sentinels' no-routes stored before this round (`roundStart`) come
    /// from the outage, not from their own coins: drop them so this refresh asks those coins again
    /// instead of waiting ten minutes. A no-route measured in this round is the coin's own answer.
    private func forgetSentinelNoRoutes(direction: SwapDirection, storedBefore roundStart: Int) {
        for sentinel in Self.nearSentinels {
            let key = Key(direction, .near, sentinel)
            if entries[key]?.state == .noRoute, storedSequence[key, default: 0] <= roundStart {
                entries.removeValue(forKey: key)
            }
        }
    }

    private func setNearVerdict(_ verdict: NearVerdict, direction: SwapDirection, roundStart: Int) {
        let previous = readableVerdict(direction)
        let sinceSequence = previous?.verdict == verdict ? previous?.sinceSequence ?? roundStart : roundStart
        nearVerdicts[direction] = Verdict(verdict: verdict, checkedAt: now(), sinceSequence: sinceSequence)
        let previousVerdict = previous?.verdict
        if previousVerdict != verdict {
            let was = previousVerdict.map { "\($0)" } ?? "none"
            DWLogger.log("SwapKit: NEAR verdict (\(direction)) \(was) → \(verdict)")
            changes.send(direction)
        }
    }

    /// One probe under the in-flight limit. Unless `force`d, an answer that is not yet due is
    /// reused — checked again after waiting for a permit, since another writer may have answered
    /// meanwhile. A cancelled task gets `.unknown` without a request. When the key got an answer
    /// asked after this one while the request was in flight, the probe's answer is dropped and the
    /// newer stored answer is returned instead (`.unknown` when it is no longer readable).
    private func probeOne(_ key: Key, asset: String, force: Bool, probe: Probe) async -> LiveRouteState {
        if !force, !isDue(key) {
            return readableEntry(key)?.state ?? .unknown
        }
        await acquirePermit()
        defer { releasePermit() }
        if Task.isCancelled {
            return .unknown
        }
        if !force, !isDue(key) {
            return readableEntry(key)?.state ?? .unknown
        }
        let asked = nextSequence()
        let state = await probe(asset, key.provider, key.direction)
        guard storedSequence[key, default: -1] < asked else {
            return readableEntry(key)?.state ?? .unknown
        }
        if state == .unknown {
            inconclusiveAt[key] = now()
        } else {
            inconclusiveAt[key] = nil
            store(state, for: key, asked: asked)
        }
        return state
    }

    private func nextSequence() -> Int {
        sequence += 1
        return sequence
    }

    private func store(_ state: LiveRouteState, for key: Key, asked: Int) {
        let previous = self.state(of: key.provider, for: key.asset, direction: key.direction)
        entries[key] = Entry(state: state, checkedAt: now())
        storedSequence[key] = asked
        if previous != self.state(of: key.provider, for: key.asset, direction: key.direction) {
            changes.send(key.direction)
        }
    }

    // MARK: Ageing

    /// Drops the answers and the NEAR verdict of `direction` that passed `forgetAfter`, and reports
    /// the direction when anything was dropped.
    private func forgetExpired(_ direction: SwapDirection) {
        let expired = entries.filter { $0.key.direction == direction && readableEntry($0.key) == nil }.map { $0.key }
        expired.forEach { entries.removeValue(forKey: $0) }
        var forgot = !expired.isEmpty
        if nearVerdicts[direction] != nil, readableVerdict(direction) == nil {
            nearVerdicts.removeValue(forKey: direction)
            forgot = true
        }
        if forgot {
            changes.send(direction)
        }
    }

    private func readableEntry(_ key: Key) -> Entry? {
        guard let entry = entries[key], now().timeIntervalSince(entry.checkedAt) < forgetAfter else { return nil }
        return entry
    }

    private func readableVerdict(_ direction: SwapDirection) -> Verdict? {
        guard let verdict = nearVerdicts[direction], now().timeIntervalSince(verdict.checkedAt) < forgetAfter else { return nil }
        return verdict
    }

    private func isDue(_ key: Key) -> Bool {
        if let last = inconclusiveAt[key], now().timeIntervalSince(last) < nearDownProbeAfter {
            return false
        }
        guard let entry = entries[key] else { return true }
        return now().timeIntervalSince(entry.checkedAt) >= probeAfter
    }

    private func isDue(_ verdict: Verdict) -> Bool {
        let interval = verdict.verdict == .down ? nearDownProbeAfter : probeAfter
        return now().timeIntervalSince(verdict.checkedAt) >= interval
    }

    // MARK: In-flight limit

    private func acquirePermit() async {
        if freePermits > 0 {
            freePermits -= 1
            return
        }
        await withCheckedContinuation { permitWaiters.append($0) }
    }

    private func releasePermit() {
        if permitWaiters.isEmpty {
            freePermits += 1
        } else {
            // The permit passes straight to the next waiter; `freePermits` stays as it is.
            permitWaiters.removeFirst().resume()
        }
    }
}
