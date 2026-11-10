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
}

/// The Core standard send: authenticates, then builds and signs without broadcasting.
protocol CoreStandardSending {
    func prepareStandardSend(address: String, amount: UInt64) async throws -> PreparedStandardSend
}

/// A payment request built and signed, not yet POSTed or broadcast. `send` POSTs the Payment and broadcasts, once.
@MainActor
final class PreparedPaymentRequestSend {
    /// The transaction's wire-order txid, known once it is signed.
    let txidWire: Data
    let fee: UInt64
    private var sendAction: (() async throws -> SendResult)?

    init(txidWire: Data, fee: UInt64, sendAction: @escaping () async throws -> SendResult) {
        self.txidWire = txidWire
        self.fee = fee
        self.sendAction = sendAction
    }

    /// Runs the POST + broadcast, once: a second call (or one after `discard`) gets nil.
    fileprivate func send() async throws -> SendResult? {
        guard let action = sendAction else { return nil }
        sendAction = nil
        return try await action()
    }

    fileprivate func discard() { sendAction = nil }
}

/// The Core payment-request send (BIP70): authenticates, re-fetches the request and builds and signs without
/// POSTing the Payment or broadcasting. Throws if the request's amount is not `amount`.
protocol CorePaymentRequestSending {
    @MainActor
    func preparePaymentRequestSend(
        requestURL: URL, callbackScheme: String?, amount: UInt64
    ) async throws -> PreparedPaymentRequestSend
}

enum CoreTwoStepResult {
    case completed
    /// The asset lock is recorded and the second step is not confirmed yet.
    case unconfirmed
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

/// The Shielded- and Platform-source routes to Core, Shielded and Platform destinations.
protocol ShieldedPlatformSending {
    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64, isMax: Bool
    ) async -> CreditsSendResult
}

/// The Shielded- and Platform-source routes to an Identity ID (a top-up from credits).
protocol IdentityTopUpFromCreditsSending {
    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64
    ) async -> CreditsSendResult
}

