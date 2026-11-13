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
import DashUIKit
import Foundation
import SwiftDashSDK

/// What Continue hands to the flow: the pair, the destination, the DASH amount in duffs and whether the amount
/// is the planned Max.
struct SendAmountRequest: Equatable {
    let route: SendRoute
    let destination: Destination
    let amount: UInt64
    let isMax: Bool
    /// The exact credits of the Shielded sweep plan when the amount is its Max, nil otherwise. `amount` is those
    /// credits rounded down to duffs; the coordinator checks the sweep against the credits.
    let sweepCredits: UInt64?

    init(route: SendRoute, destination: Destination, amount: UInt64, isMax: Bool, sweepCredits: UInt64? = nil) {
        self.route = route
        self.destination = destination
        self.amount = amount
        self.isMax = isMax
        self.sweepCredits = sweepCredits
    }
}

/// A route's Max: in duffs whatever the source's own unit, and for a Shielded source the sweep plan's exact
/// credits, which need not be whole duffs.
struct SendMaxPlan: Equatable {
    let duffs: UInt64
    let sweepCredits: UInt64?
}

/// The Max for one route; nil when it cannot be planned.
protocol SendMaxPlanning {
    func maxPlan(route: SendRoute) async -> SendMaxPlan?
    func canFund(route: SendRoute, amount: UInt64) async -> SendFundingCheck
}

/// DASH and local currency, as the Send screen and Select source show them. Every answer is nil without a rate.
protocol SendAmountConverting {
    func fiat(forDuffs duffs: UInt64) -> Decimal?
    /// Duffs for a local-currency amount, rounded down.
    func duffs(forFiat fiat: Decimal) -> UInt64?
    /// The local-currency value of `duffs`, formatted for display.
    func fiatText(forDuffs duffs: UInt64) -> String?
}

/// The app's rate (`CurrencyExchanger`) in the app's local currency (`App.fiatCurrency`).
struct LiveSendAmountConverter: SendAmountConverting {
    func fiat(forDuffs duffs: UInt64) -> Decimal? {
        try? CurrencyExchanger.shared.convertDash(amount: duffs.dashAmount, to: App.fiatCurrency)
    }

    func duffs(forFiat fiat: Decimal) -> UInt64? {
        guard let dash = try? CurrencyExchanger.shared.convertToDash(amount: fiat, currency: App.fiatCurrency) else {
            return nil
        }
        return SendAmountViewModel.duffs(of: dash)
    }

    func fiatText(forDuffs duffs: UInt64) -> String? {
        fiat(forDuffs: duffs)?.formattedFiatAmount
    }
}

/// Today's per-route Max of the old Send, asked once per route: the fee-aware Core maximum, the Core drain
/// preview, the Platform planners the internal transfer shares. Platform to an Identity is the most the
/// top-up's input planning can fund (`PlatformPaymentIdentityFundingPolicy.maxFundableDuffs`). A Shielded source's Max
/// is the SDK's sweep plan for the route's spend (a withdrawal's capped at Platform's largest withdrawal), which
/// Continue plans again for exactly those credits. The other routes the old Send has no Max for (Core to a Platform
/// address or an Identity) send exactly the amount, so their Max is the source balance less the Send screen's fee
/// estimate.
/// The Identity source's Max is the ViewModel's (`AmountRules.identityMax`).
struct LiveSendMaxPlanner: SendMaxPlanning {
    private let fees: SendFeeEstimating
    private let balances: ExternalSendBalanceReading
    private let fundingCandidates: PlatformFundingCandidatesReading
    private let shieldedPlans: ShieldedSpendPlanning

    nonisolated init(fees: SendFeeEstimating = ExternalSendFeeEstimator(),
                     balances: ExternalSendBalanceReading = LiveExternalSendBalances(),
                     fundingCandidates: PlatformFundingCandidatesReading = LivePlatformFundingCandidates(),
                     shieldedPlans: ShieldedSpendPlanning = LiveShieldedSpendPlanner()) {
        self.fees = fees
        self.balances = balances
        self.fundingCandidates = fundingCandidates
        self.shieldedPlans = shieldedPlans
    }

    func maxPlan(route: SendRoute) async -> SendMaxPlan? {
        switch route {
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded, .shieldedToIdentity:
            return await sweepPlan(route)
        default:
            return await maxDuffs(route: route).map { SendMaxPlan(duffs: $0, sweepCredits: nil) }
        }
    }

