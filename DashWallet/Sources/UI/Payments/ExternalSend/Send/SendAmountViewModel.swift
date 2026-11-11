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

/// Whether a route's funding step can pay an amount, on top of the balance less the fee.
enum SendFundingCheck: Equatable {
    /// The route's balance check is the balance less the fee alone.
    case notChecked
    case fundable
    case notFundable
    /// What the funding step draws on could not be read.
    case unknown
}

/// The Max for one route; nil when it cannot be planned.
protocol SendMaxPlanning {
    func maxPlan(route: SendRoute) async -> SendMaxPlan?
    func canFund(route: SendRoute, amount: UInt64) async -> SendFundingCheck
}

/// The Platform-Payment addresses a Platform to Identity top-up draws on; nil when they cannot be read.
protocol PlatformFundingCandidatesReading {
    func fundingCandidates() async -> [PlatformPaymentIdentityFundingPolicy.Candidate]?
}

/// The active wallet's addresses, as the top-up itself reads them
/// (`PlatformPaymentIdentityFundingPolicy.currentCandidates`).
struct LivePlatformFundingCandidates: PlatformFundingCandidatesReading {
    func fundingCandidates() async -> [PlatformPaymentIdentityFundingPolicy.Candidate]? {
        await MainActor.run { try? PlatformPaymentIdentityFundingPolicy.currentCandidates() }
    }
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
/// preview, the Platform and Shielded planners the internal transfer shares. Platform to an Identity is the most the
/// top-up's input planning can fund (`PlatformPaymentIdentityFundingPolicy.maxFundableDuffs`); Shielded to an Identity
/// is the sweep plan of the pool top-up. The other routes the old Send has no Max for (Core to a Platform address or
/// an Identity) send exactly the amount, so their Max is the source balance less the Send screen's fee estimate.
/// The Identity source's Max is the ViewModel's (`AmountRules.identityMax`).
struct LiveSendMaxPlanner: SendMaxPlanning {
    private let fees: SendFeeEstimating
    private let balances: ExternalSendBalanceReading
    private let fundingCandidates: PlatformFundingCandidatesReading

    nonisolated init(fees: SendFeeEstimating = ExternalSendFeeEstimator(),
                     balances: ExternalSendBalanceReading = LiveExternalSendBalances(),
                     fundingCandidates: PlatformFundingCandidatesReading = LivePlatformFundingCandidates()) {
        self.fees = fees
        self.balances = balances
        self.fundingCandidates = fundingCandidates
    }

