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

    /// The balance this route spends from — the one an insufficient-funds
    /// message has to name, and the one Max draws its ceiling from.
    var source: ChainNetwork {
        switch self {
        case .coreToShielded, .coreToPlatform: return .core
        case .platformToShielded, .platformToCore: return .platform
        case .shieldedToCore, .shieldedToPlatform: return .shielded
        }
    }
}

/// Shared Type-18 amount boundary for Core → Shielded transfers.
///
/// The pool fee rides ON TOP of the typed amount: the app locks
/// `amount + pool fee`, the SDK derives `shield_amount = lock − pool_fee`,
/// so the recipient receives the full typed amount (plus a sub-duff rounding
/// remainder in their favor) and the consensus surplus stays zero. Keep the
/// estimator here as the one source of truth for amount validation and both
/// transfer confirmation screens.
@MainActor
enum CoreToShieldedAmountPolicy {
    /// Asset-lock processing base cost folded into a ShieldFromAssetLock
    /// pool fee on top of `compute_minimum_shielded_fee`. Mirrors Rust
    /// `required_asset_lock_duff_balance_for_processing_start_for_address_funding`
    /// (50_000 duffs) × 1000 credits/duff.
    static let assetLockBaseCostCredits: UInt64 = 50_000_000

    /// Cached: this is read from `amountValidationMessage` and `canContinue`,
    /// both of which a SwiftUI `body` evaluates — so an uncached property
    /// crosses into Rust on every render and every keystroke. The value is a
    /// pure function of the protocol version and the fixed `(transfer, 2)`
    /// shape, so it cannot change within a launch.
    private static var cachedPoolFeeCredits: UInt64??

    static var poolFeeCredits: UInt64? {
        if let cached = cachedPoolFeeCredits { return cached }
        guard let shieldedFee = try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(
            kind: .transfer,
            numActions: 2)
        else {
            // Not cached: a failed estimate is a transient FFI condition, and
            // caching it would keep the screen permanently unusable.
            return nil
        }

        let (total, overflow) = shieldedFee.addingReportingOverflow(assetLockBaseCostCredits)
        let value: UInt64? = overflow ? nil : total
        cachedPoolFeeCredits = .some(value)
        return value
    }

    /// Pool fee in whole duffs, rounded UP so a duff-denominated lock always
    /// covers the full credit-denominated fee.
    static func poolFeeDuffs(poolFeeCredits: UInt64) -> UInt64 {
        poolFeeCredits / 1000 + (poolFeeCredits.isMultiple(of: 1000) ? 0 : 1)
    }

    /// Current pool fee in duffs; `nil` while the estimate is unavailable —
    /// callers fail closed.
    static var currentPoolFeeDuffs: UInt64? {
        poolFeeCredits.map(poolFeeDuffs(poolFeeCredits:))
    }

    /// Fee-on-top L1 lock value that delivers exactly `amountDuffs` to the
    /// shielded recipient (plus <1000 credits of round-up remainder, in the
    /// user's favor). `nil` on UInt64 overflow — callers fail closed.
    static func lockValueDuffs(forAmountDuffs amountDuffs: UInt64, poolFeeCredits: UInt64) -> UInt64? {
        let (total, overflow) = amountDuffs.addingReportingOverflow(
            poolFeeDuffs(poolFeeCredits: poolFeeCredits))
        return overflow ? nil : total
    }
}

/// Shared fee-on-top amount boundary for Core → Platform address topups.
///
/// The address-funding ST's metered fee is deducted from the locked value
/// (the single remainder recipient absorbs `lock − fee`), so the lock is
/// inflated by a fixed headroom: the Platform balance receives at least the
/// typed amount, and the unspent headroom lands back on the same balance in
/// the user's favor. Keep the constant here as the one source of truth for
/// amount validation, Max, the confirm sheet, and the executed lock value.
@MainActor
enum CoreToPlatformAmountPolicy {
    /// Duff headroom the lock carries on top of the typed amount — the
    /// credit-denominated processing base cost expressed in whole duffs.
    static let topUpHeadroomDuffs: UInt64 =
        CoreToShieldedAmountPolicy.assetLockBaseCostCredits / 1000

    /// Fee-on-top L1 lock value that delivers at least `amountDuffs` to the
    /// wallet's Platform balance. `nil` on UInt64 overflow — callers fail
    /// closed.
    static func lockValueDuffs(forAmountDuffs amountDuffs: UInt64) -> UInt64? {
        let (total, overflow) = amountDuffs.addingReportingOverflow(topUpHeadroomDuffs)
        return overflow ? nil : total
    }
}

/// Shared affordability boundary for every transfer route, whichever balance
/// it spends.
///
/// A spend debits both the requested amount and a route-specific fee/selection
/// reserve. Keeping the calculation here makes the inline validation, the
/// Continue gate, and the Max amount describe the same spendable envelope, and
/// makes every "you don't have that much" line read the same way.
enum TransferSpendAmountPolicy {
    static func spendableCredits(
        balanceCredits: UInt64,
        feeReserveCredits: UInt64
    ) -> UInt64 {
        balanceCredits > feeReserveCredits
            ? balanceCredits - feeReserveCredits
            : 0
    }

    /// Insufficient-balance line for a credit-denominated source (Shielded
    /// notes, DIP-17 Platform credits). `balanceName` is the user-facing name
    /// of the balance being spent, so a three-balance screen says which one is
    /// short. `nil` when the amount fits.
    static func insufficientBalanceMessage(
        balanceName: String,
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
        return message(balanceName: balanceName, spendableDuffs: spendableCredits / 1000)
    }

    /// Insufficient-balance line for a duff-denominated source (the BIP44 Core
    /// balance). `spendableDuffs` is the route's real ceiling, fee reserve
    /// already deducted.
    static func insufficientBalanceMessage(
        balanceName: String,
        requestedDuffs: UInt64,
        spendableDuffs: UInt64
    ) -> String? {
        guard requestedDuffs > spendableDuffs else { return nil }
        return message(balanceName: balanceName, spendableDuffs: spendableDuffs)
    }

    private static func message(balanceName: String, spendableDuffs: UInt64) -> String {
        let formattedSpendable =
            "\(spendableDuffs.formattedDashAmountWithoutCurrencySymbol) DASH"
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "Insufficient %1$@ balance. Available to send: %2$@",
                comment: "Transfer amount exceeds the source balance"),
            balanceName,
            formattedSpendable)
    }
}