    /// Platform to Identity: whether the top-up's input planning (`PlatformPaymentIdentityFundingPolicy`) can fund
    /// `amount` from the addresses.
    func canFund(route: SendRoute, amount: UInt64) async -> SendFundingCheck {
        guard route == .platformToIdentity else { return .notChecked }
        guard let candidates = await fundingCandidates.fundingCandidates() else { return .unknown }
        return PlatformPaymentIdentityFundingPolicy.canFund(candidates: candidates, fundingDuffs: amount)
            ? .fundable : .notFundable
    }

    private func maxDuffs(route: SendRoute) async -> UInt64? {
        switch route {
        case .coreToCore:
            return await MainActor.run { SwiftDashSDKWalletState.shared.feeAwareMaxSendable() }
        case .coreToShielded:
            return await coreDrainMax()
        case .platformToPlatform, .platformToShielded, .platformToCore:
            return await platformMax(route)
        case .platformToIdentity:
            return await fundingCandidates.fundingCandidates().map {
                PlatformPaymentIdentityFundingPolicy.maxFundableDuffs(candidates: $0)
            }
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded, .shieldedToIdentity, .identityToCore,
             .identityToPlatform, .identityToIdentity, .identityToShielded:
            return nil
        case .coreToPlatform, .coreToIdentity:
            return await balanceLessFee(route)
        }
    }

    /// `nil` when the balance or the fee cannot be read; 0 when the fee takes the whole balance.
    private func balanceLessFee(_ route: SendRoute) async -> UInt64? {
        guard let balance = await balances.spendableBalance(of: route.source),
              case .fee(let fee, _) = await fees.estimate(route: route, amount: balance) else { return nil }
        return balance > fee ? balance - fee : 0
    }

    private func platformMax(_ route: SendRoute) async -> UInt64? {
        let coordinator = PlatformAddressSyncCoordinator.shared
        switch route {
        case .platformToPlatform:
            let credits = await MainActor.run { coordinator.platformBalanceState.credits }
            return credits.map {
                TransferSpendAmountPolicy.spendableCredits(
                    balanceCredits: $0, feeReserveCredits: SendViewModel.platformTransferFeeReserveCredits) / 1000
            }
        case .platformToShielded:
            guard let preflight = try? await coordinator.preflightShield() else { return nil }
            return PlatformShieldAmountPolicy.maximumDuffs(capacity: PlatformShieldCapacity(preflight))
        default:
            guard let preflight = try? await coordinator.preflightWithdrawal() else { return nil }
            return preflight.canWithdraw ? preflight.netWithdrawable / 1000 : 0
        }
    }

    /// The same one-shot quote the controller's `refresh` takes, without its recovery states: a Max transfer
    /// still pending is for the old Send's Resume to finish, so there is no amount to plan.
    @MainActor
    private func coreDrainMax() async -> UInt64? {
        do {
            let context = try CoreShieldedDrainService.currentContext()
            let service = CoreShieldedDrainService()
            guard try service.store.load(context) == nil else { return nil }
            let quote = try await service.manager(for: context).shieldedWalletDrainPreview(walletId: context.walletId)
            let estimate = CoreShieldedDrainMaxController.estimate(from: quote, insufficientFundsMessage: { "" })
            return estimate.isConfirmable ? (estimate.amountDuffs ?? 0) : 0
        } catch {
            return nil
        }
    }

    /// nil when the notes cannot pay a sweep's fee or the plan cannot be read.
    private func sweepPlan(_ route: SendRoute) async -> SendMaxPlan? {
        guard let plan = try? await shieldedPlans.plan(route: route, amount: .sweepAll) else { return nil }
        return SendMaxPlan(
            duffs: plan.amountCredits / PlatformPaymentIdentityFundingPolicy.creditsPerDuff,
            sweepCredits: plan.amountCredits)
    }
}

/// SCR-04 Send: the source, the amount in DASH or local currency, Max and the fee estimate for the pair.
/// The amount is always held in duffs; the typed text is only how it is shown.
@MainActor
final class SendAmountViewModel: ObservableObject {
    enum State: Equatable {
        case amountEmpty
        case estimating
        case feeFailed
        /// The amount is above the balance less the fee or more than the route's funding step can pay, or the source
        /// holds nothing.
        case notEnough
        /// A Core top-up of an Identity below the SDK's minimum (`DWIdentityRegistrationCoordinator`).
        case belowMinimum
        case ready
    }

