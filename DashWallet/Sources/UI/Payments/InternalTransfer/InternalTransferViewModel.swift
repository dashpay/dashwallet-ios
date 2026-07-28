//
//  InternalTransferViewModel.swift
//  DashWallet
//

import Combine
import Foundation
import SwiftDashSDK
import SwiftUI

enum InternalTransferUnit: String {
    case dash
    case fiat
}

/// Every balance-to-balance route the transfer engine can execute. The
/// canonical read for validation, fees, and execution — derived from the
/// current explicit (from, to) pair, whether the screen is standalone or
/// one side is pinned by the send/receive sheet host.
enum InternalTransferRoute: Equatable {
    /// BIP44 UTXOs → asset lock → Type 18 shield.
    case coreToShielded
    /// DIP-17 credits → Type 15 shield.
    case platformToShielded
    /// Orchard notes → L1 transparent payout.
    case shieldedToCore
    /// Orchard notes → DIP-17 credits (unshield).
    case shieldedToPlatform
    /// BIP44 UTXOs → asset lock → Platform address credits (funding type 4).
    case coreToPlatform
    /// FULL-BALANCE address-credit withdrawal → L1 payout. The SDK has no
    /// partial-amount form for this route.
    case platformToCore
}

/// Shared Type-18 amount boundary for Core → Shielded transfers.
///
/// `ShieldFromAssetLock` carves its pool fee from the single-use asset-lock
/// value, so the lock must contain strictly more credits than that fee. Keep
/// the estimator here as the one source of truth for amount validation and
/// both transfer confirmation screens.
@MainActor
enum CoreToShieldedAmountPolicy {
    /// Asset-lock processing base cost folded into a ShieldFromAssetLock
    /// pool fee on top of `compute_minimum_shielded_fee`. Mirrors Rust
    /// `required_asset_lock_duff_balance_for_processing_start_for_address_funding`
    /// (50_000 duffs) × 1000 credits/duff.
    static let assetLockBaseCostCredits: UInt64 = 50_000_000

    static var poolFeeCredits: UInt64? {
        guard let shieldedFee = try? PlatformWalletManager.estimateShieldedFee(
            kind: .transfer,
            numActions: 2)
        else { return nil }

        let (total, overflow) = shieldedFee.addingReportingOverflow(assetLockBaseCostCredits)
        return overflow ? nil : total
    }

    /// User-entered Core amounts have duff precision (1000 Platform credits).
    /// The SDK rejects `amountCredits <= poolFeeCredits`, so the smallest valid
    /// value is the first whole duff strictly above the fee.
    static func minimumAmountDuffs(poolFeeCredits: UInt64) -> UInt64 {
        poolFeeCredits / 1000 + 1
    }
}

/// Shared affordability boundary for every route that spends Orchard notes.
///
/// Shielded spends debit both the requested amount and a route-specific fee.
/// Keeping the calculation here makes the inline validation, Continue gate,
/// and Max amount describe the same spendable envelope.
enum ShieldedSpendAmountPolicy {
    static func spendableCredits(
        balanceCredits: UInt64,
        feeReserveCredits: UInt64
    ) -> UInt64 {
        balanceCredits > feeReserveCredits
            ? balanceCredits - feeReserveCredits
            : 0
    }

    static func insufficientBalanceMessage(
        requestedCredits: UInt64,
        balanceCredits: UInt64,
        feeReserveCredits: UInt64
    ) -> String? {
        let spendableCredits = spendableCredits(
            balanceCredits: balanceCredits,
            feeReserveCredits: feeReserveCredits)
        guard requestedCredits > spendableCredits else { return nil }

        // The amount input supports duff precision, so report the largest
        // value the user can actually enter rather than rounding credits up.
        let spendableDuffs = spendableCredits / 1000
        let formattedSpendable =
            "\(spendableDuffs.formattedDashAmountWithoutCurrencySymbol) DASH"
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "Insufficient Shielded balance. Available to spend: %@",
                comment: "Shielded send amount exceeds spendable balance"),
            formattedSpendable)
    }
}

@MainActor
final class InternalTransferViewModel: ObservableObject {

