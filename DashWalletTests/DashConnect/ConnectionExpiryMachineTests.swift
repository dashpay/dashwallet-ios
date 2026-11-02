import Foundation
import XCTest
@testable import dashpay
@testable import SwiftDashSDK

/// When the expiry check reads, judges, waits and what it publishes
/// (`ConnectionExpiryMachine`), event by event.
final class ConnectionExpiryMachineTests: XCTestCase {
    private typealias Machine = ConnectionExpiryMachine
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let scope = "wallet-a"

    /// A machine with a judge that answers `judgements` for the apps it is
    /// asked about, and the clocks it is handed.
    private final class Harness {
        var machine: Machine
        var judgements: [String: AppConnect.ExpiryJudgement] = [:]
        var now = ConnectionExpiryMachineTests.start
        var chainTime: Date? = ConnectionExpiryMachineTests.start
        var identity: String? = "identity"
        /// The judge cannot judge for the wallet (it is no longer active).
        var judgeAnswers = true
        /// When set, every app is judged by the Core tip time alone.
        var judgeByChain: ((Int64?) -> AppConnect.ExpiryJudgement)?
        /// When set, every app is judged by the read's keys and the phone
        /// time the machine judges with.
        var judgeByKeys: ((ConnectionIdentityKeys, Int64) -> AppConnect.ExpiryJudgement)?
        private(set) var judged = 0

        init(policy: Machine.Policy = .standard) {
            machine = Machine(policy: policy) { _, _, _, _, _ in [:] }
            machine = Machine(policy: policy) { [unowned self] _, apps, keys, now, chainTime in
                guard self.judgeAnswers else { return nil }
                self.judged += 1
                if let judgeByKeys = self.judgeByKeys {
                    return Dictionary(uniqueKeysWithValues: apps.map { ($0, judgeByKeys(keys, now)) })
                }
                if let judgeByChain = self.judgeByChain {
                    return Dictionary(uniqueKeysWithValues: apps.map { ($0, judgeByChain(chainTime)) })
                }
                return self.judgements.filter { apps.contains($0.key) }
            }
        }

        @discardableResult
        func send(_ event: Machine.Event) -> [Machine.Effect] {
            machine.handle(event, clocks: Machine.Clocks(now: now, chainTime: chainTime, identityId: identity))
        }

        var attempt: Machine.Attempt? {
            if case .checking(let attempt) = machine.phase { return attempt }
            return nil
        }

        var check: ConnectionExpiries.Check { machine.expiries.check }

        /// The verdicts as the page shows them, for the rows published.
        var shownVerdicts: [String: ConnectionExpiry.Verdict] {
            machine.expiries.holding(for: machine.rows).byApp.mapValues(\.verdict)
        }

        /// Ends the running read with `result`.
        @discardableResult
        func end(_ result: ConnectionExpiryReadResult) -> [Machine.Effect] {
            guard let attempt else {
                XCTFail("no read runs")
                return []
            }
            return send(.readEnded(attempt, result))
        }
    }

    private static func row(_ id: String, updatedAt: TimeInterval = 10, status: ConnectionStatus = .active) -> DAppConnection {
        var row = DAppConnection(
            id: id, name: id, url: "\(id).app", status: status, updatedAt: Date(timeIntervalSince1970: updatedAt),
            loginKind: .oneQR)
        row.scope = scope
        return row
    }

    private static func keys(_ identity: String = "identity") -> ConnectionExpiryReadResult {
        .keys(ConnectionIdentityKeys(identityId: identity, keys: [], bindings: []))
    }

    private static func reads(_ effects: [Machine.Effect]) -> [Machine.Attempt] {
        effects.compactMap { if case .startRead(let attempt) = $0 { return attempt } else { return nil } }
    }

    private static func sleeps(_ effects: [Machine.Effect]) -> [Machine.Effect] {
        effects.filter { if case .sleep = $0 { return true } else { return false } }
    }