    /// What Send knows about the source; `state` and Continue derive from it.
    @Published private(set) var facts = SourceFacts(source: .core, route: nil)
    @Published private(set) var unit: InternalTransferUnit = .dash
    @Published private(set) var amountText = ""
    @Published private(set) var amountDuffs: UInt64 = 0
    /// The note that says why the source was changed, until the holder picks a source.
    @Published private(set) var sourceChangedNotice: String?
    /// Continue's handler is still running (it authenticates and prepares the send).
    @Published private var isContinuing = false
    /// A restored wallet's first sync is still running (`WalletSendService.isBlockedByInitialRestoreSync`).
    @Published private var isInitialRestoreSyncRunning = false
    private var initialRestoreSyncCancellable: AnyCancellable?
    private let initialRestoreSyncNow: () -> Bool

    /// Called with what Continue hands on; only when `isContinueEnabled`. Continue shows busy until it returns.
    var onContinue: ((SendAmountRequest) async -> Void)?

    private let destination: Destination
    private let pinnedSource: SendSource?
    private let recipient: IdentityRecipient?
    private let balances: ExternalSendBalanceReading
    private let feeEstimator: SendFeeEstimating
    private let maxPlanner: SendMaxPlanning
    private let converter: SendAmountConverting
    private let currentIdentity: CurrentIdentityReading
    private let ownShieldedAddress: OwnShieldedAddressReading
    private var pairFacts = SendPairFacts(ownIdentityID: nil)
    /// `load` has run: the screen's `.task` runs again whenever the view reappears, and that must not reset a picked
    /// source or a typed amount.
    private var didLoad = false
    /// The source operation running: the read of a source's balance and what follows it. A newer source operation
    /// cancels it, and a cancelled one changes nothing.
    private var sourceTask: Task<Void, Never>?
    /// The amount operation running: an estimate or a Max plan. A newer one or a source operation cancels it, and a
    /// cancelled one changes nothing.
    private var amountTask: Task<Void, Never>?

    init(destination: Destination, pinnedSource: SendSource?, recipient: IdentityRecipient? = nil,
         balances: ExternalSendBalanceReading = LiveExternalSendBalances(),
         feeEstimator: SendFeeEstimating = ExternalSendFeeEstimator(),
         maxPlanner: SendMaxPlanning = LiveSendMaxPlanner(),
         converter: SendAmountConverting = LiveSendAmountConverter(),
         currentIdentity: CurrentIdentityReading = WalletCurrentIdentityReader(),
         ownShieldedAddress: OwnShieldedAddressReading = WalletOwnShieldedAddressReader(),
         initialRestoreSync: AnyPublisher<Bool, Never> = WalletSendService.coreSpendBlockedByInitialRestoreSync,
         initialRestoreSyncNow: @escaping () -> Bool = { WalletSendService.isCoreSpendBlockedByInitialRestoreSync }) {
        self.destination = destination
        self.pinnedSource = pinnedSource
        self.recipient = destination.type == .identityID ? recipient : nil
        self.balances = balances
        self.feeEstimator = feeEstimator
        self.maxPlanner = maxPlanner
        self.converter = converter
        self.currentIdentity = currentIdentity
        self.ownShieldedAddress = ownShieldedAddress
        self.initialRestoreSyncNow = initialRestoreSyncNow
        initialRestoreSyncCancellable = initialRestoreSync
            .sink { [weak self] in self?.isInitialRestoreSyncRunning = $0 }
    }

    // MARK: - What the screen shows

    var destinationTypeText: String {
        switch destination.type {
        case .coreAddress: return NSLocalizedString("Core address", comment: "External send")
        case .shieldedAddress: return NSLocalizedString("Shielded address", comment: "External send")
        case .platformAddress: return NSLocalizedString("Platform address", comment: "External send")
        case .identityID: return NSLocalizedString("Identity", comment: "External send")
        case .paymentRequest: return NSLocalizedString("Payment request", comment: "External send")
        }
    }

    /// The address with its first six and last five characters; a payment request names its host.
    var shortAddress: String { Self.shortAddress(of: destination) }
    /// A link's label or a payment request's merchant; nil when there is none.
    var destinationLabel: String? { Self.label(of: destination) }
    /// A link's message or a payment request's memo; nil when there is none.
    var destinationNote: String? { Self.note(of: destination) }

