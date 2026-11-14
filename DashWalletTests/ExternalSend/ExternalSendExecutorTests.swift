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

@testable import dashpay
import SwiftDashSDK
import SwiftData
import XCTest

/// The Core-, Shielded- and Platform-source routes of the external send executor and its shared skeleton (AC-01,
/// AC-01b, AC-19, ADR-0039, ADR-0040): authenticate on Continue, prepare (built and signed, never broadcast) with
/// the binding fee, broadcast only on `send`, one of three outcomes, one log line per outcome.
///
/// The executor, `AuthenticationGate`, `AmountRules`, `SendOutcome` and `PreparedStandardSend` (its broadcast state
/// machine) are production. Only the edges are scripted: the PIN prompt (`SendAuthenticationPrompting`), the
/// `WalletSendService` standard-send seam, the asset-lock / `ShieldedTransferCoordinator` seam, the fee estimate
/// and the balance read. The Shielded/Platform sources add two more: the `ShieldedTransferCoordinator` `perform*`
/// calls (`ShieldedPlatformSending`) and the identity top-up from credits (`IdentityTopUpFromCreditsSending`). The
/// Identity source adds the identity credit paths (`IdentityCreditsSending`); its amounts, fees and balance are in
/// credits.
@MainActor
final class ExternalSendExecutorTests: XCTestCase {
    private typealias CoordinatorError = ShieldedTransferCoordinator.CoordinatorError
    private typealias SenderError = SwiftDashSDKTransactionSender.SendError

    private static let walletSendDomain = "org.dashfoundation.dash.wallet-send-service"
    private static let coreAddress = "yQ9ZGPBVPgqz1oTRsUwbL9uMyKJ4jXUp6C"
    private static let amount: UInt64 = 1_000_000
    private static let coreFee: UInt64 = 226
    private static let twoStepFee: UInt64 = 4_100

    private let twoStepRoutes: [SendRoute] = [.coreToShielded, .coreToPlatform, .coreToIdentity]

    /// Routes the coordinator's `perform*` calls carry. A Platform-source Identity destination goes through the
    /// identity top-up.
    private let shieldedCoordinatorRoutes: [SendRoute] = [
        .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity
    ]
    private let platformCoordinatorRoutes: [SendRoute] = [.platformToCore, .platformToShielded, .platformToPlatform]
    private let identityTopUpRoutes: [SendRoute] = [.platformToIdentity]
    private var coordinatorRoutes: [SendRoute] { shieldedCoordinatorRoutes + platformCoordinatorRoutes }
    private var creditRoutes: [SendRoute] { coordinatorRoutes + identityTopUpRoutes }
    private let identityRoutes: [SendRoute] = [.identityToCore, .identityToPlatform, .identityToIdentity]

    /// Identity amounts, fees and balances are credits (`AmountRules`). 2,000,000,000 credits is 2,000,000 duffs.
    private static let identityAmount: UInt64 = 2_000_000_000
    private static let identityFee: UInt64 = 400_000_000
    private static let identityBalance: UInt64 = 5_000_000_000

    // MARK: - Scripted edges

    private func walletSendError(_ code: Int) -> NSError {
        NSError(domain: Self.walletSendDomain, code: code)
    }

    private let cancelledCode = 1
    private let failedCode = 2
    private let offlineCode = 8
    private let rejectedCode = 9
    private let unknownCode = 10

    /// Stands for `WalletSendService.prepareStandardSendForConfirmation`, which authenticates first and then builds
    /// and signs without broadcasting (WalletSendService.swift:339-343). It hands out the real `PreparedStandardSend`
    /// whose broadcast is the scripted network edge.
    private final class FakeStandardSend: CoreStandardSending {
        var prepareError: Error?
        var broadcastOutcome: CoreTransactionBroadcastOutcome = .accepted(txid: String(repeating: "a1", count: 32))
        var fee = ExternalSendExecutorTests.coreFee
        /// Display order, as `PreparedStandardSend.txHash` holds it.
        var txHash = Data(repeating: 0xa1, count: 32)
        private(set) var prepareCalls: [(address: String, amount: UInt64)] = []
        private(set) var broadcasts = 0
        private(set) weak var lastPrepared: PreparedStandardSend?

        func prepareStandardSend(address: String, amount: UInt64) async throws -> PreparedStandardSend {
            prepareCalls.append((address, amount))
            if let prepareError { throw prepareError }
            let prepared = PreparedStandardSend(
                txData: Data([0x01]),
                txHash: txHash,
                fee: fee,
                address: address,
                amount: amount,
                ensureOnlineAction: {},
                broadcastAction: { [unowned self] in
                    broadcasts += 1
                    return broadcastOutcome
                })
            lastPrepared = prepared
            return prepared
        }
    }

    /// Stands for the asset-lock calls of `ShieldedTransferCoordinator` (`performAssetLock`, `performFundPlatform`)
    /// and the identity top-up (`ManagedPlatformWallet.topUpIdentityWithFunding`).
    private final class FakeTwoStep: CoreTwoStepSending {
        struct Run {
            let route: SendRoute
            let destination: Destination
            let amount: UInt64
            let fee: UInt64
            let isMax: Bool
        }

        var result: CoreTwoStepResult = .completed
        private(set) var runs: [Run] = []
        private(set) var sawPreauthorized: [Bool] = []

        func run(
            route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64, isMax: Bool
        ) async -> CoreTwoStepResult {
            runs.append(Run(route: route, destination: destination, amount: amount, fee: bindingFeeDuffs, isMax: isMax))
            sawPreauthorized.append(DWIdentityAuthorizer.isPreauthorized)
            return result
        }
    }

    /// Stands for the `ShieldedTransferCoordinator` calls the old Send / InternalTransfer make:
    /// `performShieldedTransfer`
    /// (:1618), `performWithdraw` (:1206), `performUnshield` (:1312), `performPlatformSend` (:1687),
    /// `performPlatformWithdraw` (:1561), `performShield(recipientRaw43:)` (:1109), and `performIdentityTopUpFromPool`
    /// for Shielded to an Identity ID, each read off the coordinator's `phase` / `lastFailure`.
    private final class FakeCreditsSend: ShieldedPlatformSending {
        struct Run {
            let route: SendRoute
            let destination: Destination
            let amount: UInt64
            let fee: UInt64
            /// The identity top-up seam has no Max flag; its runs keep false.
            var isMax = false
            var sweepCredits: UInt64?
        }

        var result: CreditsSendResult = .completed
        /// Awaited inside `run` after the call is recorded, to hold a send in flight.
        var suspension: (() async -> Void)?
        private(set) var runs: [Run] = []
        private(set) var sawPreauthorized: [Bool] = []

        func run(
            route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64, isMax: Bool,
            sweepCredits: UInt64?
        ) async -> CreditsSendResult {
            runs.append(Run(
                route: route, destination: destination, amount: amount, fee: bindingFeeDuffs, isMax: isMax,
                sweepCredits: sweepCredits))
            await suspension?()
            sawPreauthorized.append(DWIdentityAuthorizer.isPreauthorized)
            return result
        }
    }

    /// Stands for the identity top-up from Platform credits (`IdentityCreditsTopUp.fromPlatform`,
    /// `topUpFromAddresses`).
    private final class FakeIdentityTopUp: IdentityTopUpFromCreditsSending {
        var result: CreditsSendResult = .completed
        private(set) var runs: [FakeCreditsSend.Run] = []
        private(set) var sawPreauthorized: [Bool] = []

        func run(
            route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64
        ) async -> CreditsSendResult {
            runs.append(FakeCreditsSend.Run(
                route: route, destination: destination, amount: amount, fee: bindingFeeDuffs))
            sawPreauthorized.append(DWIdentityAuthorizer.isPreauthorized)
            return result
        }
    }

    /// Stands for the existing identity paths: `IdentityWithdrawViewModel.withdraw` (`withdrawCredits`,
    /// ManagedPlatformWallet.swift:3959) for Core, `transferCreditsToAddresses` (:3893) for a Platform address and
    /// `transferCredits` (:3857) for an Identity ID, signed by `KeychainSigner` (IdentityWithdrawViewModel.swift:153).
    private final class FakeIdentityCredits: IdentityCreditsSending {
        struct Run {
            let route: SendRoute
            let destination: Destination
            let amountCredits: UInt64
            let feeCredits: UInt64
            let isMax: Bool
        }

        var result: CreditsSendResult = .completed
        private(set) var runs: [Run] = []
        private(set) var sawPreauthorized: [Bool] = []

        func run(
            route: SendRoute, destination: Destination, amountCredits: UInt64, bindingFeeCredits: UInt64, isMax: Bool
        ) async -> CreditsSendResult {
            runs.append(Run(
                route: route, destination: destination, amountCredits: amountCredits, feeCredits: bindingFeeCredits,
                isMax: isMax))
            sawPreauthorized.append(DWIdentityAuthorizer.isPreauthorized)
            return result
        }
    }

    /// Stands for the BIP70 send of a payment request: authenticate, build and sign without broadcasting (what
    /// `BIP70PaymentService.confirmAndSend` does first, BIP70PaymentService.swift:292-300), then on send POST the
    /// Payment and broadcast (:303-345). `sends` counts that POST + broadcast step; the real service reaches the
    /// network only inside it.
    @MainActor
    private final class FakePaymentRequestSend: CorePaymentRequestSending {
        var prepareError: Error?
        var sendError: Error?
        var callbackURL: URL?
        var fee = ExternalSendExecutorTests.coreFee
        private(set) var prepareCalls: [BIP70ConfirmationBox] = []
        private(set) var sends = 0
        /// How often a prepared send gave its request's single-use claim back.
        private(set) var releases = 0
        private(set) weak var lastPrepared: PreparedPaymentRequestSend?

        func preparePaymentRequestSend(_ request: BIP70ConfirmationBox) async throws -> PreparedPaymentRequestSend {
            prepareCalls.append(request)
            if let prepareError { throw prepareError }
            let txidDisplay = Data(repeating: 0xb2, count: 32)
            let prepared = PreparedPaymentRequestSend(
                txidWire: Data(txidDisplay.reversed()),
                fee: fee,
                sendAction: { [unowned self] in
                    sends += 1
                    if let sendError { throw sendError }
                    return SendResult(
                        txidHexDisplay: String(repeating: "b2", count: 32), txHashDisplay: txidDisplay, fee: fee,
                        amount: request.amount, primaryAddress: ExternalSendExecutorTests.coreAddress,
                        ackMemo: "thanks", callbackURL: callbackURL)
                },
                release: { [unowned self] in releases += 1 })
            lastPrepared = prepared
            return prepared
        }
    }

    private final class FakeFees: SendFeeEstimating {
        var estimate: SendFeeEstimate = .fee(ExternalSendExecutorTests.twoStepFee)
        private(set) var calls: [(route: SendRoute, amount: UInt64)] = []

        func estimate(route: SendRoute, amount: UInt64) async -> SendFeeEstimate {
            calls.append((route, amount))
            return estimate
        }
    }

    private final class FakeBalances: ExternalSendBalanceReading {
        var spendable: UInt64? = 10_000_000
        private(set) var reads: [SendSource] = []

        func spendableBalance(of source: SendSource) async -> UInt64? {
            reads.append(source)
            return spendable
        }
    }

    /// The drain preview: by default the drain would pay exactly the default amount out of 10,000,000 duffs.
    private final class FakeDrainPreview: CoreDrainPreviewing {
        var preview: CoreDrainPreview? = CoreDrainPreview(
            candidateDuffs: 10_000_000, recipientDuffs: ExternalSendExecutorTests.amount)

        func drainPreview() async -> CoreDrainPreview? { preview }
    }

    /// The Platform funding step: by default it can pay anything.
    private final class FakePlatformSendFunding: PlatformSendFundingChecking {
        var withdrawal: SendFundingCheck = .fundable
        var identity: SendFundingCheck = .fundable
        private(set) var withdrawalAmounts: [UInt64] = []
        private(set) var identityAmounts: [UInt64] = []

        func canWithdrawToCore(amountDuffs: UInt64) async -> SendFundingCheck {
            withdrawalAmounts.append(amountDuffs)
            return withdrawal
        }

        func canFundIdentity(amountDuffs: UInt64) async -> SendFundingCheck {
            identityAmounts.append(amountDuffs)
            return identity
        }
    }

    private final class FakeFundingCandidates: PlatformFundingCandidatesReading {
        var candidates: [PlatformPaymentIdentityFundingPolicy.Candidate]?

        func fundingCandidates() async -> [PlatformPaymentIdentityFundingPolicy.Candidate]? { candidates }
    }

    private final class FakePrompt: SendAuthenticationPrompting {
        var didAuthenticate = false
        var results: [AuthenticationService.AuthOutcome] = []
        private(set) var spendAmounts: [UInt64?] = []

        func authenticate(usingBiometrics: Bool, spendAmount: UInt64?) async -> AuthenticationService.AuthOutcome {
            spendAmounts.append(spendAmount)
            return results.isEmpty ? .authenticated(usedBiometrics: false) : results.removeFirst()
        }
    }

    private let standard = FakeStandardSend()
    private let paymentRequest = FakePaymentRequestSend()
    private let twoStep = FakeTwoStep()
    private let credits = FakeCreditsSend()
    private let identityTopUp = FakeIdentityTopUp()
    private let identityCredits = FakeIdentityCredits()
    private let fees = FakeFees()
    private let balances = FakeBalances()
    private let drainPreview = FakeDrainPreview()
    private let platformFunding = FakePlatformSendFunding()
    private let prompt = FakePrompt()
    private var logged: [SendOutcome] = []
    private var restoreSyncBlocks = false
    private var context = ExternalSendContext(walletId: Data([1]), network: .testnet)

    private func makeExecutor() -> ExternalSendExecutor {
        ExternalSendExecutor(
            standardSend: standard,
            paymentRequestSend: paymentRequest,
            twoStep: twoStep,
            creditsSend: credits,
            identityTopUp: identityTopUp,
            identityCredits: identityCredits,
            fees: fees,
            balances: balances,
            drainPreview: drainPreview,
            platformFunding: platformFunding,
            prompt: prompt,
            isBlockedByInitialRestoreSync: { [unowned self] in restoreSyncBlocks },
            currentContext: { [unowned self] in context },
            logOutcome: { [unowned self] in logged.append($0) })
    }

    private func destination(for route: SendRoute) -> Destination {
        switch route {
        case .coreToShielded, .shieldedToShielded, .platformToShielded:
            return Destination(type: .shieldedAddress, text: "dash1-shielded-recipient")
        case .coreToPlatform, .shieldedToPlatform, .platformToPlatform, .identityToPlatform:
            return Destination(type: .platformAddress, text: "dash1-platform-recipient")
        case .coreToIdentity, .shieldedToIdentity, .platformToIdentity, .identityToIdentity:
            return Destination(type: .identityID, text: "identity-id-recipient")
        default:
            return Destination(type: .coreAddress, text: Self.coreAddress)
        }
    }

