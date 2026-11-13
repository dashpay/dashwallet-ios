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
import SwiftDashSDK

/// Why `prepare` produced nothing. Each case sends the user back to Send (or blocks Confirm) with nothing broadcast.
enum ExternalSendError: Error, Equatable {
    case authenticationCancelled
    case authenticationFailed
    /// The binding fee could not be worked out: Confirm is blocked and Try again prepares anew.
    case feeUnavailable
    /// The binding fee no longer fits the balance; Send recomputes Max.
    case balanceNotEnough
    case balanceUnavailable
    /// A restored wallet's first sync is still running, so no Core-funded send starts.
    case initialRestoreSync
    /// A Shielded withdrawal's amount is outside what Platform accepts for its Core fee rate; nothing was built.
    case amountOutOfRange
}

/// The Core standard send: authenticates, then builds and signs without broadcasting.
protocol CoreStandardSending {
    func prepareStandardSend(address: String, amount: UInt64) async throws -> PreparedStandardSend
}

/// A payment request built and signed, not yet POSTed or broadcast. `send` POSTs the Payment and broadcasts, once.
/// `release` gives the request's single-use claim back when the send is discarded before it ran, so the same request
/// can be built again.
@MainActor
final class PreparedPaymentRequestSend {
    /// The transaction's wire-order txid, known once it is signed.
    let txidWire: Data
    let fee: UInt64
    private var sendAction: (() async throws -> SendResult)?
    private var release: (() -> Void)?

    init(txidWire: Data, fee: UInt64, sendAction: @escaping () async throws -> SendResult,
         release: @escaping () -> Void = {}) {
        self.txidWire = txidWire
        self.fee = fee
        self.sendAction = sendAction
        self.release = release
    }

    /// Runs the POST + broadcast, once: a second call (or one after `discard`) gets nil.
    fileprivate func send() async throws -> SendResult? {
        guard let action = sendAction else { return nil }
        sendAction = nil
        release = nil
        return try await action()
    }

    /// Drops the send; one that has not run releases the request's claim.
    fileprivate func discard() {
        sendAction = nil
        release?()
        release = nil
    }
}

/// The Core payment-request send (BIP70): authenticates and builds and signs the verified request without POSTing the
/// Payment or broadcasting.
protocol CorePaymentRequestSending {
    @MainActor
    func preparePaymentRequestSend(_ request: BIP70ConfirmationBox) async throws -> PreparedPaymentRequestSend
}

enum CoreTwoStepResult {
    case completed
    /// The asset lock is recorded and the second step is not confirmed yet.
    case unconfirmed
    /// The second step failed for `after` once the coordinator recorded the asset lock it built: the money is held in
    /// the lock.
    case lockHeld(HeldAssetLock, after: Error)
    /// `assetLockRecorded`: the asset lock exists, so the money has left the source.
    case failed(Error, assetLockRecorded: Bool)
}

/// The asset-lock routes from Core (to Shielded, Platform and Identity). `bindingFeeDuffs` is the fee Confirm showed
/// less the lock transaction's L1 miner fee, which the Core transaction pays on top of the lock; `isMax` is the
/// whole-balance send, which the seam resolves per route.
protocol CoreTwoStepSending {
    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64, isMax: Bool
    ) async -> CoreTwoStepResult
}

enum CreditsSendResult {
    case completed
    /// The spend was handed over and its result is not confirmed yet.
    case unconfirmed
    /// `handedOver`: the money has left the source, whatever the error says.
    case failed(Error, handedOver: Bool)
    /// The seam refused to start, so nothing was built or spent.
    case notStarted
}

/// A Shielded spend the SDK planned at Continue (`PlatformWalletManager.shieldedPlanSpend`), in credits: the notes it
/// selects, named by `digest`, and their exact fee. `amountCredits` is what the spend reserves for the recipient (a
/// withdrawal's reserve for Core), `recipientCredits` what the recipient receives after a withdrawal's Core fee.
struct PlannedShieldedSpend: Equatable, Sendable {
    let amountCredits: UInt64
    let recipientCredits: UInt64
    let feeCredits: UInt64
    /// What leaves the pool: the amount and the fee.
    let totalDebitedCredits: UInt64
    let digest: Data
    /// The plan the spend runs; nil only for a plan a test made, which the live seam refuses to spend.
    let sdkPlan: ShieldedSpendPlan?

    init(amountCredits: UInt64, recipientCredits: UInt64, feeCredits: UInt64, totalDebitedCredits: UInt64,
         digest: Data, sdkPlan: ShieldedSpendPlan? = nil) {
        self.amountCredits = amountCredits
        self.recipientCredits = recipientCredits
        self.feeCredits = feeCredits
        self.totalDebitedCredits = totalDebitedCredits
        self.digest = digest
        self.sdkPlan = sdkPlan
    }

    init(_ plan: ShieldedSpendPlan) {
        self.init(
            amountCredits: plan.amount, recipientCredits: plan.recipientAmount, feeCredits: plan.fee,
            totalDebitedCredits: plan.totalDebited, digest: plan.digest, sdkPlan: plan)
    }
}

/// Plans a Shielded-source spend with the SDK. Throws what `shieldedPlanSpend` throws.
protocol ShieldedSpendPlanning {
    func plan(route: SendRoute, amount: ShieldedSpendAmount) async throws -> PlannedShieldedSpend
}

/// The SDK planner over the active wallet's account 0, the account the coordinator spends from. A withdrawal is
/// planned at the Core fee rate the coordinator withdraws with.
struct LiveShieldedSpendPlanner: ShieldedSpendPlanning {
    func plan(route: SendRoute, amount: ShieldedSpendAmount) async throws -> PlannedShieldedSpend {
        try await planOnMain(route: route, amount: amount)
    }

    @MainActor
    private func planOnMain(route: SendRoute, amount: ShieldedSpendAmount) async throws -> PlannedShieldedSpend {
        guard let manager = SwiftDashSDKHost.shared.manager else {
            throw ShieldedTransferCoordinator.CoordinatorError.noManager
        }
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw ShieldedTransferCoordinator.CoordinatorError.noWallet
        }
        let kind = Self.kind(of: route)
        let plan = try await manager.shieldedPlanSpend(
            walletId: wallet.walletId, account: 0, kind: kind, amount: amount,
            coreFeePerByte: kind == .withdrawal ? ShieldedTransferCoordinator.withdrawalCoreFeePerByte : nil)
        return PlannedShieldedSpend(plan)
    }

    private static func kind(of route: SendRoute) -> ShieldedSpendKind {
        switch route {
        case .shieldedToCore: return .withdrawal
        case .shieldedToShielded: return .transfer
        case .shieldedToPlatform: return .unshield
        case .shieldedToIdentity: return .identityTopUp
        default: preconditionFailure("\(route) is not a Shielded-source route")
        }
    }
}

/// The Shielded-source routes and the Platform-source routes to Core, Shielded and Platform destinations.
/// `shieldedPlan` is the SDK plan prepared at Continue for a Shielded source, which the spend runs exactly; nil for a
/// Platform source.
protocol ShieldedPlatformSending {
    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64, isMax: Bool,
        shieldedPlan: PlannedShieldedSpend?
    ) async -> CreditsSendResult
}

/// The Platform-source route to an Identity ID (a top-up from the Platform addresses' credits).
protocol IdentityTopUpFromCreditsSending {
    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64
    ) async -> CreditsSendResult
}

/// The Identity-source routes (the Current identity's credits to Core, a Platform address or an Identity ID). Amounts,
/// the binding fee and the identity balance are credits. `identityId` is the source identity the send was prepared
/// for.
protocol IdentityCreditsSending {
    func run(
        route: SendRoute, destination: Destination, identityId: Data, amountCredits: UInt64, bindingFeeCredits: UInt64,
        isMax: Bool
    ) async -> CreditsSendResult
}

/// The funds of a source the send is checked against, in the unit `AmountRules` counts for that source; nil when
/// they cannot be read.
protocol ExternalSendBalanceReading {
    func spendableBalance(of source: SendSource) async -> UInt64?
}

/// The Core wallet drain as it would run now: the coins it sweeps (confirmed or InstantSend-locked, fewer than the
/// sendable balance counts) and what it pays the recipient, nil when it would pay nothing.
struct CoreDrainPreview: Equatable {
    let candidateDuffs: UInt64
    let recipientDuffs: UInt64?
}

/// Reads the Core drain preview; nil when it cannot be read.
protocol CoreDrainPreviewing {
    func drainPreview() async -> CoreDrainPreview?
}