    var destinationIcon: DashUIKit.DashIconSource {
        switch destination.type {
        case .coreAddress, .paymentRequest: return DashIcon.Menu.dashLogoSquare.source
        case .shieldedAddress: return DashIcon.Features.shield.source
        case .platformAddress: return DashIcon.Features.platform.source
        case .identityID: return DashIcon.Features.identity.source
        }
    }

    var source: SendSource { facts.source }
    var route: SendRoute? { facts.route }
    /// The source's balance in duffs (an identity's credits already converted); nil while it is read or when it could
    /// not be read.
    var sourceBalanceDuffs: UInt64? {
        facts.knownBalance.map { source == .identity ? AmountRules.dashValue(of: $0) : $0 }
    }

    /// The fee estimate in the source's own unit (credits for an Identity); nil until known or when it failed.
    var fee: UInt64? { facts.knownFee }

    private var nativeBalance: UInt64? { facts.knownBalance }

    private var isMax: Bool {
        if case .planned = facts.max { return true }
        return false
    }

    /// The amount is a Max that a source or balance change plans again: planned, or being planned again. A Max tap
    /// whose plan has not landed is not one yet.
    private var isMaxAmount: Bool {
        isMax || facts.max == .replanning
    }

    var sourceTitle: String { Self.title(of: source) }

    var sourceBalanceText: String? { sourceBalanceDuffs?.formattedDashAmount }
    var sourceBalanceFiatText: String? { sourceBalanceDuffs.flatMap { converter.fiatText(forDuffs: $0) } }
    var fiatCurrencyCode: String { App.fiatCurrency }

    var isFiatAvailable: Bool { converter.fiat(forDuffs: 1) != nil }

    /// The amount in the other unit than the one typed: the local value of a DASH amount, or the DASH value of
    /// a local amount; nil while the amount is empty or without a rate.
    var secondaryAmountText: String? {
        guard amountDuffs > 0 else { return nil }
        switch unit {
        case .dash: return converter.fiatText(forDuffs: amountDuffs)
        case .fiat: return amountDuffs.formattedDashAmount
        }
    }

    /// The DASH side of the amount field, without a currency symbol.
    var dashAmountDisplay: String {
        switch unit {
        case .dash: return amountText
        case .fiat: return amountDuffs > 0 ? Self.typed(amountDuffs.dashAmount, digits: 8) : ""
        }
    }

    /// The local-currency side of the amount field, without a currency symbol.
    var fiatAmountDisplay: String {
        switch unit {
        case .fiat: return amountText
        case .dash:
            guard amountDuffs > 0, let fiat = converter.fiat(forDuffs: amountDuffs) else { return "" }
            return Self.typed(fiat, digits: 2)
        }
    }

    /// The To row's name for an Identity ID: "Your identity" or the username; nil falls back to the short ID.
    var recipientName: String? { recipient.flatMap(Self.recipientName(for:)) }

    /// The top-up note when the money goes to the Current identity (AC-12b).

    private var identityMaxResult: AmountRules.MaxResult? {
        guard source == .identity, !isAmountLocked, let nativeBalance, let fee else { return nil }
        return AmountRules.identityMax(balanceCredits: nativeBalance, feeCredits: fee)
    }

    /// Next to Max on the Identity source: why Max is off (AC-09).
    var reserveNote: String? {
        guard case .disabledReserveSpent = identityMaxResult else { return nil }
        return NSLocalizedString(
            "Everything above the DashPay reserve is already spent, so Max is off. You can still type an amount.",
            comment: "External send")
    }

    /// An Identity amount that can be sent but leaves less than the DashPay reserve (AC-09).
    var reserveWarning: String? {
        guard source == .identity, amountDuffs > 0, let fee, let nativeBalance, let credits = amountCredits,
              AmountRules.check(amount: credits, source: .identity, balance: nativeBalance, fee: fee)
              == .okWithReserveWarning else { return nil }
        return Self.reserveWarningText
    }

    var isAmountLocked: Bool { SendPairPolicy.isPaymentRequest(destination) }
    var isMaxVisible: Bool { !isAmountLocked }
    var isKeypadVisible: Bool { !isAmountLocked }

    var lockedCaption: String? {
        isAmountLocked ? NSLocalizedString("The amount is set by the payment request.", comment: "External send") : nil
    }

    /// Under the amount: why it cannot continue.
    var amountErrorMessage: String? {
        switch state {
        case .notEnough:
            return NSLocalizedString("Balance not enough", comment: "External send")
        case .belowMinimum:
            return String(format: NSLocalizedString("The minimum amount you can send is %@", comment: "External send"),
                          DWIdentityRegistrationCoordinator.minimumCoreTopUpDuffs.formattedDashAmount)
        case .amountEmpty, .estimating, .feeFailed, .ready:
            return nil
        }
    }