    @Published var amountText: String = "0"
    @Published var unit: InternalTransferUnit = .dash {
        didSet {
            guard oldValue != unit else { return }
            convertAmountText(from: oldValue, to: unit)
        }
    }

    /// Standalone screen's selected source balance. Defaults to `.core`
    /// because most users have BIP44 funds before they have Platform or
    /// Shielded balance.
    @Published var source: ChainNetwork = .core {
        didSet { guard oldValue != source else { return }; routeDidChange() }
    }

    /// Fixed destination when this VM drives the receive sheet's embedded
    /// form: the balance being received into. `nil` = the standalone form.
    @Published private(set) var receiveTarget: ChainNetwork? = nil {
        didSet { guard oldValue != receiveTarget else { return }; routeDidChange() }
    }

    /// Fixed source when this VM drives the send sheet's embedded form
    /// (the balance-row out arrows): the balance being sent FROM. The To
    /// rows pick `sendTarget` among the other two balances. Mutually
    /// exclusive with `receiveTarget`; `nil` = not the send sheet.
    @Published private(set) var sendSource: ChainNetwork? = nil {
        didSet { guard oldValue != sendSource else { return }; routeDidChange() }
    }

    /// The destination balance picked on the send sheet's To rows. Only
    /// meaningful while `sendSource` is set, but reused by the standalone
    /// screen as the selected To balance as well.
    @Published var sendTarget: ChainNetwork = .shielded {
        didSet { guard oldValue != sendTarget else { return }; routeDidChange() }
    }

    /// The source balance picked on the receive sheet's From rows. Only
    /// meaningful while `receiveTarget` is set.
    @Published var receiveSource: ChainNetwork = .shielded {
        didSet { guard oldValue != receiveSource else { return }; routeDidChange() }
    }

    /// Live result of `preflightWithdrawal()` for the Platform → Core route:
    /// whether a full-balance withdrawal can fund, its net payout, and the
    /// reserved fee. `nil` while unknown (loading/failed) — affordability
    /// fails closed.
    @Published private(set) var withdrawalPreflight: ManagedPlatformAddressWallet.WithdrawalPreflight?
    private var preflightTask: Task<Void, Never>?

    /// Pins the route for the receive sheet: a transfer INTO `target`.
    /// The From rows then pick the source among the other two balances.
    func applyReceiveRoute(into target: ChainNetwork) {
        sendSource = nil
        receiveTarget = target
        receiveSource = Self.sanitizedSource(into: target, proposed: receiveSource)
    }

    /// Pins the route for the send sheet: a transfer OUT OF `from`. The To
    /// rows pick the destination among the other two balances. Default
    /// destinations follow the old direct out-arrow routes: Core and
    /// Platform default to Shielded (privacy-forward); Shielded defaults
    /// to Core.
    func applySendRoute(from source: ChainNetwork) {
        receiveTarget = nil
        sendSource = source
        sendTarget = Self.sanitizedDestination(from: source, proposed: sendTarget)
    }

    func selectStandaloneSource(_ network: ChainNetwork) {
        source = network
        sendTarget = Self.sanitizedDestination(from: network, proposed: sendTarget)
    }

    func selectStandaloneTarget(_ network: ChainNetwork) {
        sendTarget = Self.sanitizedDestination(from: source, proposed: network)
    }

    func selectSendTarget(_ network: ChainNetwork) {
        let from = sendSource ?? source
        sendTarget = Self.sanitizedDestination(from: from, proposed: network)
    }

    func selectReceiveSource(_ network: ChainNetwork) {
        guard let receiveTarget else { return }
        receiveSource = Self.sanitizedSource(into: receiveTarget, proposed: network)
    }

    /// The canonical route for validation/fees/execution.
    var route: InternalTransferRoute {
        if let source = sendSource {
            return Self.route(
                from: source,
                to: Self.sanitizedDestination(from: source, proposed: sendTarget))
        }
        if let target = receiveTarget {
            return Self.route(
                from: Self.sanitizedSource(into: target, proposed: receiveSource),
                to: target)
        }
        return Self.route(
            from: source,
            to: Self.sanitizedDestination(from: source, proposed: sendTarget))
    }