/// An identity's credits as Platform reports them now, not as the wallet last stored them: nil when the read fails.
protocol IdentityNetworkBalanceReading {
    func networkBalanceCredits(identityId: Data) async -> UInt64?
}

/// Whether a route's funding step can pay an amount, on top of the balance less the fee.
enum SendFundingCheck: Equatable {
    /// The route's balance check is the balance less the fee alone.
    case notChecked
    case fundable
    case notFundable
    /// What the funding step draws on could not be read.
    case unknown
}

/// The Platform-Payment addresses a Platform to Identity top-up draws on; nil when they cannot be read.
protocol PlatformFundingCandidatesReading {
    func fundingCandidates() async -> [PlatformPaymentIdentityFundingPolicy.Candidate]?
}

/// Whether the funding step a Platform route executes can pay an amount. The aggregate balance check of `prepare`
/// cannot tell: the Platform to Core withdrawal spends one row and needs fee headroom, the Platform to Platform
/// transfer spends one account, the Platform to Identity top-up needs the amount plus its fee headroom on its input
/// addresses.
protocol PlatformSendFundingChecking {
    /// Platform to Core, a typed amount: the row the withdrawal spends holds `amountDuffs` plus the `feeDuffs` held
    /// back from it.
    func canWithdrawToCore(amountDuffs: UInt64, feeDuffs: UInt64) async -> SendFundingCheck
    /// Platform to Core Max: what the whole-balance withdrawal pays now, in duffs; nil when it cannot be read.
    func withdrawableMaxDuffs() async -> UInt64?
    /// Platform to Platform: the account the transfer selects holds `amountDuffs` plus `feeDuffs`.
    func canTransferOnPlatform(amountDuffs: UInt64, feeDuffs: UInt64) async -> SendFundingCheck
    /// Platform to Identity: the top-up's input planning can fund `amountDuffs`.
    func canFundIdentity(amountDuffs: UInt64) async -> SendFundingCheck
    /// Platform to Platform: the credits of the account the transfer pays from; nil when they cannot be read.
    func transferAccountCredits() async -> UInt64?
}

extension PlatformSendFundingChecking {
    /// The funding step of `route` for `amountDuffs`, the one check both Send and preparation ask: these routes
    /// execute on less than the aggregate balance. Platform to Core withdraws from the highest-balance row less its
    /// fee, Platform to Platform transfers out of the account holding that row (and needs the fee too: unknown
    /// without it), Platform to Identity needs the amount plus the top-up's fee headroom on its input addresses. A Max
    /// on a route whose seam spends the whole balance is not checked: the seam sizes it (Platform to Core Max is the
    /// account-wide withdrawal, not one row).
    func fundingCheck(route: SendRoute, amountDuffs: UInt64, feeDuffs: UInt64?, isMax: Bool) async -> SendFundingCheck {
        if isMax && ExternalSendExecutor.seamSpendsWholeBalance(route) { return .notChecked }
        switch route {
        case .platformToCore:
            guard let feeDuffs else { return .unknown }
            return await canWithdrawToCore(amountDuffs: amountDuffs, feeDuffs: feeDuffs)
        case .platformToPlatform:
            guard let feeDuffs else { return .unknown }
            return await canTransferOnPlatform(amountDuffs: amountDuffs, feeDuffs: feeDuffs)
        case .platformToIdentity: return await canFundIdentity(amountDuffs: amountDuffs)
        default: return .notChecked
        }
    }
}

/// The wallet and network a send is prepared under; the send is refused when either differs at dispatch.
/// `generation` counts the runtime's active-wallet changes, so a switch away and back (A → B → A) while the send was
/// prepared also differs, although wallet and network read the same again.
struct ExternalSendContext: Equatable {
    let walletId: Data?
    let network: WalletEnvironment.NetworkKind
    var generation: UInt64 = 0

    /// The active wallet of the running network, resolved through `WalletEnvironment`.
    @MainActor
    static func current() -> ExternalSendContext {
        let network = WalletEnvironment.networkKind
        return ExternalSendContext(
            walletId: WalletEnvironment.activeWalletId(for: network), network: network,
            generation: SwiftDashSDKWalletRuntime.activeWalletGeneration)
    }
}

/// A send built for the exact amount with its binding fee, not yet broadcast. `discard` releases it.
@MainActor
final class PreparedExternalSend {
    enum Plan {
        /// `callbackScheme` is the sender of a dash: link another app opened, told once the transaction was sent.
        case standard(PreparedStandardSend, callbackScheme: String? = nil)
        case paymentRequest(PreparedPaymentRequestSend)
        case routed(destination: Destination)
    }

    let route: SendRoute
    let amount: UInt64
    /// What the recipient receives, in duffs: `amount`, except for a Shielded withdrawal, whose Core fee comes out of
    /// it.
    let recipientAmount: UInt64
    let fee: UInt64
    /// The part of `fee` a Core asset lock pays the L1 miners; 0 on every other route.
    let assetLockMinerFee: UInt64
    let isMax: Bool
    /// The SDK plan of a Shielded-source spend; nil on every other route.
    let shieldedPlan: PlannedShieldedSpend?
    /// The Core to Core transaction's wire-order txid, read when the send is prepared so it outlives the plan;
    /// nil for the routed sends.
    let txidWire: Data?
    /// The x-callback-url of the app that opened the link (a merchant's, for a payment request), set only once the
    /// Core to Core send succeeded; the flow opens it.
    private(set) var callbackURL: URL?
    /// The wallet and network the executor prepared the send under; nil for a send built outside it.
    fileprivate(set) var context: ExternalSendContext?
    /// The Current identity an Identity-source send was prepared for, read before its balance check; nil on the other
    /// routes, or when there was no Current identity.
    fileprivate(set) var sourceIdentityId: Data?
    private var plan: Plan?
    /// Whether a `send` took the plan, as opposed to `discard`.
    private var planTakenBySend = false

    init(route: SendRoute, amount: UInt64, recipientAmount: UInt64? = nil, fee: UInt64, assetLockMinerFee: UInt64 = 0,
         isMax: Bool, shieldedPlan: PlannedShieldedSpend? = nil, plan: Plan) {
        self.route = route
        self.amount = amount
        self.recipientAmount = recipientAmount ?? amount
        self.fee = fee
        self.assetLockMinerFee = assetLockMinerFee
        self.isMax = isMax
        self.shieldedPlan = shieldedPlan
        switch plan {
        case .standard(let transaction, _): txidWire = transaction.txidWire
        case .paymentRequest(let request): txidWire = request.txidWire
        case .routed: txidWire = nil
        }
        self.plan = plan
    }

    /// The plan, once: a second call (or one after `discard`) gets nil.
    fileprivate func takePlan() -> Plan? {
        defer { plan = nil }
        return plan
    }

    /// `takePlan` for a send, which remembers that the plan went to a send.
    fileprivate func takePlanForSend() -> Plan? {
        let taken = takePlan()
        if taken != nil { planTakenBySend = true }
        return taken
    }

    /// Whether a send took the plan, so its result is not known here.
    fileprivate var sendTookPlan: Bool { planTakenBySend }

    fileprivate func opens(_ url: URL?) { callbackURL = url }

    /// Called once when a Core asset-lock send is still running `ExternalSendExecutor.slowNetworkDelay` after it
    /// started: the lock is waiting for the network's proof, which can take minutes. Confirm then lets the holder
    /// leave while the send finishes.
    var onSlowNetwork: (() -> Void)?

    fileprivate func reportSlowNetwork() {
        let report = onSlowNetwork
        onSlowNetwork = nil
        report?()
    }
}

@MainActor
protocol ExternalSendExecuting: AnyObject {
    /// `sweepCredits`: the Shielded sweep plan's exact credits on a Shielded Max (`SendAmountRequest.sweepCredits`).
    func prepare(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64?
    ) async throws -> PreparedExternalSend
    func send(_ prepared: PreparedExternalSend) async -> SendOutcome
    func discard(_ prepared: PreparedExternalSend)
}