    var feeFailureMessage: String? {
        state == .feeFailed ? Self.feeFailureText : nil
    }

    /// From `facts` and the amount alone. A balance, fee or funding check that could not be read offers Try again;
    /// an unknown balance is never taken for too little.
    var state: State {
        if facts.balance == .loading || facts.fee == .pending { return .estimating }
        if facts.fee == .failed || facts.funding == .unknown { return .feeFailed }
        if amountDuffs == 0 { return facts.balance == .known(0) ? .notEnough : .amountEmpty }
        if facts.balance == .unknown { return .feeFailed }
        if route == .coreToIdentity, amountDuffs < DWIdentityRegistrationCoordinator.minimumCoreTopUpDuffs {
            return .belowMinimum
        }
        if isMax { return facts.funding == .refused ? .notEnough : .ready }
        return isAffordable && !facts.confirmRefusedAmount ? .ready : .notEnough
    }

    /// The Core source cannot send during a restored wallet's first sync; the other sources can.
    var isBlockedBySync: Bool { source == .core && isInitialRestoreSyncRunning }

    /// A Max plan is running: its amount is not in yet.
    var isPlanningMax: Bool { facts.max == .planning || facts.max == .replanning }

    /// Off while the funding check of the amount is pending, even with a known fee.
    var isContinueEnabled: Bool {
        state == .ready && facts.funding != .pending && !isContinuing && !isBlockedBySync && !isPlanningMax
    }
    var isContinueLoading: Bool { state == .estimating || isContinuing }
    /// Off while a Max plan runs, so a second tap cannot start a plan that races the first one.
    var isMaxEnabled: Bool {
        !isAmountLocked && !isPlanningMax && state != .estimating && state != .feeFailed
            && identityMaxResult != .disabledReserveSpent
    }

    // MARK: - Actions

    /// The linked amount is filled before the first await, in the unit on screen then, and the starting source is
    /// applied only when the user picked none while the reads ran: input made during loading is newer and stays.
    func load() async {
        guard !didLoad else { return }
        didLoad = true
        if let linked = destination.amountDuffs {
            amountDuffs = linked
            amountText = unit == .dash ? Self.typed(linked.dashAmount, digits: 8) : shownText(forDuffs: linked)
        }
        // A source operation: a source picked while the balances are read cancels it, and the pick stays.
        sourceTask?.cancel()
        let reading = Task {
            pairFacts = SendPairFacts(
                ownIdentityID: await currentIdentity.currentIdentity()?.id,
                ownShieldedRaw43: await ownShieldedAddress.ownShieldedAddress())
            let core = await balances.spendableBalance(of: .core)
            let shielded = await balances.spendableBalance(of: .shielded)
            let platform = await balances.spendableBalance(of: .platform)
            guard !Task.isCancelled else { return }
            let starting = SendPairPolicy.startingSource(
                destination: destination, balances: SendBalances(core: core, shielded: shielded, platform: platform),
                pinned: pinnedSource, facts: pairFacts)
            await readSource(starting.source) {
                self.sourceChangedNotice = starting.sourceChanged
                    ? self.changedNotice(replacing: self.pinnedSource, with: starting.source) : nil
                await self.runEstimate()
            }
        }
        sourceTask = reading
        await reading.value
    }

    func setUnit(_ newUnit: InternalTransferUnit) {
        guard newUnit != unit, newUnit == .dash || isFiatAvailable else { return }
        unit = newUnit
        guard amountDuffs > 0 else {
            amountText = ""
            return
        }
        amountText = shownText(forDuffs: amountDuffs)
    }

    func setAmountText(_ text: String) async {
        guard !isAmountLocked else { return }
        let value = Decimal(string: text.replacingOccurrences(of: ",", with: "."),
                            locale: Locale(identifier: "en_US_POSIX")) ?? 0
        amountText = text
        facts.max = nil
        facts.confirmRefusedAmount = false
        switch unit {
        case .dash: amountDuffs = Self.duffs(of: value) ?? 0
        case .fiat: amountDuffs = value > 0 ? (converter.duffs(forFiat: value) ?? 0) : 0
        }
        await runEstimate(reusingKnownFee: true)
    }