/// App-facing value copy of the SDK's Platform → Shielded preflight. Keeping
/// the policy below independent from FFI-owned types makes its duff flooring
/// and fail-closed behavior cheap to regression-test.
struct PlatformShieldCapacity: Equatable {
    let canShield: Bool
    let accountBalanceCredits: UInt64
    let usableBalanceCredits: UInt64
    let feeReserveCredits: UInt64
    let maxShieldableCredits: UInt64
    let reason: String?

    init(_ preflight: PlatformWalletManager.ShieldedShieldPreflight) {
        canShield = preflight.canShield
        accountBalanceCredits = preflight.accountBalanceCredits
        usableBalanceCredits = preflight.usableBalanceCredits
        feeReserveCredits = preflight.feeReserveCredits
        maxShieldableCredits = preflight.maxShieldableCredits
        reason = preflight.reason
    }

    init(
        canShield: Bool,
        accountBalanceCredits: UInt64,
        usableBalanceCredits: UInt64,
        feeReserveCredits: UInt64,
        maxShieldableCredits: UInt64,
        reason: String? = nil
    ) {
        self.canShield = canShield
        self.accountBalanceCredits = accountBalanceCredits
        self.usableBalanceCredits = usableBalanceCredits
        self.feeReserveCredits = feeReserveCredits
        self.maxShieldableCredits = maxShieldableCredits
        self.reason = reason
    }
}

enum PlatformShieldAmountPolicy {
    enum PreflightRefreshEvent {
        case balancePublished
        case other
    }

    /// A live Platform rejection proves the cache stale. While waiting for the
    /// requested sync, route/Max events must not immediately read that same
    /// cache again; only a balance publication re-arms preflight.
    static func shouldRefreshPreflight(
        after event: PreflightRefreshEvent,
        awaitingPlatformResync: Bool
    ) -> Bool {
        guard awaitingPlatformResync else { return true }
        if case .balancePublished = event { return true }
        return false
    }

    /// Cache freshness is independent of the currently displayed route. A
    /// Platform balance publication completes the wait even if the user has
    /// navigated elsewhere before the sync finishes.
    static func awaitingPlatformResync(
        current: Bool,
        after event: PreflightRefreshEvent
    ) -> Bool {
        if case .balancePublished = event { return false }
        return current
    }

    /// Max is the explicit escape hatch while a live rejection waits for a
    /// fresh Platform publication. At most one retry task may own `syncNow`;
    /// when it finishes without a publication, another tap may retry.
    static func shouldStartManualResync(
        awaitingPlatformResync: Bool,
        retryInFlight: Bool
    ) -> Bool {
        awaitingPlatformResync && !retryInFlight
    }

    /// Amount input and confirmation are duff-denominated, so never round an
    /// SDK credit ceiling up to an amount the transition cannot select.
    static func maximumDuffs(capacity: PlatformShieldCapacity) -> UInt64 {
        guard capacity.canShield else { return 0 }
        return capacity.maxShieldableCredits / 1000
    }

    /// Unknown/loading/failed preflight is deliberately unaffordable. The SDK
    /// preflight is the sole authority; the aggregate Platform balance is not.
    static func canSubmit(
        requestedCredits: UInt64,
        capacity: PlatformShieldCapacity?
    ) -> Bool {
        guard requestedCredits > 0,
              let capacity,
              capacity.canShield
        else { return false }
        return requestedCredits <= capacity.maxShieldableCredits
    }

    /// Informational remainder against the balance card's aggregate. The
    /// preflight account remains the validation authority; `max` only avoids a
    /// transient smaller published snapshot understating what is held back.
    static func heldBackCredits(
        displayedPlatformCredits: UInt64,
        accountBalanceCredits: UInt64,
        submittedDuffs: UInt64
    ) -> UInt64 {
        let submitted = submittedDuffs.multipliedReportingOverflow(by: 1000)
        guard !submitted.overflow else { return 0 }
        let displayedAggregate = max(displayedPlatformCredits, accountBalanceCredits)
        return displayedAggregate > submitted.partialValue
            ? displayedAggregate - submitted.partialValue
            : 0
    }

    /// A refreshed capacity may rewrite only an amount explicitly derived from
    /// Max. Manually entered text must remain untouched for the user to review.
    static func amountAfterCapacityChange(
        currentDuffs: UInt64,
        wasMaxDerived: Bool,
        maxShieldableCredits: UInt64?
    ) -> UInt64 {
        guard wasMaxDerived, let maxShieldableCredits else {
            return currentDuffs
        }
        return maxShieldableCredits / 1000
    }
}

@MainActor
final class InternalTransferViewModel: ObservableObject {