/// Authenticates on Continue, prepares the exact send with its binding fee, and broadcasts only in `send`.
/// Every route with a source is wired except Identity to Shielded, whose unavailable fee estimate stops it at Continue;
/// Identity to its own identity has no route.
@MainActor
final class ExternalSendExecutor: ExternalSendExecuting {
    private let standardSend: CoreStandardSending
    private let paymentRequestSend: CorePaymentRequestSending
    private let twoStep: CoreTwoStepSending
    private let creditsSend: ShieldedPlatformSending
    private let identityTopUp: IdentityTopUpFromCreditsSending
    private let identityCredits: IdentityCreditsSending
    private let fees: SendFeeEstimating
    private let shieldedPlans: ShieldedSpendPlanning
    private let balances: ExternalSendBalanceReading
    private let identityNetworkBalance: IdentityNetworkBalanceReading
    private let drainPreview: CoreDrainPreviewing
    private let platformFunding: PlatformSendFundingChecking
    private let prompt: any SendAuthenticationPrompting
    private let isBlockedByInitialRestoreSync: () -> Bool
    private let currentContext: @MainActor () -> ExternalSendContext
    private let currentIdentityId: @MainActor () -> Data?
    /// Writes a send's outcome line (`SendDecision.logLine`).
    private let logOutcome: (SendOutcome, String) -> Void
    private let slowNetworkDelay: Duration
    private let paymentNetwork: @MainActor () -> PaymentNetwork?

    init(
        standardSend: CoreStandardSending = LiveCoreStandardSend(),
        paymentRequestSend: CorePaymentRequestSending = LiveCorePaymentRequestSend(),
        twoStep: CoreTwoStepSending = LiveCoreTwoStepSend(),
        creditsSend: ShieldedPlatformSending = LiveShieldedPlatformSend(),
        identityTopUp: IdentityTopUpFromCreditsSending = LiveIdentityTopUpFromCredits(),
        identityCredits: IdentityCreditsSending = LiveIdentityCreditsSend(),
        fees: SendFeeEstimating = ExternalSendFeeEstimator(),
        shieldedPlans: ShieldedSpendPlanning = LiveShieldedSpendPlanner(),
        balances: ExternalSendBalanceReading = LiveExternalSendBalances(),
        identityNetworkBalance: IdentityNetworkBalanceReading = LiveIdentityNetworkBalance(),
        drainPreview: CoreDrainPreviewing = LiveCoreDrainPreview(),
        platformFunding: PlatformSendFundingChecking = LivePlatformSendFunding(),
        prompt: any SendAuthenticationPrompting = AuthenticationService.shared,
        isBlockedByInitialRestoreSync: @escaping () -> Bool = {
            WalletSendService.isCoreSpendBlockedByInitialRestoreSync
        },
        currentContext: @escaping @MainActor () -> ExternalSendContext = { ExternalSendContext.current() },
        currentIdentityId: @escaping @MainActor () -> Data? = {
            DWCurrentUserIdentityInfo.shared.refreshedSnapshot().identityId
        },
        logOutcome: @escaping (SendOutcome, String) -> Void = { DWLogger.log($1) },
        slowNetworkDelay: Duration = .seconds(20),
        paymentNetwork: @escaping @MainActor () -> PaymentNetwork? = { try? PaymentNetworkResolver.current() }
    ) {
        self.standardSend = standardSend
        self.paymentRequestSend = paymentRequestSend
        self.twoStep = twoStep
        self.creditsSend = creditsSend
        self.identityTopUp = identityTopUp
        self.identityCredits = identityCredits
        self.fees = fees
        self.shieldedPlans = shieldedPlans
        self.balances = balances
        self.identityNetworkBalance = identityNetworkBalance
        self.drainPreview = drainPreview
        self.platformFunding = platformFunding
        self.prompt = prompt
        self.isBlockedByInitialRestoreSync = isBlockedByInitialRestoreSync
        self.currentContext = currentContext
        self.currentIdentityId = currentIdentityId
        self.logOutcome = logOutcome
        self.slowNetworkDelay = slowNetworkDelay
        self.paymentNetwork = paymentNetwork
    }

    func prepare(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64?
    ) async throws -> PreparedExternalSend {
        if route.source == .core, isBlockedByInitialRestoreSync() {
            throw ExternalSendError.initialRestoreSync
        }
        let context = currentContext()
        let sourceIdentityId = route.source == .identity ? currentIdentityId() : nil
        let prepared = try await prepareRoute(
            route: route, destination: destination, amount: amount, isMax: isMax, sweepCredits: sweepCredits)
        prepared.context = context
        prepared.sourceIdentityId = sourceIdentityId
        return prepared
    }

    private func prepareRoute(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64?
    ) async throws -> PreparedExternalSend {
        switch route {
        case .coreToCore:
            if let request = destination.verifiedRequest {
                return try await preparePaymentRequest(request, amount: amount, isMax: isMax)
            }
            return try await prepareStandard(destination: destination, amount: amount, isMax: isMax)
        case .coreToShielded, .coreToIdentity,
             .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity,
             .platformToCore, .platformToShielded, .platformToPlatform, .platformToIdentity,
             .identityToCore, .identityToPlatform, .identityToIdentity, .identityToShielded:
            return try await prepareRouted(
                route: route, destination: destination, amount: amount, isMax: isMax, sweepCredits: sweepCredits)
        }
    }

    func send(_ prepared: PreparedExternalSend) async -> SendOutcome {
        let decision: SendDecision
        // A send that already took the plan may have spent: fail closed, never offer a Retry.
        if prepared.sendTookPlan {
            return report(SendDecision(.inFlight, cause: "planAlreadySent"), of: prepared)
        }
        guard isStillPreparedFor(prepared) else {
            discard(prepared)
            return .notSent(.failed)
        }
        switch prepared.takePlanForSend() {
        case nil:
            decision = SendDecision(.notSent(.failed), cause: "noPlan")
        case let .standard(transaction, callbackScheme)?:
            decision = await broadcast(transaction)
            if case .sent = decision.outcome {
                prepared.opens(BIP70PaymentService.makeCallbackURL(
                    scheme: callbackScheme, address: transaction.address,
                    txidHexDisplay: transaction.txHash.hexEncodedString()))
            }
        case .paymentRequest(let request)?:
            decision = await sendPaymentRequest(request, into: prepared)
        case .routed(let destination)?:
            decision = await runRouted(prepared, destination: destination)
        }
        return report(decision, of: prepared)
    }

    /// Logs the send's one outcome line, with its route and what decided it.
    private func report(_ decision: SendDecision, of prepared: PreparedExternalSend) -> SendOutcome {
        logOutcome(decision.outcome, decision.logLine(route: prepared.route, isMax: prepared.isMax))
        return decision.outcome
    }

    func discard(_ prepared: PreparedExternalSend) {
        if case .paymentRequest(let request)? = prepared.takePlan() { request.discard() }
    }

    // MARK: - Core to Core

    private func prepareStandard(
        destination: Destination, amount: UInt64, isMax: Bool
    ) async throws -> PreparedExternalSend {
        let transaction: PreparedStandardSend
        do {
            transaction = try await standardSend.prepareStandardSend(address: destination.text, amount: amount)
        } catch {
            throw Self.preparationError(error)
        }
        try await requireFits(route: .coreToCore, amount: amount, fee: transaction.fee)
        return PreparedExternalSend(
            route: .coreToCore, amount: amount, fee: transaction.fee, isMax: isMax,
            plan: .standard(transaction, callbackScheme: destination.callbackScheme))
    }

    /// The request is signed for the amount it asks for, so a caller amount that differs from it is refused before
    /// anything is built, and the balance check and the prepared send carry the request's amount.
    private func preparePaymentRequest(
        _ verified: BIP70ConfirmationBox, amount: UInt64, isMax: Bool
    ) async throws -> PreparedExternalSend {
        let requestAmount = verified.confirmation.amount
        guard amount == requestAmount else { throw ExternalSendError.feeUnavailable }
        // A request verified on another network (testnet and devnet share address bytes) is never built here.
        guard verified.confirmation.network == paymentNetwork() else { throw ExternalSendError.feeUnavailable }
        let request: PreparedPaymentRequestSend
        do {
            request = try await paymentRequestSend.preparePaymentRequestSend(verified)
        } catch {
            throw Self.preparationError(error)
        }
        do {
            try await requireFits(route: .coreToCore, amount: requestAmount, fee: request.fee)
        } catch {
            request.discard()
            throw error
        }
        return PreparedExternalSend(
            route: .coreToCore, amount: requestAmount, fee: request.fee, isMax: isMax, plan: .paymentRequest(request))
    }

    /// The BIP70 send POSTs the Payment before it broadcasts, so a failure there leaves the signed bytes with the
    /// merchant; `SendOutcome(error:)` keeps whatever is not proven unsent `inFlight`.
    private func sendPaymentRequest(_ request: PreparedPaymentRequestSend, into prepared: PreparedExternalSend) async
        -> SendDecision {
        do {
            guard let result = try await request.send() else {
                return SendDecision(.notSent(.failed), cause: "requestAlreadyRun")
            }
            prepared.opens(result.callbackURL)
            return SendDecision(.sent)
        } catch {
            return .decided(by: error)
        }
    }