    /// A shown page on wallet A whose first read ended with keys, judged as
    /// `judgements`.
    private func readHarness(
        rows: [DAppConnection] = [row("a")],
        judgements: [String: AppConnect.ExpiryJudgement] = ["a": .init(verdict: .expired)]
    ) -> Harness {
        let harness = Harness()
        harness.judgements = judgements
        harness.send(.listing(scope: Self.scope, rows: rows))
        harness.send(.shown(forcesRead: false))
        harness.end(Self.keys())
        XCTAssertEqual(harness.check, .read)
        return harness
    }

    // MARK: - Listing

    func testAWalletsListingOwesAReadThatTheShownPageMakes() {
        let harness = Harness()
        let effects = harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        XCTAssertTrue(Self.reads(effects).isEmpty, "the page is not on screen")
        XCTAssertEqual(harness.check, .checking, "owed, so not \"none expired\"")
        XCTAssertTrue(effects.contains(.publish(harness.machine.expiries)))

        let shown = harness.send(.shown(forcesRead: false))
        let attempt = Self.reads(shown).first
        XCTAssertEqual(attempt?.key, Machine.Key(scope: Self.scope, identity: "identity"))
        XCTAssertEqual(attempt?.rows, DAppConnection.activeExpiryGenerations([Self.row("a")]))
    }