    private static func defaultDestination(for source: ChainNetwork) -> ChainNetwork {
        switch source {
        case .core, .platform:
            return .shielded
        case .shielded:
            return .core
        }
    }

    private static func defaultSource(for target: ChainNetwork) -> ChainNetwork {
        switch target {
        case .shielded:
            return .core
        case .core, .platform:
            return .shielded
        }
    }

    private static func sanitizedDestination(from source: ChainNetwork, proposed target: ChainNetwork) -> ChainNetwork {
        source == target ? defaultDestination(for: source) : target
    }

    private static func sanitizedSource(into target: ChainNetwork, proposed source: ChainNetwork) -> ChainNetwork {
        source == target ? defaultSource(for: target) : source
    }

    private static func route(from source: ChainNetwork, to target: ChainNetwork) -> InternalTransferRoute {
        switch (source, target) {
        case (.core, .shielded): return .coreToShielded
        case (.core, .platform): return .coreToPlatform
        case (.platform, .shielded): return .platformToShielded
        case (.platform, .core): return .platformToCore
        case (.shielded, .core): return .shieldedToCore
        case (.shielded, .platform): return .shieldedToPlatform
        case (.core, .core), (.platform, .platform), (.shielded, .shielded):
            return route(from: source, to: defaultDestination(for: source))
        }
    }

    /// Refreshes route-dependent async state. The Platform → Core route
    /// needs the withdrawal preflight — for the fee headroom that bounds a
    /// partial withdrawal, and for the net payout a Max (full-balance,
    /// AUTO-path) withdrawal pays out.
    private func routeDidChange() {
        guard route == .platformToCore else {
            preflightTask?.cancel()
            preflightTask = nil
            return
        }
        guard preflightTask == nil else { return }
        preflightTask = Task { [weak self] in
            let result = try? await PlatformAddressSyncCoordinator.shared.preflightWithdrawal()
            guard let self, !Task.isCancelled else { return }
            self.withdrawalPreflight = result
            self.preflightTask = nil
        }
    }

    /// Net payout of the full-balance (Max) Platform → Core withdrawal, in
    /// duffs (credits / 1000). `nil` until the preflight resolves positively.
    var platformWithdrawableDuffs: UInt64? {
        guard let preflight = withdrawalPreflight, preflight.canWithdraw else { return nil }
        return preflight.netWithdrawable / 1000
    }

    /// Upper bound (credits) for a PARTIAL Platform → Core withdrawal: the
    /// largest single address balance minus the preflighted fee headroom
    /// (the fee is deducted from that address's remaining balance). 0 until
    /// the preflight resolves — affordability fails closed.
    var partialWithdrawCapCredits: UInt64 {
        guard let preflight = withdrawalPreflight, preflight.canWithdraw else { return 0 }
        let largest = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.map(\.balance).max() ?? 0
        return largest > preflight.estimatedFee ? largest - preflight.estimatedFee : 0
    }

    /// True when the typed amount is exactly the full-balance net payout —
    /// the confirm flow then executes the AUTO (all-addresses) withdrawal
    /// instead of the single-input partial form.
    var isFullPlatformWithdrawal: Bool {
        route == .platformToCore
            && platformWithdrawableDuffs != nil
            && dashDuffsUnsigned == platformWithdrawableDuffs
    }

    /// BIP44-only Core balance in duffs — the same number as
    /// `SwiftDashSDKWalletState.balance.total`. Used to validate
    /// `.core` source transfers (which go through `shieldedFundFromAssetLock`,
    /// drawing from BIP44 UTXOs only).
    @Published private(set) var coreBalanceDuffs: UInt64 = 0

    /// DIP-17 Platform Payment credits (1e11 per DASH). Sourced from
    /// `PlatformAddressSyncCoordinator.platformBalance`. Used to validate
    /// `.platform` source transfers (which go through `shieldedShield`,
    /// drawing transparent credits directly).
    @Published private(set) var platformCredits: UInt64 = 0