    /// `PreparedStandardSend.broadcast` blocks until the network answers, so it runs off the main actor.
    private func broadcast(_ transaction: PreparedStandardSend) async -> SendDecision {
        let result = await Task.detached { Result { try transaction.broadcast() } }.value
        switch result {
        case .success:
            return SendDecision(.sent)
        case .failure(let error):
            return .decided(by: error)
        }
    }

    private static func preparationError(_ error: Error) -> ExternalSendError {
        let nsError = error as NSError
        guard nsError.domain == WalletSendService.errorDomain else { return .feeUnavailable }
        switch WalletSendService.ErrorCode(rawValue: nsError.code) {
        case .authenticationCancelled: return .authenticationCancelled
        case .authenticationFailed: return .authenticationFailed
        case .initialRestoreSync: return .initialRestoreSync
        default: return .feeUnavailable
        }
    }

    // MARK: - Asset-lock and credit routes

    private func prepareRouted(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64?
    ) async throws -> PreparedExternalSend {
        let authentication = await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            spendAmount: route.source == .identity ? AmountRules.dashValue(of: amount) : amount,
            prompt: prompt)
        switch authentication {
        case .ok: break
        case .cancelled: throw ExternalSendError.authenticationCancelled
        case .failed, .timedOut: throw ExternalSendError.authenticationFailed
        }

        if route.source == .shielded {
            return try await prepareShielded(
                route: route, destination: destination, amount: amount, isMax: isMax, sweepCredits: sweepCredits)
        }

        guard case .fee(var fee, var minerFee) = await fees.estimate(route: route, amount: amount) else {
            throw ExternalSendError.feeUnavailable
        }
        if isMax && route == .coreToShielded {
            // The drain spends every coin it sweeps, so what it takes beyond the Max is those coins less the Max;
            // the estimate's pool-sized L1 fee would show a total above them. A preview that no longer pays the Max
            // sends the holder back to Send to plan it again.
            guard let preview = await drainPreview.drainPreview() else {
                throw ExternalSendError.balanceUnavailable
            }
            guard preview.recipientDuffs == amount, preview.candidateDuffs >= amount else {
                throw ExternalSendError.balanceNotEnough
            }
            fee = preview.candidateDuffs - amount
            minerFee = min(minerFee, fee)
        } else if !(isMax && Self.seamSpendsWholeBalance(route)) {
            try await requireFits(route: route, amount: amount, fee: fee, isMax: isMax)
            try await requireFundable(route: route, amount: amount, fee: fee, isMax: isMax)
        }
        return PreparedExternalSend(
            route: route, amount: amount, fee: fee, assetLockMinerFee: minerFee, isMax: isMax,
            plan: .routed(destination: destination))
    }

    /// The SDK plans the spend for the exact credits (a Max's carried sweep credits); its fee is the one the spend
    /// pays, and its note check replaces the balance check. A withdrawal's fee also carries the Core fee taken from
    /// the reserve, so Confirm shows what the recipient receives and the total that leaves the pool.
    private func prepareShielded(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64?
    ) async throws -> PreparedExternalSend {
        let (amountCredits, overflow) = amount.multipliedReportingOverflow(
            by: PlatformPaymentIdentityFundingPolicy.creditsPerDuff)
        guard !overflow else { throw ExternalSendError.balanceNotEnough }
        let plan: PlannedShieldedSpend
        do {
            plan = try await shieldedPlans.plan(route: route, amount: .exact(sweepCredits ?? amountCredits))
        } catch {
            throw Self.planningError(error)
        }
        let recipientDuffs = plan.recipientCredits / PlatformPaymentIdentityFundingPolicy.creditsPerDuff
        let feeDuffs = CoreToShieldedAmountPolicy.poolFeeDuffs(
            poolFeeCredits: plan.totalDebitedCredits - plan.recipientCredits)
        return PreparedExternalSend(
            route: route, amount: amount, recipientAmount: recipientDuffs, fee: feeDuffs, isMax: isMax,
            shieldedPlan: plan, plan: .routed(destination: destination))
    }

    /// The plan reads the notes: those that cannot pay the amount and its fee (`walletOperation`) or need more than
    /// one transition carries are a balance that is not enough.
    private static func planningError(_ error: Error) -> ExternalSendError {
        switch error as? PlatformWalletError {
        case .walletOperation?, .shieldedSpendTooManyNotes?:
            return .balanceNotEnough
        case .shieldedWithdrawalAmountOutOfRange?:
            return .amountOutOfRange
        default:
            return .feeUnavailable
        }
    }

    /// The wallet, network and (for an Identity source) Current identity are still the ones the send was prepared for.
    /// `send` checks it first, and `runRouted` again after its last await, right before the seam: a seam spends from
    /// whatever is active when it runs.
    private func isStillPreparedFor(_ prepared: PreparedExternalSend) -> Bool {
        if let preparedContext = prepared.context, preparedContext != currentContext() {
            DWLogger.log("External send refused: the wallet or network changed since it was prepared")
            return false
        }
        if prepared.route.source == .identity,
           prepared.sourceIdentityId == nil || prepared.sourceIdentityId != currentIdentityId() {
            DWLogger.log("External send refused: the Current identity changed since it was prepared")
            return false
        }
        return true
    }

    /// A Platform to Core Max withdraws the whole balance as it is at dispatch: it goes only while that is still the
    /// amount Confirm showed (the Max Send planned), otherwise nothing is sent and Send plans Max again.
    private func platformMaxRefusal(_ prepared: PreparedExternalSend) async -> SendOutcome? {
        guard prepared.route == .platformToCore, prepared.isMax else { return nil }
        guard await platformFunding.withdrawableMaxDuffs() == prepared.amount else {
            DWLogger.log("External send refused: the Platform balance changed since Confirm")
            return .notSent(.balanceChanged)
        }
        return nil
    }

    /// An Identity Max keeps the DashPay reserve (`requireFits` refuses it at preparation): at dispatch it goes only
    /// while the prepared identity's balance as Platform reports it now still covers the amount, the fee and the
    /// reserve, otherwise nothing is sent and Send plans Max again. The stored balance is not used: credits spent on
    /// another device leave it high, and Platform does not enforce the reserve. A balance Platform does not report
    /// refuses the Max too.
    private func identityMaxRefusal(_ prepared: PreparedExternalSend) async -> SendOutcome? {
        guard prepared.route.source == .identity, prepared.isMax else { return nil }
        guard let identityId = prepared.sourceIdentityId,
              let balance = await identityNetworkBalance.networkBalanceCredits(identityId: identityId),
              AmountRules.check(amount: prepared.amount, source: .identity, balance: balance, fee: prepared.fee) == .ok
        else {
            DWLogger.log("External send refused: the Identity Max no longer keeps the reserve")
            return .notSent(.balanceChanged)
        }
        return nil
    }

    /// The user authenticated on Continue, so the seam's own prompt is suppressed for the run.
    private func runRouted(_ prepared: PreparedExternalSend, destination: Destination) async -> SendDecision {
        if let refusal = Self.minimumAmountRefusal(prepared) {
            return .decided(by: refusal)
        }
        if let refusal = await platformMaxRefusal(prepared) {
            return SendDecision(refusal)
        }
        if let refusal = await identityMaxRefusal(prepared) {
            return SendDecision(refusal)
        }
        guard isStillPreparedFor(prepared) else { return SendDecision(.notSent(.failed), cause: "contextChanged") }
        switch prepared.route {
        case .coreToShielded, .coreToIdentity:
            return await runTwoStep(prepared, destination: destination)
        case .platformToIdentity:
            return await runCredits {
                await identityTopUp.run(
                    route: prepared.route, destination: destination, amount: prepared.amount,
                    bindingFeeDuffs: prepared.fee)
            }
        case .identityToCore, .identityToPlatform, .identityToIdentity:
            // `send` refuses an Identity-source send prepared without a Current identity.
            guard let identityId = prepared.sourceIdentityId else {
                return SendDecision(.notSent(.failed), cause: "noSourceIdentity")
            }
            return await runCredits {
                await identityCredits.run(
                    route: prepared.route, destination: destination, identityId: identityId,
                    amountCredits: prepared.amount, bindingFeeCredits: prepared.fee, isMax: prepared.isMax)
            }
        case .identityToShielded:
            // TODO(identity-to-shielded): the recipient shield; prepare refuses the route until its fee is estimated.
            return .notSent(.failed)
        default:
            return await runCredits {
                await creditsSend.run(
                    route: prepared.route, destination: destination, amount: prepared.amount,
                    bindingFeeDuffs: prepared.fee, isMax: prepared.isMax, shieldedPlan: prepared.shieldedPlan)
            }
        }
    }

    /// What the Core asset-lock seam is handed as the fee. A Core → Shielded Max checks the drain against the whole
    /// fee Confirm showed (everything the drain takes beyond the Max, miner fee included); the other routes get the
    /// Platform side's fee, the fee less the lock's own miner fee.
    static func twoStepBindingFee(_ prepared: PreparedExternalSend) -> UInt64 {
        if prepared.route == .coreToShielded && prepared.isMax { return prepared.fee }
        return prepared.fee - prepared.assetLockMinerFee
    }

    private func runTwoStep(_ prepared: PreparedExternalSend, destination: Destination) async -> SendDecision {
        // The funding call waits for the lock's InstantSend proof, up to minutes when it is late; past the delay
        // the holder may leave Confirm and the send goes on.
        let delay = slowNetworkDelay
        let slowNetwork = Task { @MainActor [weak prepared] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            prepared?.reportSlowNetwork()
        }
        defer { slowNetwork.cancel() }
        let result = await DWIdentityAuthorizer.preauthorized {
            await twoStep.run(
                route: prepared.route, destination: destination, amount: prepared.amount,
                bindingFeeDuffs: Self.twoStepBindingFee(prepared), isMax: prepared.isMax)
        }
        switch result {
        case .completed:
            return SendDecision(.sent)
        case .unconfirmed:
            return SendDecision(.inFlight, cause: "unconfirmed")
        case let .lockHeld(lock, error):
            return .decided(by: error, after: .lockHeld(lock))
        case let .failed(error, recorded):
            return .decided(by: error, after: recorded ? .assetLockRecorded : nil)
        }
    }

    private func runCredits(_ run: () async -> CreditsSendResult) async -> SendDecision {
        creditsOutcome(await DWIdentityAuthorizer.preauthorized(run))
    }

    private func creditsOutcome(_ result: CreditsSendResult) -> SendDecision {
        switch result {
        case .completed:
            return SendDecision(.sent)
        case .unconfirmed:
            return SendDecision(.inFlight, cause: "unconfirmed")
        case .notStarted:
            return SendDecision(.notSent(.failed), cause: "notStarted")
        case let .failed(error, handedOver):
            return .decided(by: error, after: handedOver ? .handedOver : nil)
        }
    }

    // MARK: - Shared

    /// Platform's `min_withdrawal_amount` applies to the address and the shielded withdrawals to Core as to the
    /// identity withdrawal: below it the transition is rejected, so nothing is built. A Core top-up of an identity
    /// whose lock (the amount plus the Platform fee it carries) is below the SDK's minimum is refused before the asset
    /// lock is built.
    private static func minimumAmountRefusal(_ prepared: PreparedExternalSend) -> MinimumAmountRefusal? {
        let route = prepared.route
        let amountDuffs = prepared.amount
        if route == .coreToIdentity {
            let minimum = ExternalSendFeeEstimator.minimumCoreTopUpAmountDuffs(
                platformFeeDuffs: twoStepBindingFee(prepared))
            guard amountDuffs < minimum else { return nil }
            return MinimumAmountRefusal(minimumCredits: minimum * PlatformPaymentIdentityFundingPolicy.creditsPerDuff)
        }
        guard route == .platformToCore || route == .shieldedToCore else { return nil }
        let minimum = IdentityWithdrawViewModel.minimumWithdrawalCredits
        let (credits, overflow) = amountDuffs.multipliedReportingOverflow(
            by: PlatformPaymentIdentityFundingPolicy.creditsPerDuff)
        guard !overflow, credits < minimum else { return nil }
        return MinimumAmountRefusal(minimumCredits: minimum)
    }

    /// A Max send on this route spends the whole balance (the AUTO full withdrawal), so the seam works out the amount
    /// itself. A check here would refuse it: in duffs the balance rounds down and the fee rounds up. The Core wallet
    /// drain is handled in `prepareRouted`, which also sets the fee it takes; a Shielded source is planned by the SDK.
    nonisolated static func seamSpendsWholeBalance(_ route: SendRoute) -> Bool {
        route == .platformToCore
    }

    /// The balance check above counts the aggregate and the estimated fee; the funding step checks what the route
    /// executes on (`PlatformSendFundingChecking.fundingCheck`, which Send asks too).
    private func requireFundable(route: SendRoute, amount: UInt64, fee: UInt64, isMax: Bool) async throws {
        switch await platformFunding.fundingCheck(route: route, amountDuffs: amount, feeDuffs: fee, isMax: isMax) {
        case .notChecked, .fundable: return
        case .notFundable: throw ExternalSendError.balanceNotEnough
        case .unknown: throw ExternalSendError.balanceUnavailable
        }
    }

    /// A typed amount that dips into the Identity reserve only warns (AC-09); a Max is planned to keep the reserve, so
    /// one that would dip into it now (the credits fell since Send planned it) is refused and Send plans it again.
    private func requireFits(route: SendRoute, amount: UInt64, fee: UInt64, isMax: Bool = false) async throws {
        guard let balance = await balances.spendableBalance(of: route.source) else {
            throw ExternalSendError.balanceUnavailable
        }
        switch AmountRules.check(amount: amount, source: route.source, balance: balance, fee: fee) {
        case .notEnough: throw ExternalSendError.balanceNotEnough
        case .okWithReserveWarning where isMax: throw ExternalSendError.balanceNotEnough
        case .ok, .okWithReserveWarning: return
        }
    }
}