    func testAReadThatEndsWithKeysJudgesEveryActiveRow() {
        let harness = Harness()
        harness.judgements = ["a": .init(verdict: .expired)]
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a"), Self.row("b"), Self.row("c", status: .approved)]))
        harness.send(.shown(forcesRead: false))
        let effects = harness.end(Self.keys())
        XCTAssertEqual(harness.check, .read)
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired, "b": .notJudged], "only active rows, each told")
        XCTAssertEqual(harness.machine.expiries.identityId, "identity")
        XCTAssertTrue(effects.contains(.publish(harness.machine.expiries)))
    }

    func testAChangedActiveRowOwesAReadAndIsPublishedAsCheckingEvenWhileHidden() {
        let harness = readHarness()
        harness.send(.hidden)
        let effects = harness.send(.listing(scope: Self.scope, rows: [Self.row("a", updatedAt: 20)]))
        XCTAssertTrue(Self.reads(effects).isEmpty)
        XCTAssertEqual(harness.check, .checking, "not \"could not be checked\" for the changed row")
        XCTAssertTrue(effects.contains(.publish(harness.machine.expiries)))
        XCTAssertEqual(Self.reads(harness.send(.shown(forcesRead: false))).count, 1)
    }

    func testANameOrUrlChangeOwesNothing() {
        let harness = readHarness()
        var renamed = DAppConnection(
            id: "a", name: "Renamed", url: "renamed.app", status: .active,
            updatedAt: Date(timeIntervalSince1970: 10), loginKind: .oneQR)
        renamed.scope = Self.scope
        let effects = harness.send(.listing(scope: Self.scope, rows: [renamed]))
        XCTAssertEqual(effects, [])
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired], "the same generation")
    }

    func testARenewedExpiredAppHasNoVerdictWhileItIsChecked() {
        let harness = readHarness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a", updatedAt: 20)]))
        XCTAssertNotNil(harness.attempt)
        XCTAssertEqual(harness.check, .checking)
        XCTAssertEqual(harness.shownVerdicts, [:], "not back under Expired")
    }

    func testAListingWithNoWalletStopsEverything() {
        let harness = readHarness()
        let effects = harness.send(.listing(scope: nil, rows: []))
        XCTAssertEqual(harness.check, .notStarted)
        XCTAssertEqual(harness.machine.pending, .none)
        XCTAssertTrue(effects.contains(.cancelTimer(.phoneDeadline)))
        XCTAssertEqual(harness.machine.expiries.byApp, [:])
    }

    func testAnotherWalletsListingRestartsWithNoVerdicts() {
        let harness = readHarness()
        var other = Self.row("a")
        other.scope = "wallet-b"
        let effects = harness.send(.listing(scope: "wallet-b", rows: [other]))
        XCTAssertEqual(Self.reads(effects).first?.key.scope, "wallet-b")
        XCTAssertEqual(harness.machine.expiries.byApp, [:])
    }

    // MARK: - Reads that do not end with keys

    func testAFailedReadKeepsOnlyTheExpiredVerdictsOfUnchangedRows() {
        let harness = readHarness(
            rows: [Self.row("a"), Self.row("b"), Self.row("c")],
            judgements: ["a": .init(verdict: .expired), "b": .init(verdict: .expired), "c": .init(verdict: .current)])
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a", updatedAt: 20), Self.row("b"), Self.row("c")]))
        let effects = harness.end(.failed("unreachable"))
        XCTAssertEqual(harness.check, .failed)
        XCTAssertEqual(harness.shownVerdicts, ["b": .expired], "a renewed, c only current")
        XCTAssertTrue(effects.contains(.log("unreachable")))
    }

    func testANotReadyReadKeepsTheExpiredVerdictsWhileItWaits() {
        let harness = readHarness()
        let effects = harness.send(.listing(scope: Self.scope, rows: [Self.row("a"), Self.row("b")]))
        XCTAssertEqual(Self.reads(effects).count, 1)
        let ended = harness.end(.notReady)
        guard case .backingOff = harness.machine.phase else { return XCTFail("\(harness.machine.phase)") }
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired])
        XCTAssertEqual(Self.sleeps(ended), [.sleep(.backoff, 2)])
    }

    func testANotReadyRuntimeIsTriedAgainAfterWaitsThenFails() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        var waits: [Machine.Effect] = []
        for _ in 0 ..< 3 {
            waits += Self.sleeps(harness.end(.notReady))
            XCTAssertEqual(harness.check, .notStarted, "no Retry while it is tried again")
            XCTAssertEqual(Self.reads(harness.send(.timerFired(.backoff))).count, 1)
        }
        XCTAssertEqual(waits, [.sleep(.backoff, 2), .sleep(.backoff, 5), .sleep(.backoff, 15)])
        harness.end(.notReady)
        XCTAssertEqual(harness.machine.phase, .failed(.notReady))
        XCTAssertEqual(harness.check, .failed, "Retry once the waits are used up")
    }

    func testNoIdentityAfterTheWaitsFailsAndAnIdentityThatAppearsReads() {
        let harness = Harness()
        harness.identity = nil
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        for _ in 0 ..< 3 {
            harness.end(.noIdentity)
            harness.send(.timerFired(.backoff))
        }
        harness.end(.noIdentity)
        XCTAssertEqual(harness.machine.phase, .failed(.noIdentity))

        XCTAssertTrue(Self.reads(harness.send(.identityMayHaveChanged)).isEmpty, "still none")
        harness.identity = "identity"
        let effects = harness.send(.identityMayHaveChanged)
        XCTAssertEqual(Self.reads(effects).first?.key.identity, "identity")
    }

    func testWithNoActiveRowNothingIsReadAndTheCheckIsDone() {
        let harness = Harness()
        harness.identity = nil
        let listed = harness.send(.listing(scope: Self.scope, rows: [Self.row("w", status: .approved)]))
        let shown = harness.send(.shown(forcesRead: false))
        XCTAssertTrue(Self.reads(listed + shown).isEmpty, "nothing to check")
        XCTAssertEqual(harness.check, .read)
        XCTAssertEqual(harness.machine.pending, .none)
        XCTAssertEqual(harness.machine.expiries.byApp, [:])

        let readHarness = readHarness()
        let emptied = readHarness.send(.listing(scope: Self.scope, rows: [Self.row("a", status: .approved)]))
        XCTAssertTrue(Self.reads(emptied).isEmpty)
        XCTAssertEqual(readHarness.check, .read)
        XCTAssertEqual(readHarness.machine.expiries.byApp, [:])
    }

    func testARowRenewedDuringAReadGetsNoVerdictFromItAndIsReadAgain() {
        let harness = Harness()
        harness.judgements = ["a": .init(verdict: .expired), "b": .init(verdict: .expired)]
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a"), Self.row("b")]))
        harness.send(.shown(forcesRead: false))
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a", updatedAt: 20), Self.row("b")]))
        let effects = harness.end(Self.keys())
        XCTAssertEqual(harness.shownVerdicts, ["b": .expired], "the read was not made for the renewed row")
        XCTAssertEqual(Self.reads(effects).count, 1, "the renewed row is read")
        XCTAssertEqual(harness.check, .checking)
    }

    func testAJudgeThatCannotJudgeForTheWalletChangesNothing() {
        let harness = readHarness()
        let before = harness.machine.expiries
        harness.judgeAnswers = false
        harness.judgements = ["a": .init(verdict: .current)]
        let effects = harness.send(.foreground)
        XCTAssertEqual(effects, [])
        XCTAssertEqual(harness.machine.expiries, before)
    }

    func testAReadTheJudgeCannotJudgeForIsMadeAgainNotLeftChecking() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        let first = harness.attempt
        harness.judgeAnswers = false
        let effects = harness.end(Self.keys())
        XCTAssertEqual(Self.reads(effects).count, 1, "a read runs again")
        XCTAssertNotEqual(harness.attempt?.id, first?.id)
        harness.judgeAnswers = true
        harness.end(Self.keys())
        XCTAssertEqual(harness.check, .read)
    }

    func testAppearingOrComingBackAfterTheNotReadyWaitsReadsAgain() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        for _ in 0 ..< 3 {
            harness.end(.notReady)
            harness.send(.timerFired(.backoff))
        }
        harness.end(.notReady)
        XCTAssertEqual(harness.machine.phase, .failed(.notReady))
        XCTAssertEqual(Self.reads(harness.send(.foreground)).count, 1, "back in the foreground")

        for _ in 0 ..< 3 {
            harness.end(.noIdentity)
            harness.send(.timerFired(.backoff))
        }
        harness.end(.noIdentity)
        XCTAssertEqual(harness.machine.phase, .failed(.noIdentity))
        harness.send(.hidden)
        XCTAssertEqual(Self.reads(harness.send(.shown(forcesRead: false))).count, 1, "the page appearing")
    }

    func testComingBackToTheForegroundAfterTheFreshReadIntervalReads() {
        let harness = readHarness()
        harness.now = Self.start.addingTimeInterval(31)
        let effects = harness.send(.foreground)
        XCTAssertEqual(Self.reads(effects).count, 1)
    }

    func testAnExpiredAppStaysExpiredWhenTheCoreTipIsNotKnownForAWhile() {
        let expiredFrom = Machine.milliseconds(Self.start)
        let harness = Harness()
        harness.judgeByChain = { chainTime in
            guard let chainTime, chainTime >= expiredFrom else {
                return .init(verdict: .pastByPhone, rejudgeAtChainTime: expiredFrom)
            }
            return .init(verdict: .expired)
        }
        harness.send(.runtime(1))
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        harness.end(Self.keys())
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired])

        // The SDK restarts and has no tip yet.
        harness.chainTime = nil
        XCTAssertEqual(Self.reads(harness.send(.runtime(2))).count, 1)
        harness.end(Self.keys())
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired], "the chain does not go back")
    }

    /// The identity with one key expiring at `expiresAt`.
    private static func keys(expiringAt expiresAt: Int64) -> ConnectionExpiryReadResult {
        .keys(ConnectionIdentityKeys(
            identityId: "identity",
            keys: [ManagedIdentity.IdentityPublicKeyInfo(
                keyId: 3, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160, readOnly: false,
                disabledAt: nil, data: Data(repeating: 3, count: 20), totalBudget: nil, expiresAt: expiresAt)],
            bindings: []))
    }

    /// A shown page whose key is judged `past` from its expiry on, by the
    /// phone time the machine passes, and `.current` before; read once with
    /// the phone two minutes after `start`.
    private func clockHarness(past: ConnectionExpiry.Verdict, expiresAt: Int64) -> Harness {
        let harness = Harness()
        harness.judgeByKeys = { keys, now in
            .init(verdict: now >= (keys.keys.first?.expiresAt ?? .max) ? past : .current)
        }
        harness.now = Self.start.addingTimeInterval(120)
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        harness.end(Self.keys(expiringAt: expiresAt))
        return harness
    }

    func testARenewedKeyInANewReadIsJudgedCurrent() {
        let expiresAt = Machine.milliseconds(Self.start) + 60_000
        let harness = clockHarness(past: .expired, expiresAt: expiresAt)
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired])
        harness.send(.shown(forcesRead: true))
        harness.end(Self.keys(expiringAt: expiresAt + 3_600_000))
        XCTAssertEqual(harness.shownVerdicts, ["a": .current], "its later expiry is ahead")
    }

    func testAReadFromThePhonesFutureIsReadAnew() {
        let harness = readHarness()
        harness.now = Self.start.addingTimeInterval(-60)
        XCTAssertEqual(Self.reads(harness.send(.foreground)).count, 1, "back in the foreground")
        harness.end(Self.keys())
        harness.send(.hidden)
        harness.now = Self.start.addingTimeInterval(-120)
        XCTAssertEqual(Self.reads(harness.send(.shown(forcesRead: false))).count, 1, "the page appearing")
    }

    func testComingBackToTheForegroundJudgesAgain() {
        let harness = readHarness(judgements: ["a": .init(verdict: .current)])
        harness.judgements = ["a": .init(verdict: .expired)]
        let effects = harness.send(.foreground)
        XCTAssertTrue(Self.reads(effects).isEmpty)
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired])
        harness.send(.hidden)
        harness.judgements = ["a": .init(verdict: .current)]
        XCTAssertEqual(harness.send(.foreground), [], "not while the page is away")
    }

    func testPickingTheIdentityAlreadyInUseKeepsTheVerdicts() {
        let harness = readHarness()
        XCTAssertEqual(harness.send(.identityMayHaveChanged), [])
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired])
    }

    func testAnUnavailableNetworkIsNotNoneExpiredAndTheNextAppearanceReads() {
        let harness = readHarness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a"), Self.row("b")]))
        harness.end(.unavailable)
        XCTAssertEqual(harness.check, .unavailable)
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired])
        harness.send(.hidden)
        XCTAssertEqual(Self.reads(harness.send(.shown(forcesRead: false))).count, 1)
    }

    func testARegistrationThatLeavesTheIdentityDuringTheWaitsDoesNotCutThemShort() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        harness.end(.notReady)
        XCTAssertEqual(harness.send(.identityMayHaveChanged), [])
        guard case .backingOff = harness.machine.phase else { return XCTFail("\(harness.machine.phase)") }
    }

    func testLeavingThePageDuringTheWaitsOwesAReadForItsReturn() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        harness.end(.notReady)
        let hidden = harness.send(.hidden)
        XCTAssertTrue(hidden.contains(.cancelTimer(.backoff)))
        XCTAssertEqual(harness.machine.phase, .notStarted)
        XCTAssertEqual(Self.reads(harness.send(.shown(forcesRead: false))).count, 1)
    }

    func testRetryDuringTheWaitsReadsAtOnce() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        harness.end(.notReady)
        let effects = harness.send(.shown(forcesRead: true))
        XCTAssertTrue(effects.contains(.cancelTimer(.backoff)))
        XCTAssertEqual(Self.reads(effects).count, 1)
    }

    // MARK: - Identity

    func testAnotherIdentityRestartsWithNoVerdicts() {
        let harness = readHarness()
        harness.identity = "other"
        let effects = harness.send(.identityMayHaveChanged)
        XCTAssertEqual(harness.machine.expiries.byApp, [:])
        XCTAssertEqual(Self.reads(effects).first?.key.identity, "other")
        harness.end(.failed("unreachable"))
        XCTAssertEqual(harness.machine.expiries.byApp, [:], "the other identity's verdicts are not kept")
    }

    func testAReadOfAnotherIdentityIsDroppedAndMadeAgain() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        let effects = harness.end(Self.keys("other"))
        XCTAssertEqual(Self.reads(effects).count, 1)
        XCTAssertEqual(harness.check, .checking)
        XCTAssertNil(harness.machine.expiries.identityId)
    }

    func testAReadThatEndedAfterARestartIsIgnored() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        let first = harness.attempt!
        harness.identity = "other"
        harness.send(.identityMayHaveChanged)
        XCTAssertNotEqual(harness.attempt?.id, first.id)
        XCTAssertEqual(harness.send(.readEnded(first, Self.keys())), [])
    }

    // MARK: - Page

    func testShowingThePageDuringAReadOwesNothingButRetryReadsOnceMore() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        XCTAssertTrue(Self.reads(harness.send(.shown(forcesRead: false))).isEmpty)
        XCTAssertTrue(Self.reads(harness.end(Self.keys())).isEmpty, "the read answered the appearance")

        harness.send(.listing(scope: Self.scope, rows: [Self.row("a", updatedAt: 20)]))
        harness.send(.shown(forcesRead: true))
        XCTAssertEqual(harness.machine.pending, .forcedRead)
        XCTAssertEqual(Self.reads(harness.end(Self.keys())).count, 1, "Retry reads after the running read")
    }

    func testAReadFreshEnoughIsJudgedAgainOnAppearanceAndAnOlderOneIsRead() {
        let harness = readHarness()
        harness.send(.hidden)
        harness.now = Self.start.addingTimeInterval(29)
        let judged = harness.judged
        XCTAssertTrue(Self.reads(harness.send(.shown(forcesRead: false))).isEmpty)
        XCTAssertEqual(harness.judged, judged + 1, "judged again")

        harness.send(.hidden)
        harness.now = Self.start.addingTimeInterval(31)
        XCTAssertEqual(Self.reads(harness.send(.shown(forcesRead: false))).count, 1)
    }

    func testRetryReadsAFreshReadAgain() {
        let harness = readHarness()
        harness.now = Self.start.addingTimeInterval(1)
        XCTAssertEqual(Self.reads(harness.send(.shown(forcesRead: true))).count, 1)
    }

    func testLeavingThePageDuringAReadCancelsItAndReadsOnTheReturn() {
        let harness = Harness()
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        let attempt = harness.attempt!
        let hidden = harness.send(.hidden)
        XCTAssertTrue(hidden.contains(.cancelRead))
        XCTAssertEqual(harness.machine.phase, .notStarted)
        XCTAssertEqual(harness.check, .checking, "a read is owed")
        XCTAssertEqual(harness.send(.readEnded(attempt, Self.keys())), [], "the cancelled read tells nothing")
        XCTAssertEqual(Self.reads(harness.send(.shown(forcesRead: false))).count, 1)
    }

    // MARK: - Clocks

    func testAChainTipPastTheThresholdJudgesAgainWithoutReading() {
        let threshold = Machine.milliseconds(Self.start) + 60_000
        let harness = readHarness(judgements: ["a": .init(verdict: .pastByPhone, rejudgeAtChainTime: threshold)])
        XCTAssertEqual(harness.send(.chainTip(Self.start.addingTimeInterval(59))), [])

        harness.judgements = ["a": .init(verdict: .expired)]
        let effects = harness.send(.chainTip(Self.start.addingTimeInterval(60)))
        XCTAssertTrue(Self.reads(effects).isEmpty)
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired])
    }

    func testAChainTipWhileHiddenIsJudgedOnTheReturn() {
        let threshold = Machine.milliseconds(Self.start) + 60_000
        let harness = readHarness(judgements: ["a": .init(verdict: .pastByPhone, rejudgeAtChainTime: threshold)])
        harness.send(.hidden)
        harness.send(.chainTip(Self.start.addingTimeInterval(60)))
        XCTAssertEqual(harness.machine.pending, .judge)
        harness.judgements = ["a": .init(verdict: .expired)]
        // Back within the fresh-read interval: the keys read are judged.
        harness.now = Self.start.addingTimeInterval(10)
        XCTAssertTrue(Self.reads(harness.send(.shown(forcesRead: false))).isEmpty)
        XCTAssertEqual(harness.shownVerdicts, ["a": .expired])
    }

    func testAFailedReadLeavesNoThresholdForLaterTips() {
        let threshold = Machine.milliseconds(Self.start) + 60_000
        let harness = readHarness(judgements: ["a": .init(verdict: .pastByPhone, rejudgeAtChainTime: threshold)])
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a", updatedAt: 20)]))
        harness.end(.failed("unreachable"))
        XCTAssertEqual(harness.send(.chainTip(Self.start.addingTimeInterval(120))), [])
    }

    func testThePhoneDeadlineIsWaitedForADayAtMostAndJudgesAgain() {
        let harness = readHarness(judgements: ["a": .init(verdict: .current, rejudgeAtPhoneTime: Int64.max)])
        let soon = Machine.milliseconds(Self.start) + 7_200_000
        harness.judgements = ["a": .init(verdict: .current, rejudgeAtPhoneTime: soon)]
        let effects = harness.send(.timerFired(.phoneDeadline))
        XCTAssertTrue(Self.reads(effects).isEmpty, "the keys read are judged again")
        XCTAssertEqual(Self.sleeps(effects), [.sleep(.phoneDeadline, 7_200)])

        let far = Harness()
        far.judgements = ["a": .init(verdict: .current, rejudgeAtPhoneTime: Int64.max)]
        far.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        far.send(.shown(forcesRead: false))
        XCTAssertEqual(Self.sleeps(far.end(Self.keys())), [.sleep(.phoneDeadline, 24 * 60 * 60)])
    }

    // MARK: - Runtime

    func testARuntimeGenerationReadsWhenItIsNewOrAReadWaitsForIt() {
        let harness = Harness()
        harness.send(.runtime(1))
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a")]))
        harness.send(.shown(forcesRead: false))
        XCTAssertEqual(harness.attempt?.runtime, 1)
        harness.end(Self.keys())
        XCTAssertTrue(Self.reads(harness.send(.runtime(1))).isEmpty, "the manager the last read ran with")
        XCTAssertEqual(Self.reads(harness.send(.runtime(2))).count, 1, "a new manager")

        harness.end(.notReady)
        let effects = harness.send(.runtime(2))
        XCTAssertTrue(effects.contains(.cancelTimer(.backoff)))
        XCTAssertEqual(Self.reads(effects).count, 1, "a read waiting for the runtime is made now")
    }

    func testPendingWorkIsOrderedAndALaterKindIncludesAnEarlier() {
        XCTAssertLessThan(Machine.Pending.none, .judge)
        XCTAssertLessThan(Machine.Pending.judge, .read)
        XCTAssertLessThan(Machine.Pending.read, .forcedRead)
        let threshold = Machine.milliseconds(Self.start) + 60_000
        let harness = readHarness(judgements: ["a": .init(verdict: .pastByPhone, rejudgeAtChainTime: threshold)])
        harness.send(.hidden)
        harness.send(.chainTip(Self.start.addingTimeInterval(60)))
        harness.send(.listing(scope: Self.scope, rows: [Self.row("a", updatedAt: 20)]))
        XCTAssertEqual(harness.machine.pending, .read)
        XCTAssertEqual(Self.reads(harness.send(.shown(forcesRead: false))).count, 1)
    }
}