    /// The keypad's next text. A longer text that needs more decimals than the unit has is refused; a shorter
    /// one always passes, so a unit switch cannot lock the field.
    func keypadInput(_ text: String) async {
        guard text.count < amountText.count
            || InternalTransferViewModel.typedTextFitsPrecision(text, unit: unit) else { return }
        await setAmountText(text)
    }

    func tapMax() async {
        guard isMaxEnabled, await planMax() else { return }
        await runEstimate()
    }

    func pickSource(_ newSource: SendSource) async {
        guard case .route = SendPairPolicy.decide(source: newSource, destination: destination, facts: pairFacts) else {
            return
        }
        sourceChangedNotice = nil
        let wasMax = isMaxAmount
        await readSource(newSource, max: wasMax ? .replanning : nil) {
            if wasMax {
                // The Identity Max is planned from the fee, so it needs the new route's fee, not the old one's.
                if newSource == .identity { guard await self.runEstimate() else { return } }
                guard await self.planMax() else { return }
            }
            await self.runEstimate()
        }
    }

    /// Confirm found the balance no longer covers the binding fee: read the balance again, plan a Max amount
    /// again and estimate once more. A typed amount stays not enough until it or the source changes.
    func confirmReportedNotEnough() async {
        let wasMax = isMaxAmount
        await readSource(source, max: wasMax ? .replanning : nil, confirmRefusedAmount: !wasMax) {
            if wasMax { guard await self.planMax() else { return } }
            self.facts.confirmRefusedAmount = !self.isMax
            await self.runEstimate()
        }
    }

    /// The send was refused for the restore sync: reads the gate again, as the refusal can come before its sync state
    /// change reaches Send.
    func confirmReportedRestoreSync() {
        isInitialRestoreSyncRunning = initialRestoreSyncNow()
    }

    /// Confirm could not read the binding fee or the balance: Send shows that the fee could not be calculated, and
    /// Try again estimates anew.
    func confirmReportedFeeFailure() {
        facts.fee = .failed
    }

    /// Estimates again, and reads the balance again first when it could not be read. A Max re-plan it overtakes
    /// ends, so the amount stays as typed.
    func retryFee() async {
        if facts.max == .replanning { facts.max = nil }
        guard facts.balance == .unknown else {
            await runEstimate()
            return
        }
        await readSource(source, max: facts.max, confirmRefusedAmount: facts.confirmRefusedAmount) {
            await self.runEstimate()
        }
    }

    func proceed() async {
        guard isContinueEnabled, let route else { return }
        isContinuing = true
        defer { isContinuing = false }
        var sweepCredits: UInt64?
        if case .planned(let credits) = facts.max { sweepCredits = credits }
        await onContinue?(SendAmountRequest(route: route, destination: destination, amount: amountDuffs, isMax: isMax,
                                            sweepCredits: sweepCredits))
    }

    #if DEBUG
    /// Lets a SwiftUI preview show a state without the balance, estimate and Max readers.
    func setPreview(source: SendSource, balanceDuffs: UInt64?, unit: InternalTransferUnit = .dash,
                    amountText: String, amountDuffs: UInt64, fee: UInt64?, isMax: Bool = false,
                    isEstimating: Bool = false, estimateFailed: Bool = false,
                    sourceChangedNotice: String? = nil, initialRestoreSyncRunning: Bool = false,
                    ownIdentityID: String? = nil) {
        pairFacts = SendPairFacts(ownIdentityID: ownIdentityID)
        let route = SendPairPolicy.decide(source: source, destination: destination, facts: pairFacts).route
        var preview = SourceFacts(source: source, route: route)
        preview.balance = balanceDuffs.map { .known($0) } ?? .unknown
        preview.fee = isEstimating ? .pending : estimateFailed ? .failed : fee.map { .known($0) } ?? .failed
        preview.funding = .ok
        preview.max = isMax ? .planned(sweepCredits: nil) : nil
        facts = preview
        self.unit = unit
        self.amountText = amountText
        self.amountDuffs = amountDuffs
        self.sourceChangedNotice = sourceChangedNotice
        isInitialRestoreSyncRunning = initialRestoreSyncRunning
    }
    #endif

    // MARK: - Internals

    static let feeFailureText = NSLocalizedString(
        "Couldn't calculate the network fee. Check your connection and try again.", comment: "External send")

    // swiftlint:disable line_length
    static let reserveWarningText = NSLocalizedString(
        "This leaves less than the DashPay reserve. DashPay actions, like contact requests and profile updates, may stop working.", comment: "External send")
    // swiftlint:enable line_length