// MARK: - Live conformances

/// `WalletSendService` authenticates inside `prepareStandardSendForConfirmation`.
struct LiveCoreStandardSend: CoreStandardSending {
    func prepareStandardSend(address: String, amount: UInt64) async throws -> PreparedStandardSend {
        try await WalletSendService.shared.prepareStandardSendForConfirmation(address: address, amount: amount)
    }
}

/// Builds and signs the request fetched when the link was opened, the one Confirm shows, then authenticates for what
/// the send debits: the request's amount plus the fee of the transaction built, so the biometric spending limit covers
/// the whole debit (the old confirm screen gives its prompt the amount and the fee too). Nothing is broadcast before
/// the prompt; a refused prompt releases the request. The Payment POST and the broadcast run only in the prepared
/// send's action, then the send is recorded as the interactive BIP70 coordinator records it.
struct LiveCorePaymentRequestSend: CorePaymentRequestSending {
    private let makeService: @MainActor () -> BIP70PaymentService
    private let authorize: @MainActor (_ spendAmount: UInt64) async throws -> Void

    init(makeService: @escaping @MainActor () -> BIP70PaymentService = {
             // The transport rule of the interactive BIP70 path, which fetched this request.
             BIP70PaymentService.makeForCurrentWallet(requiresHTTPS: !BIP70InteractivePolicy.allowsInsecureTransport)
         },
         authorize: @escaping @MainActor (_ spendAmount: UInt64) async throws -> Void = {
             try await SendAuthorizer().authorizeSend(spendAmount: $0)
         }) {
        self.makeService = makeService
        self.authorize = authorize
    }

    @MainActor
    func preparePaymentRequestSend(_ request: BIP70ConfirmationBox) async throws -> PreparedPaymentRequestSend {
        let confirmation = request.confirmation
        let service = makeService()
        let built = try await service.buildForSend(confirmation)
        do {
            let (debit, overflow) = confirmation.amount.addingReportingOverflow(built.prepared.fee)
            guard !overflow else { throw ExternalSendError.feeUnavailable }
            try await authorize(debit)
        } catch {
            confirmation.sendGuard.reset()
            throw error
        }
        return PreparedPaymentRequestSend(
            txidWire: Data(built.prepared.txHashDisplay.reversed()), fee: built.prepared.fee,
            sendAction: {
                let result = try await service.postAndBroadcast(built)
                WalletSendService.shared.recentSends.record(
                    txidWire: Data(result.txHashDisplay.reversed()), address: result.primaryAddress,
                    amount: result.amount, fee: result.fee)
                return result
            },
            release: { confirmation.sendGuard.reset() })
    }
}