/// How `ConnectionExpiryChecker` runs the machine's effects.
@MainActor
final class ConnectionExpiryCheckerTests: XCTestCase {
    /// Hands out each read's answer, and waits that end only when released.
    @MainActor
    private final class Script {
        var answers: [ConnectionExpiryReadResult] = []
        var holdsReads = false
        var identity = "identity"
        private(set) var reads = 0
        private(set) var waits: [TimeInterval] = []
        private var heldReads: [CheckedContinuation<Void, Never>] = []
        private var heldWaits: [CheckedContinuation<Void, Never>] = []
        private(set) var reported: [ConnectionExpiries] = []

        nonisolated init() {}

        func read() async -> ConnectionExpiryReadResult {
            reads += 1
            if holdsReads { await withCheckedContinuation { heldReads.append($0) } }
            return answers.count > 1 ? answers.removeFirst() : (answers.first ?? .notReady)
        }

        func wait(_ seconds: TimeInterval) async {
            waits.append(seconds)
            await withCheckedContinuation { heldWaits.append($0) }
        }

        func releaseReads() {
            holdsReads = false
            let held = heldReads
            heldReads = []
            held.forEach { $0.resume() }
        }

        func releaseWaits() {
            let held = heldWaits
            heldWaits = []
            held.forEach { $0.resume() }
        }