    private func prepare(
        _ executor: ExternalSendExecutor, _ route: SendRoute, amount: UInt64 = amount, isMax: Bool = false,
        sweepCredits: UInt64? = nil
    ) async throws -> PreparedExternalSend {
        try await executor.prepare(
            route: route, destination: destination(for: route), amount: amount, isMax: isMax, sweepCredits: sweepCredits)
    }

    private func assertPrepareThrows(
        _ route: SendRoute, _ expected: ExternalSendError, amount: UInt64 = amount,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await prepare(makeExecutor(), route, amount: amount)
            XCTFail("expected \(expected) for \(route)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ExternalSendError, expected, "\(route)", file: file, line: line)
        }
    }

    private func isNotSent(_ outcome: SendOutcome, _ reason: String) -> Bool {
        if case .notSent(let actual) = outcome { return actual.category == reason }
        return false
    }

    private func isInFlight(_ outcome: SendOutcome) -> Bool {
        if case .inFlight = outcome { return true }
        return false
    }

    private func isSent(_ outcome: SendOutcome) -> Bool {
        if case .sent = outcome { return true }
        return false
    }

    // MARK: - Core to Core: prepare (AC-01)

    func testCoreToCorePreparesTheExactSendWithItsBindingFeeAndDoesNotBroadcast() async throws {
        let prepared = try await prepare(makeExecutor(), .coreToCore)

        XCTAssertEqual(standard.prepareCalls.count, 1)
        XCTAssertEqual(standard.prepareCalls.first?.address, Self.coreAddress)
        XCTAssertEqual(standard.prepareCalls.first?.amount, Self.amount)
        XCTAssertEqual(prepared.route, .coreToCore)
        XCTAssertEqual(prepared.amount, Self.amount)
        XCTAssertEqual(prepared.fee, Self.coreFee, "Confirm shows the built transaction's fee")
        XCTAssertEqual(standard.broadcasts, 0, "prepare never broadcasts (ADR-0039)")
        XCTAssertTrue(fees.calls.isEmpty, "the Core to Core binding fee is the built transaction's, not a new estimate")
        XCTAssertTrue(twoStep.runs.isEmpty)
        XCTAssertTrue(logged.isEmpty, "preparing is not an outcome")
    }

    func testCoreToCoreAuthenticatesOnlyInsideTheSeam() async throws {
        _ = try await prepare(makeExecutor(), .coreToCore)

        XCTAssertTrue(prompt.spendAmounts.isEmpty,
                      "WalletSendService authenticates before it builds (WalletSendService.swift:339-343)")
    }

    // MARK: - Core to Core: cancel, failure, fee (AC-01b)

    func testCoreToCoreAuthenticationCancelledPreparesNothing() async {
        standard.prepareError = walletSendError(cancelledCode)

        await assertPrepareThrows(.coreToCore, .authenticationCancelled)
        XCTAssertEqual(standard.broadcasts, 0)
        XCTAssertNil(standard.lastPrepared)
        XCTAssertTrue(logged.isEmpty, "a cancel is not an outcome; it returns to Send")
    }

    func testCoreToCoreAuthenticationFailedPreparesNothing() async {
        standard.prepareError = walletSendError(failedCode)

        await assertPrepareThrows(.coreToCore, .authenticationFailed)
        XCTAssertNil(standard.lastPrepared)
    }

    func testCoreToCoreBuildFailureBlocksConfirmWithFeeUnavailable() async {
        for code in [offlineCode, 99] {
            standard.prepareError = walletSendError(code)
            await assertPrepareThrows(.coreToCore, .feeUnavailable)
        }
        XCTAssertEqual(standard.broadcasts, 0)
    }

    func testCoreToCoreRetryAfterFeeUnavailablePreparesAgain() async throws {
        let executor = makeExecutor()
        standard.prepareError = walletSendError(offlineCode)
        do {
            _ = try await prepare(executor, .coreToCore)
            XCTFail("expected feeUnavailable")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .feeUnavailable)
        }

        standard.prepareError = nil
        let prepared = try await prepare(executor, .coreToCore)