/// The figures the old Send reads: the pooled spendable Core coins, and the Platform and Shielded credits in duffs.
struct LiveExternalSendBalances: ExternalSendBalanceReading {
    func spendableBalance(of source: SendSource) async -> UInt64? {
        await MainActor.run {
            switch source {
            case .core:
                let state = SwiftDashSDKWalletState.shared
                return state.balance == nil ? nil : state.sendableDuffs
            case .shielded:
                return PlatformAddressSyncCoordinator.shared.shieldedBalanceState.credits.map { $0 / 1000 }
            case .platform:
                return PlatformAddressSyncCoordinator.shared.platformBalanceState.credits.map { $0 / 1000 }
            case .identity:
                return DWCurrentUserIdentityInfo.shared.refreshedSnapshot().balanceCredits
            }
        }
    }
}

/// Reads the identity's credits from Platform through the running wallet, which also stores what it read.
struct LiveIdentityNetworkBalance: IdentityNetworkBalanceReading {
    func networkBalanceCredits(identityId: Data) async -> UInt64? {
        guard let wallet = await MainActor.run(body: { SwiftDashSDKHost.shared.wallet }) else { return nil }
        do {
            return try await wallet.refreshIdentityBalance(identityId: identityId)
        } catch {
            DWLogger.log("External send: the identity balance could not be read from Platform (\(type(of: error)))")
            return nil
        }
    }
}

/// What the Platform to Core withdrawal can pay out of the highest-balance row, as the coordinator's preflight
/// reports it.
struct PlatformWithdrawalCapacity: Equatable {
    let canWithdraw: Bool
    let netWithdrawableCredits: UInt64
}

/// The checks `SendAmountViewModel` and the Max planner make, read from the same sources the sends execute on.
struct LivePlatformSendFunding: PlatformSendFundingChecking {
    private let fundingCandidates: PlatformFundingCandidatesReading
    private let withdrawalCapacity: () async -> PlatformWithdrawalCapacity?
    private let readTransferAccountCredits: () async -> UInt64?
    private let readWithdrawalRowCredits: () async -> UInt64?

    init(fundingCandidates: PlatformFundingCandidatesReading = LivePlatformFundingCandidates(),
         withdrawalCapacity: @escaping () async -> PlatformWithdrawalCapacity? = {
             guard let preflight = try? await PlatformAddressSyncCoordinator.shared.preflightWithdrawal() else {
                 return nil
             }
             return PlatformWithdrawalCapacity(
                 canWithdraw: preflight.canWithdraw, netWithdrawableCredits: preflight.netWithdrawable)
         },
         transferAccountCredits: @escaping () async -> UInt64? = {
             await MainActor.run { try? PlatformAddressSyncCoordinator.shared.transferAccountCredits() }
         },
         withdrawalRowCredits: @escaping () async -> UInt64? = {
             await MainActor.run { try? PlatformAddressSyncCoordinator.shared.withdrawalRowCredits() }
         }) {
        self.fundingCandidates = fundingCandidates
        self.withdrawalCapacity = withdrawalCapacity
        self.readTransferAccountCredits = transferAccountCredits
        self.readWithdrawalRowCredits = withdrawalRowCredits
    }

    /// `withdrawToCore` spends the highest-balance row alone and holds the binding fee back from it; the account-wide
    /// preflight is what the whole-balance withdrawal (Max) pays.
    func canWithdrawToCore(amountDuffs: UInt64, feeDuffs: UInt64) async -> SendFundingCheck {
        guard let available = await readWithdrawalRowCredits() else { return .unknown }
        let (duffs, sumOverflow) = amountDuffs.addingReportingOverflow(feeDuffs)
        let (credits, overflow) = duffs.multipliedReportingOverflow(
            by: PlatformPaymentIdentityFundingPolicy.creditsPerDuff)
        guard !sumOverflow, !overflow, credits <= available else { return .notFundable }
        return .fundable
    }

    func canTransferOnPlatform(amountDuffs: UInt64, feeDuffs: UInt64) async -> SendFundingCheck {
        guard let available = await readTransferAccountCredits() else { return .unknown }
        let (duffs, sumOverflow) = amountDuffs.addingReportingOverflow(feeDuffs)
        let (credits, overflow) = duffs.multipliedReportingOverflow(
            by: PlatformPaymentIdentityFundingPolicy.creditsPerDuff)
        guard !sumOverflow, !overflow, credits <= available else { return .notFundable }
        return .fundable
    }

    func withdrawableMaxDuffs() async -> UInt64? {
        guard let capacity = await withdrawalCapacity() else { return nil }
        return capacity.canWithdraw ? capacity.netWithdrawableCredits / PlatformPaymentIdentityFundingPolicy.creditsPerDuff : 0
    }

    func canFundIdentity(amountDuffs: UInt64) async -> SendFundingCheck {
        guard let candidates = await fundingCandidates.fundingCandidates() else { return .unknown }
        return PlatformPaymentIdentityFundingPolicy.canFund(candidates: candidates, fundingDuffs: amountDuffs)
            ? .fundable : .notFundable
    }

    func transferAccountCredits() async -> UInt64? {
        await readTransferAccountCredits()
    }
}

/// The active wallet's addresses, as the top-up itself reads them
/// (`PlatformPaymentIdentityFundingPolicy.currentCandidates`).
struct LivePlatformFundingCandidates: PlatformFundingCandidatesReading {
    func fundingCandidates() async -> [PlatformPaymentIdentityFundingPolicy.Candidate]? {
        await MainActor.run { try? PlatformPaymentIdentityFundingPolicy.currentCandidates() }
    }
}

/// The same preview the Send screen's Max is planned from (`LiveSendMaxPlanner`) and the drain re-checks.
struct LiveCoreDrainPreview: CoreDrainPreviewing {
    @MainActor
    func drainPreview() async -> CoreDrainPreview? {
        guard let context = try? CoreShieldedDrainService.currentContext(),
              let manager = try? CoreShieldedDrainService().manager(for: context),
              let quote = try? await manager.shieldedWalletDrainPreview(walletId: context.walletId)
        else { return nil }
        let recipientCredits = quote.status == .insufficientFunds ? nil : quote.estimatedRecipientCredits
        return CoreDrainPreview(
            candidateDuffs: quote.candidateBalanceDuffs,
            recipientDuffs: recipientCredits.map { $0 / PlatformPaymentIdentityFundingPolicy.creditsPerDuff })
    }
}

/// The transfer ended in no terminal phase and left no error.
private struct UnfinishedTransfer: Error {}

/// A Shielded destination's raw address, only when its bech32m HRP names the running network (`dash` on mainnet,
/// `tdash` on any other), so no asset lock or SDK call runs for another network's address.
enum ShieldedDestination {
    @MainActor
    static func raw43(_ text: String, onMainnet: Bool = WalletEnvironment.isMainnet) -> Data? {
        guard let decoded = DashAddressClassifier.decodeBech32m(text), decoded.isMainnet == onMainnet,
              case .shielded(let raw43) = decoded.form else { return nil }
        return raw43
    }
}

/// Each route runs the existing asset-lock path of its destination and reads the result off it.
struct LiveCoreTwoStepSend: CoreTwoStepSending {
    private typealias CoordinatorError = ShieldedTransferCoordinator.CoordinatorError