    func maxPlan(route: SendRoute) async -> SendMaxPlan? {
        switch route {
        case .shieldedToCore:
            return await sweepPlan(.withdrawal)
        case .shieldedToPlatform:
            return await sweepPlan(.unshield)
        case .shieldedToShielded:
            return await sweepPlan(.transfer)
        case .shieldedToIdentity:
            return await sweepPlan(.identityTopUpFromPool)
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
             .identityToPlatform, .identityToIdentity:
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

    @MainActor
    private func sweepPlan(_ kind: PlatformWalletManager.ShieldedFeeKind) -> SendMaxPlan? {
        guard case .ready(let plan) = ShieldedTransferCoordinator.sweepAvailability(feeKind: kind) else {
            return nil
        }
        return SendMaxPlan(duffs: plan.amountCredits / 1000, sweepCredits: plan.amountCredits)
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
        case ready
    }

    @Published private(set) var source: SendSource = .core
    @Published private(set) var route: SendRoute?
    /// The source's balance in duffs (an identity's credits already converted); nil when it could not be read.
    @Published private(set) var sourceBalanceDuffs: UInt64?
    @Published private(set) var unit: InternalTransferUnit = .dash
    @Published private(set) var amountText = ""
    @Published private(set) var amountDuffs: UInt64 = 0
    /// The fee estimate in the source's own unit (credits for an Identity); nil until known or when it failed.
    @Published private(set) var fee: UInt64?
    @Published private var isEstimating = false
    /// The new source's balance is being read; until it lands no amount is checked against the old one.
    @Published private var isReadingBalance = false
    @Published private var isMax = false
    /// The sweep credits of the last planned Max; handed on only while the amount is that Max.
    private var maxSweepCredits: UInt64?
    /// Confirm refused this typed amount on its binding fee, which can be above Send's estimate. Holds until the
    /// amount or the source changes.
    @Published private var confirmRefusedAmount = false
    /// The route's funding step cannot pay the estimated amount (`SendMaxPlanning.canFund`).
    @Published private var fundingRefusedAmount = false
    @Published private var estimateFailed = false
    /// The note that says why the source was changed, until the holder picks a source.
    @Published private(set) var sourceChangedNotice: String?
    /// Continue's handler is still running (it authenticates and prepares the send).
    @Published private var isContinuing = false

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
    private var facts = SendPairFacts(ownIdentityID: nil)
    /// The source's balance in its own unit, for `AmountRules`.
    private var nativeBalance: UInt64?
    private var estimateGeneration = 0
    /// The route `fee` was estimated for; nil while no estimate has succeeded.
    private var feeRoute: SendRoute?

    init(destination: Destination, pinnedSource: SendSource?, recipient: IdentityRecipient? = nil,
         balances: ExternalSendBalanceReading = LiveExternalSendBalances(),
         feeEstimator: SendFeeEstimating = ExternalSendFeeEstimator(),
         maxPlanner: SendMaxPlanning = LiveSendMaxPlanner(),
         converter: SendAmountConverting = LiveSendAmountConverter(),
         currentIdentity: CurrentIdentityReading = WalletCurrentIdentityReader()) {
        self.destination = destination
        self.pinnedSource = pinnedSource
        self.recipient = destination.type == .identityID ? recipient : nil
        self.balances = balances
        self.feeEstimator = feeEstimator
        self.maxPlanner = maxPlanner
        self.converter = converter
        self.currentIdentity = currentIdentity
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
    var recipientNotice: String? { recipient.flatMap(Self.recipientNotice(for:)) }

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

    var feeFailureMessage: String? {
        state == .feeFailed ? Self.feeFailureText : nil
    }

    var state: State {
        if isEstimating || isReadingBalance { return .estimating }
        if estimateFailed { return .feeFailed }
        if amountDuffs == 0 { return sourceBalanceDuffs == 0 ? .notEnough : .amountEmpty }
        if isMax { return .ready }
        return isAffordable && !confirmRefusedAmount ? .ready : .notEnough
    }

    var isContinueEnabled: Bool { state == .ready && !isContinuing }
    var isContinueLoading: Bool { state == .estimating || isContinuing }
    var isMaxEnabled: Bool {
        !isAmountLocked && state != .estimating && state != .feeFailed && identityMaxResult != .disabledReserveSpent
    }

    // MARK: - Actions

    func load() async {
        facts = SendPairFacts(ownIdentityID: await currentIdentity.currentIdentity()?.id)
        let core = await balances.spendableBalance(of: .core) ?? 0
        let shielded = await balances.spendableBalance(of: .shielded) ?? 0
        let platform = await balances.spendableBalance(of: .platform) ?? 0
        let starting = SendPairPolicy.startingSource(
            destination: destination, balances: SendBalances(core: core, shielded: shielded, platform: platform),
            pinned: pinnedSource, facts: facts)
        await setSource(starting.source)
        sourceChangedNotice = starting.sourceChanged
            ? changedNotice(replacing: pinnedSource, with: starting.source) : nil
        if let linked = destination.amountDuffs {
            amountDuffs = linked
            amountText = Self.typed(linked.dashAmount, digits: 8)
        }
        await runEstimate()
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
        isMax = false
        confirmRefusedAmount = false
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
        guard isMaxEnabled else { return }
        await planMax()
        await runEstimate()
    }

    func pickSource(_ newSource: SendSource) async {
        guard case .route = SendPairPolicy.decide(source: newSource, destination: destination, facts: facts) else {
            return
        }
        sourceChangedNotice = nil
        confirmRefusedAmount = false
        startEstimating()
        await setSource(newSource)
        if isMax {
            // The Identity Max is planned from the fee, so it needs the new route's fee, not the old one's.
            if newSource == .identity { await runEstimate() }
            await planMax()
        }
        await runEstimate()
    }

    /// Confirm found the balance no longer covers the binding fee: read the balance again, plan a Max amount
    /// again and estimate once more. A typed amount stays not enough until it or the source changes.
    func confirmReportedNotEnough() async {
        confirmRefusedAmount = !isMax
        startEstimating()
        await setSource(source)
        if isMax { await planMax() }
        confirmRefusedAmount = !isMax
        await runEstimate()
    }

    /// Confirm could not read the binding fee or the balance: Send shows that the fee could not be calculated, and
    /// Try again estimates anew.
    func confirmReportedFeeFailure() {
        fee = nil
        feeRoute = nil
        estimateFailed = true
    }

    func retryFee() async {
        await runEstimate()
    }

    func proceed() async {
        guard isContinueEnabled, let route else { return }
        isContinuing = true
        defer { isContinuing = false }
        await onContinue?(SendAmountRequest(route: route, destination: destination, amount: amountDuffs, isMax: isMax,
                                            sweepCredits: isMax ? maxSweepCredits : nil))
    }

    #if DEBUG
    /// Lets a SwiftUI preview show a state without the balance, estimate and Max readers.
    func setPreview(source: SendSource, balanceDuffs: UInt64?, unit: InternalTransferUnit = .dash,
                    amountText: String, amountDuffs: UInt64, fee: UInt64?, isMax: Bool = false,
                    isEstimating: Bool = false, estimateFailed: Bool = false,
                    sourceChangedNotice: String? = nil) {
        self.source = source
        route = SendPairPolicy.decide(source: source, destination: destination, facts: facts).route
        sourceBalanceDuffs = balanceDuffs
        nativeBalance = balanceDuffs
        self.unit = unit
        self.amountText = amountText
        self.amountDuffs = amountDuffs
        self.fee = fee
        self.isMax = isMax
        self.isEstimating = isEstimating
        self.estimateFailed = estimateFailed
        self.sourceChangedNotice = sourceChangedNotice
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

    /// The top-up note when the money goes to the Current identity (AC-12b); nil for someone else's identity.
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
        return !fundingRefusedAmount
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
                  source: pinned, destination: destination, facts: facts) else { return nil }
        let name = Self.title(of: replacement)
        return String(format: NSLocalizedString("%@, so the source was changed to %@.", comment: "External send"),
                      reason.localizedMessage, name)
    }

    /// Switches the source and reads its balance again.
    private func setSource(_ newSource: SendSource) async {
        source = newSource
        route = SendPairPolicy.decide(source: newSource, destination: destination, facts: facts).route
        isReadingBalance = true
        nativeBalance = await balances.spendableBalance(of: newSource)
        isReadingBalance = false
        sourceBalanceDuffs = newSource == .identity ? nativeBalance.map(AmountRules.dashValue(of:)) : nativeBalance
    }

    /// The text the field shows for `duffs` in the current unit.
    private func shownText(forDuffs duffs: UInt64) -> String {
        switch unit {
        case .dash: return duffs.formattedDashAmountWithoutCurrencySymbol
        case .fiat: return converter.fiat(forDuffs: duffs).map { Self.typed($0, digits: 2) } ?? ""
        }
    }

    /// Fills the Max amount: the route's planner, or the Identity rule. When nothing can be planned the amount stays
    /// as it is and is no longer a Max, so the balance check applies to it.
    private func planMax() async {
        guard let route else { return }
        let planned: UInt64?
        if source == .identity {
            planned = await identityMaxDuffs()
            maxSweepCredits = nil
        } else {
            let plan = await maxPlanner.maxPlan(route: route)
            planned = plan?.duffs
            maxSweepCredits = plan?.sweepCredits
        }
        guard let planned else {
            isMax = false
            return
        }
        amountDuffs = planned
        amountText = planned > 0 ? shownText(forDuffs: planned) : ""
        isMax = planned > 0
    }

    private func identityMaxDuffs() async -> UInt64? {
        guard let nativeBalance, let fee else { return nil }
        switch AmountRules.identityMax(balanceCredits: nativeBalance, feeCredits: fee) {
        case .amount(let credits): return AmountRules.dashValue(of: credits)
        case .disabledReserveSpent: return 0
        }
    }

    /// Estimating from here on, so Continue never goes on with the old balance and fee; an estimate already running
    /// is overtaken, so its answer is dropped.
    private func startEstimating() {
        estimateGeneration += 1
        isEstimating = true
    }

    /// Estimates the fee for the route and amount and asks whether the route's funding step can pay the amount; an
    /// unknown answer fails like the fee, with Try again. An answer that a later estimate has overtaken is dropped.
    /// With `reusingKnownFee`, a route whose fee ignores the amount keeps the fee it already has, without Continue
    /// turning into progress; a failed or running estimate is never reused.
    private func runEstimate(reusingKnownFee: Bool = false) async {
        guard let route else { return }
        estimateGeneration += 1
        let generation = estimateGeneration
        let amount = amountDuffs
        let result: SendFeeEstimate
        if reusingKnownFee, route.hasAmountIndependentFee, feeRoute == route, let fee, !estimateFailed,
           !isEstimating {
            result = .fee(fee)
        } else {
            isEstimating = true
            result = await feeEstimator.estimate(route: route, amount: amount)
        }
        let fundable = await maxPlanner.canFund(route: route, amount: amount)
        guard generation == estimateGeneration else { return }
        isEstimating = false
        fundingRefusedAmount = fundable == .notFundable
        switch result {
        case .fee(let value, _) where fundable != .unknown:
            fee = value
            feeRoute = route
            estimateFailed = false
        case .fee, .unavailable:
            fee = nil
            feeRoute = nil
            estimateFailed = true
        }
    }
}

private extension SendPairDecision {
    var route: SendRoute? {
        if case .route(let route) = self { return route }
        return nil
    }
}
