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

import Combine
@testable import dashpay
import XCTest

/// The Send screen's ViewModel (SCR-04; AC-01, AC-01b, AC-04, AC-08, AC-09, AC-10, AC-11, AC-12, AC-12b, AC-14,
/// AC-15): only the edges are
/// faked (the balances, the fee estimate, the per-route Max planners, the Current identity, the DASH/fiat
/// conversion); the pair policy, the amount rules and the ViewModel are the real ones.
@MainActor
final class SendAmountViewModelTests: XCTestCase {
    private typealias State = SendAmountViewModel.State

    // MARK: - Fixtures

    private let coreBalance: UInt64 = 500_000_000
    private let shieldedBalance: UInt64 = 300_000_000
    private let platformBalance: UInt64 = 200_000_000
    private let identityCredits: UInt64 = 5_000_000_000
    private let oneDash: UInt64 = 100_000_000
    private let fee: UInt64 = 1_000
    /// An identity's fee, in credits.
    private let identityFeeCredits: UInt64 = 1_000_000
    private let reserveCredits = IdentityCreditBalance.lowBalance
    private let ownID = "OwnIdentityIDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    private let otherID = "OtherIdentityIDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    private let coreText = "yXeJ5kYtEbCUBY4XzGmcoMvMQUXmM6e8sA"

    private func destination(_ type: Destination.Kind = .coreAddress, text: String? = nil,
                             amountDuffs: UInt64? = nil, requestURL: URL? = nil) -> Destination {
        Destination(type: type, text: text ?? (type == .paymentRequest ? "" : coreText),
                    amountDuffs: amountDuffs, paymentRequestURL: requestURL)
    }

    // MARK: - Fakes

    private final class FakeBalances: ExternalSendBalanceReading {
        var table: [SendSource: UInt64] = [:]
        /// When set, a read of this source suspends until `release`.
        var holdSource: SendSource?
        private var held: CheckedContinuation<Void, Never>?

        var isHolding: Bool { held != nil }

        func spendableBalance(of source: SendSource) async -> UInt64? {
            if source == holdSource { await withCheckedContinuation { held = $0 } }
            return table[source]
        }

        func release() {
            holdSource = nil
            held?.resume()
            held = nil
        }
    }

    private final class FakeIdentity: CurrentIdentityReading {
        var current: SelectSourceIdentity?

        func currentIdentity() async -> SelectSourceIdentity? {
            current
        }
    }

    private final class FakeEstimator: SendFeeEstimating {
        var defaultResult: SendFeeEstimate = .fee(1_000)
        var results: [SendRoute: SendFeeEstimate] = [:]
        /// When set, the answer depends on the amount (to tell a stale answer from the latest one).
        var byAmount: ((UInt64) -> SendFeeEstimate)?
        /// The estimate for these amounts suspends until `release`, so the `estimating` state can be observed.
        var gatedAmounts: Set<UInt64> = []
        private(set) var calls: [(route: SendRoute, amount: UInt64)] = []
        private var gates: [UInt64: CheckedContinuation<Void, Never>] = [:]
        /// Released before the estimate reached its gate, so it passes straight through instead of waiting forever.
        private var releasedEarly: Set<UInt64> = []

        func estimate(route: SendRoute, amount: UInt64) async -> SendFeeEstimate {
            calls.append((route, amount))
            if gatedAmounts.contains(amount), releasedEarly.remove(amount) == nil {
                await withCheckedContinuation { gates[amount] = $0 }
            }
            return byAmount?(amount) ?? results[route] ?? defaultResult
        }

        func isWaiting(_ amount: UInt64) -> Bool {
            gates[amount] != nil
        }

        func release(_ amount: UInt64) {
            guard let gate = gates.removeValue(forKey: amount) else {
                releasedEarly.insert(amount)
                return
            }
            gate.resume()
        }
    }

    private final class FakeMaxPlanner: SendMaxPlanning {
        /// A route missing from the table cannot be planned (nil). Duffs, whatever the source's own unit.
        var table: [SendRoute: UInt64] = [:]
        /// A Shielded sweep plan's exact credits, by route.
        var sweepCredits: [SendRoute: UInt64] = [:]
        /// What the funding step answers for any amount.
        var fundingCheck: SendFundingCheck = .notChecked
        private(set) var requested: [SendRoute] = []

        func maxPlan(route: SendRoute) async -> SendMaxPlan? {
            requested.append(route)
            return table[route].map { SendMaxPlan(duffs: $0, sweepCredits: sweepCredits[route]) }
        }

        func canFund(route: SendRoute, amount: UInt64) async -> SendFundingCheck {
            fundingCheck
        }
    }

    private final class FakeFundingCandidates: PlatformFundingCandidatesReading {
        /// nil: the addresses cannot be read.
        var candidates: [PlatformPaymentIdentityFundingPolicy.Candidate]? = []

        func fundingCandidates() async -> [PlatformPaymentIdentityFundingPolicy.Candidate]? {
            candidates
        }
    }

    /// 1 DASH = 50 units of the local currency.
    private final class FakeConverter: SendAmountConverting {
        var rate: Decimal? = 50

        func fiat(forDuffs duffs: UInt64) -> Decimal? {
            rate.map { Decimal(duffs) / 100_000_000 * $0 }
        }

        func duffs(forFiat fiat: Decimal) -> UInt64? {
            guard let rate else { return nil }
            var value = fiat / rate * 100_000_000
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 0, .down)
            return NSDecimalNumber(decimal: rounded).uint64Value
        }