        func report(_ expiries: ConnectionExpiries) { reported.append(expiries) }
    }

    private func makeChecker(_ script: Script) -> ConnectionExpiryChecker {
        let dependencies = ConnectionExpiryChecker.Dependencies(
            readKeys: { _ in await script.read() },
            judge: { _, apps, _, _, _ in
                Dictionary(uniqueKeysWithValues: apps.map { ($0, AppConnect.ExpiryJudgement(verdict: .expired)) })
            },
            now: { Date(timeIntervalSince1970: 1_800_000_000) }, chainTime: { nil }, identityId: { script.identity },
            sleep: { await script.wait($0) })
        return ConnectionExpiryChecker(dependencies: dependencies) { script.report($0) }
    }

    private static func row(_ id: String) -> DAppConnection {
        var row = DAppConnection(
            id: id, name: id, url: "\(id).app", status: .active, updatedAt: Date(timeIntervalSince1970: 10),
            loginKind: .oneQR)
        row.scope = "wallet-a"
        return row
    }

    private static let keys = ConnectionExpiryReadResult.keys(
        ConnectionIdentityKeys(identityId: "identity", keys: [], bindings: []))

    private func waitFor(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    func testAReadIsMadeAndWhatItFoundIsReported() async {
        let script = Script()
        script.answers = [Self.keys]
        let checker = makeChecker(script)
        checker.listingChanged(scope: "wallet-a", rows: [Self.row("a")])
        checker.pageShown(forcesRead: false)
        await waitFor { checker.expiries.check == .read }
        XCTAssertEqual(script.reads, 1)
        XCTAssertEqual(checker.expiries.byApp["a"]?.verdict, .expired)
        XCTAssertEqual(script.reported.last, checker.expiries)
    }

    func testAWaitEndsInItsEventUnlessCancelled() async {
        let script = Script()
        script.answers = [.notReady]
        let checker = makeChecker(script)
        checker.listingChanged(scope: "wallet-a", rows: [Self.row("a")])
        checker.pageShown(forcesRead: false)
        await waitFor { script.waits == [2] }
        script.releaseWaits()
        await waitFor { script.reads == 2 }
        XCTAssertEqual(script.reads, 2, "the wait ended: read again")

        await waitFor { script.waits == [2, 5] }
        checker.pageHidden()
        script.releaseWaits()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(script.reads, 2, "a cancelled wait reads nothing")
    }

    func testACancelledReadIsNotReported() async {
        let script = Script()
        script.answers = [
            ConnectionExpiryReadResult.failed("first"),
            .keys(ConnectionIdentityKeys(identityId: "other", keys: [], bindings: [])),
        ]
        script.holdsReads = true
        let checker = makeChecker(script)
        checker.listingChanged(scope: "wallet-a", rows: [Self.row("a")])
        checker.pageShown(forcesRead: false)
        await waitFor { script.reads == 1 }
        script.identity = "other"
        checker.identityMayHaveChanged()
        await waitFor { script.reads == 2 }
        script.releaseReads()
        await waitFor { checker.expiries.check != .checking }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(checker.expiries.check, .read, "only the read that was not cancelled ended")
        XCTAssertFalse(script.reported.contains { $0.check == .failed })
    }

    func testOnlyAChangeIsReported() async {
        let script = Script()
        script.answers = [Self.keys]
        let checker = makeChecker(script)
        checker.listingChanged(scope: "wallet-a", rows: [Self.row("a")])
        checker.pageShown(forcesRead: false)
        await waitFor { checker.expiries.check == .read }
        let reported = script.reported.count
        var renamed = Self.row("a")
        renamed = DAppConnection(
            id: "a", name: "Renamed", url: renamed.url, status: .active, updatedAt: renamed.updatedAt, loginKind: .oneQR)
        renamed.scope = "wallet-a"
        checker.listingChanged(scope: "wallet-a", rows: [renamed])
        checker.chainTipChanged(Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(script.reported.count, reported)
    }

    func testAManagerKeepsItsGenerationAndAnotherGetsTheNext() {
        let generations = ManagerGenerations()
        let first = NSObject()
        XCTAssertEqual(generations.generation(of: nil), 0)
        XCTAssertEqual(generations.generation(of: first), 1)
        XCTAssertEqual(generations.generation(of: first), 1)
        XCTAssertEqual(generations.generation(of: nil), 1, "none running keeps the number")
        XCTAssertEqual(generations.generation(of: NSObject()), 2)
    }
}