/// The Identity-source routes (the Current identity's credits to Core, a Platform address or an Identity ID). Amounts,
/// the binding fee and the identity balance are credits.
protocol IdentityCreditsSending {
    func run(
        route: SendRoute, destination: Destination, amountCredits: UInt64, bindingFeeCredits: UInt64, isMax: Bool
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

/// A send built for the exact amount with its binding fee, not yet broadcast. `discard` releases it.
@MainActor
final class PreparedExternalSend {
    enum Plan {
        case standard(PreparedStandardSend)
        case paymentRequest(PreparedPaymentRequestSend)
        case routed(destination: Destination)
    }

    let route: SendRoute
    let amount: UInt64
    let fee: UInt64
    /// The part of `fee` a Core asset lock pays the L1 miners; 0 on every other route.
    let assetLockMinerFee: UInt64
    let isMax: Bool
    /// The Core to Core transaction's wire-order txid, read when the send is prepared so it outlives the plan;
    /// nil for the routed sends.
    let txidWire: Data?
    /// The merchant's x-callback-url, set only once a payment-request send succeeded; the flow opens it.
    private(set) var callbackURL: URL?
    private var plan: Plan?

    init(route: SendRoute, amount: UInt64, fee: UInt64, assetLockMinerFee: UInt64 = 0, isMax: Bool, plan: Plan) {
        self.route = route
        self.amount = amount
        self.fee = fee
        self.assetLockMinerFee = assetLockMinerFee
        self.isMax = isMax
        switch plan {
        case .standard(let transaction): txidWire = transaction.txidWire
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

    fileprivate func opens(_ url: URL?) { callbackURL = url }
}

@MainActor
protocol ExternalSendExecuting: AnyObject {
    func prepare(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool
    ) async throws -> PreparedExternalSend
    func send(_ prepared: PreparedExternalSend) async -> SendOutcome
    func discard(_ prepared: PreparedExternalSend)
}

/// Authenticates on Continue, prepares the exact send with its binding fee, and broadcasts only in `send`.
/// Every route with a source is wired; Identity to Shielded and Identity to its own identity have no route (ADR-0041).
@MainActor
final class ExternalSendExecutor: ExternalSendExecuting {
    private let standardSend: CoreStandardSending
    private let paymentRequestSend: CorePaymentRequestSending
    private let twoStep: CoreTwoStepSending
    private let creditsSend: ShieldedPlatformSending
    private let identityTopUp: IdentityTopUpFromCreditsSending
    private let identityCredits: IdentityCreditsSending
    private let fees: SendFeeEstimating
    private let balances: ExternalSendBalanceReading
    private let drainPreview: CoreDrainPreviewing
    private let prompt: any SendAuthenticationPrompting
    private let logOutcome: (SendOutcome) -> Void

    init(
        standardSend: CoreStandardSending = LiveCoreStandardSend(),
        paymentRequestSend: CorePaymentRequestSending = LiveCorePaymentRequestSend(),
        twoStep: CoreTwoStepSending = LiveCoreTwoStepSend(),
        creditsSend: ShieldedPlatformSending = LiveShieldedPlatformSend(),
        identityTopUp: IdentityTopUpFromCreditsSending = LiveIdentityTopUpFromCredits(),
        identityCredits: IdentityCreditsSending = LiveIdentityCreditsSend(),
        fees: SendFeeEstimating = ExternalSendFeeEstimator(),
        balances: ExternalSendBalanceReading = LiveExternalSendBalances(),
        drainPreview: CoreDrainPreviewing = LiveCoreDrainPreview(),
        prompt: any SendAuthenticationPrompting = AuthenticationService.shared,
        logOutcome: @escaping (SendOutcome) -> Void = { $0.log() }
    ) {
        self.standardSend = standardSend
        self.paymentRequestSend = paymentRequestSend
        self.twoStep = twoStep
        self.creditsSend = creditsSend
        self.identityTopUp = identityTopUp
        self.identityCredits = identityCredits
        self.fees = fees
        self.balances = balances
        self.drainPreview = drainPreview
        self.prompt = prompt
        self.logOutcome = logOutcome
    }

    func prepare(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool
    ) async throws -> PreparedExternalSend {
        switch route {
        case .coreToCore:
            if let requestURL = destination.paymentRequestURL {
                return try await preparePaymentRequest(
                    url: requestURL, callbackScheme: destination.callbackScheme, amount: amount, isMax: isMax)
            }
            return try await prepareStandard(destination: destination, amount: amount, isMax: isMax)
        case .coreToShielded, .coreToPlatform, .coreToIdentity,
             .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity,
             .platformToCore, .platformToShielded, .platformToPlatform, .platformToIdentity,
             .identityToCore, .identityToPlatform, .identityToIdentity:
            return try await prepareRouted(route: route, destination: destination, amount: amount, isMax: isMax)
        }
    }

    func send(_ prepared: PreparedExternalSend) async -> SendOutcome {
        let outcome: SendOutcome
        switch prepared.takePlan() {
        case nil:
            outcome = .notSent(.failed)
        case .standard(let transaction)?:
            outcome = await broadcast(transaction)
        case .paymentRequest(let request)?:
            outcome = await sendPaymentRequest(request, into: prepared)
        case .routed(let destination)?:
            outcome = await runRouted(prepared, destination: destination)
        }
        logOutcome(outcome)
        return outcome
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
            route: .coreToCore, amount: amount, fee: transaction.fee, isMax: isMax, plan: .standard(transaction))
    }

    private func preparePaymentRequest(
        url: URL, callbackScheme: String?, amount: UInt64, isMax: Bool
    ) async throws -> PreparedExternalSend {
        let request: PreparedPaymentRequestSend
        do {
            request = try await paymentRequestSend.preparePaymentRequestSend(
                requestURL: url, callbackScheme: callbackScheme, amount: amount)
        } catch {
            throw Self.preparationError(error)
        }
        do {
            try await requireFits(route: .coreToCore, amount: amount, fee: request.fee)
        } catch {
            request.discard()
            throw error
        }
        return PreparedExternalSend(
            route: .coreToCore, amount: amount, fee: request.fee, isMax: isMax, plan: .paymentRequest(request))
    }

    /// The BIP70 send POSTs the Payment before it broadcasts, so a failure there leaves the signed bytes with the
    /// merchant; `SendOutcome(error:)` keeps whatever is not proven unsent `inFlight`.
    private func sendPaymentRequest(_ request: PreparedPaymentRequestSend, into prepared: PreparedExternalSend) async
        -> SendOutcome {
        do {
            guard let result = try await request.send() else { return .notSent(.failed) }
            prepared.opens(result.callbackURL)
            return .sent
        } catch {
            return SendOutcome(error: error)
        }
    }

    /// `PreparedStandardSend.broadcast` blocks until the network answers, so it runs off the main actor.
    private func broadcast(_ transaction: PreparedStandardSend) async -> SendOutcome {
        let result = await Task.detached { Result { try transaction.broadcast() } }.value
        switch result {
        case .success:
            return .sent
        case .failure(let error):
            return SendOutcome(error: error)
        }
    }

    private static func preparationError(_ error: Error) -> ExternalSendError {
        let nsError = error as NSError
        guard nsError.domain == WalletSendService.errorDomain else { return .feeUnavailable }
        switch WalletSendService.ErrorCode(rawValue: nsError.code) {
        case .authenticationCancelled: return .authenticationCancelled
        case .authenticationFailed: return .authenticationFailed
        default: return .feeUnavailable
        }
    }

    // MARK: - Asset-lock and credit routes

    private func prepareRouted(
        route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool
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
            try await requireFits(route: route, amount: amount, fee: fee)
        }
        return PreparedExternalSend(
            route: route, amount: amount, fee: fee, assetLockMinerFee: minerFee, isMax: isMax,
            plan: .routed(destination: destination))
    }

    /// The user authenticated on Continue, so the seam's own prompt is suppressed for the run.
    private func runRouted(_ prepared: PreparedExternalSend, destination: Destination) async -> SendOutcome {
        switch prepared.route {
        case .coreToShielded, .coreToPlatform, .coreToIdentity:
            return await runTwoStep(prepared, destination: destination)
        case .shieldedToIdentity, .platformToIdentity:
            let result = await DWIdentityAuthorizer.preauthorized {
                await identityTopUp.run(
                    route: prepared.route, destination: destination, amount: prepared.amount,
                    bindingFeeDuffs: prepared.fee)
            }
            // The Shielded top-up hands over by unshielding to an own Platform address; a failure after that leaves
            // the money there, and no recovery finishes the top-up.
            if prepared.route == .shieldedToIdentity, case .failed(_, handedOver: true) = result {
                return .movedToPlatform
            }
            return creditsOutcome(result)
        case .identityToCore, .identityToPlatform, .identityToIdentity:
            return await runCredits {
                await identityCredits.run(
                    route: prepared.route, destination: destination, amountCredits: prepared.amount,
                    bindingFeeCredits: prepared.fee, isMax: prepared.isMax)
            }
        default:
            if let refusal = Self.withdrawalMinimumRefusal(route: prepared.route, amountDuffs: prepared.amount) {
                return SendOutcome(error: refusal)
            }
            return await runCredits {
                await creditsSend.run(
                    route: prepared.route, destination: destination, amount: prepared.amount,
                    bindingFeeDuffs: prepared.fee, isMax: prepared.isMax)
            }
        }
    }

    private func runTwoStep(_ prepared: PreparedExternalSend, destination: Destination) async -> SendOutcome {
        let result = await DWIdentityAuthorizer.preauthorized {
            await twoStep.run(
                route: prepared.route, destination: destination, amount: prepared.amount,
                bindingFeeDuffs: prepared.fee - prepared.assetLockMinerFee, isMax: prepared.isMax)
        }
        switch result {
        case .completed:
            return .sent
        case .unconfirmed:
            return .inFlight
        case let .failed(error, recorded):
            return recorded ? .inFlight : SendOutcome(error: error)
        }
    }

    private func runCredits(_ run: () async -> CreditsSendResult) async -> SendOutcome {
        creditsOutcome(await DWIdentityAuthorizer.preauthorized(run))
    }

    private func creditsOutcome(_ result: CreditsSendResult) -> SendOutcome {
        switch result {
        case .completed:
            return .sent
        case .unconfirmed:
            return .inFlight
        case .notStarted:
            return .notSent(.failed)
        case let .failed(error, handedOver):
            return handedOver ? .inFlight : SendOutcome(error: error)
        }
    }

    // MARK: - Shared

    /// Platform's `min_withdrawal_amount` applies to the address and the shielded withdrawals to Core as to the
    /// identity withdrawal: below it the transition is rejected, so nothing is built.
    private static func withdrawalMinimumRefusal(route: SendRoute, amountDuffs: UInt64) -> MinimumAmountRefusal? {
        guard route == .platformToCore || route == .shieldedToCore else { return nil }
        let minimum = IdentityWithdrawViewModel.minimumWithdrawalCredits
        let (credits, overflow) = amountDuffs.multipliedReportingOverflow(
            by: PlatformPaymentIdentityFundingPolicy.creditsPerDuff)
        guard !overflow, credits < minimum else { return nil }
        return MinimumAmountRefusal(minimumCredits: minimum)
    }

    /// A Max send on these routes spends the whole balance (the sweep, the AUTO full withdrawal), so the seam works
    /// out the amount itself. A check here would refuse it: in duffs the balance rounds down and the fee rounds up.
    /// The Core wallet drain is handled in `prepareRouted`, which also sets the fee it takes.
    private static func seamSpendsWholeBalance(_ route: SendRoute) -> Bool {
        switch route {
        case .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .platformToCore:
            return true
        default:
            return false
        }
    }

    private func requireFits(route: SendRoute, amount: UInt64, fee: UInt64) async throws {
        guard let balance = await balances.spendableBalance(of: route.source) else {
            throw ExternalSendError.balanceUnavailable
        }
        if AmountRules.check(amount: amount, source: route.source, balance: balance, fee: fee) == .notEnough {
            throw ExternalSendError.balanceNotEnough
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

/// Authenticates as Core to Core does, re-fetches the request, refuses a changed amount and builds and signs it.
/// The Payment POST and the broadcast run only in the prepared send's action, then the send is recorded as the
/// interactive BIP70 coordinator records it.
struct LiveCorePaymentRequestSend: CorePaymentRequestSending {
    /// The request's amount differs from the one Confirm showed, so nothing was built.
    struct AmountChanged: Error {}

    @MainActor
    func preparePaymentRequestSend(
        requestURL: URL, callbackScheme: String?, amount: UInt64
    ) async throws -> PreparedPaymentRequestSend {
        try await SendAuthorizer().authorizeSend(spendAmount: amount)
        let service = BIP70PaymentService.makeForCurrentWallet()
        let confirmation = try await service.prepareForConfirmation(
            from: requestURL, scheme: "dash", network: try PaymentNetworkResolver.current(),
            callbackScheme: callbackScheme)
        guard confirmation.amount == amount else { throw AmountChanged() }
        let built = try await service.buildForSend(confirmation)
        return PreparedPaymentRequestSend(
            txidWire: Data(built.prepared.txHashDisplay.reversed()), fee: built.prepared.fee,
            sendAction: {
                let result = try await service.postAndBroadcast(built)
                WalletSendService.shared.recentSends.record(
                    txidWire: Data(result.txHashDisplay.reversed()), address: result.primaryAddress,
                    amount: result.amount, fee: result.fee)
                return result
            })
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

/// Each route runs the existing asset-lock path of its destination and reads the result off it.
struct LiveCoreTwoStepSend: CoreTwoStepSending {
    private typealias CoordinatorError = ShieldedTransferCoordinator.CoordinatorError

    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64, isMax: Bool
    ) async -> CoreTwoStepResult {
        switch route {
        case .coreToShielded:
            return await toShielded(destination: destination, amount: amount, isMax: isMax)
        case .coreToPlatform:
            return await toPlatform(destination: destination, amount: amount, reserveDuffs: bindingFeeDuffs)
        case .coreToIdentity:
            return await toIdentity(destination: destination, amount: amount)
        default:
            preconditionFailure("\(route) is not a Core asset-lock route")
        }
    }

    /// The coordinator adds the Type-18 pool fee on top of `amount`. Max drains the whole wallet to the recipient.
    @MainActor
    private func toShielded(destination: Destination, amount: UInt64, isMax: Bool) async -> CoreTwoStepResult {
        guard case .shielded(let raw43)? = DashAddressClassifier.decodeBech32m(destination.text)?.form else {
            return .failed(CoordinatorError.noShieldedAddress, assetLockRecorded: false)
        }
        let coordinator = ShieldedTransferCoordinator()
        if isMax {
            do {
                let confirmation = try await Self.drainConfirmation(confirmedDuffs: amount)
                await coordinator.performWalletDrain(confirmation, recipient: .external(raw43: raw43))
            } catch {
                return .failed(error, assetLockRecorded: false)
            }
        } else {
            await coordinator.performAssetLock(recipientAmountDuffs: amount, recipientRaw43: raw43)
        }
        switch coordinator.phase {
        case .success:
            return .completed
        case .submittedUnconfirmed:
            return .unconfirmed
        default:
            return .failed(
                coordinator.lastFailure ?? UnfinishedTransfer(),
                assetLockRecorded: coordinator.lastAssetLockOutPoint != nil)
        }
    }

    /// The Max drain's confirmation, read from a fresh preview. The drain sweeps whatever is eligible when it builds,
    /// so a preview that now pays the recipient more than `confirmedDuffs` is refused: that money was never shown.
    @MainActor
    private static func drainConfirmation(confirmedDuffs: UInt64) async throws -> CoreShieldedDrainConfirmation {
        let context = try CoreShieldedDrainService.currentContext()
        let manager = try CoreShieldedDrainService().manager(for: context)
        let quote = try await manager.shieldedWalletDrainPreview(walletId: context.walletId)
        guard quote.status != .insufficientFunds,
              let recipientCredits = quote.estimatedRecipientCredits,
              recipientCredits / PlatformPaymentIdentityFundingPolicy.creditsPerDuff <= confirmedDuffs
        else { throw CoordinatorError.drainBalanceChanged }
        return CoreShieldedDrainConfirmation(context: context, quote: quote)
    }

    /// The lock carries `amount` plus the reserve for the funding transition's fee; the reserve returns to an own
    /// address.
    @MainActor
    private func toPlatform(destination: Destination, amount: UInt64, reserveDuffs: UInt64) async -> CoreTwoStepResult {
        let (lockValue, overflow) = amount.addingReportingOverflow(reserveDuffs)
        guard !overflow else {
            return .failed(CoordinatorError.addressFundingFeeUnavailable, assetLockRecorded: false)
        }
        let check = AssetLockInputLimit.Check(
            amountDuffs: lockValue, inputBudget: AssetLockInputPolicy.platformInputBudget)
        let lock = AssetLockRecord()
        do {
            try AssetLockInputLimit.requireFits(check)
            try await AssetLockInputLimit.mappingRefusal(check) {
                try await PlatformAddressSyncCoordinator.shared.fundExternalFromCore(
                    destination: destination.text,
                    recipientAmountDuffs: amount,
                    lockValueDuffs: lockValue,
                    onAssetLockBuilt: { _ in lock.markBuilt() })
            }
            return .completed
        } catch {
            return .failed(error, assetLockRecorded: lock.isBuilt)
        }
    }

    /// Whether an asset lock may have been built when a Core top-up threw `error`. Only refusals of the lock's coin
    /// selection prove it was not: any other failure counts as a possibly built lock (ADR-0040: doubt is `inFlight`).
    static func lockMayExist(after error: Error) -> Bool {
        if error is AssetLockInputLimit.TooManyInputsError { return false }
        switch error as? PlatformWalletError {
        case .assetLockInsufficientFunds?, .coreInsufficientFunds?, .noSelectableInputs?, .assetLockTooManyInputs?:
            return false
        default:
            return true
        }
    }

    /// `topUpIdentityWithFunding` reports no asset-lock outpoint, so a failure is classified by its type.
    @MainActor
    private func toIdentity(destination: Destination, amount: UInt64) async -> CoreTwoStepResult {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            return .failed(CoordinatorError.noWallet, assetLockRecorded: false)
        }
        guard let identityId = ScriptAddressCodec.base58Decode(destination.text), identityId.count == 32 else {
            return .failed(PlatformAddressSyncCoordinator.SendError.invalidDestination, assetLockRecorded: false)
        }
        let check = AssetLockInputLimit.Check(
            amountDuffs: amount, inputBudget: AssetLockInputPolicy.platformInputBudget)
        do {
            try AssetLockInputLimit.requireFits(check)
            _ = try await AssetLockInputLimit.mappingRefusal(check) {
                try await wallet.topUpIdentityWithFunding(identityId: identityId, amountDuffs: amount, accountIndex: 0)
            }
            return .completed
        } catch {
            return .failed(error, assetLockRecorded: Self.lockMayExist(after: error))
        }
    }
}

/// Set from the SDK's asset-lock-built callback, which runs on the SDK's runtime thread.
private final class AssetLockRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var built = false

    var isBuilt: Bool {
        lock.lock()
        defer { lock.unlock() }
        return built
    }

    func markBuilt() {
        lock.lock()
        built = true
        lock.unlock()
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
    }

    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64, isMax: Bool
    ) async -> CreditsSendResult {
        let perDuff = PlatformPaymentIdentityFundingPolicy.creditsPerDuff
        let (credits, amountOverflow) = amount.multipliedReportingOverflow(by: perDuff)
        let (headroom, feeOverflow) = bindingFeeDuffs.multipliedReportingOverflow(by: perDuff)
        guard !amountOverflow, !feeOverflow else {
            return .failed(PlatformAddressSyncCoordinator.SendError.invalidAmount, handedOver: false)
        }
        return await perform(Request(
            route: route, destination: destination, credits: credits, feeHeadroomCredits: headroom, isMax: isMax))
    }

    @MainActor
    private func perform(_ request: Request) async -> CreditsSendResult {
        let coordinator = ShieldedTransferCoordinator()
        let refusal: CreditsSendResult?
        switch request.route {
        case .shieldedToShielded, .shieldedToCore, .shieldedToPlatform:
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

    /// Runs the Shielded-source coordinator call; a result when the call could not be made.
    @MainActor
    private func performShielded(
        _ coordinator: ShieldedTransferCoordinator, _ request: Request
    ) async -> CreditsSendResult? {
        let destination = request.destination
        switch request.route {
        case .shieldedToShielded:
            guard let raw43 = shieldedRaw43(destination) else { return noShieldedAddress }
            await coordinator.performShieldedTransfer(
                amountCredits: request.credits, sweepAll: request.isMax, recipientRaw43: raw43)
        case .shieldedToCore:
            await coordinator.performWithdraw(
                amountCredits: request.credits, sweepAll: request.isMax, toCoreAddress: destination.text)
        case .shieldedToPlatform:
            await coordinator.performUnshield(
                amountCredits: request.credits, sweepAll: request.isMax, toPlatformAddress: destination.text)
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

    private func shieldedRaw43(_ destination: Destination) -> Data? {
        guard case .shielded(let raw43)? = DashAddressClassifier.decodeBech32m(destination.text)?.form else {
            return nil
        }
        return raw43
    }
}

/// The identity top-up from Platform or Shielded credits (`IdentityCreditsTopUp`, the core of the Top Up sheet). A
/// failure before any credits moved is `notStarted`; the Shielded route is `handedOver` once its unshield step is done.
struct LiveIdentityTopUpFromCredits: IdentityTopUpFromCreditsSending {
    func run(
        route: SendRoute, destination: Destination, amount: UInt64, bindingFeeDuffs: UInt64
    ) async -> CreditsSendResult {
        await topUp(route: route, destination: destination, amount: amount)
    }

    @MainActor
    private func topUp(route: SendRoute, destination: Destination, amount: UInt64) async -> CreditsSendResult {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer,
              let identityId = ScriptAddressCodec.base58Decode(destination.text), identityId.count == 32
        else { return .notStarted }
        var handedOver = false
        let topUp = IdentityCreditsTopUp(unshieldCompleted: { handedOver = true })
        do {
            switch route {
            case .platformToIdentity:
                _ = try await topUp.fromPlatform(
                    identityId: identityId, amountDuffs: amount, wallet: wallet, modelContainer: modelContainer)
            case .shieldedToIdentity:
                _ = try await topUp.fromShielded(
                    identityId: identityId, amountDuffs: amount, wallet: wallet, modelContainer: modelContainer)
            default:
                preconditionFailure("\(route) is not an identity top-up from credits route")
            }
            return .completed
        } catch is PlatformPaymentIdentityFundingPolicy.PlanningError {
            return .notStarted
        } catch IdentityTopUpViewModel.TopUpError.noPlatformReceiveAddress {
            return .notStarted
        } catch {
            return .failed(error, handedOver: handedOver)
        }
    }
}

/// The Current identity's credit spends the app already makes: `withdrawCredits` as
/// `IdentityWithdrawViewModel.withdraw`, `transferCreditsToAddresses` and `transferCredits`, signed by
/// `KeychainSigner`. None of these calls reports a handed-over transition or a Max flag:
/// a failure is `handedOver: false` and `SendOutcome(error:)` decides.
struct LiveIdentityCreditsSend: IdentityCreditsSending {
    func run(
        route: SendRoute, destination: Destination, amountCredits: UInt64, bindingFeeCredits: UInt64, isMax: Bool
    ) async -> CreditsSendResult {
        await spend(route: route, destination: destination, amountCredits: amountCredits)
    }

    @MainActor
    private func spend(route: SendRoute, destination: Destination, amountCredits: UInt64) async -> CreditsSendResult {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let modelContainer = SwiftDashSDKHost.shared.modelContainer,
              let identityId = DWCurrentUserIdentityInfo.shared.refreshedSnapshot().identityId
        else { return .notStarted }
        let signer = KeychainSigner(modelContainer: modelContainer)
        do {
            switch route {
            case .identityToCore:
                let minimum = IdentityWithdrawViewModel.minimumWithdrawalCredits
                guard amountCredits >= minimum else {
                    return .failed(MinimumAmountRefusal(minimumCredits: minimum), handedOver: false)
                }
                try await wallet.withdrawCredits(
                    identityId: identityId, amount: amountCredits, toAddress: destination.text, signer: signer)
            case .identityToPlatform:
                guard let recipient = PlatformAddressCreditOutput(
                    bech32mAddress: destination.text, credits: amountCredits)
                else { return .failed(PlatformAddressSyncCoordinator.SendError.invalidDestination, handedOver: false) }
                _ = try await wallet.transferCreditsToAddresses(
                    fromIdentityId: identityId, recipients: [recipient], signer: signer)
            case .identityToIdentity:
                guard let toIdentityId = ScriptAddressCodec.base58Decode(destination.text),
                      toIdentityId.count == 32 else {
                    return .failed(PlatformAddressSyncCoordinator.SendError.invalidDestination, handedOver: false)
                }
                try await wallet.transferCredits(
                    fromIdentityId: identityId, toIdentityId: toIdentityId, amount: amountCredits, signer: signer)
            default:
                preconditionFailure("\(route) is not an Identity-source route")
            }
            return .completed
        } catch {
            return .failed(error, handedOver: false)
        }
    }
}