        func fiatText(forDuffs duffs: UInt64) -> String? {
            fiat(forDuffs: duffs).map { "$\($0)" }
        }
    }

    private let balances = FakeBalances()
    private let identity = FakeIdentity()
    private let estimator = FakeEstimator()
    private let planner = FakeMaxPlanner()
    private let converter = FakeConverter()
    private let fundingCandidates = FakeFundingCandidates()
    private var continued: [SendAmountRequest] = []
    private var restoreSyncBlocks = false

    override func setUp() {
        super.setUp()
        balances.table = [.core: coreBalance, .shielded: shieldedBalance, .platform: platformBalance,
                          .identity: identityCredits]
        identity.current = SelectSourceIdentity(id: ownID, username: "alice")
        planner.table = [.coreToCore: 499_990_000, .shieldedToCore: 299_000_000, .platformToCore: 199_000_000,
                         .coreToShielded: 499_996_000]
        estimator.results = [.shieldedToCore: .fee(2_000), .platformToCore: .fee(3_000),
                             .coreToShielded: .fee(4_000), .identityToCore: .fee(identityFeeCredits)]
    }

    private func makeVM(_ destination: Destination? = nil, pinned: SendSource? = nil,
                        recipient: IdentityRecipient? = nil) async -> SendAmountViewModel {
        let vm = SendAmountViewModel(destination: destination ?? self.destination(), pinnedSource: pinned,
                                     recipient: recipient,
                                     balances: balances, feeEstimator: estimator, maxPlanner: planner,
                                     converter: converter, currentIdentity: identity,
                                     initialRestoreSync: Just(restoreSyncBlocks).eraseToAnyPublisher())
        vm.onContinue = { [unowned self] request in continued.append(request) }
        await vm.load()
        return vm
    }

    private func waitUntilGated(_ amount: UInt64) async {
        for _ in 0 ..< 200 where !estimator.isWaiting(amount) {
            await Task.yield()
        }
        XCTAssertTrue(estimator.isWaiting(amount), "the estimate never started for \(amount)")
    }

    // MARK: - AC-04 / AC-01: what the screen names

    func testNamesTheDestinationTypeFromTheWholeDestination() async {
        let core = await makeVM(destination(.coreAddress))
        XCTAssertEqual(core.destinationTypeText, "Core address")
        let shielded = await makeVM(destination(.shieldedAddress, text: "shielded-" + coreText))
        XCTAssertEqual(shielded.destinationTypeText, "Shielded address")
        let platform = await makeVM(destination(.platformAddress, text: "platform-" + coreText))
        XCTAssertEqual(platform.destinationTypeText, "Platform address")
    }

    func testShowsAShortenedAddressThatKeepsBothEnds() async {
        let vm = await makeVM()
        XCTAssertLessThan(vm.shortAddress.count, coreText.count)
        XCTAssertTrue(vm.shortAddress.contains("…"))
        XCTAssertTrue(vm.shortAddress.hasPrefix(String(coreText.prefix(6))))
        XCTAssertTrue(vm.shortAddress.hasSuffix(String(coreText.suffix(5))))
    }

    func testShowsTheSourceBalanceWithItsFiatValue() async {
        let vm = await makeVM()
        XCTAssertEqual(vm.source, .core)
        XCTAssertEqual(vm.sourceBalanceText, coreBalance.formattedDashAmount)
        XCTAssertEqual(vm.sourceBalanceFiatText, converter.fiatText(forDuffs: coreBalance))
        XCTAssertNotNil(vm.sourceBalanceFiatText)
    }

    // MARK: - AC-10: the starting source

    func testStartsFromCoreWhenItHoldsABalance() async {
        let vm = await makeVM()
        XCTAssertEqual(vm.source, .core)
        XCTAssertEqual(vm.route, .coreToCore)
    }

    func testASecondLoadKeepsThePickedSourceAndTheTypedAmount() async {
        let vm = await makeVM()
        await vm.pickSource(.platform)
        await vm.setAmountText("0.5")

        await vm.load()

        XCTAssertEqual(vm.source, .platform)
        XCTAssertEqual(vm.amountText, "0.5")
    }

    func testStartsFromTheFirstFundedSourceThatCanPay() async {
        balances.table[.core] = 0
        let vm = await makeVM()
        XCTAssertEqual(vm.source, .shielded)
        XCTAssertEqual(vm.route, .shieldedToCore)
        balances.table[.shielded] = 0
        let platform = await makeVM()
        XCTAssertEqual(platform.source, .platform)
    }

    func testNeverStartsFromIdentityEvenWhenOnlyItIsFunded() async {
        balances.table = [.core: 0, .shielded: 0, .platform: 0, .identity: identityCredits]
        let vm = await makeVM()
        XCTAssertNotEqual(vm.source, .identity)
    }

    func testNoFundedSourceStartsAtTheFirstPayableSourceAtZeroAndBlocksContinue() async {
        balances.table = [.core: 0, .shielded: 0, .platform: 0, .identity: identityCredits]
        let vm = await makeVM(destination(.identityID, text: otherID))
        XCTAssertEqual(vm.source, .shielded, "Core cannot pay someone else's identity")
        XCTAssertEqual(vm.sourceBalanceDuffs, 0)
        XCTAssertEqual(vm.state, .notEnough)
        XCTAssertFalse(vm.isContinueEnabled)
    }

    func testSkipsASourceThatCannotPayTheDestination() async {
        let vm = await makeVM(destination(.identityID, text: otherID))
        XCTAssertEqual(vm.source, .shielded)
        XCTAssertEqual(vm.route, .shieldedToIdentity)
    }

    // MARK: - AC-11: DASH and local currency

    func testTypingDashSetsTheDashAmountAndShowsItsFiatValue() async {
        let vm = await makeVM()
        await vm.setAmountText("1")
        XCTAssertEqual(vm.unit, .dash)
        XCTAssertEqual(vm.amountDuffs, oneDash)
        XCTAssertEqual(vm.secondaryAmountText, converter.fiatText(forDuffs: oneDash))
    }

    func testTypingFiatSendsTheConvertedDashAmount() async {
        let vm = await makeVM()
        vm.setUnit(.fiat)
        await vm.setAmountText("25")
        XCTAssertEqual(vm.amountDuffs, oneDash / 2)
        XCTAssertEqual(vm.secondaryAmountText, (oneDash / 2).formattedDashAmount)
        XCTAssertEqual(estimator.calls.last?.amount, oneDash / 2, "the estimate runs on the DASH amount")
        await vm.proceed()
        XCTAssertEqual(continued.last?.amount, oneDash / 2)
    }

    func testSwitchingUnitConvertsTheTextAndRoundTripsToTheSameDashAmount() async {
        let vm = await makeVM()
        await vm.setAmountText("1")
        vm.setUnit(.fiat)
        XCTAssertEqual(vm.amountText, "50")
        XCTAssertEqual(vm.amountDuffs, oneDash)
        vm.setUnit(.dash)
        XCTAssertEqual(vm.amountText, "1")
        XCTAssertEqual(vm.amountDuffs, oneDash)
    }

    func testWithoutARateFiatIsUnavailableAndDashEntryStillWorks() async {
        converter.rate = nil
        let vm = await makeVM()
        XCTAssertFalse(vm.isFiatAvailable)
        XCTAssertNil(vm.sourceBalanceFiatText)
        vm.setUnit(.fiat)
        XCTAssertEqual(vm.unit, .dash)
        await vm.setAmountText("1")
        XCTAssertEqual(vm.amountDuffs, oneDash)
        XCTAssertEqual(vm.state, .ready)
    }

    func testWithARateFiatIsAvailable() async {
        let vm = await makeVM()
        XCTAssertTrue(vm.isFiatAvailable)
    }

    // MARK: - Continue

    func testAnEmptyAmountBlocksContinue() async {
        let vm = await makeVM()
        XCTAssertEqual(vm.state, .amountEmpty)
        XCTAssertFalse(vm.isContinueEnabled)
        await vm.proceed()
        XCTAssertTrue(continued.isEmpty)
    }

    func testAValidAmountEnablesContinueAndHandsOnRouteDestinationAmountAndIsMax() async {
        let dest = destination()
        let vm = await makeVM(dest)
        await vm.setAmountText("1")
        XCTAssertEqual(vm.state, .ready)
        XCTAssertTrue(vm.isContinueEnabled)
        await vm.proceed()
        XCTAssertEqual(continued, [SendAmountRequest(route: .coreToCore, destination: dest, amount: oneDash,
                                                     isMax: false)])
    }

    // MARK: - AC-19: a restored wallet's initial sync

    func testDuringTheInitialRestoreSyncACoreSourceCannotContinue() async {
        restoreSyncBlocks = true
        for dest in [destination(), destination(.shieldedAddress, text: "dash1-shielded"),
                     destination(.platformAddress, text: "dash1-platform")] {
            let vm = await makeVM(dest, pinned: .core)
            await vm.setAmountText("1")
            XCTAssertEqual(vm.source, .core)
            XCTAssertTrue(vm.isBlockedBySync, "\(dest.type)")
            XCTAssertFalse(vm.isContinueEnabled, "\(dest.type)")
            await vm.proceed()
        }
        XCTAssertTrue(continued.isEmpty)
    }

    func testDuringTheInitialRestoreSyncAnotherSourceStillContinues() async {
        restoreSyncBlocks = true
        let vm = await makeVM(pinned: .platform)
        await vm.setAmountText("1")
        XCTAssertEqual(vm.source, .platform)
        XCTAssertFalse(vm.isBlockedBySync)
        XCTAssertTrue(vm.isContinueEnabled)
    }

    func testOnceTheRestoreSyncIsDoneACoreSourceContinues() async {
        let vm = await makeVM(pinned: .core)
        await vm.setAmountText("1")
        XCTAssertFalse(vm.isBlockedBySync)
        XCTAssertTrue(vm.isContinueEnabled)
    }

    func testTheEstimateRunsForTheRouteAndAmount() async {
        let vm = await makeVM()
        await vm.setAmountText("1")
        XCTAssertEqual(estimator.calls.last?.route, .coreToCore)
        XCTAssertEqual(estimator.calls.last?.amount, oneDash)
        XCTAssertEqual(vm.fee, fee)
    }

    // MARK: - AC-08, AC-12b: the Core to Identity top-up minimum

    private let topUpMinimum = DWIdentityRegistrationCoordinator.minimumCoreTopUpDuffs

    /// The DASH text the keypad would type for `duffs`.
    private func typed(_ duffs: UInt64) -> String {
        "\(Decimal(duffs) / Decimal(oneDash))"
    }

    func testACoreToIdentityAmountBelowTheTopUpMinimumCannotContinue() async {
        let vm = await makeVM(destination(.identityID, text: ownID), recipient: recipient(own: true))
        XCTAssertEqual(vm.route, .coreToIdentity)

        await vm.setAmountText(typed(topUpMinimum - 1))

        XCTAssertEqual(vm.amountDuffs, topUpMinimum - 1)
        XCTAssertEqual(vm.state, .belowMinimum)
        XCTAssertFalse(vm.isContinueEnabled)
        XCTAssertEqual(vm.amountErrorMessage,
                       "The minimum amount you can send is \(topUpMinimum.formattedDashAmount)")
        await vm.proceed()
        XCTAssertTrue(continued.isEmpty, "nothing reaches the flow, so nothing authenticates")
    }

    func testACoreToIdentityAmountOfExactlyTheTopUpMinimumContinues() async {
        let vm = await makeVM(destination(.identityID, text: ownID), recipient: recipient(own: true))

        await vm.setAmountText(typed(topUpMinimum))

        XCTAssertEqual(vm.state, .ready)
        XCTAssertNil(vm.amountErrorMessage)
        await vm.proceed()
        XCTAssertEqual(continued.map(\.amount), [topUpMinimum])
    }

    func testACoreToIdentityMaxBelowTheTopUpMinimumFillsTheAmountAndCannotContinue() async {
        planner.table[.coreToIdentity] = topUpMinimum - 100
        let vm = await makeVM(destination(.identityID, text: ownID), recipient: recipient(own: true))

        await vm.tapMax()

        XCTAssertEqual(vm.amountDuffs, topUpMinimum - 100, "Max fills the value")
        XCTAssertEqual(vm.state, .belowMinimum)
        XCTAssertFalse(vm.isContinueEnabled)
        XCTAssertNotNil(vm.amountErrorMessage, "with the reason")
    }

    func testTheTopUpMinimumAppliesOnlyToCoreToIdentity() async {
        let core = await makeVM()
        await core.setAmountText(typed(topUpMinimum - 1))
        XCTAssertEqual(core.state, .ready, "Core to Core")
        let platform = await makeVM(destination(.identityID, text: ownID), pinned: .platform,
                                    recipient: recipient(own: true))
        XCTAssertEqual(platform.route, .platformToIdentity)
        await platform.setAmountText(typed(topUpMinimum - 1))
        XCTAssertEqual(platform.state, .ready, "Platform to Identity")
    }

    func testAnAmountAboveTheBalanceSaysTheBalanceIsNotEnough() async {
        let vm = await makeVM()
        await vm.setAmountText("6")
        XCTAssertEqual(vm.state, .notEnough)
        XCTAssertEqual(vm.amountErrorMessage, "Balance not enough")
    }

    // MARK: - AC-08: Max and the balance check

    func testMaxFillsTheAmountTheRoutePlannerReturnsAndCarriesIsMax() async {
        let vm = await makeVM()
        await vm.tapMax()
        XCTAssertEqual(planner.requested.last, .coreToCore)
        XCTAssertEqual(vm.amountDuffs, 499_990_000)
        XCTAssertEqual(vm.amountText, UInt64(499_990_000).formattedDashAmountWithoutCurrencySymbol)
        XCTAssertEqual(vm.state, .ready)
        await vm.proceed()
        XCTAssertEqual(continued.last?.amount, 499_990_000)
        XCTAssertEqual(continued.last?.isMax, true)
    }

    func testAMaxTheFundingStepCannotPayIsNotEnoughAndContinueIsDisabled() async {
        let vm = await makeVM()
        await vm.tapMax()
        XCTAssertEqual(vm.state, .ready)

        planner.fundingCheck = .notFundable
        await vm.tapMax()

        XCTAssertEqual(vm.state, .notEnough)
        XCTAssertFalse(vm.isContinueEnabled)
    }

    /// A sweep plan of 123_456_789 credits shows as 123_456 duffs; Continue hands on the plan's exact credits, which
    /// the coordinator checks the sweep against. A typed amount after it hands on none.
    func testShieldedMaxHandsOnThePlansExactCreditsAndATypedAmountDropsThem() async {
        balances.table[.core] = 0
        planner.table[.shieldedToCore] = 123_456
        planner.sweepCredits[.shieldedToCore] = 123_456_789
        let vm = await makeVM()
        await vm.tapMax()
        await vm.proceed()
        XCTAssertEqual(continued.last?.amount, 123_456)
        XCTAssertEqual(continued.last?.sweepCredits, 123_456_789)

        await vm.setAmountText("1")
        await vm.proceed()
        XCTAssertEqual(continued.last?.isMax, false)
        XCTAssertNil(continued.last?.sweepCredits)
    }

    func testMaxUsesTheRoutePlannerOfEachSource() async {
        balances.table[.core] = 0
        let shielded = await makeVM()
        await shielded.tapMax()
        XCTAssertEqual(planner.requested.last, .shieldedToCore)
        XCTAssertEqual(shielded.amountDuffs, 299_000_000)

        balances.table[.shielded] = 0
        let platform = await makeVM()
        await platform.tapMax()
        XCTAssertEqual(planner.requested.last, .platformToCore)
        XCTAssertEqual(platform.amountDuffs, 199_000_000)

        balances.table = [.core: coreBalance, .shielded: 0, .platform: 0]
        let drain = await makeVM(destination(.shieldedAddress, text: "shielded-" + coreText))
        await drain.tapMax()
        XCTAssertEqual(planner.requested.last, .coreToShielded)
        XCTAssertEqual(drain.amountDuffs, 499_996_000)
    }

    func testMaxKeepsTheExactDuffsWhileShownInFiat() async {
        planner.table[.coreToCore] = 123_456_789
        let vm = await makeVM()
        vm.setUnit(.fiat)
        await vm.tapMax()
        XCTAssertEqual(vm.amountText, "61.73")
        XCTAssertEqual(vm.amountDuffs, 123_456_789, "not re-derived from the rounded fiat text")
        await vm.proceed()
        XCTAssertEqual(continued.last?.amount, 123_456_789)
        XCTAssertEqual(continued.last?.isMax, true)
    }

    func testEditingTheAmountAfterMaxClearsIsMax() async {
        let vm = await makeVM()
        await vm.tapMax()
        await vm.setAmountText("1")
        await vm.proceed()
        XCTAssertEqual(continued.last?.isMax, false)
        XCTAssertEqual(continued.last?.amount, oneDash)
    }

    func testMaxPlannedAsZeroLeavesTheAmountEmpty() async {
        planner.table[.coreToCore] = 0
        let vm = await makeVM()
        await vm.tapMax()
        XCTAssertEqual(vm.amountDuffs, 0)
        XCTAssertEqual(vm.state, .amountEmpty)
    }

    /// A route that cannot plan its Max now (a pending drain, a failed estimate) drops Max, so the typed-amount
    /// balance check applies to whatever amount stays.
    func testMaxThatCannotBePlannedIsDroppedAndTheAmountIsCheckedAgain() async {
        planner.table[.coreToCore] = coreBalance
        let vm = await makeVM()
        await vm.tapMax()
        XCTAssertEqual(vm.state, .ready)
        planner.table[.coreToCore] = nil
        await vm.tapMax()
        XCTAssertEqual(vm.amountDuffs, coreBalance, "an unplannable Max is not guessed from balance minus fee")
        XCTAssertEqual(vm.state, .notEnough, "the amount is no longer a Max, so the balance check applies")
        await vm.proceed()
        XCTAssertTrue(continued.isEmpty)
    }

    func testPickingASourceWhoseMaxCannotBePlannedDropsMax() async {
        planner.table[.coreToCore] = coreBalance
        planner.table[.platformToCore] = nil
        let vm = await makeVM()
        await vm.tapMax()
        await vm.pickSource(.platform)
        XCTAssertEqual(planner.requested.last, .platformToCore)
        XCTAssertEqual(vm.state, .notEnough, "\(coreBalance) is above the Platform balance less the fee")
        await vm.setAmountText("0.5")
        await vm.proceed()
        XCTAssertEqual(continued.last?.isMax, false)
    }

    func testReturnFromConfirmWhenMaxCannotBePlannedAnyMoreDropsMax() async {
        planner.table[.coreToCore] = coreBalance - 1_000
        let vm = await makeVM()
        await vm.tapMax()
        balances.table[.core] = 100_000_000
        planner.table[.coreToCore] = nil
        await vm.confirmReportedNotEnough()
        XCTAssertEqual(vm.state, .notEnough)
        XCTAssertFalse(vm.isContinueEnabled)
    }

    func testAMaxAmountIsTrustedEvenWhenItPlusTheFeeExceedsTheBalance() async {
        planner.table[.coreToCore] = coreBalance
        let vm = await makeVM()
        await vm.tapMax()
        XCTAssertEqual(vm.amountDuffs, coreBalance)
        XCTAssertEqual(vm.state, .ready, "a planner amount is not re-checked on Send")
        XCTAssertTrue(vm.isContinueEnabled)
        await vm.setAmountText("5")
        XCTAssertEqual(vm.state, .notEnough, "an edit clears isMax and the check applies again")
    }

    // MARK: - LiveSendMaxPlanner: the balance less the fee on the routes without a planner of their own

    func testTheLivePlannerFillsTheBalanceLessTheFeeOnTheTwoRoutesWithoutAPlanner() async {
        balances.table = [.core: 5_000_000, .shielded: 3_000_000, .platform: 2_000_000]
        estimator.results = [
            .coreToPlatform: .fee(7_251, assetLockMinerFee: 2_250),
            .coreToIdentity: .fee(2_250, assetLockMinerFee: 2_250)
        ]
        let live = LiveSendMaxPlanner(fees: estimator, balances: balances, fundingCandidates: fundingCandidates)
        let coreToPlatform = await live.maxPlan(route: .coreToPlatform)?.duffs
        let coreToIdentity = await live.maxPlan(route: .coreToIdentity)?.duffs
        XCTAssertEqual(coreToPlatform, 5_000_000 - 7_251)
        XCTAssertEqual(coreToIdentity, 5_000_000 - 2_250)
    }

    /// Shielded to an Identity ID is sized like the other Shielded routes, by the sweep plan of the pool top-up, so
    /// the Send screen's fee estimate is never asked for it.
    func testTheLivePlannerSizesShieldedToIdentityByTheSweepPlanNotTheBalanceLessTheFee() async {
        balances.table = [.shielded: 3_000_000]
        estimator.results = [.shieldedToIdentity: .fee(13_001)]
        let live = LiveSendMaxPlanner(fees: estimator, balances: balances, fundingCandidates: fundingCandidates)
        let plan = await live.maxPlan(route: .shieldedToIdentity)
        XCTAssertNotEqual(plan?.duffs, 3_000_000 - 13_001)
        XCTAssertTrue(estimator.calls.isEmpty, "\(estimator.calls)")
    }

    func testTheLivePlannerHasNoMaxWithoutABalanceOrAFeeAndZeroWhenTheFeeEatsTheBalance() async {
        balances.table = [.core: 1_000]
        estimator.results = [.coreToPlatform: .unavailable, .coreToIdentity: .fee(2_250, assetLockMinerFee: 2_250)]
        let live = LiveSendMaxPlanner(fees: estimator, balances: balances, fundingCandidates: fundingCandidates)
        let noFee = await live.maxPlan(route: .coreToPlatform)?.duffs
        let feeAboveBalance = await live.maxPlan(route: .coreToIdentity)?.duffs
        XCTAssertNil(noFee)
        XCTAssertEqual(feeAboveBalance, 0)
    }

    // MARK: - LiveSendMaxPlanner: Platform to Identity, sized by the top-up's own input planning

    private func address(_ firstByte: UInt8, credits: UInt64) -> PlatformPaymentIdentityFundingPolicy.Candidate {
        PlatformPaymentIdentityFundingPolicy.Candidate(
            addressType: 0, hash: Data([firstByte] + Array(repeating: 0, count: 19)), balance: credits)
    }

    /// One address of 1 DASH: the top-up keeps its fee headroom on that address, so the Max is below the balance
    /// less the observed fee.
    func testThePlatformToIdentityMaxIsWhatTheTopUpCanFundNotTheBalanceLessTheFee() async {
        let candidates = [address(1, credits: oneDash * PlatformPaymentIdentityFundingPolicy.creditsPerDuff)]
        fundingCandidates.candidates = candidates
        balances.table = [.platform: oneDash]
        estimator.results = [.platformToIdentity: .fee(41_500)]
        let live = LiveSendMaxPlanner(fees: estimator, balances: balances, fundingCandidates: fundingCandidates)

        let max = await live.maxPlan(route: .platformToIdentity)

        let fundable = PlatformPaymentIdentityFundingPolicy.maxFundableDuffs(candidates: candidates)
        XCTAssertEqual(max, SendMaxPlan(duffs: fundable, sweepCredits: nil))
        XCTAssertLessThan(fundable, oneDash - 41_500)
    }

    func testThePlatformToIdentityMaxIsZeroWhenNoAddressCanPayAndNilWhenTheyCannotBeRead() async {
        balances.table = [.platform: oneDash]
        let live = LiveSendMaxPlanner(fees: estimator, balances: balances, fundingCandidates: fundingCandidates)
        fundingCandidates.candidates = [address(1, credits: PlatformPaymentIdentityFundingPolicy.feeHeadroomCredits)]
        let nothingFundable = await live.maxPlan(route: .platformToIdentity)?.duffs
        fundingCandidates.candidates = nil
        let unreadable = await live.maxPlan(route: .platformToIdentity)?.duffs
        XCTAssertEqual(nothingFundable, 0)
        XCTAssertNil(unreadable)
    }

    func testTheLivePlannerChecksAnAmountOnlyOnPlatformToIdentity() async {
        let credits = oneDash * PlatformPaymentIdentityFundingPolicy.creditsPerDuff
        fundingCandidates.candidates = [address(1, credits: credits)]
        let live = LiveSendMaxPlanner(fees: estimator, balances: balances, fundingCandidates: fundingCandidates)
        let otherRoute = await live.canFund(route: .platformToCore, amount: 10 * oneDash)
        fundingCandidates.candidates = nil
        let unreadable = await live.canFund(route: .platformToIdentity, amount: 1)
        XCTAssertEqual(otherRoute, .notChecked)
        XCTAssertEqual(unreadable, .unknown)
    }

    /// The Send screen checks a typed Platform to Identity amount against what the top-up can fund, so an amount
    /// within the balance less the fee but above that ceiling is not enough here instead of failing at Confirm.
    func testATypedPlatformToIdentityAmountAboveWhatTheTopUpCanFundIsNotEnough() async {
        let candidates = [address(1, credits: oneDash * PlatformPaymentIdentityFundingPolicy.creditsPerDuff)]
        fundingCandidates.candidates = candidates
        balances.table[.platform] = oneDash
        let live = LiveSendMaxPlanner(fees: estimator, balances: balances, fundingCandidates: fundingCandidates)
        let vm = SendAmountViewModel(destination: destination(.identityID, text: ownID), pinnedSource: .platform,
                                     recipient: recipient(own: true), balances: balances, feeEstimator: estimator,
                                     maxPlanner: live, converter: converter, currentIdentity: identity)
        await vm.load()
        XCTAssertEqual(vm.route, .platformToIdentity)
        let fundable = PlatformPaymentIdentityFundingPolicy.maxFundableDuffs(candidates: candidates)

        await vm.setAmountText(InternalTransferViewModel.formatTyped((fundable + 1).dashAmount, fractionDigits: 8))
        XCTAssertEqual(vm.amountDuffs, fundable + 1)
        XCTAssertEqual(vm.state, .notEnough, "within the balance less the fee, above what the top-up can fund")
        XCTAssertFalse(vm.isContinueEnabled)

        await vm.setAmountText(InternalTransferViewModel.formatTyped(fundable.dashAmount, fractionDigits: 8))
        XCTAssertEqual(vm.state, .ready)

        await vm.tapMax()
        XCTAssertEqual(vm.amountDuffs, fundable)
        XCTAssertEqual(vm.state, .ready)
    }

    func testATypedPlatformToIdentityAmountIsNotEnoughWhenNoAddressCanPay() async {
        fundingCandidates.candidates = [address(1, credits: PlatformPaymentIdentityFundingPolicy.feeHeadroomCredits)]
        balances.table[.platform] = oneDash
        let live = LiveSendMaxPlanner(fees: estimator, balances: balances, fundingCandidates: fundingCandidates)
        let vm = SendAmountViewModel(destination: destination(.identityID, text: ownID), pinnedSource: .platform,
                                     recipient: recipient(own: true), balances: balances, feeEstimator: estimator,
                                     maxPlanner: live, converter: converter, currentIdentity: identity)
        await vm.load()
        await vm.setAmountText("0.001")
        XCTAssertEqual(vm.state, .notEnough)
    }

    /// Addresses that cannot be read say nothing about the amount: the screen offers Try again, not "not enough".
    func testAPlatformToIdentityAmountIsUnknownNotNotEnoughWhenTheAddressesCannotBeRead() async {
        balances.table[.platform] = oneDash
        let live = LiveSendMaxPlanner(fees: estimator, balances: balances, fundingCandidates: fundingCandidates)
        let vm = SendAmountViewModel(destination: destination(.identityID, text: ownID), pinnedSource: .platform,
                                     recipient: recipient(own: true), balances: balances, feeEstimator: estimator,
                                     maxPlanner: live, converter: converter, currentIdentity: identity)
        await vm.load()
        fundingCandidates.candidates = nil

        await vm.setAmountText("0.001")
        XCTAssertEqual(vm.state, .feeFailed, "a typed amount")
        XCTAssertNotNil(vm.feeFailureMessage)
        XCTAssertFalse(vm.isContinueEnabled)

        let credits = oneDash * PlatformPaymentIdentityFundingPolicy.creditsPerDuff
        fundingCandidates.candidates = [address(1, credits: credits)]
        await vm.retryFee()
        XCTAssertEqual(vm.state, .ready, "Try again reads the addresses again")

        fundingCandidates.candidates = nil
        await vm.tapMax()
        XCTAssertEqual(vm.state, .feeFailed, "Max")
        XCTAssertFalse(vm.isContinueEnabled)
    }

    // MARK: - Return from Confirm with .balanceNotEnough

    func testReturnFromConfirmReReadsTheBalanceAndFlagsATypedAmountNowTooHigh() async {
        let vm = await makeVM()
        await vm.setAmountText("4.99999")
        XCTAssertEqual(vm.state, .ready)
        balances.table[.core] = 100_000_000
        let before = estimator.calls.count
        await vm.confirmReportedNotEnough()
        XCTAssertGreaterThan(estimator.calls.count, before, "the fee is estimated again")
        XCTAssertEqual(vm.sourceBalanceDuffs, 100_000_000)
        XCTAssertEqual(vm.state, .notEnough)
        XCTAssertFalse(vm.isContinueEnabled)
    }

    /// Confirm refused the amount on a binding fee above Send's estimate; the balance did not move. Send shows
    /// not enough until the holder changes the amount or the source (SCR-04 `not-enough`).
    func testReturnFromConfirmWithAnUnchangedBalanceShowsNotEnoughUntilTheAmountOrSourceChanges() async {
        let vm = await makeVM()
        await vm.setAmountText("4.99999")
        XCTAssertEqual(vm.state, .ready)
        await vm.confirmReportedNotEnough()
        XCTAssertEqual(vm.sourceBalanceDuffs, coreBalance, "the balance is unchanged")
        XCTAssertEqual(vm.state, .notEnough)
        XCTAssertFalse(vm.isContinueEnabled)
        await vm.proceed()
        XCTAssertTrue(continued.isEmpty)

        await vm.setAmountText("4.9")
        XCTAssertEqual(vm.state, .ready, "a new amount is checked afresh")

        await vm.confirmReportedNotEnough()
        XCTAssertEqual(vm.state, .notEnough)
        await vm.pickSource(.shielded)
        await vm.setAmountText("1")
        XCTAssertEqual(vm.state, .ready, "a new source is checked afresh")
    }

    func testReturnFromConfirmReplansAMaxAmount() async {
        let vm = await makeVM()
        await vm.tapMax()
        balances.table[.core] = 100_000_000
        planner.table[.coreToCore] = 99_990_000
        await vm.confirmReportedNotEnough()
        XCTAssertEqual(vm.amountDuffs, 99_990_000)
        XCTAssertEqual(vm.state, .ready)
        await vm.proceed()
        XCTAssertEqual(continued.last?.isMax, true)
        XCTAssertEqual(continued.last?.amount, 99_990_000)
    }

    func testAnAmountAboveTheBalanceMinusTheFeeIsNotEnoughAndCannotContinue() async {
        let vm = await makeVM()
        await vm.setAmountText("4.999991")
        XCTAssertEqual(vm.state, .notEnough)
        XCTAssertFalse(vm.isContinueEnabled)
        await vm.proceed()
        XCTAssertTrue(continued.isEmpty)
        await vm.setAmountText("5")
        XCTAssertEqual(vm.state, .notEnough)
    }

    func testTheBalanceMinusTheFeeItselfIsAllowed() async {
        let vm = await makeVM()
        await vm.setAmountText("4.99999")
        XCTAssertEqual(vm.amountDuffs, coreBalance - fee)
        XCTAssertEqual(vm.state, .ready)
    }

    func testTheCheckUsesTheFeeOfTheStartingRoute() async {
        balances.table[.core] = 0
        let vm = await makeVM()
        XCTAssertEqual(vm.route, .shieldedToCore)
        await vm.setAmountText("2.99998")
        XCTAssertEqual(vm.state, .ready, "300_000_000 - 2_000")
        await vm.setAmountText("2.999981")
        XCTAssertEqual(vm.state, .notEnough)
    }

    // MARK: - AC-01b: the fee estimate states

    /// The Platform withdrawal fee does not depend on the amount, so typing reuses the fee already known: no new
    /// estimate and no progress per keystroke; affordability stays a local check (AC-08). A failure is never reused.
    func testTypingOnPlatformToCoreReusesTheFeeAndNeverLoads() async {
        let vm = await makeVM(pinned: .platform)
        XCTAssertEqual(vm.route, .platformToCore)
        XCTAssertEqual(vm.fee, 3_000)
        let before = estimator.calls.count

        estimator.gatedAmounts = [oneDash]
        let typing = Task { await vm.setAmountText("1") }
        var loaded = false
        for _ in 0 ..< 50 {
            loaded = loaded || vm.isContinueLoading
            await Task.yield()
        }
        estimator.gatedAmounts = []
        estimator.release(oneDash)
        await typing.value
        XCTAssertFalse(loaded, "Continue never turns into progress while typing")
        XCTAssertFalse(vm.isContinueLoading)
        XCTAssertEqual(estimator.calls.count, before, "the known fee is reused")
        XCTAssertEqual(vm.state, .ready)

        await vm.setAmountText("1.99998")
        XCTAssertEqual(vm.state, .notEnough, "200_000_000 - 3_000 is the most")
        XCTAssertEqual(estimator.calls.count, before)

        estimator.results[.platformToCore] = .unavailable
        let failing = await makeVM(pinned: .platform)
        XCTAssertEqual(failing.state, .feeFailed)
        estimator.results[.platformToCore] = .fee(3_000)
        let afterFailure = estimator.calls.count
        await failing.setAmountText("1")
        XCTAssertEqual(estimator.calls.count, afterFailure + 1, "a failed estimate is estimated again")
        XCTAssertEqual(failing.state, .ready)
    }

    func testWhileTheEstimateRunsContinueIsLoadingAndMaxIsDisabled() async {
        estimator.gatedAmounts = [oneDash]
        let vm = await makeVM()
        let typing = Task { await vm.setAmountText("1") }
        await waitUntilGated(oneDash)
        XCTAssertEqual(vm.state, .estimating)
        XCTAssertTrue(vm.isContinueLoading)
        XCTAssertFalse(vm.isContinueEnabled)
        XCTAssertFalse(vm.isMaxEnabled)
        estimator.release(oneDash)
        await typing.value
        XCTAssertEqual(vm.state, .ready)
        XCTAssertFalse(vm.isContinueLoading)
        XCTAssertTrue(vm.isMaxEnabled)
    }

    func testOnlyTheLatestEstimateCounts() async {
        estimator.gatedAmounts = [oneDash]
        estimator.byAmount = { $0 == 100_000_000 ? .fee(111) : .fee(222) }
        let vm = await makeVM()
        let first = Task { await vm.setAmountText("1") }
        await waitUntilGated(oneDash)
        await vm.setAmountText("2")
        estimator.release(oneDash)
        await first.value
        XCTAssertEqual(vm.amountDuffs, 2 * oneDash)
        XCTAssertEqual(vm.fee, 222, "the answer for the earlier amount is dropped")
        XCTAssertEqual(vm.state, .ready)
    }

    func testAFailedEstimateBlocksMaxAndContinueAndOffersTryAgainForEverySource() async {
        for (zeroed, expected) in [([SendSource](), SendSource.core), ([.core], .shielded),
                                   ([.core, .shielded], .platform)] {
            balances.table = [.core: coreBalance, .shielded: shieldedBalance, .platform: platformBalance]
            zeroed.forEach { balances.table[$0] = 0 }
            estimator.defaultResult = .unavailable
            estimator.results = [:]
            let vm = await makeVM()
            await vm.setAmountText("1")
            XCTAssertEqual(vm.source, expected)
            XCTAssertEqual(vm.state, .feeFailed, "\(expected)")
            XCTAssertNil(vm.fee, "an unavailable estimate is never a zero fee")
            XCTAssertFalse(vm.isContinueEnabled, "\(expected)")
            XCTAssertFalse(vm.isMaxEnabled, "\(expected)")
            await vm.proceed()
            XCTAssertTrue(continued.isEmpty, "\(expected)")
        }
    }

    func testAFailedEstimateShowsTheCouldNotCalculateMessage() async {
        estimator.defaultResult = .unavailable
        let vm = await makeVM()
        XCTAssertEqual(vm.state, .feeFailed)
        XCTAssertEqual(vm.feeFailureMessage,
                       "Couldn't calculate the network fee. Check your connection and try again.")
    }

    func testTryAgainReRunsTheEstimateAndRestoresTheScreen() async {
        estimator.defaultResult = .unavailable
        let vm = await makeVM()
        await vm.setAmountText("1")
        XCTAssertEqual(vm.state, .feeFailed)
        let before = estimator.calls.count
        estimator.defaultResult = .fee(fee)
        await vm.retryFee()
        XCTAssertGreaterThan(estimator.calls.count, before)
        XCTAssertEqual(vm.state, .ready)
        XCTAssertEqual(vm.fee, fee)
        XCTAssertTrue(vm.isContinueEnabled)
        XCTAssertTrue(vm.isMaxEnabled)
        XCTAssertNil(vm.feeFailureMessage)
    }

    func testMaxDoesNothingWhileTheEstimateIsFailed() async {
        estimator.defaultResult = .unavailable
        let vm = await makeVM()
        await vm.tapMax()
        XCTAssertEqual(vm.amountDuffs, 0)
        XCTAssertTrue(planner.requested.isEmpty)
    }

    // MARK: - Changing the source reruns the estimate and Max

    func testPickingASourceReRunsTheEstimateForItsRouteAndKeepsTheAmount() async {
        let vm = await makeVM()
        await vm.setAmountText("1")
        await vm.pickSource(.shielded)
        XCTAssertEqual(vm.source, .shielded)
        XCTAssertEqual(vm.route, .shieldedToCore)
        XCTAssertEqual(estimator.calls.last?.route, .shieldedToCore)
        XCTAssertEqual(vm.fee, 2_000)
        XCTAssertEqual(vm.amountDuffs, oneDash)
        XCTAssertEqual(vm.sourceBalanceText, shieldedBalance.formattedDashAmount)
    }

    func testPickingASourceRecomputesAMaxAmount() async {
        let vm = await makeVM()
        await vm.tapMax()
        await vm.pickSource(.platform)
        XCTAssertEqual(planner.requested.last, .platformToCore)
        XCTAssertEqual(vm.amountDuffs, 199_000_000)
        await vm.proceed()
        XCTAssertEqual(continued.last?.route, .platformToCore)
        XCTAssertEqual(continued.last?.isMax, true)
    }

    /// Between the pick and the new balance and fee, Continue is never enabled with the old ones.
    func testContinueIsDisabledFromThePickUntilTheNewSourceIsEstimated() async {
        let vm = await makeVM()
        await vm.setAmountText("1")
        XCTAssertTrue(vm.isContinueEnabled)
        balances.holdSource = .platform

        let pick = Task { await vm.pickSource(.platform) }
        for _ in 0 ..< 200 where !balances.isHolding { await Task.yield() }
        XCTAssertTrue(balances.isHolding)
        XCTAssertEqual(vm.state, .estimating)
        XCTAssertFalse(vm.isContinueEnabled)
        await vm.proceed()
        XCTAssertTrue(continued.isEmpty)

        balances.release()
        await pick.value
        XCTAssertEqual(vm.state, .ready)
    }

    /// An estimate typed for the old source that answers while the new source loads is dropped: it neither ends
    /// the estimating state nor leaves its fee behind.
    func testAnEstimateForTheOldSourceAnsweringDuringThePickIsDropped() async {
        estimator.gatedAmounts = [oneDash]
        let vm = await makeVM()
        let typing = Task { await vm.setAmountText("1") }
        await waitUntilGated(oneDash)
        balances.holdSource = .platform

        let pick = Task { await vm.pickSource(.platform) }
        for _ in 0 ..< 200 where !balances.isHolding { await Task.yield() }
        XCTAssertTrue(balances.isHolding)
        estimator.gatedAmounts = []
        estimator.release(oneDash)
        await typing.value
        XCTAssertEqual(vm.state, .estimating, "the Core answer does not end the Platform estimate")
        XCTAssertFalse(vm.isContinueEnabled)

        balances.release()
        await pick.value
        XCTAssertEqual(vm.fee, 3_000, "the Platform fee, not the Core one")
        XCTAssertEqual(vm.state, .ready)
    }

    /// An amount typed while the new source's balance loads is never checked against the old source's balance.
    func testATypedAmountDuringThePickIsNotCheckedAgainstTheOldBalance() async {
        let vm = await makeVM()
        balances.holdSource = .platform

        let pick = Task { await vm.pickSource(.platform) }
        for _ in 0 ..< 200 where !balances.isHolding { await Task.yield() }
        XCTAssertTrue(balances.isHolding)
        await vm.setAmountText("3")
        XCTAssertNotEqual(vm.state, .ready, "3 DASH fits Core's 5, not Platform's 2")
        XCTAssertFalse(vm.isContinueEnabled)

        balances.release()
        await pick.value
        XCTAssertEqual(vm.state, .notEnough)
    }

    /// After Confirm refused a typed amount, Send never shows it ready while the balance is read again.
    func testReturnFromConfirmNeverShowsATypedAmountReadyWhileTheBalanceIsReadAgain() async {
        let vm = await makeVM()
        await vm.setAmountText("4.99999")
        XCTAssertEqual(vm.state, .ready)
        balances.holdSource = .core

        let back = Task { await vm.confirmReportedNotEnough() }
        for _ in 0 ..< 200 where !balances.isHolding { await Task.yield() }
        XCTAssertTrue(balances.isHolding)
        XCTAssertNotEqual(vm.state, .ready)
        XCTAssertFalse(vm.isContinueEnabled)

        balances.release()
        await back.value
        XCTAssertEqual(vm.state, .notEnough)
    }

    /// Max stays on screen in its disabled states; a tap there does nothing (SCR-04).
    func testMaxStaysVisibleButDisabledWhileEstimatingAfterAFeeFailureAndWithTheReserveSpent() async {
        let vm = await makeVM()
        estimator.gatedAmounts = [100_000_000]
        let typing = Task { await vm.setAmountText("1") }
        for _ in 0 ..< 200 where !estimator.isWaiting(100_000_000) { await Task.yield() }
        XCTAssertEqual(vm.state, .estimating)
        XCTAssertTrue(vm.isMaxVisible)
        XCTAssertFalse(vm.isMaxEnabled)
        estimator.release(100_000_000)
        await typing.value

        estimator.defaultResult = .unavailable
        await vm.setAmountText("2")
        XCTAssertEqual(vm.state, .feeFailed)
        XCTAssertTrue(vm.isMaxVisible)
        XCTAssertFalse(vm.isMaxEnabled)
        await vm.tapMax()
        XCTAssertEqual(vm.amountDuffs, 200_000_000, "a tap on a disabled Max changes nothing")

        let identity = await identityVM(credits: reserveCredits + identityFeeCredits / 2)
        XCTAssertTrue(identity.isMaxVisible)
        XCTAssertFalse(identity.isMaxEnabled)
    }

    func testPickingAnUnavailableSourceChangesNothing() async {
        let vm = await makeVM(destination(.identityID, text: otherID))
        XCTAssertEqual(vm.source, .shielded)
        await vm.pickSource(.core)
        XCTAssertEqual(vm.source, .shielded)
    }

    // MARK: - AC-15: dash: links and payment requests

    func testADashLinkAmountIsPrefilledAndStaysEditable() async {
        let vm = await makeVM(destination(.coreAddress, amountDuffs: oneDash))
        XCTAssertEqual(vm.amountDuffs, oneDash)
        XCTAssertEqual(vm.amountText, "1")
        XCTAssertFalse(vm.isAmountLocked)
        XCTAssertTrue(vm.isMaxVisible)
        XCTAssertEqual(vm.state, .ready)
        await vm.setAmountText("2")
        XCTAssertEqual(vm.amountDuffs, 2 * oneDash)
    }

    func testAPaymentRequestAmountIsLockedWithoutMaxOrKeypad() async throws {
        let url = try XCTUnwrap(URL(string: "https://merchant.example/pay/1"))
        let vm = await makeVM(destination(.paymentRequest, amountDuffs: oneDash, requestURL: url))
        XCTAssertTrue(vm.isAmountLocked)
        XCTAssertFalse(vm.isMaxVisible)
        XCTAssertFalse(vm.isKeypadVisible)
        XCTAssertEqual(vm.lockedCaption, "The amount is set by the payment request.")
        XCTAssertEqual(vm.amountDuffs, oneDash)
        await vm.setAmountText("3")
        XCTAssertEqual(vm.amountDuffs, oneDash, "the amount of a payment request cannot be changed")
        await vm.tapMax()
        XCTAssertEqual(vm.amountDuffs, oneDash)
        XCTAssertTrue(planner.requested.isEmpty)
    }

    func testAPaymentRequestPaysFromCoreAndContinueIsEnabled() async throws {
        let url = try XCTUnwrap(URL(string: "https://merchant.example/pay/1"))
        let dest = destination(.paymentRequest, amountDuffs: oneDash, requestURL: url)
        balances.table[.core] = 0
        let broke = await makeVM(dest)
        XCTAssertEqual(broke.source, .core, "only Core can pay a payment request")
        balances.table[.core] = coreBalance
        let vm = await makeVM(dest)
        XCTAssertEqual(vm.state, .ready)
        XCTAssertTrue(vm.isContinueEnabled)
        await vm.proceed()
        XCTAssertEqual(continued, [SendAmountRequest(route: .coreToCore, destination: dest, amount: oneDash,
                                                     isMax: false)])
    }

    func testAnOrdinaryAddressIsNeverLocked() async {
        let vm = await makeVM()
        XCTAssertFalse(vm.isAmountLocked)
        XCTAssertTrue(vm.isMaxVisible)
        XCTAssertTrue(vm.isKeypadVisible)
        XCTAssertNil(vm.lockedCaption)
    }

    // MARK: - AC-09: the Identity source and the DashPay reserve

    private func identityVM(credits: UInt64? = nil) async -> SendAmountViewModel {
        if let credits { balances.table[.identity] = credits }
        let vm = await makeVM()
        await vm.pickSource(.identity)
        return vm
    }

    func testTheIdentityBalanceInCreditsShowsAtItsDashValue() async {
        let vm = await identityVM()
        XCTAssertEqual(vm.source, .identity)
        XCTAssertEqual(vm.route, .identityToCore)
        XCTAssertEqual(vm.sourceBalanceDuffs, AmountRules.dashValue(of: identityCredits))
        XCTAssertEqual(vm.sourceBalanceText, AmountRules.dashValue(of: identityCredits).formattedDashAmount)
        XCTAssertEqual(vm.fee, identityFeeCredits)
    }

    func testIdentityMaxIsTheCreditsLessTheFeeAndTheDashPayReserve() async {
        let vm = await identityVM()
        await vm.tapMax()
        let expected = AmountRules.dashValue(of: identityCredits - identityFeeCredits - reserveCredits)
        XCTAssertEqual(vm.amountDuffs, expected)
        XCTAssertTrue(planner.requested.isEmpty, "the Identity Max is AmountRules.identityMax, not a route planner")
        XCTAssertEqual(vm.state, .ready)
        await vm.proceed()
        XCTAssertEqual(continued.last?.amount, expected)
        XCTAssertEqual(continued.last?.isMax, true)
        XCTAssertEqual(continued.last?.route, .identityToCore)
    }

    /// A Max carried from Core to Identity is planned with the Identity fee in credits, not the Core fee in duffs,
    /// so it still leaves the DashPay reserve.
    func testAMaxCarriedToTheIdentitySourceIsPlannedWithTheIdentityFee() async {
        let vm = await makeVM()
        await vm.tapMax()
        XCTAssertEqual(vm.fee, fee, "the Core fee, in duffs")

        await vm.pickSource(.identity)

        XCTAssertEqual(vm.amountDuffs, AmountRules.dashValue(of: identityCredits - identityFeeCredits - reserveCredits))
        XCTAssertEqual(vm.fee, identityFeeCredits)
        XCTAssertEqual(vm.state, .ready)
    }

    func testIdentityMaxKeepsTheReserveWithoutANoteOrWarning() async {
        let vm = await identityVM()
        XCTAssertTrue(vm.isMaxEnabled)
        await vm.tapMax()
        XCTAssertEqual(vm.amountDuffs, AmountRules.dashValue(of: identityCredits - identityFeeCredits - reserveCredits))
        XCTAssertNil(vm.reserveNote)
        XCTAssertNil(vm.reserveWarning, "Max leaves exactly the reserve")
    }

    func testOtherSourcesShowNoReserveNoteOrWarning() async {
        let vm = await makeVM()
        await vm.tapMax()
        XCTAssertNil(vm.reserveNote)
        XCTAssertNil(vm.reserveWarning)
    }

    func testWithNothingAboveTheReserveMaxIsDisabledWithTheSpentNote() async {
        let vm = await identityVM(credits: reserveCredits + identityFeeCredits / 2)
        XCTAssertFalse(vm.isMaxEnabled)
        XCTAssertEqual(vm.reserveNote, "Everything above the DashPay reserve is already spent, so Max is off. "
            + "You can still type an amount.")
        await vm.tapMax()
        XCTAssertEqual(vm.amountDuffs, 0)
        XCTAssertEqual(vm.state, .amountEmpty)
    }

    func testATypedAmountBelowTheReserveIsAllowedWithTheWarningWhenMaxIsDisabled() async {
        let vm = await identityVM(credits: reserveCredits + identityFeeCredits / 2)
        await vm.setAmountText("0.0001")
        XCTAssertEqual(vm.amountDuffs, 10_000)
        XCTAssertEqual(vm.state, .ready)
        XCTAssertTrue(vm.isContinueEnabled)
        XCTAssertEqual(vm.reserveWarning, "This leaves less than the DashPay reserve. DashPay actions, like "
            + "contact requests and profile updates, may stop working.")
        await vm.proceed()
        XCTAssertEqual(continued.last?.amount, 10_000)
        XCTAssertEqual(continued.last?.isMax, false)
    }

    func testATypedAmountThatLeavesLessThanTheReserveWarnsButCanBeSent() async {
        let vm = await identityVM()
        let aboveMax = AmountRules.dashValue(of: identityCredits - identityFeeCredits - reserveCredits) + 500
        await vm.setAmountText(InternalTransferViewModel.formatTyped(aboveMax.dashAmount, fractionDigits: 8))
        XCTAssertEqual(vm.amountDuffs, aboveMax)
        XCTAssertEqual(vm.state, .ready)
        XCTAssertNotNil(vm.reserveWarning)
        XCTAssertTrue(vm.isContinueEnabled)
    }

    func testATypedAmountThatKeepsTheReserveShowsNoWarning() async {
        let vm = await identityVM()
        await vm.setAmountText("0.039")
        XCTAssertEqual(vm.state, .ready)
        XCTAssertNil(vm.reserveWarning)
    }

    func testAnIdentityAmountAboveTheCreditsLessTheFeeIsNotEnoughWithoutTheWarning() async {
        let vm = await identityVM()
        await vm.setAmountText("0.05")
        XCTAssertEqual(vm.state, .notEnough)
        XCTAssertFalse(vm.isContinueEnabled)
        XCTAssertNil(vm.reserveWarning)
    }

    /// 999,999,999 DASH is about 1e17 duffs; in credits it would be 1e20, past `UInt64.max`.
    func testANineDigitIdentityAmountIsNotEnoughInsteadOfOverflowing() async {
        let vm = await identityVM()
        await vm.setAmountText("999999999")
        XCTAssertEqual(vm.amountDuffs, 99_999_999_900_000_000)
        XCTAssertEqual(vm.state, .notEnough)
        XCTAssertFalse(vm.isContinueEnabled)
        XCTAssertNil(vm.reserveWarning)
    }

    func testLeavingIdentityRemovesTheReserveTexts() async {
        let vm = await identityVM()
        // 0.04 DASH leaves 0.999e9 credits after the 1e6 fee: below the 1e9 reserve, so the warning shows.
        await vm.setAmountText("0.04")
        XCTAssertNotNil(vm.reserveWarning)
        await vm.pickSource(.core)
        XCTAssertNil(vm.reserveNote)
        XCTAssertNil(vm.reserveWarning)
    }

    // MARK: - AC-12 / AC-12b: the recipient identity

    private func recipient(_ id: String? = nil, username: String? = "bob", own: Bool = false) -> IdentityRecipient {
        IdentityRecipient(id: id ?? (own ? ownID : otherID), username: username, isOwnCurrentIdentity: own)
    }

    func testAnotherIdentityShowsItsUsernameAndNoNotice() async {
        let vm = await makeVM(destination(.identityID, text: otherID), recipient: recipient())
        XCTAssertEqual(vm.recipientName, "bob")
        XCTAssertNil(vm.recipientNotice)
        XCTAssertEqual(vm.shortAddress.count, 12)
        XCTAssertNil(vm.sourceChangedNotice)
    }

    func testAnIdentityWithoutAUsernameShowsTheShortIDAloneAndNoNotice() async {
        let vm = await makeVM(destination(.identityID, text: otherID), recipient: recipient(username: nil))
        XCTAssertNil(vm.recipientName, "the To row falls back to the short ID")
        XCTAssertNil(vm.recipientNotice)
    }

    func testTheCurrentIdentityFromCoreIsATopUpOfYourIdentity() async {
        let vm = await makeVM(destination(.identityID, text: ownID), recipient: recipient(own: true))
        XCTAssertEqual(vm.source, .core)
        XCTAssertEqual(vm.route, .coreToIdentity)
        XCTAssertEqual(vm.recipientName, "Your identity")
        XCTAssertEqual(vm.recipientNotice, "This tops up your own Identity credits.")
        XCTAssertNil(vm.sourceChangedNotice)
    }

    func testAnotherIdentityOfTheSameWalletIsTreatedAsSomeoneElses() async {
        let sibling = recipient("SiblingIdentityIDxxxxxxxxxxxxxxxxxxxxxxxxxxx", username: "alice2")
        let vm = await makeVM(destination(.identityID, text: sibling.id), recipient: sibling)
        XCTAssertEqual(vm.source, .shielded, "Core cannot pay it")
        XCTAssertEqual(vm.recipientName, "alice2")
        XCTAssertNil(vm.recipientNotice)
    }

    func testOtherDestinationsHaveNoRecipientStates() async {
        let vm = await makeVM()
        XCTAssertNil(vm.recipientName)
        XCTAssertNil(vm.recipientNotice)
    }

    func testAnIdentityIDIsNamedIdentity() async {
        let other = await makeVM(destination(.identityID, text: otherID), recipient: recipient())
        XCTAssertEqual(other.destinationTypeText, "Identity")
        let own = await makeVM(destination(.identityID, text: ownID), recipient: recipient(own: true))
        XCTAssertEqual(own.destinationTypeText, "Identity")
    }

    // MARK: - AC-14: the pinned source

    func testAPinnedSourceThatCanPayIsKeptWithoutANotice() async {
        let platform = await makeVM(destination(.identityID, text: ownID), pinned: .platform,
                                    recipient: recipient(own: true))
        XCTAssertEqual(platform.source, .platform)
        XCTAssertEqual(platform.route, .platformToIdentity)
        XCTAssertNil(platform.sourceChangedNotice)
        let shielded = await makeVM(pinned: .shielded)
        XCTAssertEqual(shielded.source, .shielded, "kept although Core holds more")
        XCTAssertEqual(shielded.sourceBalanceDuffs, shieldedBalance)
        XCTAssertNil(shielded.sourceChangedNotice)
    }

    func testAPinnedSourceWithoutBalanceIsKeptWhenItCanPay() async {
        balances.table[.core] = 0
        let vm = await makeVM(pinned: .core)
        XCTAssertEqual(vm.source, .core)
        XCTAssertNil(vm.sourceChangedNotice)
    }

    func testAPinnedCoreCannotPaySomeoneElsesIdentityAndIsReplacedWithTheNotice() async {
        let vm = await makeVM(destination(.identityID, text: otherID), pinned: .core, recipient: recipient())
        XCTAssertEqual(vm.source, .shielded)
        XCTAssertEqual(vm.route, .shieldedToIdentity)
        XCTAssertEqual(vm.sourceChangedNotice,
                       "Core can't pay someone else's identity, so the source was changed to Shielded.")
    }

    func testTheSourceChangedNoticeShowsWithoutARecipientStatement() async {
        let vm = await makeVM(destination(.identityID, text: otherID), pinned: .core, recipient: recipient())
        XCTAssertNotNil(vm.sourceChangedNotice)
        XCTAssertNil(vm.recipientNotice)
    }

    func testAReplacedPinIsNeverIdentityEvenWhenOnlyItIsFunded() async {
        balances.table = [.core: 0, .shielded: 0, .platform: 0, .identity: identityCredits]
        let vm = await makeVM(destination(.identityID, text: otherID), pinned: .core, recipient: recipient())
        XCTAssertEqual(vm.source, .shielded)
        XCTAssertNotNil(vm.sourceChangedNotice)
    }

    func testAPinnedShieldedCannotPayAPaymentRequestAndIsReplacedByCore() async throws {
        let url = try XCTUnwrap(URL(string: "https://merchant.example/pay/1"))
        let vm = await makeVM(destination(.paymentRequest, amountDuffs: oneDash, requestURL: url), pinned: .shielded)
        XCTAssertEqual(vm.source, .core)
        XCTAssertEqual(vm.sourceChangedNotice,
                       "A payment request can only be paid from Core, so the source was changed to Core.")
    }

    func testChangingTheSourceAfterAReplacementClearsTheNotice() async {
        let vm = await makeVM(destination(.identityID, text: otherID), pinned: .core, recipient: recipient())
        XCTAssertNotNil(vm.sourceChangedNotice)
        await vm.pickSource(.identity)
        XCTAssertEqual(vm.source, .identity)
        XCTAssertNil(vm.sourceChangedNotice)
    }

    func testAPinnedPlatformCannotPaySomeoneElsesIdentityAndIsReplacedWithTheNotice() async {
        let vm = await makeVM(destination(.identityID, text: otherID), pinned: .platform, recipient: recipient())
        XCTAssertEqual(vm.source, .shielded)
        XCTAssertEqual(vm.route, .shieldedToIdentity)
        XCTAssertEqual(vm.sourceChangedNotice,
                       "Platform can't pay someone else's identity yet, so the source was changed to Shielded.")
        await vm.pickSource(.platform)
        XCTAssertEqual(vm.source, .shielded, "Platform stays unavailable for this destination")
    }

    func testTheHolderCanStillPickAnotherSourceFromAPin() async {
        let vm = await makeVM(pinned: .shielded)
        await vm.pickSource(.platform)
        XCTAssertEqual(vm.source, .platform)
    }
}