    private var isApplyingMax = false
    @Published var amountText: String = "0" {
        didSet {
            guard !isApplyingMax else { return }
            clearMaxSelection()
        }
    }
    @Published private(set) var isFullShieldedSweep = false
    /// Why Max produced the amount it did — a held-back fee, a pending sweep
    /// remainder, or why it could not produce one at all. Surfaced through
    /// `amountValidationMessage` so tapping Max is never a silent no-op.
    @Published private(set) var maxNotice: String?
    /// Exact duff amount selected by Max. Fiat text is presentation-only and
    /// may round to two decimals, so reparsing it must never move the transfer
    /// above (or below) the source's real spendable ceiling.
    private var maxAmountDuffs: UInt64?
    private var shieldedSweepAmountCredits: UInt64?
    private var isPlatformShieldMaxDerived = false
    private var isPlatformShieldMaxQueued = false
    private var hasPlatformShieldCapacityChangeNotice = false
    @Published var unit: InternalTransferUnit = .dash {
        didSet {
            guard oldValue != unit else { return }
            if let maxAmountDuffs {
                isApplyingMax = true
                defer { isApplyingMax = false }
                applyMaxAmountText(maxAmountDuffs)
            } else {
                convertAmountText(from: oldValue, to: unit)
            }
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
    private var withdrawalPreflightTask: Task<Void, Never>?

    /// SDK-owned selection capacity for Platform → Shielded. `nil` while a
    /// request is loading or after it fails; both states fail closed rather
    /// than falling back to the aggregate Platform balance.
    @Published private(set) var platformShieldCapacity: PlatformShieldCapacity?
    @Published private(set) var isPlatformShieldPreflightLoading = false
    private var platformShieldPreflightTask: Task<Void, Never>?
    private var platformShieldPreflightGeneration: UInt64 = 0
    private var awaitingPlatformShieldResync = false
    private var platformShieldManualResyncTask: Task<Void, Never>?

    /// Captured by Confirm so a capacity-change response knows whether it may
    /// replace the amount with the newly preflighted Max.
    var platformShieldAmountWasMax: Bool {
        route == .platformToShielded && isPlatformShieldMaxDerived
    }

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

    /// Endpoint picks always apply. A pick that collides with the opposite
    /// endpoint moves THAT endpoint to its default instead — the two sides
    /// can never be the same balance.
    func selectStandaloneSource(_ network: ChainNetwork) {
        source = network
        sendTarget = Self.sanitizedDestination(from: network, proposed: sendTarget)
    }

    func selectStandaloneTarget(_ network: ChainNetwork) {
        sendTarget = network
        source = Self.sanitizedSource(into: network, proposed: source)
    }

    func selectSendTarget(_ network: ChainNetwork) {
        let from = sendSource ?? source
        sendTarget = Self.sanitizedDestination(from: from, proposed: network)
    }

    func selectReceiveSource(_ network: ChainNetwork) {
        guard let receiveTarget else { return }
        receiveSource = Self.sanitizedSource(into: receiveTarget, proposed: network)
    }

    /// The To selection the pickers display: `sendTarget` guarded against
    /// ever equaling the active From — always the same endpoint `route`
    /// executes, so a radio can't highlight a balance the transfer won't use.
    var resolvedSendTarget: ChainNetwork {
        Self.sanitizedDestination(from: sendSource ?? source, proposed: sendTarget)
    }

    /// The From selection the receive sheet's pickers display, guarded
    /// against equaling the pinned destination.
    var resolvedReceiveSource: ChainNetwork {
        guard let receiveTarget else { return receiveSource }
        return Self.sanitizedSource(into: receiveTarget, proposed: receiveSource)
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

    /// Refreshes route-dependent async state. Both Platform-funded routes use
    /// SDK preflights so their UI amount always matches the builder's real
    /// input-selection envelope.
    private func routeDidChange() {
        clearMaxSelection()
        refreshShieldedSpendCeiling()

        if route == .platformToCore {
            startWithdrawalPreflightIfNeeded()
        } else {
            withdrawalPreflightTask?.cancel()
            withdrawalPreflightTask = nil
            withdrawalPreflight = nil
        }

        if route == .platformToShielded {
            refreshPlatformShieldPreflight()
        } else {
            cancelPlatformShieldPreflight()
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

    /// The most a Core-funded route can actually lock, in duffs: the fee-aware
    /// spendable balance (confirmed − InstantSend-locked − the L1 fee reserve).
    ///
    /// NOT `coreBalanceDuffs`, which is the displayed total and includes
    /// unconfirmed/immature coins the asset lock cannot spend. Validation, the
    /// Continue gate and Max all read this one number so the screen can't offer
    /// an amount the transaction builder must then reject.
    ///
    /// Recomputed on each published balance instead of per view render — the
    /// underlying reserve estimate walks the account's UTXO set over the FFI.
    @Published private(set) var coreSpendableDuffs: UInt64 = 0

    /// DIP-17 Platform Payment credits (1e11 per DASH). Sourced from
    /// `PlatformAddressSyncCoordinator.platformBalance`. Used to validate
    /// `.platform` source transfers (which go through `shieldedShield`,
    /// drawing transparent credits directly).
    @Published private(set) var platformCredits: UInt64 = 0

    /// Real shielded balance in credits, fed by the coordinator's reconciled
    /// balance mirror. Updates whenever a shielded sync pass completes.
    @Published private(set) var shieldedBalance: UInt64 = 0

    /// Largest amount the pool can fund inside ONE transition — see
    /// `ShieldedTransferCoordinator.spendCeilingCredits`. A typed amount above
    /// this needs more notes than the 20 KiB state-transition limit admits and
    /// would be rejected at broadcast, after the proof was built. `nil` while
    /// the note set is reconciling, in which case the balance envelope is the
    /// only bound this screen can apply; the coordinator still fails closed.
    @Published private(set) var shieldedSpendCeilingCredits: UInt64?

    /// Drives the one-time restore gate reactively. A normal catch-up may set
    /// this to false, but it only blocks while the recovery marker is active.
    @Published private(set) var isChainSynced = SyncingActivityMonitor.shared.state == .syncDone

    private var cancellables = Set<AnyCancellable>()

    deinit {
        // The monitor holds observers strongly — remove or leak the VM.
        SyncingActivityMonitor.shared.remove(observer: self)
    }

    init() {
        SyncingActivityMonitor.shared.add(observer: self)
        coreBalanceDuffs = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        coreSpendableDuffs = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
        platformCredits = PlatformAddressSyncCoordinator.shared.platformBalance

        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] balance in
                self?.coreBalanceDuffs = balance?.total ?? 0
                self?.coreSpendableDuffs = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
            }
            .store(in: &cancellables)

        PlatformAddressSyncCoordinator.shared.$platformBalance
            .receive(on: RunLoop.main)
            .sink { [weak self] credits in
                guard let self else { return }
                self.platformCredits = credits
                // Clear the stale-cache barrier on publication regardless of
                // route. If this route is inactive, the next route entry will
                // preflight the now-refreshed cache normally.
                self.awaitingPlatformShieldResync =
                    PlatformShieldAmountPolicy.awaitingPlatformResync(
                        current: self.awaitingPlatformShieldResync,
                        after: .balancePublished)
                if self.route == .platformToShielded {
                    self.refreshPlatformShieldPreflight(after: .balancePublished)
                }
            }
            .store(in: &cancellables)

        shieldedBalance = PlatformAddressSyncCoordinator.shared.shieldedBalance
        PlatformAddressSyncCoordinator.shared.$shieldedBalance
            .receive(on: RunLoop.main)
            .sink { [weak self] credits in
                self?.shieldedBalance = credits
                self?.refreshShieldedSpendCeiling()
            }
            .store(in: &cancellables)
    }

    /// Fee kind for the pool-spending routes; `nil` for every other route.
    private func shieldedFeeKind(for route: InternalTransferRoute) -> PlatformWalletManager.ShieldedFeeKind? {
        switch route {
        case .shieldedToCore: return .withdrawal
        case .shieldedToPlatform: return .unshield
        default: return nil
        }
    }

    /// Recomputes `shieldedSpendCeilingCredits` from the current note set.
    /// Cached rather than computed per keystroke — it reads SwiftData.
    private func refreshShieldedSpendCeiling() {
        guard let feeKind = shieldedFeeKind(for: route) else {
            shieldedSpendCeilingCredits = nil
            return
        }
        shieldedSpendCeilingCredits = ShieldedTransferCoordinator.spendCeilingCredits(feeKind: feeKind)
    }

    /// The raw numeric value the user has typed, with locale comma normalised
    /// to a dot. Interpretation depends on `unit` — this is *not yet* the DASH
    /// amount when in `.fiat` mode.
    private var rawTypedDecimal: Decimal {
        let sanitized = amountText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: sanitized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    var parsedDashAmount: Decimal {
        if let maxAmountDuffs {
            return maxAmountDuffs.dashAmount
        }
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
    /// Only Core-funded routes during a restored wallet's first sync block.
    var isBlockedBySync: Bool {
        switch route {
        case .coreToShielded, .coreToPlatform:
            return WalletSendService.isBlockedByInitialRestoreSync(
                isResyncingWallet: DWGlobalOptions.sharedInstance().isResyncingWallet,
                isChainSynced: isChainSynced)
        default:
            return false
        }
    }

    /// Inline, user-facing explanation for an amount rejected before Confirm.
    /// Zero stays quiet while the user has not entered an amount; a
    /// fee-estimation failure fails closed with a generic retry.
    var amountValidationMessage: String? {
        if let maxNotice { return maxNotice }
        guard dashDuffsUnsigned > 0 else { return nil }

        // The Core → Shielded pool fee rides on top of the amount, so there
        // is no route minimum — but without the estimate the lock value
        // cannot be derived, so fail closed before Confirm.
        if route == .coreToShielded,
           CoreToShieldedAmountPolicy.currentPoolFeeDuffs == nil {
            return Self.feeEstimateUnavailableMessage
        }

        return insufficientBalanceMessage
    }

    /// "You don't have that much" for the ACTIVE route, named after the balance
    /// it spends. Mirrors `canContinue`'s envelope route by route, so a Continue
    /// button disabled on affordability is never left unexplained.
    private var insufficientBalanceMessage: String? {
        let balanceName = route.source.balanceName

        switch route {
        case .coreToShielded:
            // The pool fee rides on top of the amount, so the spendable
            // envelope shrinks by the fee. Mirrors `canContinue`:
            // requested > spendable − fee ⟺ requested + fee > spendable.
            guard let feeDuffs = CoreToShieldedAmountPolicy.currentPoolFeeDuffs else {
                return Self.feeEstimateUnavailableMessage
            }
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedDuffs: dashDuffsUnsigned,
                spendableDuffs: coreSpendableDuffs > feeDuffs
                    ? coreSpendableDuffs - feeDuffs : 0)

        case .coreToPlatform:
            // The headroom rides on top of the amount, so the spendable
            // envelope shrinks by it — same shape as Core → Shielded above.
            let headroomDuffs = CoreToPlatformAmountPolicy.topUpHeadroomDuffs
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedDuffs: dashDuffsUnsigned,
                spendableDuffs: coreSpendableDuffs > headroomDuffs
                    ? coreSpendableDuffs - headroomDuffs : 0)

        case .platformToShielded:
            if awaitingPlatformShieldResync {
                return Self.platformShieldCapacityRefreshRequiredMessage
            }
            if isPlatformShieldPreflightLoading {
                return Self.platformShieldPreflightLoadingMessage
            }
            guard let capacity = platformShieldCapacity else {
                return Self.platformShieldPreflightUnavailableMessage
            }
            guard capacity.canShield else {
                return Self.platformShieldHeadroomUnavailableMessage
            }
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedCredits: creditsPreview,
                balanceCredits: capacity.maxShieldableCredits,
                feeReserveCredits: 0)

        case .shieldedToCore, .shieldedToPlatform:
            // A Max sweep is planned against the real note set rather than the
            // amount+reserve envelope, so it is affordable by construction.
            if isFullShieldedSweep { return nil }
            // The ceiling is priced from the notes that would actually be
            // spent, so it supersedes the flat reserve — which always charges
            // a full-size bundle and would reject amounts a one- or two-note
            // spend can afford.
            if let ceiling = shieldedSpendCeilingCredits {
                if creditsPreview > shieldedBalance {
                    // Simply more than the wallet holds: name that, rather than
                    // blaming note fragmentation.
                    return TransferSpendAmountPolicy.insufficientBalanceMessage(
                        balanceName: balanceName,
                        requestedDuffs: creditsPreview / 1000,
                        spendableDuffs: ceiling / 1000)
                }
                return creditsPreview > ceiling ? Self.shieldedCeilingMessage(ceiling) : nil
            }
            // Ceiling unavailable (notes reconciling): fall back to the flat
            // worst-case reserve.
            guard let reserve = feeReserveCredits else {
                return Self.feeEstimateUnavailableMessage
            }
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedCredits: creditsPreview,
                balanceCredits: shieldedBalance,
                feeReserveCredits: reserve)

        case .platformToCore:
            // Stay quiet while the preflight is still resolving: Continue is
            // disabled, but the amount is not yet known to be unaffordable.
            guard let preflight = withdrawalPreflight else { return nil }
            guard preflight.canWithdraw else {
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Your %@ balance is too low to cover the withdrawal fee.",
                        comment: "Platform withdrawal cannot fund its own fee"),
                    balanceName)
            }
            if isFullPlatformWithdrawal { return nil }
            guard creditsPreview > partialWithdrawCapCredits else { return nil }

            // A partial withdrawal spends a single address, so it is bounded by
            // the largest address balance. Amounts above that are reachable
            // only through the full-balance (Max) withdrawal over every address.
            let formattedCap =
                "\((partialWithdrawCapCredits / 1000).formattedDashAmountWithoutCurrencySymbol) DASH"
            if let fullDuffs = platformWithdrawableDuffs, dashDuffsUnsigned <= fullDuffs {
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "A partial withdrawal is limited to %@. Tap Max to withdraw the full balance.",
                        comment: "Platform partial withdrawal cap"),
                    formattedCap)
            }
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedDuffs: dashDuffsUnsigned,
                spendableDuffs: platformWithdrawableDuffs ?? partialWithdrawCapCredits / 1000)
        }
    }

    private static let feeEstimateUnavailableMessage = NSLocalizedString(
        "There was an error, please try again later",
        comment: "Internal transfer fee estimate unavailable")

    var canContinue: Bool {
        // Gate on duffs, not raw DASH: a sub-duff amount (e.g. 1e-9 DASH)
        // renders as 0 in the confirm sheet, so it must not enable Continue —
        // otherwise the credit routes would submit a nonzero amount while the
        // UI shows 0.
        guard dashDuffsUnsigned > 0, !isBlockedBySync else { return false }
        switch route {
        case .coreToShielded:
            // Fee-on-top: the lock value is amount + pool fee, so the balance
            // must cover both. Fails closed when the estimate is unavailable
            // or the sum overflows.
            guard let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits,
                  let lockDuffs = CoreToShieldedAmountPolicy.lockValueDuffs(
                      forAmountDuffs: dashDuffsUnsigned,
                      poolFeeCredits: poolFeeCredits)
            else { return false }
            return lockDuffs <= coreSpendableDuffs
        case .coreToPlatform:
            // Fee-on-top: the lock value is amount + headroom (the funding
            // ST's metered fee comes out of the headroom, not the amount),
            // so the L1 spendable balance must cover both. Fails closed on
            // overflow.
            guard let lockDuffs = CoreToPlatformAmountPolicy.lockValueDuffs(
                forAmountDuffs: dashDuffsUnsigned)
            else { return false }
            return lockDuffs <= coreSpendableDuffs
        case .platformToShielded:
            return !isPlatformShieldPreflightLoading
                && PlatformShieldAmountPolicy.canSubmit(
                    requestedCredits: creditsPreview,
                    capacity: platformShieldCapacity)
        case .shieldedToCore, .shieldedToPlatform:
            if isFullShieldedSweep {
                return shieldedSweepAmountCredits != nil
            }
            // Unshield/withdraw: the SDK debits amount + fee from the shielded
            // pool (recipient receives the full amount), so the balance must
            // cover amount + fee. Fail closed if the reserve is unavailable.
            if let ceiling = shieldedSpendCeilingCredits {
                return creditsPreview <= ceiling
            }
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

    /// Fee/selection headroom (credits) the SDK requires ON TOP of the amount
    /// for the active route, used by `canContinue` and Max. `nil` means the
    /// requirement is currently unavailable for a fee-reserved route → callers
    /// fail closed (block). A literal `0` (the asset-lock route) is NOT `nil` —
    /// that route reserves nothing from the source balance.
    private var feeReserveCredits: UInt64? {
        switch route {
        case .coreToShielded, .coreToPlatform:
            // Both Core-funded routes charge their fee/headroom ON TOP of the
            // amount, but duff-denominated and enforced in the route branches
            // (`canContinue`, Max) directly. Neither reserves credits from
            // the source balance here.
            return 0
        case .platformToShielded:
            // Governed by the SDK's account/address-aware shield preflight.
            return nil
        case .shieldedToCore:
            // The withdraw/unshield fee scales with the number of spent notes;
            // the SDK recomputes it from real note selection at send time.
            // Reserve the worst case the 20 KiB state-transition limit admits
            // (`ShieldedActionBudget.maxActionsPerTransition`) so a fragmented
            // wallet can't pass the affordability check and then fail SDK note
            // selection.
            return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(
                kind: .withdrawal,
                numActions: ShieldedActionBudget.maxActionsPerTransition)
        case .shieldedToPlatform:
            return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(
                kind: .unshield,
                numActions: ShieldedActionBudget.maxActionsPerTransition)
        case .platformToCore:
            // Full-balance withdrawal: the fee is already netted out of the
            // preflight's `netWithdrawable`; no reserve on top.
            return 0
        }
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
        if isFullShieldedSweep, let shieldedSweepAmountCredits {
            return shieldedSweepAmountCredits
        }
        return NSDecimalNumber(decimal: Decimal(dashDuffsUnsigned) * 1000).uint64Value
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
    /// fraction digits so long balances don't wrap the card.
    /// Internal — the Send screen's source cards use the same format.
    ///
    /// Truncates rather than rounds: half-even rounding would render 0.39999999
    /// as "0.4", so the card would claim more than Max can ever fill and the
    /// difference reads as a broken Max button.
    static func cardBalanceString(duffs: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5
        formatter.roundingMode = .down
        return formatter.string(from: NSDecimalNumber(decimal: duffs.dashAmount))
            ?? duffs.formattedDashAmountWithoutCurrencySymbol
    }

    /// Source-aware Max fill. Keeps the same unit semantics — DASH or fiat —
    /// but draws the upper bound from whichever bucket the user picked.
    func fillMaxFromWallet() {
        if route == .platformToShielded {
            fillPlatformShieldMax()
            return
        }

        clearMaxSelection()
        let sourceDuffs: UInt64
        switch route {
        case .coreToShielded:
            // Fee-on-top Max: the lock is amount + pool fee, so the largest
            // recipient amount is L1-fee-aware spendable minus the pool fee.
            // Fails closed (fills 0) when the fee estimate is unavailable.
            guard let feeDuffs = CoreToShieldedAmountPolicy.currentPoolFeeDuffs else {
                maxNotice = Self.feeEstimateUnavailableMessage
                sourceDuffs = 0
                break
            }
            sourceDuffs = coreSpendableDuffs > feeDuffs
                ? coreSpendableDuffs - feeDuffs : 0
            if coreSpendableDuffs == 0 {
                maxNotice = Self.coreZeroMaxMessage(
                    totalDuffs: coreBalanceDuffs,
                    confirmedSpendableDuffs: SwiftDashSDKWalletState.shared.balance?.spendable ?? 0)
            } else if sourceDuffs == 0 {
                maxNotice = Self.feeReserveExceedsBalanceMessage(route.source)
            } else {
                // The balance card shows the total, so a Max that lands below
                // it reads as a bug unless the held-back part is accounted for.
                maxNotice = Self.coreHeldBackMessage(coreBalanceDuffs - sourceDuffs)
            }
        case .coreToPlatform:
            // Fee-on-top Max: the lock is amount + headroom, so the largest
            // topup is the L1-fee-aware spendable minus the headroom.
            let headroomDuffs = CoreToPlatformAmountPolicy.topUpHeadroomDuffs
            sourceDuffs = coreSpendableDuffs > headroomDuffs
                ? coreSpendableDuffs - headroomDuffs : 0
            if coreSpendableDuffs == 0 {
                maxNotice = Self.coreZeroMaxMessage(
                    totalDuffs: coreBalanceDuffs,
                    confirmedSpendableDuffs: SwiftDashSDKWalletState.shared.balance?.spendable ?? 0)
            } else if sourceDuffs == 0 {
                maxNotice = Self.feeReserveExceedsBalanceMessage(route.source)
            } else {
                // The balance card shows the total, so a Max that lands below
                // it reads as a bug unless the held-back part is accounted for.
                maxNotice = Self.coreHeldBackMessage(coreBalanceDuffs - sourceDuffs)
            }
        case .platformToShielded:
            // Handled above because an unresolved async preflight must preserve
            // the user's current text while queueing the Max request.
            return
        case .shieldedToCore, .shieldedToPlatform:
            let feeKind: PlatformWalletManager.ShieldedFeeKind =
                route == .shieldedToCore ? .withdrawal : .unshield
            switch ShieldedTransferCoordinator.sweepAvailability(feeKind: feeKind) {
            case .ready(let plan):
                isFullShieldedSweep = true
                shieldedSweepAmountCredits = plan.amountCredits
                if plan.remainingCredits > 0 {
                    maxNotice = Self.shieldedRemainderMessage(
                        plan.remainingCredits,
                        followUpCredits: plan.followUpCredits)
                }
                sourceDuffs = plan.amountCredits / 1000
            case .waitingForConfirmation(let credits):
                maxNotice = Self.shieldedConfirmingMessage(credits)
                sourceDuffs = 0
            case .unavailable:
                maxNotice = NSLocalizedString(
                    "Your Shielded balance is not ready to spend. Sync and try Max again.",
                    comment: "Shielded Max unavailable")
                sourceDuffs = 0
            }
        case .platformToCore:
            // Max = the full-balance net payout (executed via the AUTO,
            // all-addresses path). The preflight is a network round trip, so
            // say so rather than silently filling 0 — and re-arm it, since a
            // failed attempt would otherwise only retry on a route change.
            sourceDuffs = platformWithdrawableDuffs ?? 0
            if sourceDuffs == 0 {
                if withdrawalPreflight?.canWithdraw == false {
                    maxNotice = Self.feeReserveExceedsBalanceMessage(route.source)
                } else {
                    maxNotice = NSLocalizedString(
                        "Still calculating the withdrawable amount. Tap Max again in a moment.",
                        comment: "Platform withdrawal preflight not resolved")
                    startWithdrawalPreflightIfNeeded()
                }
            }
        }

        isApplyingMax = true
        defer { isApplyingMax = false }
        applyMaxAmountText(sourceDuffs)
    }

    /// Platform Max is asynchronous because only the Rust wallet knows which
    /// address suffix its shield builder can select. If that answer is not
    /// ready, remember the user's intent and leave the current text untouched.
    private func fillPlatformShieldMax() {
        if awaitingPlatformShieldResync {
            isPlatformShieldMaxQueued = true
            maxNotice = Self.platformShieldResyncInProgressMessage
            startManualPlatformShieldResyncIfNeeded()
            return
        }
        guard !isPlatformShieldPreflightLoading,
              let capacity = platformShieldCapacity
        else {
            isPlatformShieldMaxQueued = true
            maxNotice = Self.platformShieldPreflightLoadingMessage
            refreshPlatformShieldPreflightIfNeeded()
            return
        }

        applyPlatformShieldMax(capacity)
    }

    private func applyPlatformShieldMax(_ capacity: PlatformShieldCapacity) {
        let preservesCapacityChangeNotice = hasPlatformShieldCapacityChangeNotice
        let preservedNotice = preservesCapacityChangeNotice ? maxNotice : nil
        clearMaxSelection()

        let sourceDuffs = PlatformShieldAmountPolicy.maximumDuffs(capacity: capacity)
        isApplyingMax = true
        applyMaxAmountText(sourceDuffs)
        isApplyingMax = false
        isPlatformShieldMaxDerived = true

        if let preservedNotice {
            maxNotice = preservedNotice
            hasPlatformShieldCapacityChangeNotice = true
        } else if sourceDuffs == 0 {
            maxNotice = capacity.accountBalanceCredits > 0
                ? Self.platformShieldHeadroomUnavailableMessage
                : Self.emptyBalanceMessage(.platform)
        } else {
            let heldBackCredits = PlatformShieldAmountPolicy.heldBackCredits(
                displayedPlatformCredits: platformCredits,
                accountBalanceCredits: capacity.accountBalanceCredits,
                submittedDuffs: sourceDuffs)
            if heldBackCredits > 0 {
                maxNotice = Self.platformShieldHeldBackMessage(heldBackCredits)
            }
        }
    }

    /// Render Max in the selected input unit while retaining `duffs` as the
    /// executable amount. In fiat mode the visible cents are approximate;
    /// converting those rounded cents back to DASH caused Max to exceed the
    /// balance and disabled Continue.
    private func applyMaxAmountText(_ duffs: UInt64) {
        guard duffs > 0 else {
            maxAmountDuffs = nil
            amountText = "0"
            return
        }

        maxAmountDuffs = duffs
        switch unit {
        case .dash:
            amountText = duffs.formattedDashAmountWithoutCurrencySymbol
        case .fiat:
            let dashDecimal = duffs.dashAmount
            if let fiat = try? CurrencyExchanger.shared.convertDash(amount: dashDecimal, to: App.fiatCurrency) {
                amountText = Self.formatTyped(fiat, fractionDigits: 2)
            } else {
                maxAmountDuffs = nil
                amountText = "0"
            }
        }
    }

    private func clearMaxSelection() {
        maxAmountDuffs = nil
        isFullShieldedSweep = false
        shieldedSweepAmountCredits = nil
        isPlatformShieldMaxDerived = false
        isPlatformShieldMaxQueued = false
        hasPlatformShieldCapacityChangeNotice = false
        maxNotice = nil
    }

    /// Kick off (or re-arm) the Platform → Core withdrawal preflight. Split out
    /// of `routeDidChange` so Max can retry a preflight that failed, instead of
    /// leaving the route stuck at 0 until the user toggles the route.
    private func startWithdrawalPreflightIfNeeded() {
        guard route == .platformToCore, withdrawalPreflightTask == nil else { return }
        withdrawalPreflightTask = Task { [weak self] in
            let result = try? await PlatformAddressSyncCoordinator.shared.preflightWithdrawal()
            guard let self, !Task.isCancelled else { return }
            self.withdrawalPreflight = result
            self.withdrawalPreflightTask = nil
        }
    }

    private func refreshPlatformShieldPreflightIfNeeded() {
        guard route == .platformToShielded,
              platformShieldPreflightTask == nil
        else { return }
        refreshPlatformShieldPreflight()
    }

    /// User-driven escape for an offline/failed scheduled resync. It retries
    /// Platform sync, never the cache-only preflight. The stale-cache barrier
    /// remains until `$platformBalance` publishes; completion merely re-arms
    /// the button so a later tap can try one more time.
    private func startManualPlatformShieldResyncIfNeeded() {
        guard PlatformShieldAmountPolicy.shouldStartManualResync(
            awaitingPlatformResync: awaitingPlatformShieldResync,
            retryInFlight: platformShieldManualResyncTask != nil)
        else { return }

        platformShieldManualResyncTask = Task { [weak self] in
            await PlatformAddressSyncCoordinator.shared.syncNow()
            guard let self, !Task.isCancelled else { return }
            self.platformShieldManualResyncTask = nil
            if self.awaitingPlatformShieldResync {
                self.maxNotice = Self.platformShieldCapacityRefreshRequiredMessage
            }
        }
    }

    /// Replaces any in-flight result and advances a generation token. The SDK
    /// call may not observe Swift task cancellation immediately, so the token
    /// also prevents a late result from an older balance snapshot winning.
    private func refreshPlatformShieldPreflight(
        after event: PlatformShieldAmountPolicy.PreflightRefreshEvent = .other
    ) {
        guard route == .platformToShielded,
              PlatformShieldAmountPolicy.shouldRefreshPreflight(
                after: event,
                awaitingPlatformResync: awaitingPlatformShieldResync)
        else { return }

        if case .balancePublished = event {
            awaitingPlatformShieldResync = false
        }

        platformShieldPreflightGeneration &+= 1
        let generation = platformShieldPreflightGeneration
        platformShieldPreflightTask?.cancel()
        platformShieldCapacity = nil
        isPlatformShieldPreflightLoading = true
        if isPlatformShieldMaxDerived && !hasPlatformShieldCapacityChangeNotice {
            maxNotice = Self.platformShieldPreflightLoadingMessage
        }

        platformShieldPreflightTask = Task { [weak self] in
            do {
                let result = try await PlatformAddressSyncCoordinator.shared.preflightShield()
                guard let self,
                      !Task.isCancelled,
                      self.route == .platformToShielded,
                      self.platformShieldPreflightGeneration == generation
                else { return }

                let capacity = PlatformShieldCapacity(result)
                self.platformShieldCapacity = capacity
                self.isPlatformShieldPreflightLoading = false
                self.platformShieldPreflightTask = nil

                if self.hasPlatformShieldCapacityChangeNotice {
                    self.maxNotice = Self.platformShieldCapacityChangedMessage(
                        maxShieldableCredits: capacity.maxShieldableCredits)
                }

                if self.isPlatformShieldMaxDerived || self.isPlatformShieldMaxQueued {
                    self.applyPlatformShieldMax(capacity)
                }
            } catch {
                guard let self,
                      !Task.isCancelled,
                      self.route == .platformToShielded,
                      self.platformShieldPreflightGeneration == generation
                else { return }

                self.platformShieldCapacity = nil
                self.isPlatformShieldPreflightLoading = false
                self.platformShieldPreflightTask = nil
                if !self.hasPlatformShieldCapacityChangeNotice
                    && (self.isPlatformShieldMaxQueued || self.isPlatformShieldMaxDerived) {
                    self.maxNotice = Self.platformShieldPreflightUnavailableMessage
                }
            }
        }
    }

    private func cancelPlatformShieldPreflight() {
        platformShieldPreflightGeneration &+= 1
        platformShieldPreflightTask?.cancel()
        platformShieldPreflightTask = nil
        platformShieldCapacity = nil
        isPlatformShieldPreflightLoading = false
        isPlatformShieldMaxQueued = false
        awaitingPlatformShieldResync =
            PlatformShieldAmountPolicy.awaitingPlatformResync(
                current: awaitingPlatformShieldResync,
                after: .other)
    }

    /// Called when Confirm's last-moment preflight no longer covers the frozen
    /// submitted amount. The sheet is dismissed by its host. A Max-derived
    /// amount follows the new ceiling; manual input remains verbatim and fails
    /// validation until the user edits it.
    func handlePlatformShieldCapacityChanged(
        maxShieldableCredits: UInt64?,
        submittedAmountWasMax: Bool
    ) {
        guard route == .platformToShielded else { return }

        let refreshedDuffs = PlatformShieldAmountPolicy.amountAfterCapacityChange(
            currentDuffs: dashDuffsUnsigned,
            wasMaxDerived: submittedAmountWasMax,
            maxShieldableCredits: maxShieldableCredits)

        if submittedAmountWasMax, maxShieldableCredits != nil {
            isApplyingMax = true
            applyMaxAmountText(refreshedDuffs)
            isApplyingMax = false
            isPlatformShieldMaxDerived = true
        } else if submittedAmountWasMax {
            // The typed SDK failure proves the submitted Max is stale, but the
            // cache cannot yet provide a truthful replacement.
            // Preserve it visually and keep its Max provenance so the next
            // successful refresh can replace it; affordability stays closed.
            isPlatformShieldMaxDerived = true
        } else {
            maxAmountDuffs = nil
            isPlatformShieldMaxDerived = false
        }

        isPlatformShieldMaxQueued = false
        hasPlatformShieldCapacityChangeNotice = true
        if let maxShieldableCredits {
            awaitingPlatformShieldResync = false
            maxNotice = Self.platformShieldCapacityChangedMessage(
                maxShieldableCredits: maxShieldableCredits)
            refreshPlatformShieldPreflight()
        } else {
            maxNotice = Self.platformShieldCapacityRefreshRequiredMessage
            // Fail closed until the coordinator's scheduled Platform sync
            // publishes a balance snapshot. Do not re-read the cache here.
            platformShieldPreflightGeneration &+= 1
            platformShieldPreflightTask?.cancel()
            platformShieldPreflightTask = nil
            platformShieldCapacity = nil
            isPlatformShieldPreflightLoading = false
            awaitingPlatformShieldResync = true
        }
    }

    /// The part of the Core balance Max cannot offer: unconfirmed/immature
    /// coins plus the reserved L1 fee.
    private static func coreHeldBackMessage(_ duffs: UInt64) -> String {
        let formatted = duffs.formattedDashAmountWithoutCurrencySymbol
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "%@ DASH is held back for the network fee and unconfirmed coins.",
                comment: "Core Max holds back fee and unconfirmed funds"),
            formatted)
    }

    /// Why a Core Max produced nothing, told apart by the three states that
    /// reach it: no funds at all, funds that are still confirming, and a
    /// confirmed balance too small to also cover the L1 fee.
    ///
    /// Shared with the classic send amount screen (`SendAmountModel`), which
    /// runs the same Core Max against the same balance and must explain a
    /// zero result in the same words. `nonisolated` so that caller — which
    /// is not main-actor bound — can reach it; the body is pure string work.
    nonisolated static func coreZeroMaxMessage(
        totalDuffs: UInt64,
        confirmedSpendableDuffs: UInt64
    ) -> String {
        guard totalDuffs > 0 else { return emptyBalanceMessage(.core) }
        guard confirmedSpendableDuffs > 0 else {
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "None of your %@ DASH is spendable yet — it is still confirming.",
                    comment: "Core Max has nothing confirmed to spend"),
                totalDuffs.formattedDashAmountWithoutCurrencySymbol)
        }
        return feeReserveExceedsBalanceMessage(.core)
    }

    // Shared with `SendViewModel`'s Platform → external Shielded route,
    // which runs the same preflight — hence `internal`, not `private`.
    static let platformShieldPreflightLoadingMessage = NSLocalizedString(
        "Checking how much of your Platform balance can be moved…",
        comment: "Platform to Shielded preflight in progress")

    static let platformShieldPreflightUnavailableMessage = NSLocalizedString(
        "Could not check the available Platform balance. Sync and try again.",
        comment: "Platform to Shielded preflight failed")

    private static let platformShieldCapacityRefreshRequiredMessage = NSLocalizedString(
        "Your available Platform balance changed, but the new maximum could not be checked. The amount was not changed. Sync and try again.",
        comment: "Platform Shield capacity changed but refresh failed")

    private static let platformShieldResyncInProgressMessage = NSLocalizedString(
        "Refreshing your Platform balance before checking the new maximum…",
        comment: "Platform Shield manual resync in progress")

    // Shared with `SendViewModel` — see the note above.
    static let platformShieldHeadroomUnavailableMessage = NSLocalizedString(
        "Your Platform balance cannot currently cover the Shield transfer selection headroom.",
        comment: "Platform balance cannot fund shield selection headroom")

    private static func platformShieldHeldBackMessage(_ credits: UInt64) -> String {
        let formatted = (credits / 1000).formattedDashAmountWithoutCurrencySymbol
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "%@ DASH remains in Platform because some address funds cannot be selected and transfer headroom is reserved.",
                comment: "Platform Shield Max leaves selection headroom and unselectable funds"),
            formatted)
    }

    private static func platformShieldCapacityChangedMessage(
        maxShieldableCredits: UInt64
    ) -> String {
        let maxDuffs = maxShieldableCredits / 1000
        guard maxDuffs > 0 else {
            return NSLocalizedString(
                "Your available Platform balance changed and can no longer cover this Shield transfer. Review the amount and try again.",
                comment: "Platform Shield capacity changed to zero")
        }
        let formatted = maxDuffs.formattedDashAmountWithoutCurrencySymbol
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "Your available Platform balance changed. The new maximum is %@ DASH. Review it and confirm again.",
                comment: "Platform Shield capacity changed before confirmation"),
            formatted)
    }

    /// Shared with `SendViewModel`'s Core → Shielded Max (same fee-on-top
    /// envelope) — keep `internal`.
    nonisolated static func feeReserveExceedsBalanceMessage(_ source: ChainNetwork) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(
                "Your %@ balance is too low to cover the transfer fee.",
                comment: "Max cannot fund the fee"),
            source.balanceName)
    }

    nonisolated private static func emptyBalanceMessage(_ source: ChainNetwork) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(
                "Your %@ balance is empty.",
                comment: "Max pressed with no funds"),
            source.balanceName)
    }

    private static func shieldedConfirmingMessage(_ credits: UInt64) -> String {
        let formatted = (credits / 1000).formattedDashAmountWithoutCurrencySymbol
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "%@ DASH is still confirming. Use Max again once it settles.",
                comment: "Shielded Max pending change"),
            formatted)
    }

    private static func shieldedCeilingMessage(_ credits: UInt64) -> String {
        let formatted = (credits / 1000).formattedDashAmountWithoutCurrencySymbol
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "Your Shielded balance is split across notes, and at most %@ DASH of it can be sent in one transaction. Send the rest afterwards.",
                comment: "Shielded amount above the single-transaction ceiling"),
            formatted)
    }

    private static func shieldedRemainderMessage(
        _ credits: UInt64,
        followUpCredits: UInt64
    ) -> String {
        let formatted = (credits / 1000).formattedDashAmountWithoutCurrencySymbol
        guard followUpCredits > 0 else {
            // Spending these notes costs more than they hold, so no later
            // sweep can move them — do not send the user round that loop.
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "%@ DASH stays in your Shielded balance: those notes are worth less than the fee to send them.",
                    comment: "Shielded Max dust remainder"),
                formatted)
        }
        return String.localizedStringWithFormat(
            NSLocalizedString(
                "%@ DASH is held in notes that don't fit in one transaction. Use Max again after this one settles to send the rest.",
                comment: "Shielded Max multi-bundle remainder"),
            formatted)
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