    /// Real shielded balance in credits, fed by the coordinator's reconciled
    /// balance mirror. Updates whenever a shielded sync pass completes.
    @Published private(set) var shieldedBalance: UInt64 = 0

    /// True once the L1 chain sync completed (`SyncingActivityMonitor`
    /// `.syncDone`). Core-funded routes (asset locks spend BIP44 UTXOs)
    /// can't Continue before that — the UTXO set may be stale. Mirrors
    /// `SendViewModel.isChainSynced`; `WalletSendService` guards the
    /// classic path at the boundary.
    @Published private(set) var isChainSynced = SyncingActivityMonitor.shared.state == .syncDone

    private var cancellables = Set<AnyCancellable>()

    deinit {
        // The monitor holds observers strongly — remove or leak the VM.
        SyncingActivityMonitor.shared.remove(observer: self)
    }

    init() {
        SyncingActivityMonitor.shared.add(observer: self)
        coreBalanceDuffs = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        platformCredits = PlatformAddressSyncCoordinator.shared.platformBalance

        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] balance in
                self?.coreBalanceDuffs = balance?.total ?? 0
            }
            .store(in: &cancellables)

        PlatformAddressSyncCoordinator.shared.$platformBalance
            .receive(on: RunLoop.main)
            .sink { [weak self] credits in
                self?.platformCredits = credits
            }
            .store(in: &cancellables)

        shieldedBalance = PlatformAddressSyncCoordinator.shared.shieldedBalance
        PlatformAddressSyncCoordinator.shared.$shieldedBalance
            .receive(on: RunLoop.main)
            .sink { [weak self] credits in
                self?.shieldedBalance = credits
            }
            .store(in: &cancellables)
    }

    /// The raw numeric value the user has typed, with locale comma normalised
    /// to a dot. Interpretation depends on `unit` — this is *not yet* the DASH
    /// amount when in `.fiat` mode.
    private var rawTypedDecimal: Decimal {
        let sanitized = amountText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: sanitized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    var parsedDashAmount: Decimal {
        let raw = rawTypedDecimal
        switch unit {
        case .dash:
            return raw
        case .fiat:
            guard raw > 0 else { return 0 }
            return (try? CurrencyExchanger.shared.convertToDash(amount: raw, currency: App.fiatCurrency)) ?? 0
        }
    }

    /// Continue is enabled when the typed amount is > 0 AND fits in the
    /// currently-selected source bucket. Each route has its own balance
    /// envelope — asset-lock spends BIP44 duffs, transparent shield spends
    /// DIP-17 credits.
    /// True when the picked route spends Core UTXOs but the chain hasn't
    /// finished syncing — Continue stays disabled and the screen explains
    /// why (a stale UTXO set can't safely fund an asset lock).
    var isBlockedBySync: Bool {
        switch route {
        case .coreToShielded, .coreToPlatform:
            return !isChainSynced
        default:
            return false
        }
    }

    var coreToShieldedMinimumAmountDuffs: UInt64? {
        guard route == .coreToShielded,
              let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits
        else { return nil }
        return CoreToShieldedAmountPolicy.minimumAmountDuffs(
            poolFeeCredits: poolFeeCredits)
    }

    /// Inline, user-facing explanation for an amount rejected before Confirm.
    /// Zero stays quiet while the user has not entered an amount; a
    /// fee-estimation failure fails closed with a generic retry.
    var amountValidationMessage: String? {
        guard dashDuffsUnsigned > 0 else { return nil }

        switch route {
        case .coreToShielded:
            guard let minimumDuffs = coreToShieldedMinimumAmountDuffs else {
                return NSLocalizedString(
                    "There was an error, please try again later",
                    comment: "Internal transfer fee estimate unavailable")
            }
            guard dashDuffsUnsigned < minimumDuffs else { return nil }

            let formattedMinimum =
                "\(minimumDuffs.formattedDashAmountWithoutCurrencySymbol) DASH"
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "The minimum amount you can send is %@",
                    comment: "Internal transfer minimum amount"),
                formattedMinimum)

        case .shieldedToCore, .shieldedToPlatform:
            guard let reserve = feeReserveCredits else {
                return NSLocalizedString(
                    "There was an error, please try again later",
                    comment: "Shielded transfer fee estimate unavailable")
            }
            return ShieldedSpendAmountPolicy.insufficientBalanceMessage(
                requestedCredits: creditsPreview,
                balanceCredits: shieldedBalance,
                feeReserveCredits: reserve)

        default:
            return nil
        }
    }

    var canContinue: Bool {
        // Gate on duffs, not raw DASH: a sub-duff amount (e.g. 1e-9 DASH)
        // renders as 0 in the confirm sheet, so it must not enable Continue —
        // otherwise the credit routes would submit a nonzero amount while the
        // UI shows 0.
        guard dashDuffsUnsigned > 0, !isBlockedBySync else { return false }
        switch route {
        case .coreToShielded:
            // The Type-18 pool fee is carved from the asset-lock value. The
            // SDK refuses to broadcast a single-use lock at or below that fee;
            // enforce the same strict boundary before opening Confirm.
            guard let minimumDuffs = coreToShieldedMinimumAmountDuffs,
                  dashDuffsUnsigned >= minimumDuffs
            else { return false }
            return dashDuffsUnsigned <= coreBalanceDuffs
        case .coreToPlatform:
            // Asset-lock routes: the pool/processing fee is carved from the
            // locked value (not charged on top of the Core balance) and the
            // Rust side rejects an undersized lock, so no source-balance fee
            // headroom is reserved here.
            return dashDuffsUnsigned <= coreBalanceDuffs
        case .platformToShielded:
            // Shield (Type 15): the SDK's input selection requires
            // balance ≥ amount + reserve. Fail closed if the reserve is
            // unavailable. Subtraction keeps the UInt64 add overflow-safe.
            guard let reserve = feeReserveCredits else { return false }
            return platformCredits >= reserve
                && creditsPreview <= platformCredits - reserve
        case .shieldedToCore, .shieldedToPlatform:
            // Unshield/withdraw: the SDK debits amount + fee from the shielded
            // pool (recipient receives the full amount), so the balance must
            // cover amount + fee. Fail closed if the reserve is unavailable.
            guard let reserve = feeReserveCredits else { return false }
            return shieldedBalance >= reserve
                && creditsPreview <= shieldedBalance - reserve
        case .platformToCore:
            // Either the exact full-balance net payout (Max → AUTO path over
            // every address), or a partial amount within the single-input
            // cap (largest address balance − fee headroom). Fails closed
            // while the preflight is unknown.
            guard withdrawalPreflight?.canWithdraw == true else { return false }
            if isFullPlatformWithdrawal { return true }
            return creditsPreview <= partialWithdrawCapCredits
        }
    }

    /// Fixed input-selection reserve the Shield route requires ON TOP of the
    /// amount — mirrors Rust `FEE_RESERVE_CREDITS = 1_000_000_000`
    /// (rs-platform-wallet `platform_wallet.rs`; `select_shield_inputs` rejects
    /// `balance < amount + reserve`). It is a conservative selection headroom,
    /// NOT the on-chain fee (which is ~6× smaller); the unclaimed remainder
    /// stays on the source address rather than being spent.
    private static let shieldSelectionReserveCredits: UInt64 = 1_000_000_000

    /// Fee/selection headroom (credits) the SDK requires ON TOP of the amount
    /// for the active route, used by `canContinue` and Max. `nil` means the
    /// requirement is currently unavailable for a fee-reserved route → callers
    /// fail closed (block). A literal `0` (the asset-lock route) is NOT `nil` —
    /// that route reserves nothing from the source balance.
    private var feeReserveCredits: UInt64? {
        switch route {
        case .coreToShielded, .coreToPlatform:
            // Asset-lock routes reserve nothing from the source balance.
            return 0
        case .platformToShielded:
            // Shield: fixed 1e9-credit selection reserve, not the (smaller) fee.
            return Self.shieldSelectionReserveCredits
        case .shieldedToCore:
            // The withdraw/unshield fee scales with the number of spent notes;
            // the SDK recomputes it from real note selection (up to the
            // 16-action `max_shielded_transition_actions` cap) at send time.
            // Reserve that worst case so a fragmented wallet can't pass the
            // affordability check and then fail SDK note selection.
            return try? PlatformWalletManager.estimateShieldedFee(kind: .withdrawal, numActions: 16)
        case .shieldedToPlatform:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .unshield, numActions: 16)
        case .platformToCore:
            // Full-balance withdrawal: the fee is already netted out of the
            // preflight's `netWithdrawable`; no reserve on top.
            return 0
        }
    }

    /// A credit balance minus the route's fee reserve, floored at 0 — so a Max
    /// fill leaves room for the fee/headroom the SDK requires on top of the
    /// amount. Fails closed (returns 0) when the reserve is unavailable.
    private func creditsMinusFeeReserve(_ balanceCredits: UInt64) -> UInt64 {
        guard let fee = feeReserveCredits else { return 0 }
        return ShieldedSpendAmountPolicy.spendableCredits(
            balanceCredits: balanceCredits,
            feeReserveCredits: fee)
    }

    /// `parsedDashAmount` expressed as Int64 duffs, for `DashAmount` views.
    var dashDuffs: Int64 {
        Int64(parsedDashAmount.plainDashAmount)
    }

    /// Same as `dashDuffs` but unsigned, for SDK calls and balance compares
    /// (avoids re-rounding via Int64).
    var dashDuffsUnsigned: UInt64 {
        parsedDashAmount.plainDashAmount
    }

    /// Fiat-formatted DASH amount — always returns the fiat representation
    /// regardless of `unit`. Used by the confirm sheet which always shows
    /// fiat alongside the credits.
    var fiatAmountString: String {
        CurrencyExchanger.shared.fiatAmountString(for: parsedDashAmount)
    }

    /// Currency symbol for the active fiat (e.g. `$`). Used by the view to
    /// prefix the big-number text in FIAT mode.
    var primaryCurrencySymbol: String {
        NumberFormatter.fiatFormatter.currencySymbol ?? ""
    }

    /// The small grey line under the big number. Shows whichever unit is *not*
    /// currently the input unit.
    var secondaryDisplayString: String {
        switch unit {
        case .dash:
            return CurrencyExchanger.shared.fiatAmountString(for: parsedDashAmount)
        case .fiat:
            return parsedDashAmount.formattedDashAmount
        }
    }

    /// Credit amount handed to the SDK, aligned to the displayed duff precision
    /// (1 duff = 1000 credits) so the confirm sheet's DASH amount exactly equals
    /// what gets submitted — no sub-duff dust that shows as 0 but transfers a
    /// nonzero credit amount. Decimal keeps the conversion overflow-safe for
    /// absurd inputs (saturates rather than trapping).
    var creditsPreview: UInt64 {
        NSDecimalNumber(decimal: Decimal(dashDuffsUnsigned) * 1000).uint64Value
    }

    /// The transfer amount as DASH (no currency symbol), for the
    /// "You will transfer" preview line. Credits are never shown to the user;
    /// `creditsPreview` (the raw integer) is kept only for SDK args + the
    /// reverse balance check.
    var dashAmountFormatted: String {
        parsedDashAmount.formattedDashAmountWithoutCurrencySymbol
    }

    /// Formatted BIP44 balance as DASH for the balance cards — display
    /// precision only (max 5 fraction digits); full precision stays
    /// everywhere amounts are typed or submitted.
    var coreBalanceFormatted: String {
        Self.cardBalanceString(duffs: coreBalanceDuffs)
    }

    /// Formatted Platform Payment balance as DASH for the balance cards
    /// (max 5 fraction digits). The credits-to-duffs conversion is `/ 1000`
    /// (1e8 duffs per DASH vs 1e11 credits per DASH).
    var platformCreditsFormatted: String {
        Self.cardBalanceString(duffs: platformCredits / 1000)
    }

    /// Formatted live shielded balance as DASH for the balance cards
    /// (max 5 fraction digits). Credits → duffs is `/ 1000`.
    var shieldedBalanceFormatted: String {
        Self.cardBalanceString(duffs: shieldedBalance / 1000)
    }

    /// Active fiat currency code (e.g. "THB") — the amount row's second
    /// unit pill label.
    var fiatCurrencyCode: String {
        App.fiatCurrency
    }

    /// Card-row balance display: plain decimal, no grouping, at most 5
    /// fraction digits (rounded) so long balances don't wrap the card.
    /// Internal — the Send screen's source cards use the same format.
    static func cardBalanceString(duffs: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5
        return formatter.string(from: NSDecimalNumber(decimal: duffs.dashAmount))
            ?? duffs.formattedDashAmountWithoutCurrencySymbol
    }

    /// Source-aware Max fill. Keeps the same unit semantics — DASH or fiat —
    /// but draws the upper bound from whichever bucket the user picked.
    func fillMaxFromWallet() {
        let sourceDuffs: UInt64
        switch route {
        case .coreToShielded, .coreToPlatform:
            // Fee-aware max: spendable minus the send fee reserve (mirrors
            // DSAccount.maxOutputAmount), never the raw total — the asset-lock
            // spends core UTXOs and still needs room for the L1 fee.
            sourceDuffs = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
        case .platformToShielded:
            // Reserve the fee the SDK charges on top of the amount so Max
            // stays sendable (credits → duffs: integer divide by 1000).
            sourceDuffs = creditsMinusFeeReserve(platformCredits) / 1000
        case .shieldedToCore, .shieldedToPlatform:
            // Reverse: upper bound is the shielded balance minus the fee reserve
            // (debited on top of the amount), so Max stays sendable.
            sourceDuffs = creditsMinusFeeReserve(shieldedBalance) / 1000
        case .platformToCore:
            // Max = the full-balance net payout (executed via the AUTO,
            // all-addresses path); 0 until the preflight resolves.
            sourceDuffs = platformWithdrawableDuffs ?? 0
        }

        switch unit {
        case .dash:
            amountText = sourceDuffs.formattedDashAmountWithoutCurrencySymbol
        case .fiat:
            let dashDecimal = sourceDuffs.dashAmount
            guard dashDecimal > 0 else {
                amountText = "0"
                return
            }
            if let fiat = try? CurrencyExchanger.shared.convertDash(amount: dashDecimal, to: App.fiatCurrency) {
                amountText = Self.formatTyped(fiat, fractionDigits: 2)
            } else {
                amountText = "0"
            }
        }
    }

    // MARK: - Conversion on unit toggle

    private func convertAmountText(from old: InternalTransferUnit, to new: InternalTransferUnit) {
        let raw = rawTypedDecimal
        guard raw > 0 else { return }
        let currency = App.fiatCurrency
        do {
            switch (old, new) {
            case (.dash, .fiat):
                let fiat = try CurrencyExchanger.shared.convertDash(amount: raw, to: currency)
                amountText = Self.formatTyped(fiat, fractionDigits: 2)
            case (.fiat, .dash):
                let dash = try CurrencyExchanger.shared.convertToDash(amount: raw, currency: currency)
                amountText = Self.formatTyped(dash, fractionDigits: 8)
            default:
                break
            }
        } catch {
            // Rate fetch failed — leave `amountText` as-is so the user can re-type.
        }
    }

    /// Formats a Decimal as a user-typed-style string: no grouping separator,
    /// dot as the decimal mark, trailing zeros trimmed. Capped at
    /// `fractionDigits` decimals. Internal — reused by the Send screen's
    /// amount handling.
    static func formatTyped(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.decimalSeparator = "."
        let rounded = NSDecimalNumber(decimal: value)
        return formatter.string(from: rounded) ?? "\(value)"
    }
}


// MARK: - SyncingActivityMonitorObserver

extension InternalTransferViewModel: SyncingActivityMonitorObserver {
    nonisolated func syncingActivityMonitorProgressDidChange(_ progress: Double) {}

    nonisolated func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State,
                                                          state: SyncingActivityMonitor.State) {
        Task { @MainActor in
            self.isChainSynced = state == .syncDone
        }
    }
}