    /// Builds the coordinator the Shielded route runs on.
    var makeCoordinator: @MainActor () -> ShieldedTransferCoordinator = { ShieldedTransferCoordinator() }

    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64, isMax: Bool
    ) async -> CoreTwoStepResult {
        switch route {
        case .coreToShielded:
            return await toShielded(destination: destination, amount: amount, feeDuffs: bindingFeeDuffs, isMax: isMax)
        case .coreToIdentity:
            return await toIdentity(destination: destination, amount: amount, platformFeeDuffs: bindingFeeDuffs)
        default:
            preconditionFailure("\(route) is not a Core asset-lock route")
        }
    }

    /// The coordinator adds the Type-18 pool fee on top of `amount`. Max drains the whole wallet to the recipient;
    /// `feeDuffs` is what Confirm showed it takes beyond the Max.
    @MainActor
    private func toShielded(
        destination: Destination, amount: UInt64, feeDuffs: UInt64, isMax: Bool
    ) async -> CoreTwoStepResult {
        guard let raw43 = ShieldedDestination.raw43(destination.text) else {
            return .failed(CoordinatorError.noShieldedAddress, assetLockRecorded: false)
        }
        let coordinator = makeCoordinator()
        if isMax {
            do {
                let confirmation = try await Self.drainConfirmation(confirmedDuffs: amount, confirmedFeeDuffs: feeDuffs)
                await coordinator.performWalletDrain(confirmation, recipient: .external(raw43: raw43))
            } catch {
                return .failed(error, assetLockRecorded: false)
            }
        } else {
            await coordinator.performAssetLock(recipientAmountDuffs: amount, recipientRaw43: raw43)
        }
        return Self.result(
            of: coordinator, fundingTypeRaw: ShieldedTransferCoordinator.shieldedAssetLockFundingType)
    }

    @MainActor
    private static func result(of coordinator: ShieldedTransferCoordinator, fundingTypeRaw: Int) -> CoreTwoStepResult {
        result(
            phase: coordinator.phase, lastFailure: coordinator.lastFailure,
            heldLock: coordinator.lastAssetLockOutPoint.map {
                HeldAssetLock(fundingTypeRaw: fundingTypeRaw, txidWire: $0.txidWire, vout: $0.vout)
            })
    }

    /// What a coordinator's asset-lock call reports once it returned. `heldLock` is the built lock the coordinator
    /// recorded and still keeps after the failure (`ShieldedTransferCoordinator.keepsLockForRetry`).
    static func result(
        phase: ShieldedTransferCoordinator.Phase, lastFailure: Error?, heldLock: HeldAssetLock?
    ) -> CoreTwoStepResult {
        switch phase {
        case .success:
            return .completed
        case .submittedUnconfirmed:
            return .unconfirmed
        default:
            let failure = lastFailure ?? UnfinishedTransfer()
            if let heldLock { return .lockHeld(heldLock, after: failure) }
            return .failed(failure, assetLockRecorded: false)
        }
    }

    /// The Max drain's confirmation, read from a fresh preview. The drain sweeps whatever is eligible when it builds,
    /// so the preview must still pay the recipient exactly the confirmed Max out of exactly the confirmed balance
    /// (Max plus fee); any change, up or down, is refused and the holder plans Max again.
    @MainActor
    private static func drainConfirmation(
        confirmedDuffs: UInt64, confirmedFeeDuffs: UInt64
    ) async throws -> CoreShieldedDrainConfirmation {
        let context = try CoreShieldedDrainService.currentContext()
        let manager = try CoreShieldedDrainService().manager(for: context)
        let quote = try await manager.shieldedWalletDrainPreview(walletId: context.walletId)
        guard drainQuoteMatches(quote, confirmedDuffs: confirmedDuffs, confirmedFeeDuffs: confirmedFeeDuffs) else {
            throw CoordinatorError.drainBalanceChanged
        }
        return CoreShieldedDrainConfirmation(context: context, quote: quote)
    }

    /// Whether a drain preview pays exactly what Confirm showed: the Max to the recipient and the fee on top of it.
    nonisolated static func drainQuoteMatches(
        _ quote: WalletDrainPreview, confirmedDuffs: UInt64, confirmedFeeDuffs: UInt64
    ) -> Bool {
        guard quote.status != .insufficientFunds, let recipientCredits = quote.estimatedRecipientCredits else {
            return false
        }
        let (confirmedCandidate, overflow) = confirmedDuffs.addingReportingOverflow(confirmedFeeDuffs)
        return !overflow
            && recipientCredits / PlatformPaymentIdentityFundingPolicy.creditsPerDuff == confirmedDuffs
            && quote.candidateBalanceDuffs == confirmedCandidate
    }

    /// Whether an asset lock may have been built when a Core top-up threw `error`. Only refusals of the lock's coin
    /// selection, and the SDK's parameter checks that run before it, prove it was not: any other failure counts as a
    /// possibly built lock (ADR-0040: doubt is `inFlight`).
    static func lockMayExist(after error: Error) -> Bool {
        if error is AssetLockInputLimit.TooManyInputsError { return false }
        switch error as? PlatformWalletError {
        case .assetLockInsufficientFunds?, .coreInsufficientFunds?, .noSelectableInputs?, .assetLockTooManyInputs?,
             .invalidParameter?:
            return false
        default:
            return true
        }
    }

    /// The lock a Core → Identity send builds: the amount plus the top-up's Platform fee, which Platform takes out of
    /// the lock, so the identity receives at least the amount. `nil` when the sum overflows.
    nonisolated static func identityTopUpLockDuffs(amountDuffs: UInt64, platformFeeDuffs: UInt64) -> UInt64? {
        let (lock, overflow) = amountDuffs.addingReportingOverflow(platformFeeDuffs)
        return overflow ? nil : lock
    }

    /// `topUpIdentityWithFunding` reports no asset-lock outpoint, so a failure is classified by its type.
    @MainActor
    private func toIdentity(destination: Destination, amount: UInt64, platformFeeDuffs: UInt64) async
        -> CoreTwoStepResult {
        // Held like the coordinator's asset-lock calls, so a removal of unconfirmed transactions cannot reload the
        // runtime under the funding call and lose the just-built lock's local record.
        guard ShieldedAssetLocksInFlight.shared.beginFundingCall() else {
            return .failed(CoordinatorError.walletReloading, assetLockRecorded: false)
        }
        defer { ShieldedAssetLocksInFlight.shared.endFundingCall() }
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            return .failed(CoordinatorError.noWallet, assetLockRecorded: false)
        }
        guard let identityId = ScriptAddressCodec.base58Decode(destination.text), identityId.count == 32 else {
            return .failed(PlatformAddressSyncCoordinator.SendError.invalidDestination, assetLockRecorded: false)
        }
        guard let lockDuffs = Self.identityTopUpLockDuffs(amountDuffs: amount, platformFeeDuffs: platformFeeDuffs)
        else {
            return .failed(PlatformAddressSyncCoordinator.SendError.invalidAmount, assetLockRecorded: false)
        }
        let check = AssetLockInputLimit.Check(
            amountDuffs: lockDuffs, inputBudget: AssetLockInputPolicy.platformInputBudget)
        do {
            try AssetLockInputLimit.requireFits(check)
            _ = try await AssetLockInputLimit.mappingRefusal(check) {
                try await wallet.topUpIdentityWithFunding(
                    identityId: identityId, amountDuffs: lockDuffs, accountIndex: 0)
            }
            return .completed
        } catch {
            return Self.identityTopUpFailure(after: error)
        }
    }

    static let coreTopUpMinimumRefusal = MinimumAmountRefusal(
        minimumCredits: DWIdentityRegistrationCoordinator.minimumCoreTopUpDuffs
            * PlatformPaymentIdentityFundingPolicy.creditsPerDuff)

    /// What a Core top-up that threw `error` reports. `toIdentity` passes a 32-byte identity id, so the SDK's
    /// invalid-parameter refusal is its minimum-amount check.
    static func identityTopUpFailure(after error: Error) -> CoreTwoStepResult {
        if case .invalidParameter? = error as? PlatformWalletError {
            return .failed(coreTopUpMinimumRefusal, assetLockRecorded: false)
        }
        return .failed(error, assetLockRecorded: lockMayExist(after: error))
    }
}

/// Each route runs the coordinator call the old Send makes and reads the result off the coordinator's phase. A failed
/// run carries its error and `handedOver: false`: `SendOutcome` decides from the error whether anything left.
struct LiveShieldedPlatformSend: ShieldedPlatformSending {
    private typealias CoordinatorError = ShieldedTransferCoordinator.CoordinatorError