    /// The address with its first six and last five characters; a payment request names its host.
    static func shortAddress(of destination: Destination) -> String {
        let text = destination.text.isEmpty ? (destination.paymentRequestURL?.host ?? "") : destination.text
        guard text.count > 12 else { return text }
        return text.prefix(6) + "…" + text.suffix(5)
    }

    /// The whole address, then a payment request's URL on a line of its own.
    static func fullAddress(of destination: Destination) -> String {
        [destination.text, destination.paymentRequestURL?.absoluteString ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The label, sanitized and prefixed with 🔒 when a payment request's merchant verified, as the old Send does.
    static func label(of destination: Destination) -> String? {
        guard let label = sanitized(destination.label) else { return nil }
        return destination.isVerifiedMerchant ? "🔒 " + label : label
    }

    static func note(of destination: Destination) -> String? {
        sanitized(destination.message)
    }

    /// The text the sender wrote, with every non-ASCII character spelled out by its Unicode name (a 🔒 reads
    /// `\N{LOCK}`), as the old Send shows a merchant name and memo, so no label can pass for the verified lock.
    private static func sanitized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed.spellingOutUnicodeNames
    }

    /// "Your identity" or the username of an Identity ID recipient; nil when it has neither.
    static func recipientName(for recipient: IdentityRecipient) -> String? {
        recipient.isOwnCurrentIdentity
            ? NSLocalizedString("Your identity", comment: "External send") : recipient.username
    }

    /// The top-up note Confirm shows when the money goes to the Current identity (AC-12b); nil for someone else's
    /// identity. The Send screen does not repeat it.
    static func recipientNotice(for recipient: IdentityRecipient) -> String? {
        guard recipient.isOwnCurrentIdentity else { return nil }
        return NSLocalizedString("This tops up your own Identity credits.", comment: "External send")
    }

    nonisolated static func title(of source: SendSource) -> String {
        switch source {
        case .core: return NSLocalizedString("Core", comment: "External send")
        case .shielded: return NSLocalizedString("Shielded", comment: "External send")
        case .platform: return NSLocalizedString("Platform", comment: "External send")
        case .identity: return NSLocalizedString("Identity", comment: "External send")
        }
    }

    /// Whole duffs of a DASH amount; nil when it does not fit in `UInt64`.
    nonisolated static func duffs(of dash: Decimal) -> UInt64? {
        let scaled = (dash * .duffs).whole
        guard scaled >= 0, scaled <= Decimal(UInt64.max) else { return nil }
        return NSDecimalNumber(decimal: scaled).uint64Value
    }

    private static func typed(_ value: Decimal, digits: Int) -> String {
        InternalTransferViewModel.formatTyped(value, fractionDigits: digits)
    }

    private var isAffordable: Bool {
        guard let fee, let nativeBalance else { return false }
        guard let native = source == .identity ? amountCredits : amountDuffs else { return false }
        return facts.funding != .refused
            && AmountRules.check(amount: native, source: source, balance: nativeBalance, fee: fee) != .notEnough
    }

    /// The amount in credits; nil when it does not fit in `UInt64`, which no identity balance can cover.
    private var amountCredits: UInt64? {
        let (credits, overflow) = amountDuffs.multipliedReportingOverflow(
            by: PlatformPaymentIdentityFundingPolicy.creditsPerDuff)
        return overflow ? nil : credits
    }

    /// "<why the pinned source could not pay>, so the source was changed to <new source>."
    private func changedNotice(replacing pinned: SendSource?, with replacement: SendSource) -> String? {
        guard let pinned,
              case .unavailable(let reason) = SendPairPolicy.decide(
                  source: pinned, destination: destination, facts: pairFacts) else { return nil }
        let name = Self.title(of: replacement)
        return String(format: NSLocalizedString("%@, so the source was changed to %@.", comment: "External send"),
                      reason.localizedMessage, name)
    }

    /// A source operation: cancels the running operations, starts a fresh snapshot for `newSource`, reads its
    /// balance, then runs `work`. A newer source operation cancels it: that one owns the snapshot and what follows,
    /// so `work` ends at the first step that reports it was overtaken, and every later step starts nothing.
    private func readSource(_ newSource: SendSource, max: SourceFacts.Max? = nil, confirmRefusedAmount: Bool = false,
                            then work: @escaping @MainActor () async -> Void) async {
        sourceTask?.cancel()
        amountTask?.cancel()
        facts = SourceFacts(
            source: newSource, route: SendPairPolicy.decide(source: newSource, destination: destination,
                                                            facts: pairFacts).route,
            max: max, confirmRefusedAmount: confirmRefusedAmount)
        let reading = Task {
            let balance = await balances.spendableBalance(of: newSource)
            guard !Task.isCancelled else { return }
            facts.balance = balance.map { .known($0) } ?? .unknown
            await work()
        }
        sourceTask = reading
        await reading.value
    }

    /// An amount operation: cancels the running one (a Max plan it overtook is dropped) and runs `work`, which
    /// changes nothing once a newer operation cancelled it. Starts nothing when its caller was cancelled. Returns
    /// false when it or its caller was overtaken, so the caller stops there.
    @discardableResult
    private func runAmountOperation(_ work: @escaping @MainActor () async -> Void) async -> Bool {
        guard !Task.isCancelled else { return false }
        amountTask?.cancel()
        if facts.max == .planning { facts.max = nil }
        let task = Task { await work() }
        amountTask = task
        await task.value
        return !task.isCancelled && !Task.isCancelled
    }

    /// The text the field shows for `duffs` in the current unit.
    private func shownText(forDuffs duffs: UInt64) -> String {
        switch unit {
        case .dash: return duffs.formattedDashAmountWithoutCurrencySymbol
        case .fiat: return converter.fiat(forDuffs: duffs).map { Self.typed($0, digits: 2) } ?? ""
        }
    }

    /// Fills the Max amount: the route's planner, or the Identity rule. When nothing can be planned the amount stays
    /// as it is and is no longer a Max, so the balance check applies to it. A plan that a source change or an amount
    /// edit overtook while it ran is dropped: its amount is not for the route or the amount now on screen. Returns
    /// false when it was overtaken.
    @discardableResult
    private func planMax() async -> Bool {
        guard let route else { return true }
        return await runAmountOperation {
            if self.facts.max != .replanning { self.facts.max = .planning }
            let plan: SendMaxPlan?
            if self.source == .identity {
                plan = await self.identityMaxDuffs().map { SendMaxPlan(duffs: $0, sweepCredits: nil) }
            } else {
                plan = await self.maxPlanner.maxPlan(route: route)
            }
            guard !Task.isCancelled else { return }
            guard let plan else {
                self.facts.max = nil
                return
            }
            self.amountDuffs = plan.duffs
            self.amountText = plan.duffs > 0 ? self.shownText(forDuffs: plan.duffs) : ""
            self.facts.max = plan.duffs > 0 ? .planned(sweepCredits: plan.sweepCredits) : nil
        }
    }

    private func identityMaxDuffs() async -> UInt64? {
        guard let nativeBalance, let fee else { return nil }
        switch AmountRules.identityMax(balanceCredits: nativeBalance, feeCredits: fee) {
        case .amount(let credits): return AmountRules.dashValue(of: credits)
        case .disabledReserveSpent: return 0
        }
    }

    /// Estimates the fee for the route and amount and asks whether the route's funding step can pay the amount; an
    /// unknown answer fails like the fee, with Try again. An answer that a later operation has overtaken is dropped.
    /// With `reusingKnownFee`, a route whose fee ignores the amount keeps the fee it already has, without Continue
    /// turning into progress; a failed or running estimate is never reused. The funding check runs either way.
    @discardableResult
    private func runEstimate(reusingKnownFee: Bool = false) async -> Bool {
        guard let route else { return true }
        return await runAmountOperation {
            let amount = self.amountDuffs
            let reused = reusingKnownFee && route.hasAmountIndependentFee ? self.facts.knownFee : nil
            if reused == nil { self.facts.fee = .pending }
            self.facts.funding = .pending
            let result: SendFeeEstimate
            if let reused {
                result = .fee(reused)
            } else {
                result = await self.feeEstimator.estimate(route: route, amount: amount)
            }
            let fundable = await self.maxPlanner.canFund(route: route, amount: amount)
            guard !Task.isCancelled else { return }
            self.facts.funding = SourceFacts.Funding(fundable)
            switch result {
            case .fee(let value, _): self.facts.fee = .known(value)
            case .unavailable: self.facts.fee = .failed
            }
        }
    }
}

private extension SendPairDecision {
    var route: SendRoute? {
        if case .route(let route) = self { return route }
        return nil
    }
}