        XCTAssertEqual(standard.prepareCalls.count, 2, "Try again is a new prepare; the seam authenticates again")
        XCTAssertEqual(prepared.fee, Self.coreFee)
    }

    // MARK: - Core to Core: the binding fee against the balance (ADR-0039)

    func testCoreToCoreBindingFeeNoLongerFittingDiscardsThePreparedSend() async {
        balances.spendable = Self.amount + Self.coreFee - 1

        await assertPrepareThrows(.coreToCore, .balanceNotEnough)

        XCTAssertEqual(balances.reads, [.core])
        XCTAssertEqual(standard.broadcasts, 0)
        XCTAssertNil(standard.lastPrepared, "the prepared send is discarded, releasing its inputs")
    }

    func testCoreToCoreBindingFeeExactlyFittingTheBalancePrepares() async throws {
        balances.spendable = Self.amount + Self.coreFee

        let prepared = try await prepare(makeExecutor(), .coreToCore)

        XCTAssertEqual(prepared.fee, Self.coreFee)
    }

    func testCoreToCoreUnreadableBalanceBlocksConfirmAndReleasesThePreparedSend() async {
        balances.spendable = nil

        await assertPrepareThrows(.coreToCore, .balanceUnavailable)

        XCTAssertEqual(standard.broadcasts, 0)
        XCTAssertNil(standard.lastPrepared, "the prepared send is released")
    }

    // MARK: - Core to Core: send and outcomes (AC-01, AC-19)

    func testCoreToCoreSendBroadcastsOnceOnConfirmAndReportsSent() async throws {
        let executor = makeExecutor()
        let prepared = try await prepare(executor, .coreToCore)
        XCTAssertEqual(standard.broadcasts, 0)

        let outcome = await executor.send(prepared)

        XCTAssertTrue(isSent(outcome), "\(outcome)")
        XCTAssertEqual(standard.broadcasts, 1)
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(isSent(logged[0]))
    }

    func testCoreToCoreRejectedBroadcastIsNotSentRejected() async throws {
        standard.broadcastOutcome = .rejected(txid: "t", reason: "bad-txns")
        let executor = makeExecutor()
        let prepared = try await prepare(executor, .coreToCore)

        let outcome = await executor.send(prepared)

        XCTAssertTrue(isNotSent(outcome, "rejected"), "\(outcome)")
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(isNotSent(logged[0], "rejected"))
    }

    func testCoreToCoreUnknownBroadcastIsInFlightWithoutRetry() async throws {
        standard.broadcastOutcome = .unknown(txid: "t", reason: "no acceptance signal")
        let executor = makeExecutor()
        let prepared = try await prepare(executor, .coreToCore)

        let outcome = await executor.send(prepared)

        XCTAssertTrue(isInFlight(outcome), "\(outcome)")
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(isInFlight(logged[0]))
    }

    func testCoreToCoreDiscardBroadcastsNothingAndDropsThePreparedSend() async throws {
        let executor = makeExecutor()
        let prepared = try await prepare(executor, .coreToCore)

        executor.discard(prepared)

        XCTAssertEqual(standard.broadcasts, 0)
        XCTAssertTrue(logged.isEmpty, "Cancel on Confirm is not an outcome")
    }

    func testSendOnADiscardedCoreSendBroadcastsNothingAndIsNotSentFailed() async throws {
        let executor = makeExecutor()
        let prepared = try await prepare(executor, .coreToCore)
        executor.discard(prepared)

        let outcome = await executor.send(prepared)

        XCTAssertTrue(isNotSent(outcome, "failed"), "\(outcome)")
        XCTAssertEqual(standard.broadcasts, 0)
    }

    func testSendOnADiscardedTwoStepSendRunsNothingAndIsNotSentFailed() async throws {
        let executor = makeExecutor()
        for route in twoStepRoutes {
            let prepared = try await prepare(executor, route)
            executor.discard(prepared)

            let outcome = await executor.send(prepared)

            XCTAssertTrue(isNotSent(outcome, "failed"), "\(route): \(outcome)")
        }
        XCTAssertTrue(twoStep.runs.isEmpty)
    }

    // MARK: - A restored wallet's initial sync (AC-19)

    func testEveryCoreFundedRouteIsRefusedDuringTheInitialRestoreSyncBeforeAuthentication() async {
        restoreSyncBlocks = true
        for route in twoStepRoutes + [.coreToCore] {
            await assertPrepareThrows(route, .initialRestoreSync)
        }
        do {
            _ = try await prepareRequest(makeExecutor())
            XCTFail("a payment request must not prepare during the initial restore sync")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .initialRestoreSync)
        }
        XCTAssertTrue(prompt.spendAmounts.isEmpty, "nothing authenticates")
        XCTAssertTrue(standard.prepareCalls.isEmpty)
        XCTAssertTrue(paymentRequest.prepareCalls.isEmpty)
        XCTAssertTrue(twoStep.runs.isEmpty)
    }

    /// Core → Core reaches the service's own restore-sync backstop when Send had not seen the sync state change; the
    /// refusal is reported as the restore sync, not as a fee that could not be read.
    func testCoreToCoreRefusalByTheServiceDuringTheInitialRestoreSyncIsReportedAsSuch() async {
        standard.prepareError = walletSendError(WalletSendService.ErrorCode.initialRestoreSync.rawValue)

        await assertPrepareThrows(.coreToCore, .initialRestoreSync)
        XCTAssertEqual(standard.broadcasts, 0)
    }

    func testRoutesFromOtherSourcesIgnoreTheInitialRestoreSync() async throws {
        restoreSyncBlocks = true
        _ = try await prepare(makeExecutor(), .platformToCore)
    }

    // MARK: - Core asset-lock routes: what the coordinator's call reports (AC-19)

    func testACompletedCoordinatorCallIsCompleted() {
        guard case .completed = LiveCoreTwoStepSend.result(phase: .success, lastFailure: nil, heldLock: nil) else {
            return XCTFail("expected completed")
        }
    }

    func testAnUnconfirmedCoordinatorCallIsUnconfirmed() {
        let result = LiveCoreTwoStepSend.result(
            phase: .submittedUnconfirmed, lastFailure: nil, heldLock: Self.heldLock)
        guard case .unconfirmed = result else { return XCTFail("expected unconfirmed, got \(result)") }
    }

    private static let heldLock = HeldAssetLock(fundingTypeRaw: 4, txidWire: Data(repeating: 0xAB, count: 32), vout: 1)

    /// A lock the coordinator keeps after the failure holds the money: the send reports that lock.
    func testAFailureThatKeptTheBuiltLockReportsTheLock() {
        let failure = PlatformWalletError.transactionBroadcastUnconfirmed("unconfirmed")
        let result = LiveCoreTwoStepSend.result(phase: .failed("x"), lastFailure: failure, heldLock: Self.heldLock)
        guard case .lockHeld(let lock) = result else { return XCTFail("expected lockHeld, got \(result)") }
        XCTAssertEqual(lock, Self.heldLock)
    }

    /// A definite broadcast rejection removes the lock again (`keepsLockForRetry`), so the coordinator records no
    /// lock: the money is still in Core and Send fails with Retry instead of reporting a payment in progress.
    func testARejectedLockIsNotReportedAndTheSendIsNotSent() {
        let rejected = PlatformWalletError.transactionBroadcastRejected("rejected")
        XCTAssertFalse(ShieldedTransferCoordinator.keepsLockForRetry(after: rejected))
        let result = LiveCoreTwoStepSend.result(
            phase: .failed("x"), lastFailure: ShieldedTransferCoordinator.CoordinatorError.transferFailed(rejected),
            heldLock: nil)
        guard case .failed(let error, let recorded) = result else { return XCTFail("expected failed, got \(result)") }
        XCTAssertFalse(recorded)
        guard case .notSent(.rejected) = SendOutcome(error: error) else {
            return XCTFail("expected notSent(rejected), got \(SendOutcome(error: error))")
        }
    }

    func testAFailureWithoutAnErrorIsStillAFailure() {
        let result = LiveCoreTwoStepSend.result(phase: .idle, lastFailure: nil, heldLock: nil)
        guard case .failed(_, let recorded) = result else { return XCTFail("expected failed, got \(result)") }
        XCTAssertFalse(recorded)
    }

    // MARK: - Core to Core: a dash: payment request (AC-15)

    private static let requestURL = URL(fileURLWithPath: "/pay/1")

    private let verifiedRequest = BIP70ConfirmationBox.fixture(address: coreAddress, amount: amount)

    private var requestDestination: Destination {
        Destination(type: .coreAddress, text: Self.coreAddress, paymentRequestURL: Self.requestURL,
                    verifiedRequest: verifiedRequest)
    }

    private func prepareRequest(
        _ executor: ExternalSendExecutor, amount: UInt64 = amount
    ) async throws -> PreparedExternalSend {
        try await executor.prepare(route: .coreToCore, destination: requestDestination, amount: amount, isMax: false, sweepCredits: nil)
    }

    func testPaymentRequestPreparesThroughTheBIP70SeamWithItsBindingFeeAndNeitherPostsNorBroadcasts() async throws {
        let prepared = try await prepareRequest(makeExecutor())

        XCTAssertEqual(paymentRequest.prepareCalls.count, 1)
        XCTAssertIdentical(paymentRequest.prepareCalls.first, verifiedRequest, "the request fetched at open")
        XCTAssertEqual(prepared.route, .coreToCore)
        XCTAssertEqual(prepared.amount, Self.amount)
        XCTAssertEqual(prepared.fee, Self.coreFee, "Confirm shows the built transaction's fee")
        XCTAssertEqual(paymentRequest.sends, 0, "prepare neither POSTs the Payment nor broadcasts (ADR-0039)")
        XCTAssertTrue(standard.prepareCalls.isEmpty, "a payment request never takes the standard send")
        XCTAssertTrue(fees.calls.isEmpty)
        XCTAssertTrue(logged.isEmpty, "preparing is not an outcome")
    }

    func testPaymentRequestWithAnAmountOtherThanTheRequestsIsRefusedBeforeAnythingIsBuilt() async throws {
        do {
            _ = try await prepareRequest(makeExecutor(), amount: Self.amount - 1)
            XCTFail("expected feeUnavailable")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .feeUnavailable)
        }
        XCTAssertTrue(paymentRequest.prepareCalls.isEmpty, "nothing is signed for an amount the request does not ask")
        XCTAssertTrue(balances.reads.isEmpty)

        let prepared = try await prepareRequest(makeExecutor(), amount: verifiedRequest.confirmation.amount)
        XCTAssertEqual(prepared.amount, verifiedRequest.confirmation.amount)
    }

    func testPaymentRequestAuthenticatesOnlyInsideTheSeam() async throws {
        _ = try await prepareRequest(makeExecutor())

        XCTAssertTrue(prompt.spendAmounts.isEmpty, "as Core to Core: the seam authenticates before it builds")
    }

    func testPaymentRequestPreparedSendExposesItsTxidWire() async throws {
        let prepared = try await prepareRequest(makeExecutor())

        XCTAssertEqual(prepared.txidWire, Data(repeating: 0xb2, count: 32))
    }

    func testPaymentRequestAuthenticationCancelledOrFailedPreparesNothing() async throws {
        let executor = makeExecutor()
        for (code, expected) in [(cancelledCode, ExternalSendError.authenticationCancelled),
                                 (failedCode, .authenticationFailed)] {
            paymentRequest.prepareError = walletSendError(code)
            do {
                _ = try await prepareRequest(executor)
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? ExternalSendError, expected)
            }
        }
        XCTAssertEqual(paymentRequest.sends, 0)
        XCTAssertNil(paymentRequest.lastPrepared)
        XCTAssertTrue(logged.isEmpty, "a cancel is not an outcome; it returns to Send")
    }

    func testPaymentRequestFetchOrBuildFailureBlocksConfirmWithFeeUnavailable() async throws {
        let executor = makeExecutor()
        for error in [walletSendError(offlineCode), BIP70Error.expired as Error] {
            paymentRequest.prepareError = error
            do {
                _ = try await prepareRequest(executor)
                XCTFail("expected feeUnavailable for \(error)")
            } catch {
                XCTAssertEqual(error as? ExternalSendError, .feeUnavailable)
            }
        }
        XCTAssertEqual(paymentRequest.sends, 0)
    }

    func testPaymentRequestBindingFeeNoLongerFittingDiscardsThePreparedSend() async {
        balances.spendable = Self.amount + Self.coreFee - 1
        do {
            _ = try await prepareRequest(makeExecutor())
            XCTFail("expected balanceNotEnough")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .balanceNotEnough)
        }

        XCTAssertEqual(balances.reads, [.core])
        XCTAssertEqual(paymentRequest.sends, 0)
        XCTAssertNil(paymentRequest.lastPrepared, "the prepared send is discarded, releasing its inputs")
    }

    func testPaymentRequestSendPostsAndBroadcastsOnceThroughTheSeamAndReportsSent() async throws {
        let executor = makeExecutor()
        let prepared = try await prepareRequest(executor)
        XCTAssertEqual(paymentRequest.sends, 0)

        let outcome = await executor.send(prepared)

        XCTAssertTrue(isSent(outcome), "\(outcome)")
        XCTAssertEqual(paymentRequest.sends, 1)
        XCTAssertEqual(standard.broadcasts, 0)
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(isSent(logged[0]))
    }

    func testPaymentRequestSendTwiceRunsTheSeamOnce() async throws {
        let executor = makeExecutor()
        let prepared = try await prepareRequest(executor)
        _ = await executor.send(prepared)

        let outcome = await executor.send(prepared)

        XCTAssertTrue(isInFlight(outcome), "\(outcome)")
        XCTAssertEqual(paymentRequest.sends, 1)
    }

    /// The BIP70 send POSTs the Payment before it broadcasts (BIP70PaymentService.swift:303-327), so a POST or ack
    /// failure leaves the signed bytes with the merchant, who may broadcast them itself: not provably unsent. A
    /// retry would rebuild a conflicting spend, so it is `inFlight`, never `notSent`.
    func testPaymentRequestPostOrAckFailureIsInFlightNeverNotSent() async throws {
        paymentRequest.sendError = BIP70Error.paymentNotAcknowledged(
            txHashDisplay: Data(repeating: 0xb2, count: 32), reason: "timeout")
        let executor = makeExecutor()
        let prepared = try await prepareRequest(executor)

        let outcome = await executor.send(prepared)

        XCTAssertTrue(isInFlight(outcome), "\(outcome)")
        XCTAssertEqual(paymentRequest.sends, 1, "no retry of the POST or the broadcast")
        XCTAssertTrue(logged.last.map(isInFlight) ?? false)
    }

    func testPaymentRequestBroadcastWithoutAcceptanceVerdictIsInFlight() async throws {
        paymentRequest.sendError = BIP70Error.broadcastOutcomeUnknown(
            txHashDisplay: Data(repeating: 0xb2, count: 32), reason: "no acceptance signal")
        let executor = makeExecutor()

        let outcome = await executor.send(try await prepareRequest(executor))

        XCTAssertTrue(isInFlight(outcome), "\(outcome)")
        XCTAssertEqual(paymentRequest.sends, 1)
    }

    func testPaymentRequestRejectedBroadcastIsNotSentRejected() async throws {
        paymentRequest.sendError = SenderError.transactionRejected(txid: "t", reason: "bad-txns")
        let executor = makeExecutor()

        let outcome = await executor.send(try await prepareRequest(executor))

        XCTAssertTrue(isNotSent(outcome, "rejected"), "\(outcome)")
        XCTAssertTrue(logged.last.map { isNotSent($0, "rejected") } ?? false)
    }

    func testPaymentRequestUnprovenFailureIsInFlight() async throws {
        paymentRequest.sendError = NSError(domain: "unmapped", code: 1)
        let executor = makeExecutor()

        let outcome = await executor.send(try await prepareRequest(executor))

        XCTAssertTrue(isInFlight(outcome), "any doubt is inFlight (ADR-0040): \(outcome)")
    }

    func testPaymentRequestSendExposesTheMerchantCallbackURLOnlyAfterItSucceeded() async throws {
        let callback = URL(fileURLWithPath: "/callback/paid")
        paymentRequest.callbackURL = callback
        let executor = makeExecutor()
        let prepared = try await prepareRequest(executor)
        XCTAssertNil(prepared.callbackURL, "nothing to open before send")

        _ = await executor.send(prepared)

        XCTAssertEqual(prepared.callbackURL, callback, "the flow opens it as the current Send does")
    }

    func testPaymentRequestWithoutCallbackOrAFailedSendHasNoCallbackURL() async throws {
        let executor = makeExecutor()
        let plain = try await prepareRequest(executor)
        _ = await executor.send(plain)
        XCTAssertNil(plain.callbackURL, "the merchant gave none")

        paymentRequest.callbackURL = URL(fileURLWithPath: "/callback/paid")
        paymentRequest.sendError = BIP70Error.broadcastOutcomeUnknown(
            txHashDisplay: Data(repeating: 0xb2, count: 32), reason: "no acceptance signal")
        let failed = try await prepareRequest(executor)
        _ = await executor.send(failed)
        XCTAssertNil(failed.callbackURL, "only a sent payment opens the callback")
    }

    func testOtherRoutesNeverHaveACallbackURL() async throws {
        let executor = makeExecutor()
        for route in [SendRoute.coreToCore] + twoStepRoutes {
            let prepared = try await prepare(executor, route)
            _ = await executor.send(prepared)
            XCTAssertNil(prepared.callbackURL, "\(route)")
        }
    }

    /// A plain dash: link another app opened: the sender hears back once the transaction was broadcast, as the
    /// current Send does after `sendCompletedToAddress`.
    func testStandardSendOfALinkAnotherAppOpenedExposesThePayAckOnlyAfterItWasSent() async throws {
        standard.txHash = Data([0xd7] + [UInt8](repeating: 0x5d, count: 31))
        let executor = makeExecutor()
        let prepared = try await executor.prepare(
            route: .coreToCore,
            destination: Destination(type: .coreAddress, text: Self.coreAddress, callbackScheme: "app"),
            amount: Self.amount, isMax: false, sweepCredits: nil)
        XCTAssertNil(prepared.callbackURL, "nothing to open before send")

        _ = await executor.send(prepared)

        XCTAssertEqual(
            prepared.callbackURL?.absoluteString,
            "app://callback=payack&address=\(Self.coreAddress)"
                + "&txid=d7" + String(repeating: "5d", count: 31))
    }

    private func prepareLinkAnotherAppOpened(
        _ executor: ExternalSendExecutor, _ route: SendRoute, amount: UInt64 = amount
    ) async throws -> PreparedExternalSend {
        let plain = destination(for: route)
        return try await executor.prepare(
            route: route, destination: Destination(type: plain.type, text: plain.text, callbackScheme: "app"),
            amount: amount, isMax: false, sweepCredits: nil)
    }

    /// The pay-ack carries a Core txid and a Platform or Shielded send names none, so a sent one opens nothing.
    func testRoutedSendOfALinkAnotherAppOpenedHasNoCallbackURLEvenAfterItWasSent() async throws {
        let executor = makeExecutor()
        for route in twoStepRoutes + creditRoutes {
            let prepared = try await prepareLinkAnotherAppOpened(executor, route)

            let outcome = await executor.send(prepared)

            XCTAssertTrue(isSent(outcome), "\(route)")
            XCTAssertNil(prepared.callbackURL, "\(route)")
        }
    }

    func testIdentitySendOfALinkAnotherAppOpenedHasNoCallbackURLEvenAfterItWasSent() async throws {
        scriptIdentity()
        let executor = makeExecutor()
        for route in identityRoutes {
            let prepared = try await prepareLinkAnotherAppOpened(executor, route, amount: Self.identityAmount)

            let outcome = await executor.send(prepared)

            XCTAssertTrue(isSent(outcome), "\(route)")
            XCTAssertNil(prepared.callbackURL, "\(route)")
        }
    }

    func testRoutedSendThatWasNotSentHasNoCallbackURL() async throws {
        let executor = makeExecutor()
        let twoStepResults: [CoreTwoStepResult] = [
            .unconfirmed, .failed(CoordinatorError.noWallet, assetLockRecorded: false),
        ]
        for result in twoStepResults {
            twoStep.result = result
            for route in twoStepRoutes {
                let prepared = try await prepareLinkAnotherAppOpened(executor, route)
                _ = await executor.send(prepared)
                XCTAssertNil(prepared.callbackURL, "only a sent payment opens the callback: \(route) \(result)")
            }
        }
        for result in [CreditsSendResult.unconfirmed, .notStarted] {
            credits.result = result
            identityTopUp.result = result
            for route in creditRoutes {
                let prepared = try await prepareLinkAnotherAppOpened(executor, route)
                _ = await executor.send(prepared)
                XCTAssertNil(prepared.callbackURL, "only a sent payment opens the callback: \(route) \(result)")
            }
        }
    }

    func testStandardSendWithoutASchemeHasNoCallbackURL() async throws {
        let executor = makeExecutor()
        let prepared = try await executor.prepare(
            route: .coreToCore, destination: Destination(type: .coreAddress, text: Self.coreAddress),
            amount: Self.amount, isMax: false, sweepCredits: nil)

        _ = await executor.send(prepared)

        XCTAssertNil(prepared.callbackURL, "a scanned, pasted or typed address has no sender")
    }

    func testStandardSendThatWasNotSentHasNoCallbackURL() async throws {
        let executor = makeExecutor()
        let outcomes: [CoreTransactionBroadcastOutcome] = [
            .rejected(txid: "t", reason: "bad-txns"), .unknown(txid: "t", reason: "no acceptance signal"),
        ]
        for outcome in outcomes {
            standard.broadcastOutcome = outcome
            let prepared = try await executor.prepare(
                route: .coreToCore,
                destination: Destination(type: .coreAddress, text: Self.coreAddress, callbackScheme: "app"),
                amount: Self.amount, isMax: false, sweepCredits: nil)

            _ = await executor.send(prepared)

            XCTAssertNil(prepared.callbackURL, "only a sent payment opens the callback: \(outcome)")
        }
    }

    func testPaymentRequestDiscardPostsAndBroadcastsNothing() async throws {
        let executor = makeExecutor()
        let prepared = try await prepareRequest(executor)

        executor.discard(prepared)
        let outcome = await executor.send(prepared)

        XCTAssertEqual(paymentRequest.sends, 0)
        XCTAssertTrue(isNotSent(outcome, "failed"), "\(outcome)")
        XCTAssertEqual(logged.count, 1, "Cancel is no outcome; only the later send logs")
    }

    /// The request is carried from open to Confirm, so an unsent prepared send gives its single-use claim back for
    /// the next Continue; a send that ran keeps it.
    func testPaymentRequestDiscardReleasesTheRequestOnlyWhileUnsent() async throws {
        let executor = makeExecutor()
        let discarded = try await prepareRequest(executor)

        executor.discard(discarded)
        executor.discard(discarded)
        XCTAssertEqual(paymentRequest.releases, 1, "released once")

        let sent = try await prepareRequest(executor)
        _ = await executor.send(sent)
        executor.discard(sent)
        XCTAssertEqual(paymentRequest.releases, 1, "a send that ran keeps its claim")
    }

    func testPaymentRequestBindingFeeNoLongerFittingReleasesTheRequest() async {
        balances.spendable = Self.amount + Self.coreFee - 1

        _ = try? await prepareRequest(makeExecutor())

        XCTAssertEqual(paymentRequest.releases, 1)
    }

    func testPlainCoreDestinationStillUsesTheStandardSeam() async throws {
        let executor = makeExecutor()
        let prepared = try await prepare(executor, .coreToCore)
        _ = await executor.send(prepared)

        XCTAssertEqual(standard.prepareCalls.count, 1)
        XCTAssertEqual(standard.broadcasts, 1)
        XCTAssertTrue(paymentRequest.prepareCalls.isEmpty)
        XCTAssertEqual(paymentRequest.sends, 0)
    }

    // MARK: - Two-step routes: authenticate on Continue

    func testTwoStepAuthenticationCancelledPreparesNothing() async {
        for route in twoStepRoutes {
            prompt.results = [.cancelled]
            await assertPrepareThrows(route, .authenticationCancelled)
        }
        XCTAssertEqual(prompt.spendAmounts.count, twoStepRoutes.count)
        XCTAssertTrue(fees.calls.isEmpty, "nothing is prepared before the user authenticates")
        XCTAssertTrue(twoStep.runs.isEmpty)
        XCTAssertTrue(logged.isEmpty)
    }

    func testTwoStepAuthenticationFailedPreparesNothing() async {
        for route in twoStepRoutes {
            prompt.results = [.failed]
            await assertPrepareThrows(route, .authenticationFailed)
        }
        XCTAssertTrue(fees.calls.isEmpty)
        XCTAssertTrue(twoStep.runs.isEmpty)
    }

    func testTwoStepAuthenticatesTheAmountThroughTheGate() async throws {
        let executor = makeExecutor()
        for route in twoStepRoutes {
            _ = try await prepare(executor, route)
        }

        XCTAssertEqual(prompt.spendAmounts, twoStepRoutes.map { _ in Self.amount })
    }

    func testTwoStepSendsNothingToTheStandardSeam() async throws {
        let executor = makeExecutor()
        for route in twoStepRoutes {
            let prepared = try await prepare(executor, route)
            _ = await executor.send(prepared)
        }

        XCTAssertTrue(standard.prepareCalls.isEmpty, "only Core to Core uses the standard send")
    }

    // MARK: - Two-step routes: prepare

    func testTwoStepPrepareRecomputesTheBindingFeeAndStartsNoAssetLock() async throws {
        let executor = makeExecutor()
        for route in twoStepRoutes {
            fees.estimate = .fee(Self.twoStepFee + UInt64(fees.calls.count))
            let prepared = try await prepare(executor, route)

            XCTAssertEqual(prepared.route, route)
            XCTAssertEqual(prepared.amount, Self.amount)
            XCTAssertEqual(prepared.fee, Self.twoStepFee + UInt64(fees.calls.count - 1), "\(route)")
        }
        XCTAssertEqual(fees.calls.map(\.route), twoStepRoutes)
        XCTAssertEqual(fees.calls.map(\.amount), twoStepRoutes.map { _ in Self.amount })
        XCTAssertTrue(twoStep.runs.isEmpty, "prepare never starts an asset lock")
        XCTAssertTrue(logged.isEmpty)
    }

    // MARK: Platform funding step

    func testPlatformToCoreWhereTheSelectedRowCannotWithdrawTheAmountIsBalanceNotEnoughAtPrepare() async {
        balances.spendable = Self.amount * 10
        platformFunding.withdrawal = .notFundable
        await assertPrepareThrows(.platformToCore, .balanceNotEnough)
        XCTAssertEqual(platformFunding.withdrawalAmounts, [Self.amount])
        XCTAssertTrue(credits.runs.isEmpty)
    }

    func testPlatformToCoreWithoutAPreflightIsBalanceUnavailable() async {
        balances.spendable = Self.amount * 10
        platformFunding.withdrawal = .unknown
        await assertPrepareThrows(.platformToCore, .balanceUnavailable)
    }

    func testPlatformToCoreTheRowCanWithdrawPrepares() async throws {
        balances.spendable = Self.amount * 10
        _ = try await prepare(makeExecutor(), .platformToCore)
        XCTAssertEqual(platformFunding.withdrawalAmounts, [Self.amount])
    }

    func testPlatformToCoreMaxSkipsTheRowCheckBecauseTheWithdrawalTakesTheWholeBalance() async throws {
        balances.spendable = Self.amount * 10
        platformFunding.withdrawal = .notFundable
        _ = try await prepare(makeExecutor(), .platformToCore, isMax: true)
        XCTAssertTrue(platformFunding.withdrawalAmounts.isEmpty)
    }

    func testPlatformToIdentityTheTopUpCannotFundTheAmountIsBalanceNotEnoughAtPrepare() async {
        balances.spendable = Self.amount * 10
        platformFunding.identity = .notFundable
        await assertPrepareThrows(.platformToIdentity, .balanceNotEnough)
        XCTAssertEqual(platformFunding.identityAmounts, [Self.amount])
    }

    func testPlatformToIdentityWithoutAddressesIsBalanceUnavailable() async {
        balances.spendable = Self.amount * 10
        platformFunding.identity = .unknown
        await assertPrepareThrows(.platformToIdentity, .balanceUnavailable)
    }

    func testPlatformToIdentityTheTopUpCanFundPrepares() async throws {
        balances.spendable = Self.amount * 10
        _ = try await prepare(makeExecutor(), .platformToIdentity)
        XCTAssertEqual(platformFunding.identityAmounts, [Self.amount])
    }

    /// The estimate counts 41,500 duffs of fee, the top-up reserves 200,000: a balance between the two passes the
    /// aggregate check and is refused by the top-up's own planning.
    func testPlatformToIdentityBalanceBetweenTheEstimateAndTheHeadroomIsRefusedAtPrepare() async throws {
        let amount: UInt64 = 1_000_000
        fees.estimate = .fee(41_500)
        let candidates = FakeFundingCandidates()
        let funding = LivePlatformSendFunding(fundingCandidates: candidates, withdrawalCapacity: { nil })
        let executor = ExternalSendExecutor(
            standardSend: standard, paymentRequestSend: paymentRequest, twoStep: twoStep, creditsSend: credits,
            identityTopUp: identityTopUp, identityCredits: identityCredits, fees: fees, balances: balances,
            drainPreview: drainPreview, platformFunding: funding, prompt: prompt,
            logOutcome: { [unowned self] in logged.append($0) })
        func row(_ duffs: UInt64) -> [PlatformPaymentIdentityFundingPolicy.Candidate] {
            [.init(addressType: 0, hash: Data(repeating: 1, count: 20), balance: duffs * 1000)]
        }

        balances.spendable = amount + 100_000
        candidates.candidates = row(amount + 100_000)
        do {
            _ = try await prepare(executor, .platformToIdentity, amount: amount)
            XCTFail("expected balanceNotEnough")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .balanceNotEnough)
        }

        balances.spendable = amount + 200_000
        candidates.candidates = row(amount + 200_000)
        _ = try await prepare(executor, .platformToIdentity, amount: amount)
    }

    /// Two rows together cover the amount, but the withdrawal spends only the highest one.
    func testPlatformToCoreAggregateEnoughButTheSelectedRowIsNotIsRefusedAtPrepare() async throws {
        let amount: UInt64 = 1_000_000
        fees.estimate = .fee(41_500)
        balances.spendable = amount + 100_000
        var capacity: PlatformWithdrawalCapacity? = PlatformWithdrawalCapacity(
            canWithdraw: true, netWithdrawableCredits: (amount - 1) * 1000)
        let funding = LivePlatformSendFunding(
            fundingCandidates: FakeFundingCandidates(), withdrawalCapacity: { capacity })
        let executor = ExternalSendExecutor(
            standardSend: standard, paymentRequestSend: paymentRequest, twoStep: twoStep, creditsSend: credits,
            identityTopUp: identityTopUp, identityCredits: identityCredits, fees: fees, balances: balances,
            drainPreview: drainPreview, platformFunding: funding, prompt: prompt,
            logOutcome: { [unowned self] in logged.append($0) })

        do {
            _ = try await prepare(executor, .platformToCore, amount: amount)
            XCTFail("expected balanceNotEnough")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .balanceNotEnough)
        }

        capacity = PlatformWithdrawalCapacity(canWithdraw: false, netWithdrawableCredits: 0)
        do {
            _ = try await prepare(executor, .platformToCore, amount: amount)
            XCTFail("expected balanceNotEnough")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .balanceNotEnough)
        }

        capacity = PlatformWithdrawalCapacity(canWithdraw: true, netWithdrawableCredits: amount * 1000)
        _ = try await prepare(executor, .platformToCore, amount: amount)

        capacity = nil
        do {
            _ = try await prepare(executor, .platformToCore, amount: amount)
            XCTFail("expected balanceUnavailable")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .balanceUnavailable)
        }
    }

    func testTwoStepFeeUnavailableBlocksConfirm() async {
        fees.estimate = .unavailable
        for route in twoStepRoutes {
            await assertPrepareThrows(route, .feeUnavailable)
        }
        XCTAssertTrue(twoStep.runs.isEmpty)
    }

    func testTwoStepBindingFeeNoLongerFittingIsBalanceNotEnough() async {
        balances.spendable = Self.amount + Self.twoStepFee - 1
        for route in twoStepRoutes {
            await assertPrepareThrows(route, .balanceNotEnough)
        }
        XCTAssertEqual(balances.reads, twoStepRoutes.map { _ in .core })
        XCTAssertTrue(twoStep.runs.isEmpty)
    }

    func testTwoStepBindingFeeExactlyFittingTheBalancePrepares() async throws {
        balances.spendable = Self.amount + Self.twoStepFee
        let executor = makeExecutor()
        for route in twoStepRoutes {
            _ = try await prepare(executor, route)
        }
    }

    /// The binding fee includes the asset lock's L1 miner fee, so amount + Platform fee alone is not enough.
    func testTwoStepAmountPlusPlatformFeeFittingButNotTheL1MinerFeeIsBalanceNotEnough() async {
        let minerFee: UInt64 = 2_250
        fees.estimate = .fee(Self.twoStepFee + minerFee, assetLockMinerFee: minerFee)
        balances.spendable = Self.amount + Self.twoStepFee
        for route in twoStepRoutes {
            await assertPrepareThrows(route, .balanceNotEnough)
        }
        XCTAssertTrue(twoStep.runs.isEmpty)
    }

    /// The seam gets the fee without the L1 miner fee: the Core → Platform lock carries the amount plus that reserve,
    /// and the Core transaction pays its miners on top, never out of the lock.
    func testTwoStepSeamGetsTheBindingFeeWithoutTheAssetLockMinerFee() async throws {
        let minerFee: UInt64 = 2_250
        fees.estimate = .fee(Self.twoStepFee + minerFee, assetLockMinerFee: minerFee)
        let executor = makeExecutor()
        for route in twoStepRoutes {
            let prepared = try await prepare(executor, route)
            XCTAssertEqual(prepared.fee, Self.twoStepFee + minerFee, "Confirm shows the whole fee for \(route)")
            _ = await executor.send(prepared)
        }
        XCTAssertEqual(twoStep.runs.map(\.fee), twoStepRoutes.map { _ in Self.twoStepFee })
    }

    /// Coin selection refuses before any asset lock exists: nothing left the wallet, so the holder can retry.
    func testTwoStepInsufficientFundsBeforeTheLockIsNotSent() async throws {
        let executor = makeExecutor()
        let errors: [Error] = [
            PlatformWalletError.assetLockInsufficientFunds("available 1, required 2"),
            PlatformWalletError.coreInsufficientFunds("short"),
            PlatformWalletError.noSelectableInputs("none"),
            PlatformWalletError.assetLockTooManyInputs("too many")
        ]
        for error in errors {
            twoStep.result = .failed(error, assetLockRecorded: false)
            let outcome = await executor.send(try await prepare(executor, .coreToPlatform))
            XCTAssertTrue(isNotSent(outcome, "failed"), "\(error): \(outcome)")
        }
    }

    /// `topUpIdentityWithFunding` reports no outpoint; a refusal of coin selection still proves no lock was built.
    func testIdentityTopUpFromCoreClassifiesItsFailureByType() {
        let beforeLock: [Error] = [
            PlatformWalletError.assetLockInsufficientFunds("x"), PlatformWalletError.coreInsufficientFunds("x"),
            PlatformWalletError.noSelectableInputs("x"), PlatformWalletError.assetLockTooManyInputs("x"),
            AssetLockInputLimit.TooManyInputsError(
                check: AssetLockInputLimit.Check(amountDuffs: 1, inputBudget: AssetLockInputPolicy.platformInputBudget))
        ]
        for error in beforeLock {
            XCTAssertFalse(LiveCoreTwoStepSend.lockMayExist(after: error), "\(error)")
        }
        let unknown: [Error] = [
            PlatformWalletError.transactionBroadcastRejected("x"), PlatformWalletError.walletOperation("x"),
            NSError(domain: "unmapped", code: 1)
        ]
        for error in unknown {
            XCTAssertTrue(LiveCoreTwoStepSend.lockMayExist(after: error), "doubt is inFlight (ADR-0040): \(error)")
        }
    }

    /// The FFI refuses a Core top-up below its minimum before it builds any lock.
    func testCoreToIdentityBelowTheTopUpMinimumIsNotSentAndNeverReachesTheSeam() async throws {
        let executor = makeExecutor()
        let outcome = await executor.send(try await prepare(executor, .coreToIdentity, amount: 50_499))
        XCTAssertTrue(isNotSent(outcome, "belowMinimum"), "\(outcome)")
        XCTAssertTrue(twoStep.runs.isEmpty, "no asset lock is started")

        _ = await executor.send(try await prepare(executor, .coreToIdentity, amount: 50_500))
        XCTAssertEqual(twoStep.runs.map(\.amount), [50_500], "the minimum itself is sent")
    }

    func testIdentityTopUpFromCoreInvalidParameterIsNotSentNotInFlight() async throws {
        let refusal = PlatformWalletError.invalidParameter(
            "`amount_duffs` is below the minimum top-up asset-lock balance")
        XCTAssertFalse(LiveCoreTwoStepSend.lockMayExist(after: refusal))

        let executor = makeExecutor()
        twoStep.result = LiveCoreTwoStepSend.identityTopUpFailure(after: refusal)
        let outcome = await executor.send(try await prepare(executor, .coreToIdentity))
        XCTAssertTrue(isNotSent(outcome, "belowMinimum"), "\(outcome)")
    }

    func testRetryAfterFeeUnavailableAuthenticatesAgainEvenInAnAuthenticatedSession() async throws {
        let executor = makeExecutor()
        prompt.didAuthenticate = true
        fees.estimate = .unavailable
        do {
            _ = try await prepare(executor, .coreToPlatform)
            XCTFail("expected feeUnavailable")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .feeUnavailable)
        }

        fees.estimate = .fee(Self.twoStepFee)
        _ = try await prepare(executor, .coreToPlatform)

        XCTAssertEqual(prompt.spendAmounts.count, 2, "no session reuse: Try again asks again")
    }

    func testTwoStepUnreadableBalanceBlocksConfirm() async {
        balances.spendable = nil
        for route in twoStepRoutes {
            await assertPrepareThrows(route, .balanceUnavailable)
        }
        XCTAssertTrue(twoStep.runs.isEmpty)
    }

    // MARK: - Two-step routes: send and outcomes (Flow 2, ADR-0040)

    func testTwoStepSendRunsTheFrozenPreparedRouteInsidePreauthorized() async throws {
        let executor = makeExecutor()
        for route in twoStepRoutes {
            let prepared = try await prepare(executor, route)

            _ = await executor.send(prepared)
        }

        XCTAssertEqual(twoStep.runs.map(\.route), twoStepRoutes)
        for (index, route) in twoStepRoutes.enumerated() {
            XCTAssertEqual(twoStep.runs[index].destination, destination(for: route))
            XCTAssertEqual(twoStep.runs[index].amount, Self.amount)
            XCTAssertEqual(twoStep.runs[index].fee, Self.twoStepFee, "the lock carries the fee Confirm showed")
        }
        XCTAssertEqual(twoStep.sawPreauthorized, twoStepRoutes.map { _ in true },
                       "the user authenticated on Continue; the seam must not prompt again")
        XCTAssertEqual(prompt.spendAmounts.count, twoStepRoutes.count, "send does not authenticate")
    }

    func testTwoStepConfirmedIsSent() async throws {
        twoStep.result = .completed
        let executor = makeExecutor()
        for route in twoStepRoutes {
            let outcome = await executor.send(try await prepare(executor, route))
            XCTAssertTrue(isSent(outcome), "\(route): \(outcome)")
        }
        XCTAssertEqual(logged.count, twoStepRoutes.count)
        XCTAssertTrue(logged.allSatisfy(isSent))
    }

    func testTwoStepSecondStepPendingIsInFlight() async throws {
        twoStep.result = .unconfirmed
        let executor = makeExecutor()
        for route in twoStepRoutes {
            let outcome = await executor.send(try await prepare(executor, route))
            XCTAssertTrue(isInFlight(outcome), "\(route): \(outcome)")
        }
        XCTAssertTrue(logged.allSatisfy(isInFlight))
    }

    func testTwoStepFailureAfterTheAssetLockWasRecordedIsInFlightEvenForAPreBroadcastError() async throws {
        twoStep.result = .failed(CoordinatorError.noWallet, assetLockRecorded: true)
        let executor = makeExecutor()
        for route in twoStepRoutes {
            let outcome = await executor.send(try await prepare(executor, route))
            XCTAssertTrue(isInFlight(outcome), "the money left; recovery finishes it. \(route): \(outcome)")
        }
    }

    /// A lock the coordinator recorded is reported with its outpoint, so the user can finish it; nothing else changes.
    func testTwoStepFailureWithAHeldLockIsLockHeldWithThatLock() async throws {
        twoStep.result = .lockHeld(Self.heldLock)
        let executor = makeExecutor()
        for route in [SendRoute.coreToShielded, .coreToPlatform] {
            let outcome = await executor.send(try await prepare(executor, route))
            guard case .lockHeld(let lock) = outcome else { return XCTFail("\(route): \(outcome)") }
            XCTAssertEqual(lock, Self.heldLock, "\(route)")
        }
        XCTAssertEqual(logged.count, 2)
        XCTAssertTrue(logged.allSatisfy { if case .lockHeld = $0 { return true } else { return false } })
    }

    func testTwoStepFailureBeforeBroadcastIsNotSentWithTheMappedReason() async throws {
        let executor = makeExecutor()
        let cases: [(Error, String)] = [
            (CoordinatorError.noWallet, "failed"),
            (CoordinatorError.authCancelled, "failed"),
            (CoordinatorError.transferFailed(SenderError.transactionRejected(txid: "t", reason: "r")), "rejected"),
            (SenderError.walletNotReady("syncing"), "failed")
        ]
        for (error, reason) in cases {
            twoStep.result = .failed(error, assetLockRecorded: false)
            let outcome = await executor.send(try await prepare(executor, .coreToShielded))
            XCTAssertTrue(isNotSent(outcome, reason), "\(error): \(outcome)")
            XCTAssertTrue(logged.last.map { isNotSent($0, reason) } ?? false)
        }
        XCTAssertEqual(logged.count, cases.count)
    }

    func testTwoStepUnprovenFailureIsInFlight() async throws {
        twoStep.result = .failed(NSError(domain: "unmapped", code: 1), assetLockRecorded: false)
        let executor = makeExecutor()

        let outcome = await executor.send(try await prepare(executor, .coreToPlatform))

        XCTAssertTrue(isInFlight(outcome), "any doubt is inFlight (ADR-0040): \(outcome)")
    }

    func testTwoStepDiscardStartsNoAssetLock() async throws {
        let executor = makeExecutor()
        for route in twoStepRoutes {
            executor.discard(try await prepare(executor, route))
        }

        XCTAssertTrue(twoStep.runs.isEmpty)
        XCTAssertTrue(logged.isEmpty)
    }

    // MARK: - Shielded and Platform sources: authenticate on Continue

    private func source(of route: SendRoute) -> SendSource {
        shieldedCoordinatorRoutes.contains(route) ? .shielded : .platform
    }

    func testCreditSourceAuthenticationCancelledPreparesNothing() async {
        for route in creditRoutes {
            prompt.results = [.cancelled]
            await assertPrepareThrows(route, .authenticationCancelled)
        }
        XCTAssertEqual(prompt.spendAmounts.count, creditRoutes.count)
        XCTAssertTrue(fees.calls.isEmpty, "nothing is prepared before the user authenticates")
        XCTAssertTrue(credits.runs.isEmpty)
        XCTAssertTrue(identityTopUp.runs.isEmpty)
        XCTAssertTrue(logged.isEmpty, "a cancel is not an outcome")
    }

    func testCreditSourceAuthenticationFailedPreparesNothing() async {
        for route in creditRoutes {
            prompt.results = [.failed]
            await assertPrepareThrows(route, .authenticationFailed)
        }
        XCTAssertTrue(fees.calls.isEmpty)
        XCTAssertTrue(credits.runs.isEmpty)
        XCTAssertTrue(identityTopUp.runs.isEmpty)
    }

    func testCreditSourceAuthenticatesTheAmountThroughTheGateAndNeverTouchesTheStandardSeam() async throws {
        let executor = makeExecutor()
        for route in creditRoutes {
            _ = try await prepare(executor, route)
        }

        XCTAssertEqual(prompt.spendAmounts, creditRoutes.map { _ in Self.amount })
        XCTAssertTrue(standard.prepareCalls.isEmpty)
        XCTAssertTrue(twoStep.runs.isEmpty)
    }

    // MARK: - Shielded and Platform sources: prepare

    func testCreditSourcePrepareFreezesTheBindingFeeForTheExactAmountAndSpendsNothing() async throws {
        let executor = makeExecutor()
        for route in creditRoutes {
            fees.estimate = .fee(Self.twoStepFee + UInt64(fees.calls.count))
            let prepared = try await prepare(executor, route)

            XCTAssertEqual(prepared.route, route)
            XCTAssertEqual(prepared.amount, Self.amount)
            XCTAssertEqual(prepared.fee, Self.twoStepFee + UInt64(fees.calls.count - 1), "\(route)")
        }
        XCTAssertEqual(fees.calls.map(\.route), creditRoutes)
        XCTAssertEqual(fees.calls.map(\.amount), creditRoutes.map { _ in Self.amount })
        XCTAssertTrue(credits.runs.isEmpty, "prepare never spends")
        XCTAssertTrue(identityTopUp.runs.isEmpty, "prepare never spends")
        XCTAssertTrue(logged.isEmpty)
    }

    func testCreditSourceFeeUnavailableBlocksConfirm() async {
        fees.estimate = .unavailable
        for route in creditRoutes {
            await assertPrepareThrows(route, .feeUnavailable)
        }
        XCTAssertTrue(credits.runs.isEmpty)
    }

    func testCreditSourceBalanceIsReadFromTheRoutesOwnSource() async throws {
        let executor = makeExecutor()
        for route in creditRoutes {
            _ = try await prepare(executor, route)
        }

        XCTAssertEqual(balances.reads, creditRoutes.map(source(of:)),
                       "the re-check counts the Shielded or Platform balance, never Core")
    }

    func testCreditSourceBindingFeeNoLongerFittingIsBalanceNotEnough() async {
        balances.spendable = Self.amount + Self.twoStepFee - 1
        for route in creditRoutes {
            await assertPrepareThrows(route, .balanceNotEnough)
        }
        XCTAssertTrue(credits.runs.isEmpty)
        XCTAssertTrue(identityTopUp.runs.isEmpty)
    }

    func testCreditSourceBindingFeeExactlyFittingTheBalancePrepares() async throws {
        balances.spendable = Self.amount + Self.twoStepFee
        let executor = makeExecutor()
        for route in creditRoutes {
            _ = try await prepare(executor, route)
        }
    }

    func testCreditSourceUnreadableBalanceBlocksConfirm() async {
        balances.spendable = nil
        for route in creditRoutes {
            await assertPrepareThrows(route, .balanceUnavailable)
        }
        XCTAssertTrue(credits.runs.isEmpty)
    }

    func testCreditSourceRetryAfterFeeUnavailableAuthenticatesAgain() async throws {
        let executor = makeExecutor()
        prompt.didAuthenticate = true
        fees.estimate = .unavailable
        do {
            _ = try await prepare(executor, .platformToCore)
            XCTFail("expected feeUnavailable")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .feeUnavailable)
        }

        fees.estimate = .fee(Self.twoStepFee)
        _ = try await prepare(executor, .platformToCore)

        XCTAssertEqual(prompt.spendAmounts.count, 2, "no session reuse: Try again asks again")
    }

    // MARK: - Shielded and Platform sources: send

    func testCoordinatorRoutesSendRunsTheFrozenPreparedRouteInsidePreauthorized() async throws {
        let executor = makeExecutor()
        for route in coordinatorRoutes {
            _ = await executor.send(try await prepare(executor, route))
        }

        XCTAssertEqual(credits.runs.map(\.route), coordinatorRoutes)
        for (index, route) in coordinatorRoutes.enumerated() {
            XCTAssertEqual(credits.runs[index].destination, destination(for: route))
            XCTAssertEqual(credits.runs[index].amount, Self.amount)
            XCTAssertEqual(credits.runs[index].fee, Self.twoStepFee, "the run carries the fee Confirm showed")
        }
        XCTAssertEqual(credits.sawPreauthorized, coordinatorRoutes.map { _ in true },
                       "the user authenticated on Continue; the coordinator must not prompt again")
        XCTAssertTrue(identityTopUp.runs.isEmpty, "only Identity destinations use the identity top-up")
        XCTAssertEqual(prompt.spendAmounts.count, coordinatorRoutes.count, "send does not authenticate")
    }

    func testIdentityDestinationRoutesSendThroughTheIdentityTopUpInsidePreauthorized() async throws {
        let executor = makeExecutor()
        for route in identityTopUpRoutes {
            _ = await executor.send(try await prepare(executor, route))
        }

        XCTAssertEqual(identityTopUp.runs.map(\.route), identityTopUpRoutes)
        for (index, route) in identityTopUpRoutes.enumerated() {
            XCTAssertEqual(identityTopUp.runs[index].destination, destination(for: route))
            XCTAssertEqual(identityTopUp.runs[index].amount, Self.amount)
            XCTAssertEqual(identityTopUp.runs[index].fee, Self.twoStepFee)
        }
        XCTAssertEqual(identityTopUp.sawPreauthorized, identityTopUpRoutes.map { _ in true })
        XCTAssertTrue(credits.runs.isEmpty, "never the coordinator seam")
    }

    func testCreditSourceCompletedIsSentOncePerRoute() async throws {
        let executor = makeExecutor()
        for route in creditRoutes {
            let outcome = await executor.send(try await prepare(executor, route))
            XCTAssertTrue(isSent(outcome), "\(route): \(outcome)")
        }
        XCTAssertEqual(logged.count, creditRoutes.count)
        XCTAssertTrue(logged.allSatisfy(isSent))
    }

    /// Platform's `min_withdrawal_amount` (1000 duffs) applies to the address and the shielded withdrawals as to the
    /// identity one: below it the send is refused before anything is built.
    func testWithdrawalToCoreBelowTheNetworkMinimumIsNotSentBelowMinimum() async throws {
        let minimumDuffs = IdentityWithdrawViewModel.minimumWithdrawalCredits / 1000
        let executor = makeExecutor()
        for route in [SendRoute.platformToCore, .shieldedToCore] {
            for isMax in [false, true] {
                let prepared = try await prepare(executor, route, amount: minimumDuffs - 1, isMax: isMax)
                let outcome = await executor.send(prepared)
                XCTAssertTrue(isNotSent(outcome, "belowMinimum"), "\(route) isMax \(isMax): \(outcome)")
            }
        }
        XCTAssertTrue(credits.runs.isEmpty, "nothing reaches the seam")

        for route in [SendRoute.platformToCore, .shieldedToCore] {
            _ = await executor.send(try await prepare(executor, route, amount: minimumDuffs))
        }
        XCTAssertEqual(credits.runs.map(\.route), [.platformToCore, .shieldedToCore], "the minimum itself is sent")
    }

    func testOtherCreditRoutesHaveNoWithdrawalMinimum() async throws {
        let executor = makeExecutor()
        for route in [SendRoute.shieldedToShielded, .shieldedToPlatform, .platformToShielded, .platformToPlatform] {
            _ = await executor.send(try await prepare(executor, route, amount: 1))
        }
        XCTAssertEqual(credits.runs.count, 4)
    }

    func testCreditSourceFailureBeforeBroadcastIsNotSentWithTheMappedReason() async throws {
        let executor = makeExecutor()
        let cases: [(Error, String)] = [
            (CoordinatorError.shieldedBalanceUnavailable, "failed"),
            (CoordinatorError.authCancelled, "failed"),
            (CoordinatorError.shieldedSweepWaiting(1_000), "earlierPaymentPending"),
            (CoordinatorError.transferFailed(PlatformWalletError.transactionBroadcastRejected("r")), "rejected"),
            (PlatformWalletError.signingKeyUnavailable("k"), "signingKeyUnavailable")
        ]
        for route in creditRoutes {
            let countBefore = logged.count
            for (error, reason) in cases {
                credits.result = .failed(error, handedOver: false)
                identityTopUp.result = .failed(error, handedOver: false)
                let outcome = await executor.send(try await prepare(executor, route))
                XCTAssertTrue(isNotSent(outcome, reason), "\(route) \(error): \(outcome)")
                XCTAssertTrue(logged.last.map { isNotSent($0, reason) } ?? false)
            }
            XCTAssertEqual(logged.count - countBefore, cases.count)
        }
    }

    func testCreditSourceCoordinatorAlreadyRunningIsNotSentFailedBeforeAnythingIsBuilt() async throws {
        credits.result = .notStarted
        identityTopUp.result = .notStarted
        let executor = makeExecutor()
        for route in creditRoutes {
            let outcome = await executor.send(try await prepare(executor, route))
            XCTAssertTrue(isNotSent(outcome, "failed"), "beginTransfer refused: \(route): \(outcome)")
        }
        XCTAssertTrue(logged.allSatisfy { isNotSent($0, "failed") })
    }

    func testCreditSourceShieldedSpendUnconfirmedIsInFlightWithoutRetry() async throws {
        credits.result = .unconfirmed
        identityTopUp.result = .unconfirmed
        let executor = makeExecutor()
        for route in creditRoutes {
            let outcome = await executor.send(try await prepare(executor, route))
            XCTAssertTrue(isInFlight(outcome), "\(route): \(outcome)")
        }
        XCTAssertTrue(logged.allSatisfy(isInFlight))
    }

    func testCreditSourcePlatformRejectionAfterHandoverIsInFlight() async throws {
        let afterHandover = CoordinatorError.transferFailed(PlatformWalletError.shieldedBroadcastFailed("raw"))
        credits.result = .failed(afterHandover, handedOver: false)
        identityTopUp.result = .failed(afterHandover, handedOver: false)
        let executor = makeExecutor()
        for route in creditRoutes {
            let outcome = await executor.send(try await prepare(executor, route))
            XCTAssertTrue(isInFlight(outcome), "a Platform rejection proves nothing: \(route): \(outcome)")
        }
    }

    func testCreditSourceUnprovenFailureIsInFlight() async throws {
        let unmapped = NSError(domain: "unmapped", code: 1)
        credits.result = .failed(unmapped, handedOver: false)
        identityTopUp.result = .failed(unmapped, handedOver: false)
        let executor = makeExecutor()
        for route in creditRoutes {
            let outcome = await executor.send(try await prepare(executor, route))
            XCTAssertTrue(isInFlight(outcome), "any doubt is inFlight (ADR-0040): \(route): \(outcome)")
        }
    }

    /// The top-up from Platform addresses refuses an identity the wallet does not manage before it builds the
    /// transition, so nothing moved: Send failed with the reason, never the "Send in progress" Toast.
    func testPlatformToIdentityRefusedWithIdentityNotFoundIsNotSent() async throws {
        identityTopUp.result = .failed(PlatformWalletError.identityNotFound("raw"), handedOver: false)
        let executor = makeExecutor()
        let outcome = await executor.send(try await prepare(executor, .platformToIdentity))
        XCTAssertTrue(isNotSent(outcome, "identityNotFound"), "\(outcome)")
        XCTAssertTrue(logged.last.map { isNotSent($0, "identityNotFound") } ?? false)
    }

    func testPlatformToIdentityFailureAfterTheMoneyWasHandedOverIsInFlightEvenForAPreBroadcastError() async throws {
        identityTopUp.result = .failed(CoordinatorError.noWallet, handedOver: true)
        let executor = makeExecutor()
        let outcome = await executor.send(try await prepare(executor, .platformToIdentity))
        XCTAssertTrue(isInFlight(outcome), "the credits left the source: \(outcome)")
    }

    /// Shielded to an Identity ID is one top-up from the pool on the Shielded seam, with the entered identity and
    /// the amount, whoever owns the identity; the unshield-then-top-up seam is never used.
    func testShieldedToIdentityRunsTheOneStepTopUpOnceWithTheIdentityAndTheAmount() async throws {
        let executor = makeExecutor()
        let outcome = await executor.send(try await prepare(executor, .shieldedToIdentity))

        XCTAssertTrue(isSent(outcome), "\(outcome)")
        XCTAssertEqual(credits.runs.map(\.route), [.shieldedToIdentity])
        XCTAssertEqual(credits.runs.first?.destination, destination(for: .shieldedToIdentity))
        XCTAssertEqual(credits.runs.first?.amount, Self.amount)
        XCTAssertTrue(identityTopUp.runs.isEmpty, "never the unshield and topUpFromAddresses seam")
    }

    func testShieldedToIdentityUnconfirmedIsInFlightAndARefusalBeforeSubmissionIsNotSent() async throws {
        let executor = makeExecutor()
        credits.result = .unconfirmed
        let unconfirmed = await executor.send(try await prepare(executor, .shieldedToIdentity))
        credits.result = .failed(CoordinatorError.shieldedBalanceUnavailable, handedOver: false)
        let refused = await executor.send(try await prepare(executor, .shieldedToIdentity))

        XCTAssertTrue(isInFlight(unconfirmed), "\(unconfirmed)")
        XCTAssertTrue(isNotSent(refused, "failed"), "\(refused)")
        XCTAssertTrue(identityTopUp.runs.isEmpty)
    }

    func testCreditSourceDiscardSpendsNothingAndSendAfterwardsIsNotSentFailed() async throws {
        let executor = makeExecutor()
        for route in creditRoutes {
            let prepared = try await prepare(executor, route)
            let linesBefore = logged.count
            executor.discard(prepared)
            XCTAssertEqual(logged.count, linesBefore, "Cancel on Confirm is not an outcome: \(route)")

            let outcome = await executor.send(prepared)

            XCTAssertTrue(isNotSent(outcome, "failed"), "\(route): \(outcome)")
            XCTAssertEqual(logged.count, linesBefore + 1, "one outcome line per send: \(route)")
        }
        XCTAssertTrue(credits.runs.isEmpty)
        XCTAssertTrue(identityTopUp.runs.isEmpty)
    }

    // MARK: - Max (isMax carried from prepare to the seams)

    func testPrepareCarriesIsMaxOnThePreparedSend() async throws {
        let executor = makeExecutor()
        for route in [SendRoute.coreToCore] + twoStepRoutes + creditRoutes {
            let plain = try await prepare(executor, route)
            let max = try await prepare(executor, route, isMax: true)

            XCTAssertFalse(plain.isMax, "\(route)")
            XCTAssertTrue(max.isMax, "\(route)")
        }
    }

    func testShieldedAndPlatformCoordinatorRoutesReceiveIsMaxOnSend() async throws {
        let executor = makeExecutor()
        for route in coordinatorRoutes {
            _ = await executor.send(try await prepare(executor, route, isMax: true))
            _ = await executor.send(try await prepare(executor, route))
        }

        // shieldedTo* live: sweepAll true; platformToCore live: fullBalance true.
        XCTAssertEqual(credits.runs.map(\.isMax), coordinatorRoutes.flatMap { _ in [true, false] })
    }

    /// A sweep plan of 6_082_800 + 800 credits is not whole duffs; the coordinator checks the sweep against it, so
    /// the Shielded seam gets those credits as planned. A typed amount carries none.
    func testShieldedMaxHandsThePlansExactCreditsToTheSeam() async throws {
        let planCredits: UInt64 = 6_082_800 + 800
        let executor = makeExecutor()
        for route in shieldedCoordinatorRoutes {
            _ = await executor.send(try await prepare(
                executor, route, amount: planCredits / 1000, isMax: true, sweepCredits: planCredits))
            _ = await executor.send(try await prepare(executor, route))
        }

        XCTAssertEqual(credits.runs.map(\.sweepCredits), shieldedCoordinatorRoutes.flatMap { _ in [planCredits, nil] })
    }

    func testCoreToShieldedReceivesIsMaxForTheWholeWalletDrain() async throws {
        let executor = makeExecutor()
        _ = await executor.send(try await prepare(executor, .coreToShielded, isMax: true))
        _ = await executor.send(try await prepare(executor, .coreToShielded))
        _ = await executor.send(try await prepare(executor, .coreToPlatform, isMax: true))

        XCTAssertEqual(twoStep.runs.map(\.route), [.coreToShielded, .coreToShielded, .coreToPlatform])
        XCTAssertEqual(twoStep.runs.map(\.isMax), [true, false, true], "the seam decides what Max means per route")
    }

    /// Balance 1_234_567_890 credits reads as 1_234_567 duffs; the fee 12_345_678 credits as 12_346 duffs; the
    /// planner's Max is floor((1_234_567_890 - 12_345_678) / 1000) = 1_222_222 duffs. In duffs 1_222_222 + 12_346 >
    /// 1_234_567, though the send fits in credits. Where the seam spends the whole balance itself, Max passes.
    func testMaxWithNonRoundCreditsPassesConfirmWhereTheSeamSpendsTheWholeBalance() async throws {
        balances.spendable = 1_234_567_890 / 1000
        fees.estimate = .fee((12_345_678 + 999) / 1000)
        let max: UInt64 = (1_234_567_890 - 12_345_678) / 1000
        let wholeBalanceRoutes: [SendRoute] = [
            .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity, .platformToCore
        ]
        let executor = makeExecutor()
        for route in wholeBalanceRoutes {
            let prepared = try await prepare(executor, route, amount: max, isMax: true)
            XCTAssertTrue(prepared.isMax, "\(route)")
        }
        for route in wholeBalanceRoutes {
            await assertPrepareThrows(route, .balanceNotEnough, amount: max)
        }
        for route in [SendRoute.platformToPlatform, .platformToShielded] {
            do {
                _ = try await prepare(executor, route, amount: max, isMax: true)
                XCTFail("\(route): the seam sends exactly the amount, so it is still checked")
            } catch {
                XCTAssertEqual(error as? ExternalSendError, .balanceNotEnough, "\(route)")
            }
        }
    }

    /// The Core → Shielded Max is the drain preview's amount: the swept coins − pool fee − the drain's own L1 fee.
    /// The fee Confirm checks carries a pool-sized L1 fee with a margin, larger than the drain's, so amount + fee
    /// exceeds the balance. The drain spends the whole balance itself, so Max passes; a typed amount is still checked.
    func testCoreToShieldedMaxSizedLikeTheDrainPassesDespiteThePoolSizedL1Fee() async throws {
        let spendable: UInt64 = 5_000_000
        let poolSizedL1: UInt64 = 3_000
        let drainL1: UInt64 = 2_000
        balances.spendable = spendable
        fees.estimate = .fee(Self.twoStepFee + poolSizedL1, assetLockMinerFee: poolSizedL1)
        let drainMax = spendable - Self.twoStepFee - drainL1
        drainPreview.preview = CoreDrainPreview(candidateDuffs: spendable, recipientDuffs: drainMax)
        let executor = makeExecutor()

        let prepared = try await prepare(executor, .coreToShielded, amount: drainMax, isMax: true)

        XCTAssertTrue(prepared.isMax)
        XCTAssertEqual(prepared.amount, drainMax)
        await assertPrepareThrows(.coreToShielded, .balanceNotEnough, amount: drainMax)
    }

    /// Confirm shows the fee the drain takes from the coins it sweeps, the preview's candidate balance less the Max.
    /// Unconfirmed coins without an InstantSend lock count in the sendable balance but are not swept, so they are
    /// not shown as fee. A typed amount keeps the estimator's fee.
    func testCoreToShieldedMaxPreparesTheFeeTheDrainTakesFromTheCoinsItSweeps() async throws {
        let candidate: UInt64 = 5_000_000
        let unconfirmed: UInt64 = 700_000
        let poolSizedL1: UInt64 = 3_000
        let drainL1: UInt64 = 2_000
        balances.spendable = candidate + unconfirmed
        let estimated = Self.twoStepFee + poolSizedL1
        fees.estimate = .fee(estimated, assetLockMinerFee: poolSizedL1)
        let drainMax = candidate - Self.twoStepFee - drainL1
        drainPreview.preview = CoreDrainPreview(candidateDuffs: candidate, recipientDuffs: drainMax)
        let executor = makeExecutor()

        let max = try await prepare(executor, .coreToShielded, amount: drainMax, isMax: true)
        XCTAssertEqual(max.fee, candidate - drainMax)
        XCTAssertEqual(max.assetLockMinerFee, poolSizedL1)

        let typed = try await prepare(executor, .coreToShielded, amount: 1_000_000, isMax: false)
        XCTAssertEqual(typed.fee, estimated)
    }

    /// The drain would now pay another amount than the Max (money arrived or left since Send planned it), or
    /// nothing: Send plans Max again instead of Confirm showing the difference as fee.
    func testCoreToShieldedMaxTheDrainNoLongerPaysSendsBackToPlanMaxAgain() async {
        let drainMax: UInt64 = 4_000_000
        let executor = makeExecutor()
        for recipient in [drainMax + 300_000, drainMax - 300_000, nil] as [UInt64?] {
            drainPreview.preview = CoreDrainPreview(candidateDuffs: 5_000_000, recipientDuffs: recipient)
            do {
                _ = try await prepare(executor, .coreToShielded, amount: drainMax, isMax: true)
                XCTFail("recipient \(String(describing: recipient))")
            } catch {
                XCTAssertEqual(error as? ExternalSendError, .balanceNotEnough, "\(String(describing: recipient))")
            }
        }
    }

    func testCoreToShieldedMaxWithAnUnreadableDrainPreviewBlocksConfirm() async {
        drainPreview.preview = nil
        let executor = makeExecutor()
        do {
            _ = try await prepare(executor, .coreToShielded, amount: 4_000_000, isMax: true)
            XCTFail("the fee the drain takes is unknown without its preview")
        } catch {
            XCTAssertEqual(error as? ExternalSendError, .balanceUnavailable)
        }
    }

    func testMaxSendWhoseAmountIsSpendableMinusFeeIsNotRejected() async throws {
        let spendable: UInt64 = 5_000_000
        balances.spendable = spendable
        let max = spendable - Self.twoStepFee
        drainPreview.preview = CoreDrainPreview(candidateDuffs: spendable, recipientDuffs: max)
        let executor = makeExecutor()
        for route in creditRoutes + twoStepRoutes {
            let prepared = try await prepare(executor, route, amount: max, isMax: true)
            XCTAssertEqual(prepared.amount, max, "\(route)")
            XCTAssertTrue(prepared.isMax, "\(route)")
        }
    }

    // MARK: - Identity source

    /// Scripts the identity figures: the binding fee and the identity balance, both in credits.
    private func scriptIdentity(balance: UInt64? = identityBalance, fee: UInt64 = identityFee) {
        balances.spendable = balance
        fees.estimate = .fee(fee)
    }

    func testIdentityAuthenticationCancelledOrFailedPreparesNothing() async {
        scriptIdentity()
        for route in identityRoutes {
            prompt.results = [.cancelled]
            await assertPrepareThrows(route, .authenticationCancelled, amount: Self.identityAmount)
            prompt.results = [.failed]
            await assertPrepareThrows(route, .authenticationFailed, amount: Self.identityAmount)
        }
        XCTAssertEqual(prompt.spendAmounts.count, identityRoutes.count * 2)
        XCTAssertTrue(fees.calls.isEmpty, "nothing is prepared before the user authenticates")
        XCTAssertTrue(balances.reads.isEmpty)
        XCTAssertTrue(identityCredits.runs.isEmpty)
        XCTAssertTrue(logged.isEmpty, "a cancel is not an outcome")
    }

    func testIdentityAuthenticatesTheAmountAtItsDashValueAndUsesNoOtherSeam() async throws {
        scriptIdentity()
        let executor = makeExecutor()
        for route in identityRoutes {
            _ = try await prepare(executor, route, amount: Self.identityAmount)
        }

        let dashValue = AmountRules.dashValue(of: Self.identityAmount)
        XCTAssertEqual(dashValue, 2_000_000)
        XCTAssertEqual(prompt.spendAmounts, identityRoutes.map { _ in dashValue },
                       "credits count at their DASH value for the biometric limit (spec 6.1), not as raw credits")
        XCTAssertTrue(standard.prepareCalls.isEmpty)
        XCTAssertTrue(twoStep.runs.isEmpty)
        XCTAssertTrue(credits.runs.isEmpty)
        XCTAssertTrue(identityTopUp.runs.isEmpty)
    }

    func testIdentityPrepareFreezesTheBindingFeeInCreditsAndSpendsNothing() async throws {
        let executor = makeExecutor()
        for route in identityRoutes {
            scriptIdentity(fee: Self.identityFee + UInt64(fees.calls.count))
            let prepared = try await prepare(executor, route, amount: Self.identityAmount)

            XCTAssertEqual(prepared.route, route)
            XCTAssertEqual(prepared.amount, Self.identityAmount)
            XCTAssertEqual(prepared.fee, Self.identityFee + UInt64(fees.calls.count - 1), "\(route): credits")
        }
        XCTAssertEqual(fees.calls.map(\.route), identityRoutes)
        XCTAssertEqual(fees.calls.map(\.amount), identityRoutes.map { _ in Self.identityAmount })
        XCTAssertTrue(identityCredits.runs.isEmpty, "prepare never spends")
        XCTAssertTrue(logged.isEmpty)
    }

    func testIdentityFeeUnavailableBlocksConfirm() async {
        scriptIdentity()
        fees.estimate = .unavailable
        for route in identityRoutes {
            await assertPrepareThrows(route, .feeUnavailable, amount: Self.identityAmount)
        }
        XCTAssertTrue(identityCredits.runs.isEmpty)
    }

    func testIdentityBalanceIsReadFromTheIdentitySource() async throws {
        scriptIdentity()
        let executor = makeExecutor()
        for route in identityRoutes {
            _ = try await prepare(executor, route, amount: Self.identityAmount)
        }

        XCTAssertEqual(balances.reads, identityRoutes.map { _ in .identity },
                       "the re-check counts the Current identity's credits, never Core or Platform")
    }

    func testIdentityBindingFeeNoLongerFittingTheCreditBalanceIsBalanceNotEnough() async {
        scriptIdentity(balance: Self.identityAmount + Self.identityFee - 1)
        for route in identityRoutes {
            await assertPrepareThrows(route, .balanceNotEnough, amount: Self.identityAmount)
        }
        XCTAssertTrue(identityCredits.runs.isEmpty)
        XCTAssertTrue(logged.isEmpty)
    }

    func testIdentityRecheckCountsCreditsNotDuffs() async {
        // The same figures read as duffs would pass: 2,000,000,000 credits against a 5,000,000 balance does not fit.
        scriptIdentity(balance: 5_000_000)
        for route in identityRoutes {
            await assertPrepareThrows(route, .balanceNotEnough, amount: Self.identityAmount)
        }
    }

    func testIdentityAmountLeavingTheDashPayReserveWarnsButStillPrepares() async throws {
        let reserve = IdentityCreditBalance.lowBalance
        let executor = makeExecutor()
        // Exactly fitting (nothing left) and one credit short of the reserve: both are okWithReserveWarning.
        for balance in [Self.identityAmount + Self.identityFee, Self.identityAmount + Self.identityFee + reserve - 1] {
            scriptIdentity(balance: balance)
            XCTAssertEqual(
                AmountRules.check(
                    amount: Self.identityAmount, source: .identity, balance: balance, fee: Self.identityFee),
                .okWithReserveWarning)
            for route in identityRoutes {
                let prepared = try await prepare(executor, route, amount: Self.identityAmount)
                XCTAssertEqual(prepared.amount, Self.identityAmount, "reserve warning is no blocker: \(route)")
            }
        }
    }

    func testIdentityUnreadableBalanceOrNoCurrentIdentityBlocksConfirmBeforeAnythingIsBuilt() async {
        scriptIdentity(balance: nil)
        for route in identityRoutes {
            await assertPrepareThrows(route, .balanceUnavailable, amount: Self.identityAmount)
        }
        XCTAssertTrue(identityCredits.runs.isEmpty)
        XCTAssertTrue(standard.prepareCalls.isEmpty)
        XCTAssertTrue(logged.isEmpty)
    }

    func testIdentitySendRunsTheFrozenPreparedRouteInsidePreauthorized() async throws {
        scriptIdentity()
        let executor = makeExecutor()
        for route in identityRoutes {
            _ = await executor.send(try await prepare(executor, route, amount: Self.identityAmount))
        }

        XCTAssertEqual(identityCredits.runs.map(\.route), identityRoutes)
        for (index, route) in identityRoutes.enumerated() {
            let run = identityCredits.runs[index]
            XCTAssertEqual(run.destination, destination(for: route))
            XCTAssertEqual(run.amountCredits, Self.identityAmount, "the seam gets credits, as prepared")
            XCTAssertEqual(run.feeCredits, Self.identityFee, "the run carries the fee Confirm showed")
            XCTAssertFalse(run.isMax)
        }
        XCTAssertEqual(identityCredits.sawPreauthorized, identityRoutes.map { _ in true },
                       "the user authenticated on Continue; the identity path must not prompt again")
        XCTAssertEqual(prompt.spendAmounts.count, identityRoutes.count, "send does not authenticate")
        XCTAssertTrue(credits.runs.isEmpty)
        XCTAssertTrue(identityTopUp.runs.isEmpty)
        XCTAssertTrue(twoStep.runs.isEmpty)
    }

    func testIdentityToCoreAcceptsAP2SHPayoutAddress() async throws {
        scriptIdentity()
        let p2sh = Destination(type: .coreAddress, text: "7h9dhRvmgdg3cUng5kAsT3sn8mdd9eYYCz")
        let executor = makeExecutor()
        let prepared = try await executor.prepare(
            route: .identityToCore, destination: p2sh, amount: Self.identityAmount, isMax: false, sweepCredits: nil)

        let outcome = await executor.send(prepared)

        XCTAssertTrue(isSent(outcome), "\(outcome)")
        XCTAssertEqual(identityCredits.runs.first?.destination, p2sh, "Platform accepts P2SH output scripts")
    }

    func testIdentityCompletedIsSentOncePerRoute() async throws {
        scriptIdentity()
        let executor = makeExecutor()
        for route in identityRoutes {
            let before = logged.count
            let outcome = await executor.send(try await prepare(executor, route, amount: Self.identityAmount))
            XCTAssertTrue(isSent(outcome), "\(route): \(outcome)")
            XCTAssertEqual(logged.count - before, 1, "one outcome line per send: \(route)")
            XCTAssertTrue(logged.last.map(isSent) ?? false)
        }
    }

    func testIdentityTransitionPendingIsInFlight() async throws {
        scriptIdentity()
        identityCredits.result = .unconfirmed
        let executor = makeExecutor()
        for route in identityRoutes {
            let before = logged.count
            let outcome = await executor.send(try await prepare(executor, route, amount: Self.identityAmount))
            XCTAssertTrue(isInFlight(outcome), "\(route): \(outcome)")
            XCTAssertEqual(logged.count - before, 1)
            XCTAssertTrue(logged.last.map(isInFlight) ?? false)
        }
    }

    func testIdentityFailureBeforeBroadcastIsNotSentWithTheMappedReason() async throws {
        scriptIdentity()
        let executor = makeExecutor()
        let cases: [(Error, String)] = [
            (PlatformWalletError.signingKeyUnavailable("k"), "signingKeyUnavailable"),
            (PlatformWalletError.transactionBroadcastRejected("r"), "rejected"),
            (CoordinatorError.noWallet, "failed")
        ]
        for route in identityRoutes {
            let before = logged.count
            for (error, reason) in cases {
                identityCredits.result = .failed(error, handedOver: false)
                let outcome = await executor.send(try await prepare(executor, route, amount: Self.identityAmount))
                XCTAssertTrue(isNotSent(outcome, reason), "\(route) \(error): \(outcome)")
                XCTAssertTrue(logged.last.map { isNotSent($0, reason) } ?? false)
            }
            XCTAssertEqual(logged.count - before, cases.count)
        }
    }

    func testIdentityRejectionAfterHandoverIsInFlight() async throws {
        scriptIdentity()
        identityCredits.result = .failed(PlatformWalletError.transactionBroadcastRejected("r"), handedOver: true)
        let executor = makeExecutor()
        for route in identityRoutes {
            let outcome = await executor.send(try await prepare(executor, route, amount: Self.identityAmount))
            XCTAssertTrue(isInFlight(outcome), "handed over, a rejection proves nothing: \(route): \(outcome)")
        }
    }

    func testIdentityUnprovenFailureIsInFlight() async throws {
        scriptIdentity()
        identityCredits.result = .failed(NSError(domain: "unmapped", code: 1), handedOver: false)
        let executor = makeExecutor()
        for route in identityRoutes {
            let outcome = await executor.send(try await prepare(executor, route, amount: Self.identityAmount))
            XCTAssertTrue(isInFlight(outcome), "any doubt is inFlight (ADR-0040): \(route): \(outcome)")
        }
    }

    func testIdentityNotStartedIsNotSentFailed() async throws {
        scriptIdentity()
        identityCredits.result = .notStarted
        let executor = makeExecutor()
        for route in identityRoutes {
            let outcome = await executor.send(try await prepare(executor, route, amount: Self.identityAmount))
            XCTAssertTrue(isNotSent(outcome, "failed"), "no Current identity or signer at send: \(route): \(outcome)")
        }
    }

    func testIdentityBelowMinimumAmountRefusalIsNotSentBelowMinimum() async throws {
        scriptIdentity()
        identityCredits.result = .failed(MinimumAmountRefusal(minimumCredits: 1_000_000), handedOver: false)
        let executor = makeExecutor()
        for route in identityRoutes {
            let before = logged.count
            let outcome = await executor.send(try await prepare(executor, route, amount: Self.identityAmount))
            XCTAssertTrue(isNotSent(outcome, "belowMinimum"), "\(route): \(outcome)")
            XCTAssertEqual(logged.count - before, 1)
        }
    }

    func testIdentityDiscardSpendsNothingAndSendAfterwardsIsNotSentFailed() async throws {
        scriptIdentity()
        let executor = makeExecutor()
        for route in identityRoutes {
            let prepared = try await prepare(executor, route, amount: Self.identityAmount)
            let linesBefore = logged.count
            executor.discard(prepared)
            XCTAssertEqual(logged.count, linesBefore, "Cancel on Confirm is not an outcome: \(route)")

            let outcome = await executor.send(prepared)

            XCTAssertTrue(isNotSent(outcome, "failed"), "\(route): \(outcome)")
            XCTAssertEqual(logged.count, linesBefore + 1, "one outcome line per send: \(route)")
        }
        XCTAssertTrue(identityCredits.runs.isEmpty)
    }

    func testIdentityMaxCarriesIsMaxAndTheAmountAboveTheReserveIsNotRejected() async throws {
        scriptIdentity()
        guard case .amount(let max) = AmountRules.identityMax(
            balanceCredits: Self.identityBalance, feeCredits: Self.identityFee)
        else { return XCTFail("identity Max is available") }
        let executor = makeExecutor()
        for route in identityRoutes {
            let plain = try await prepare(executor, route, amount: Self.identityAmount)
            let prepared = try await prepare(executor, route, amount: max, isMax: true)
            XCTAssertFalse(plain.isMax, "\(route)")
            XCTAssertTrue(prepared.isMax, "\(route)")
            XCTAssertEqual(prepared.amount, max, "\(route)")

            _ = await executor.send(plain)
            _ = await executor.send(prepared)
        }

        XCTAssertEqual(identityCredits.runs.map(\.isMax), identityRoutes.flatMap { _ in [false, true] })
        XCTAssertEqual(identityCredits.runs.filter(\.isMax).map(\.amountCredits), identityRoutes.map { _ in max })
    }

    // MARK: - Live adapters through their real code
    //
    // The Live adapters run here as shipped, up to the SDK edge. Building, signing and broadcasting need a funded SDK
    // wallet and the network, which a unit-test host does not have (docs/features/external-send, Test coverage), so
    // these cover the branches that end before the wallet: destination decoding, amount overflow, the withdrawal
    // minimum, and how the executor reports them.

    private func isFailure(_ result: CoreTwoStepResult, matching match: (Error) -> Bool, recorded: Bool) -> Bool {
        guard case let .failed(error, assetLockRecorded) = result else { return false }
        return match(error) && assetLockRecorded == recorded
    }

    private func isNoShieldedAddress(_ error: Error) -> Bool {
        if case .noShieldedAddress? = error as? CoordinatorError { return true }
        return false
    }

    private func isFailure(_ result: CreditsSendResult, matching match: (Error) -> Bool, handedOver: Bool) -> Bool {
        guard case let .failed(error, wasHandedOver) = result else { return false }
        return match(error) && wasHandedOver == handedOver
    }

    func testLiveCoreToShieldedRefusesANonShieldedRecipientBeforeAnyLockAlsoOnMax() async {
        let live = LiveCoreTwoStepSend()
        let notShielded = Destination(type: .shieldedAddress, text: Self.coreAddress)
        for isMax in [false, true] {
            let result = await live.run(
                route: .coreToShielded, destination: notShielded, amount: Self.amount, bindingFeeDuffs: 1,
                isMax: isMax)
            let refused = isFailure(result, matching: isNoShieldedAddress, recorded: false)
            XCTAssertTrue(refused, "isMax \(isMax): \(result)")
        }
    }

    /// The external Core → Platform send counts as a funding call like the Internal Transfer route, taken before the
    /// coordinator reads the wallet, so while a removal reloads the wallet it is refused before anything is built.
    func testLiveCoreToPlatformIsRefusedBeforeAnythingIsBuiltWhileAWalletReloads() async {
        let registry = ShieldedAssetLocksInFlight.shared
        guard registry.beginRemoval() == .admitted else {
            return XCTFail("the shared registry has activity left over")
        }
        let result = await LiveCoreTwoStepSend().run(
            route: .coreToPlatform, destination: destination(for: .coreToPlatform), amount: Self.amount,
            bindingFeeDuffs: Self.twoStepFee, isMax: false)
        registry.endRemoval()

        let refused = isFailure(result, matching: {
            if case .walletReloading? = $0 as? CoordinatorError { return true }
            return false
        }, recorded: false)
        XCTAssertTrue(refused, "\(result)")
        XCTAssertFalse(registry.hasActivity, "a refused send leaves no funding call counted")
    }

    // MARK: - External Core → Platform through the coordinator, up to the Platform funding call (AC-19)
    //
    // The executor, the Live two-step adapter and `ShieldedTransferCoordinator` run as shipped; only the Platform
    // address calls (`CoreToPlatformFunding`, `PlatformAddressSyncCoordinator` in the app), the PIN gate and the host's
    // wallet are replaced.

    private final class FakePlatformFunding: CoreToPlatformFunding {
        enum Call: Equatable {
            case own(recipientAmountDuffs: UInt64, lockValueDuffs: UInt64)
            case external(destination: String, recipientAmountDuffs: UInt64, lockValueDuffs: UInt64)
            case resume
        }

        private(set) var calls: [Call] = []
        /// What the SDK reports to `onAssetLockBuilt` before the call returns or throws `failure`.
        var built: AssetLockBuiltOutPoint?
        var failure: Error?
        var check: @MainActor (Data, UInt32) throws -> Void = { _, _ in }

        func fundFromCore(
            recipientAmountDuffs: UInt64, lockValueDuffs: UInt64, onAssetLockBuilt: AssetLockBuiltHandler?
        ) async throws {
            calls.append(.own(recipientAmountDuffs: recipientAmountDuffs, lockValueDuffs: lockValueDuffs))
            try finish(onAssetLockBuilt)
        }

        func fundExternalFromCore(
            destination: String, recipientAmountDuffs: UInt64, lockValueDuffs: UInt64,
            onAssetLockBuilt: AssetLockBuiltHandler?
        ) async throws {
            calls.append(.external(
                destination: destination, recipientAmountDuffs: recipientAmountDuffs, lockValueDuffs: lockValueDuffs))
            try finish(onAssetLockBuilt)
        }

        func checkFundFromCoreResumable(outPointTxid: Data, outPointVout: UInt32) throws {
            try check(outPointTxid, outPointVout)
        }

        func resumeFundFromCore(outPointTxid: Data, outPointVout: UInt32, recipientAmountDuffs: UInt64) async throws {
            calls.append(.resume)
        }

        private func finish(_ onAssetLockBuilt: AssetLockBuiltHandler?) throws {
            if let built { onAssetLockBuilt?(built) }
            if let failure { throw failure }
        }
    }

    @MainActor
    private final class CountingAuthorizer: TransferAuthorizing {
        private(set) var calls = 0

        func authorize() async throws {
            calls += 1
        }
    }

    private static let fundingWalletId = Data(repeating: 0x77, count: 32)

    private func builtOutPoint() throws -> AssetLockBuiltOutPoint {
        try XCTUnwrap(AssetLockBuiltOutPoint(rawBytes: Data(repeating: 0x5A, count: 32) + Data([2, 0, 0, 0])))
    }

    private func fundingCoordinator(
        _ funding: FakePlatformFunding, _ authorizer: CountingAuthorizer, container: ModelContainer
    ) -> ShieldedTransferCoordinator {
        let environment = ShieldedTransferCoordinator.BasicEnvironment(
            manager: PlatformWalletManager(), walletId: Self.fundingWalletId, network: .testnet,
            modelContainer: container)
        return ShieldedTransferCoordinator(
            platformFunding: funding, authorizer: authorizer, hostEnvironment: { environment })
    }

    private func executorOverTheCoordinator(
        _ funding: FakePlatformFunding, _ authorizer: CountingAuthorizer
    ) throws -> ExternalSendExecutor {
        let container = try DashModelContainer.inMemoryWithoutCloudKit()
        return ExternalSendExecutor(
            standardSend: standard, paymentRequestSend: paymentRequest,
            twoStep: LiveCoreTwoStepSend(makeCoordinator: { [unowned self] in
                fundingCoordinator(funding, authorizer, container: container)
            }),
            creditsSend: credits, identityTopUp: identityTopUp, identityCredits: identityCredits, fees: fees,
            balances: balances, drainPreview: drainPreview, prompt: prompt,
            logOutcome: { [unowned self] in logged.append($0) })
    }

    /// The recipient's address reaches the external funding call with the amount and the confirmed lock value; the
    /// wallet's own top-up never runs. A broadcast the network rejected after the lock was built removes the lock
    /// again, so the send is not sent, with Retry.
    func testExternalCoreToPlatformPaysTheRecipientAndARejectedLockIsNotSent() async throws {
        let funding = FakePlatformFunding()
        funding.built = try builtOutPoint()
        funding.failure = PlatformWalletError.transactionBroadcastRejected("rejected")
        let executor = try executorOverTheCoordinator(funding, CountingAuthorizer())

        let prepared = try await prepare(executor, .coreToPlatform)
        let outcome = await executor.send(prepared)

        XCTAssertEqual(funding.calls, [.external(
            destination: destination(for: .coreToPlatform).text, recipientAmountDuffs: Self.amount,
            lockValueDuffs: prepared.amount + prepared.fee - prepared.assetLockMinerFee)])
        XCTAssertTrue(isNotSent(outcome, "rejected"), "\(outcome)")
        XCTAssertFalse(ShieldedAssetLocksInFlight.shared.hasActivity, "the attempt released its claim and call")
    }

    /// A failure after the lock was built, other than a rejection, leaves the lock on chain: the coordinator keeps it
    /// and the send reports that lock as held, with the outpoint and funding type the resume needs, never not sent.
    func testExternalCoreToPlatformThatKeptItsLockIsLockHeld() async throws {
        let funding = FakePlatformFunding()
        let built = try builtOutPoint()
        funding.built = built
        funding.failure = PlatformWalletError.signingKeyUnavailable("funding transition")
        let executor = try executorOverTheCoordinator(funding, CountingAuthorizer())

        let outcome = await executor.send(try await prepare(executor, .coreToPlatform))

        XCTAssertEqual(funding.calls.count, 1)
        guard case .lockHeld(let lock) = outcome else { return XCTFail("expected lockHeld, got \(outcome)") }
        XCTAssertEqual(lock, HeldAssetLock(fundingTypeRaw: 4, txidWire: built.txid, vout: built.vout))
        XCTAssertFalse(ShieldedAssetLocksInFlight.shared.hasActivity, "the attempt released its claim and call")
    }

    /// A resume of a Core → Platform lock with neither a recipient record nor a proof that it is own ends with the
    /// explained refusal without asking for the PIN, and no resume call is made.
    func testAResumeOfALockWhoseRecipientIsUnknownIsRefusedBeforeThePIN() async throws {
        let container = try DashModelContainer.inMemoryWithoutCloudKit()
        let built = try builtOutPoint()
        container.mainContext.insert(PersistentAssetLock(
            outPointHex: built.outPointHex, walletId: Self.fundingWalletId, transactionBytes: Data(), fundingTypeRaw: 4,
            identityIndexRaw: -1, amountDuffs: 200_000_000, statusRaw: 2))
        try container.mainContext.save()
        let suite = "ExternalSendExecutorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsFundingRecipientStore(defaults: defaults)
        let funding = FakePlatformFunding()
        funding.check = { txid, vout in
            _ = try CoreFundingRecipientCheck(recipientStore: store, container: container, log: { _ in })
                .recipient(outPointTxid: txid, outPointVout: vout)
        }
        let authorizer = CountingAuthorizer()
        let coordinator = fundingCoordinator(funding, authorizer, container: container)

        await coordinator.resumeFundPlatform(
            outPointTxidWire: built.txid, outPointVout: built.vout, recipientAmountDuffs: Self.amount)

        XCTAssertEqual(coordinator.phase, .failed(CoreFundingResumer.ResumeError.cannotFinishMessage))
        XCTAssertEqual(authorizer.calls, 0, "refused before the PIN")
        XCTAssertTrue(funding.calls.isEmpty, "\(funding.calls)")
        XCTAssertFalse(ShieldedAssetLocksInFlight.shared.hasActivity)
    }

    func testLiveCoreToPlatformRefusesALockValueThatOverflows() async {
        let result = await LiveCoreTwoStepSend().run(
            route: .coreToPlatform, destination: destination(for: .coreToPlatform), amount: .max,
            bindingFeeDuffs: 1, isMax: false)
        let refused = isFailure(result, matching: {
            if case .addressFundingFeeUnavailable? = $0 as? CoordinatorError { return true }
            return false
        }, recorded: false)
        XCTAssertTrue(refused, "\(result)")
    }

    func testLiveCreditSendRefusesAnAmountOrFeeThatOverflowsInCredits() async {
        let live = LiveShieldedPlatformSend()
        for route in coordinatorRoutes {
            for (amount, fee) in [(UInt64.max, UInt64(1)), (Self.amount, UInt64.max)] {
                let result = await live.run(
                    route: route, destination: destination(for: route), amount: amount, bindingFeeDuffs: fee,
                    isMax: false, sweepCredits: nil)
                let invalidAmount = isFailure(result, matching: {
                    if case .invalidAmount? = $0 as? PlatformAddressSyncCoordinator.SendError { return true }
                    return false
                }, handedOver: false)
                XCTAssertTrue(invalidAmount, "\(route) amount \(amount) fee \(fee): \(result)")
            }
        }
    }

    func testLiveCreditSendRefusesANonShieldedRecipientOnTheShieldedRoutes() async {
        let live = LiveShieldedPlatformSend()
        let notShielded = Destination(type: .shieldedAddress, text: Self.coreAddress)
        for route in [SendRoute.shieldedToShielded, .platformToShielded] {
            let result = await live.run(
                route: route, destination: notShielded, amount: Self.amount, bindingFeeDuffs: 1, isMax: true, sweepCredits: nil)
            let refused = isFailure(result, matching: isNoShieldedAddress, handedOver: false)
            XCTAssertTrue(refused, "\(route): \(result)")
        }
    }

    func testLiveCreditSendRefusesAnIdentityIdThatIsNotThirtyTwoBytesBeforeTheTopUp() async {
        let live = LiveShieldedPlatformSend()
        for text in ["identity-id-recipient", Self.coreAddress] {
            let result = await live.run(
                route: .shieldedToIdentity, destination: Destination(type: .identityID, text: text),
                amount: Self.amount, bindingFeeDuffs: 1, isMax: false, sweepCredits: nil)
            let refused = isFailure(result, matching: {
                if case .invalidDestination? = $0 as? PlatformAddressSyncCoordinator.SendError { return true }
                return false
            }, handedOver: false)
            XCTAssertTrue(refused, "\(text): \(result)")
        }
    }

    /// The executor over the Live two-step and credit adapters: refusals before the SDK edge are not sent, with
    /// Retry, and the withdrawal minimum stops a send before the Live seam.
    func testTheExecutorReportsLiveRefusalsBeforeTheSDKEdgeAsNotSent() async throws {
        let executor = ExternalSendExecutor(
            standardSend: standard, paymentRequestSend: paymentRequest, twoStep: LiveCoreTwoStepSend(),
            creditsSend: LiveShieldedPlatformSend(), identityTopUp: identityTopUp, identityCredits: identityCredits,
            fees: fees, balances: balances, drainPreview: drainPreview, prompt: prompt,
            logOutcome: { [unowned self] in logged.append($0) })
        let notShielded = Destination(type: .shieldedAddress, text: Self.coreAddress)
        let cases: [(SendRoute, Bool)] = [
            (.coreToShielded, false), (.coreToShielded, true), (.platformToShielded, false),
            (.shieldedToIdentity, false)
        ]
        for (route, isMax) in cases {
            let prepared = try await executor.prepare(
                route: route, destination: notShielded, amount: Self.amount, isMax: isMax, sweepCredits: nil)
            let outcome = await executor.send(prepared)
            XCTAssertTrue(isNotSent(outcome, "failed"), "\(route) isMax \(isMax): \(outcome)")
        }
        let belowMinimum = try await executor.prepare(
            route: .shieldedToCore, destination: destination(for: .shieldedToCore), amount: 1, isMax: false, sweepCredits: nil)
        let outcome = await executor.send(belowMinimum)
        XCTAssertTrue(isNotSent(outcome, "belowMinimum"), "\(outcome)")
    }

    // MARK: - A send that already took the plan, and the context it was prepared under

    func testASecondSendWhileTheFirstIsInFlightAndAfterItIsInFlightAndTheSeamRunsOnce() async throws {
        let executor = makeExecutor()
        let prepared = try await prepare(executor, .platformToCore)
        var release: CheckedContinuation<Void, Never>?
        credits.suspension = { await withCheckedContinuation { release = $0 } }

        let first = Task { await executor.send(prepared) }
        while release == nil { await Task.yield() }
        let second = await executor.send(prepared)
        XCTAssertTrue(isInFlight(second), "\(second)")

        release?.resume()
        let firstOutcome = await first.value
        guard case .sent = firstOutcome else { return XCTFail("\(firstOutcome)") }
        let third = await executor.send(prepared)
        XCTAssertTrue(isInFlight(third), "\(third)")
        XCTAssertEqual(credits.runs.count, 1)
    }

    func testASendAfterADiscardIsNotSentWithRetry() async throws {
        let executor = makeExecutor()
        let prepared = try await prepare(executor, .platformToCore)
        executor.discard(prepared)

        let outcome = await executor.send(prepared)

        XCTAssertTrue(isNotSent(outcome, "failed"), "\(outcome)")
        XCTAssertTrue(credits.runs.isEmpty)
    }

    func testASendIsRefusedWhenTheWalletOrNetworkChangedSincePrepare() async throws {
        let executor = makeExecutor()
        for changed in [
            ExternalSendContext(walletId: Data([2]), network: .testnet),
            ExternalSendContext(walletId: Data([1]), network: .mainnet)
        ] {
            context = ExternalSendContext(walletId: Data([1]), network: .testnet)
            let prepared = try await prepare(executor, .platformToCore)
            context = changed

            let outcome = await executor.send(prepared)

            XCTAssertTrue(isNotSent(outcome, "failed"), "\(outcome)")
        }
        XCTAssertTrue(credits.runs.isEmpty, "nothing reaches the seam")
    }

    func testASendUnderTheContextItWasPreparedUnderIsDispatched() async throws {
        let executor = makeExecutor()
        let prepared = try await prepare(executor, .platformToCore)

        let outcome = await executor.send(prepared)

        guard case .sent = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(credits.runs.count, 1)
    }

    // MARK: - A Platform address of the other network

    func testACreditOutputIsBuiltOnlyForAnAddressOfTheRunningNetwork() throws {
        func address(mainnet: Bool) throws -> String {
            let payload = Data([0xb0] + Array(repeating: 0x02, count: 20))
            return try XCTUnwrap(Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: mainnet), data: payload))
        }
        for running in [true, false] {
            XCTAssertNotNil(PlatformAddressCreditOutput(
                bech32mAddress: try address(mainnet: running), credits: 1, onMainnet: running))
            XCTAssertNil(PlatformAddressCreditOutput(
                bech32mAddress: try address(mainnet: !running), credits: 1, onMainnet: running))
        }
    }

    // MARK: - A Shielded destination of the other network

    private func shieldedText(mainnet: Bool) throws -> String {
        let payload = Data([0x10] + Array(repeating: 0x07, count: 43))
        return try XCTUnwrap(Bech32m.encode(hrp: Bech32m.platformHrp(mainnet: mainnet), data: payload))
    }

    func testAShieldedDestinationOfTheOtherNetworkIsRefusedBeforeTheCoordinatorIsBuilt() async throws {
        let running = WalletEnvironment.isMainnet
        XCTAssertNotNil(ShieldedDestination.raw43(try shieldedText(mainnet: running)))
        XCTAssertNil(ShieldedDestination.raw43(try shieldedText(mainnet: !running)))

        var coordinatorsBuilt = 0
        let twoStep = LiveCoreTwoStepSend(makeCoordinator: {
            coordinatorsBuilt += 1
            return ShieldedTransferCoordinator()
        })
        let other = Destination(type: .shieldedAddress, text: try shieldedText(mainnet: !running))
        for isMax in [false, true] {
            let result = await twoStep.run(
                route: .coreToShielded, destination: other, amount: Self.amount, bindingFeeDuffs: 0, isMax: isMax)
            guard case .failed(_, let recorded) = result else { return XCTFail("\(result)") }
            XCTAssertFalse(recorded)
        }
        XCTAssertEqual(coordinatorsBuilt, 0)
    }
}

extension BIP70ConfirmationBox {
    /// A verified payment request paying `amount` to `address`, as the BIP70 fetch hands it over.
    static func fixture(address: String, amount: UInt64, merchantName: String? = "Merchant",
                        memo: String? = "Order 7", isSecure: Bool = false,
                        callbackScheme: String? = nil) -> BIP70ConfirmationBox {
        let details = PaymentDetails(network: "test", outputs: [], memo: memo)
        return BIP70ConfirmationBox(Confirmation(
            merchantName: merchantName, isSecure: isSecure, recipients: [(address: address, amount: amount)],
            amount: amount, estimatedFee: 226, network: .testnet, paymentURL: nil, scheme: "dash",
            merchantData: nil, memo: memo, callbackScheme: callbackScheme,
            request: PaymentRequest(serializedDetails: details.encoded())))
    }
}