    /// The send in the credits the coordinator counts.
    private struct Request {
        let route: SendRoute
        let destination: Destination
        let credits: UInt64
        /// The binding fee, held back from a full Platform withdrawal.
        let feeHeadroomCredits: UInt64
        let isMax: Bool
        let shieldedPlan: PlannedShieldedSpend?
    }

    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64, isMax: Bool,
        shieldedPlan: PlannedShieldedSpend?
    ) async -> CreditsSendResult {
        let perDuff = PlatformPaymentIdentityFundingPolicy.creditsPerDuff
        let (amountCredits, amountOverflow) = amount.multipliedReportingOverflow(by: perDuff)
        let credits = shieldedPlan?.amountCredits ?? amountCredits
        let (headroom, feeOverflow) = bindingFeeDuffs.multipliedReportingOverflow(by: perDuff)
        guard !amountOverflow, !feeOverflow else {
            return .failed(PlatformAddressSyncCoordinator.SendError.invalidAmount, handedOver: false)
        }
        return await perform(Request(
            route: route, destination: destination, credits: credits, feeHeadroomCredits: headroom, isMax: isMax,
            shieldedPlan: shieldedPlan))
    }

    @MainActor
    private func perform(_ request: Request) async -> CreditsSendResult {
        let coordinator = ShieldedTransferCoordinator()
        let refusal: CreditsSendResult?
        switch request.route {
        case .shieldedToShielded, .shieldedToCore, .shieldedToPlatform, .shieldedToIdentity:
            refusal = await performShielded(coordinator, request)
        default:
            refusal = await performPlatform(coordinator, request)
        }
        if let refusal { return refusal }
        switch coordinator.phase {
        case .success:
            return .completed
        case .submittedUnconfirmed:
            return .unconfirmed
        default:
            return .failed(coordinator.lastFailure ?? UnfinishedTransfer(), handedOver: false)
        }
    }

    /// Runs the Shielded-source coordinator call against the SDK plan prepared at Continue; a result when the call
    /// could not be made. Without an SDK plan nothing is spent.
    @MainActor
    private func performShielded(
        _ coordinator: ShieldedTransferCoordinator, _ request: Request
    ) async -> CreditsSendResult? {
        let destination = request.destination
        let plan = request.shieldedPlan?.sdkPlan
        switch request.route {
        case .shieldedToShielded:
            guard let raw43 = shieldedRaw43(destination) else { return noShieldedAddress }
            guard let plan else { return .notStarted }
            await coordinator.performShieldedTransfer(
                amountCredits: request.credits, sweepAll: request.isMax, recipientRaw43: raw43, plan: plan)
        case .shieldedToCore:
            guard let plan else { return .notStarted }
            await coordinator.performWithdraw(
                amountCredits: request.credits, sweepAll: request.isMax, toCoreAddress: destination.text, plan: plan)
        case .shieldedToPlatform:
            guard let plan else { return .notStarted }
            await coordinator.performUnshield(
                amountCredits: request.credits, sweepAll: request.isMax, toPlatformAddress: destination.text,
                plan: plan)
        case .shieldedToIdentity:
            guard let identityId = ScriptAddressCodec.base58Decode(destination.text), identityId.count == 32 else {
                return .failed(PlatformAddressSyncCoordinator.SendError.invalidDestination, handedOver: false)
            }
            guard let plan else { return .notStarted }
            await coordinator.performIdentityTopUpFromPool(
                amountCredits: request.credits, sweepAll: request.isMax, identityId: identityId, plan: plan)
        default:
            preconditionFailure("\(request.route) is not a Shielded-source coordinator route")
        }
        return nil
    }

    /// Runs the Platform-source coordinator call; a result when the call could not be made.
    @MainActor
    private func performPlatform(
        _ coordinator: ShieldedTransferCoordinator, _ request: Request
    ) async -> CreditsSendResult? {
        let destination = request.destination
        switch request.route {
        case .platformToPlatform:
            await coordinator.performPlatformSend(destination: destination.text, amountCredits: request.credits)
        case .platformToCore:
            await coordinator.performPlatformWithdraw(
                amountCredits: request.credits, fullBalance: request.isMax,
                feeHeadroomCredits: request.feeHeadroomCredits, toCoreAddress: destination.text)
        case .platformToShielded:
            guard let raw43 = shieldedRaw43(destination) else { return noShieldedAddress }
            await coordinator.performShield(amountCredits: request.credits, recipientRaw43: raw43)
        default:
            preconditionFailure("\(request.route) is not a Platform-source coordinator route")
        }
        return nil
    }

    private var noShieldedAddress: CreditsSendResult {
        .failed(CoordinatorError.noShieldedAddress, handedOver: false)
    }

    @MainActor
    private func shieldedRaw43(_ destination: Destination) -> Data? {
        ShieldedDestination.raw43(destination.text)
    }
}

/// The identity top-up from Platform credits (`IdentityCreditsTopUp.fromPlatform`, the core of the Top Up sheet). Every
/// identity, the holder's Current one too, takes the SDK's top-up for any identity (dashpay/platform#5929): it reads
/// the identity from Platform, so one Platform does not show yet is `identityNotFound` before anything is signed. A
/// missing wallet is `notStarted`; a failure carries its error.
struct LiveIdentityTopUpFromCredits: IdentityTopUpFromCreditsSending {
    /// The wallet or its store is not open, so nothing was planned or sent.
    struct WalletNotOpen: Error {}

    /// Tops up `identityId` with `amountDuffs` from the Platform addresses.
    var topUp: @MainActor (_ identityId: Data, _ amountDuffs: UInt64) async throws -> Void = Self.topUpFromPlatform

    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64
    ) async -> CreditsSendResult {
        await topUp(route: route, destination: destination, amount: amount)
    }

    @MainActor
    private func topUp(route: SendRoute, destination: Destination, amount: UInt64) async -> CreditsSendResult {
        guard let identityId = ScriptAddressCodec.base58Decode(destination.text), identityId.count == 32
        else { return .notStarted }
        precondition(route == .platformToIdentity, "\(route) is not an identity top-up from credits route")
        do {
            try await topUp(identityId, amount)
            return .completed
        } catch is WalletNotOpen {
            return .notStarted
        } catch PlatformWalletError.notFound {
            // FFI 98 here is `WalletRemovedBeforeSend`: the wallet was removed or re-created before the top-up was
            // broadcast (signing may already have run), so nothing was sent and the send starts over from preparation.
            return .notStarted
        } catch {
            // A `PlanningError` is thrown before any credits moved; `SendOutcome(error:)` reports it not sent.
            return .failed(error, handedOver: false)
        }
    }

    @MainActor
    private static func topUpFromPlatform(identityId: Data, amountDuffs: UInt64) async throws {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer
        else { throw WalletNotOpen() }
        _ = try await IdentityCreditsTopUp().fromPlatform(
            identityId: identityId, amountDuffs: amountDuffs, wallet: wallet, modelContainer: modelContainer,
            anyIdentity: true)
    }
}

/// The Current identity's credit spends the app already makes (`IdentityCreditSpend`: `withdrawCredits` as
/// `IdentityWithdrawViewModel.withdraw`, `transferCreditsToAddresses` and `transferCredits`), signed by
/// `KeychainSigner`. None of these calls reports a handed-over transition or a Max flag:
/// a failure is `handedOver: false` and `SendOutcome(error:)` decides.
struct LiveIdentityCreditsSend: IdentityCreditsSending {
    func run(
        route: SendRoute, destination: Destination, identityId: Data, amountCredits: UInt64, bindingFeeCredits: UInt64,
        isMax: Bool
    ) async -> CreditsSendResult {
        await spend(route: route, destination: destination, identityId: identityId, amountCredits: amountCredits)
    }

    @MainActor
    private func spend(
        route: SendRoute, destination: Destination, identityId: Data, amountCredits: UInt64
    ) async -> CreditsSendResult {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer
        else { return .notStarted }
        let signer = KeychainSigner(modelContainer: modelContainer)
        // The SDK hands the signer's unretained callback context to the FFI; keep it alive until every call returned.
        defer { withExtendedLifetime(signer) {} }
        do {
            switch route {
            case .identityToCore:
                let minimum = IdentityWithdrawViewModel.minimumWithdrawalCredits
                guard amountCredits >= minimum else {
                    return .failed(MinimumAmountRefusal(minimumCredits: minimum), handedOver: false)
                }
                try await IdentityCreditSpend.withdraw(
                    wallet: wallet, identityId: identityId, amountCredits: amountCredits,
                    toCoreAddress: destination.text, signer: signer)
            case .identityToPlatform:
                guard let recipient = PlatformAddressCreditOutput(
                    bech32mAddress: destination.text, credits: amountCredits, onMainnet: WalletEnvironment.isMainnet)
                else { return .failed(PlatformAddressSyncCoordinator.SendError.invalidDestination, handedOver: false) }
                try await IdentityCreditSpend.transfer(
                    wallet: wallet, identityId: identityId, to: recipient, platformAddress: destination.text,
                    signer: signer)
            case .identityToIdentity:
                guard let toIdentityId = ScriptAddressCodec.base58Decode(destination.text),
                      toIdentityId.count == 32 else {
                    return .failed(PlatformAddressSyncCoordinator.SendError.invalidDestination, handedOver: false)
                }
                try await IdentityCreditSpend.transfer(
                    wallet: wallet, identityId: identityId, toIdentityId: toIdentityId, amountCredits: amountCredits,
                    signer: signer)
            default:
                preconditionFailure("\(route) is not an Identity-source route")
            }
            return .completed
        } catch {
            return .failed(error, handedOver: false)
        }
    }
}
