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

/// Where an internal transfer delivers. The FROM side is a `ChainNetwork`
/// balance; the DashPay identity's credit balance is additionally reachable
/// as a destination. Identity credits are the fuel for Platform state
/// transitions, not a fourth spendable balance, so `ChainNetwork` and
/// `InternalTransferRoute` never learn about it — an identity transfer is
/// executed by the identity top-up, not by a balance-to-balance route.
enum TransferDestination: Equatable, Hashable {
    case balance(ChainNetwork)
    case identity
}

/// Where an internal transfer draws from. The mirror of `TransferDestination`
/// — the identity's credit balance is spendable as well as fundable, through
/// its own state transition rather than through an `InternalTransferRoute`.
enum TransferSource: Equatable, Hashable {
    case balance(ChainNetwork)
    case identity
}

/// Where identity credits can land in ONE state transition.
///
/// Shielded has no case on purpose: nothing moves credits from an identity
/// straight into the Orchard pool. Reaching it means withdrawing here first
/// and shielding after, which is two user-visible transfers, not this one.
enum IdentityWithdrawalTarget: CaseIterable, Equatable, Hashable {
    /// IdentityCreditWithdrawal → the wallet's own Core receive address.
    case transparent
    /// Credit transfer → the wallet's own Platform receive address.
    case platform

    /// `nil` for `.shielded`, the balance no single transition reaches.
    init?(_ network: ChainNetwork) {
        switch network {
        case .core: self = .transparent
        case .platform: self = .platform
        case .shielded: return nil
        }
    }

    var network: ChainNetwork {
        switch self {
        case .transparent: return .core
        case .platform: return .platform
        }
    }
}

/// Confirm-sheet input for the Identity destination: the identity being
/// topped up and the balance the top-up spends.
struct IdentityTopUpTransfer: Equatable {
    let identityId: Data
    let source: ChainNetwork
}

/// Confirm-sheet input for the Identity source: the identity being drawn
/// down and where its credits land.
struct IdentityWithdrawalTransfer: Equatable {
    let identityId: Data
    let target: IdentityWithdrawalTarget
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

    static var poolFeeCredits: UInt64? {
        guard let shieldedFee = try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(
            kind: .transfer,
            numActions: 2)
        else { return nil }

        let (total, overflow) = shieldedFee.addingReportingOverflow(assetLockBaseCostCredits)
        return overflow ? nil : total
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

    /// Short on purpose: it is shown in the amount row, in the slot the
    /// converted figure occupies. Which balance fell short and by how much is
    /// already on screen — the From card carries both.
    private static func message(balanceName: String, spendableDuffs: UInt64) -> String {
        NSLocalizedString(
            "Insufficient balance",
            comment: "Transfer amount exceeds the source balance")
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

    /// True while the standalone destination is the DashPay identity rather
    /// than a balance. An overlay on the balance-route state: `source` stays
    /// the spendable FROM balance, `route` keeps meaning balance-to-balance
    /// and is not consulted while this is set — validation, Continue and
    /// execution go through the identity top-up path instead. Standalone
    /// only; the send/receive-pinned variants stay balance-to-balance.
    @Published private(set) var isIdentityDestination = false {
        didSet { guard oldValue != isIdentityDestination else { return }; routeDidChange() }
    }

    /// Standalone screen: the FROM side is the identity's credit balance
    /// rather than `source`. Mutually exclusive with `isIdentityDestination`
    /// — an identity cannot fund itself. While set, `route` is a stale
    /// balance pair and only `identityWithdrawalTransfer` describes the
    /// transfer, exactly as with the destination overlay.
    @Published private(set) var isIdentitySource = false {
        didSet { guard oldValue != isIdentitySource else { return }; routeDidChange() }
    }

    /// The 32-byte id of the identity a transfer would top up, loaded when
    /// the Identity destination is selected. `nil` when the wallet has no
    /// registered identity — affordability then fails closed with an
    /// explanatory message instead of offering a transfer with nowhere to go.
    /// Whether Platform and the identity are reachable endpoints at all.
    ///
    /// Advanced mode is what admits them; without it a transfer is Transparent
    /// to Shielded and back, which is the pair an ordinary user is offered.
    ///
    /// Published rather than read at each use: the switch lives in Settings and
    /// can be flipped while this screen is on display, and a view that read the
    /// flag once would keep offering an endpoint the transfer can no longer
    /// reach. `advancedModeDidChange` is the announcement it exists for.
    @Published private(set) var isAdvancedMode = DWGlobalOptions.sharedInstance().advancedModeEnabled

    @Published private(set) var identityId: Data?

    /// The identity's own credit balance for the destination card (credits,
    /// 1000 per duff) — the persisted row's value, same read the profile
    /// sheet renders.
    @Published private(set) var identityBalanceCredits: UInt64 = 0

    /// Ceiling (duffs) for an identity top-up funded from the Platform
    /// balance, per the executor's own planner
    /// (`PlatformPaymentIdentityFundingPolicy.maxFundableDuffs`). `nil`
    /// while the candidates are unread — affordability fails closed. Cached
    /// because reading candidates is a SwiftData fetch: refreshed on
    /// destination changes and Platform balance publications, not per
    /// keystroke.
    @Published private(set) var platformIdentityFundableDuffs: UInt64?

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

    /// Destination-typed standalone pick: a balance keeps the pre-existing
    /// endpoint behavior; Identity overlays it without moving the source —
    /// every balance is a valid FROM for a top-up, so there is nothing to
    /// sanitise away from.
    func selectStandaloneDestination(_ destination: TransferDestination) {
        switch destination {
        case .balance(let network):
            isIdentityDestination = false
            // With the identity on the FROM side, `source` is not in play and
            // `selectStandaloneTarget`'s collision sanitising would move a
            // balance the transfer never touches.
            if isIdentitySource {
                sendTarget = network
            } else {
                selectStandaloneTarget(network)
            }
        case .identity:
            // An identity cannot fund itself: taking the TO side releases
            // the FROM side back to a balance.
            isIdentitySource = false
            isIdentityDestination = true
            refreshIdentitySnapshot()
        }
    }

    /// Source-typed standalone pick, the mirror of
    /// `selectStandaloneDestination`. Identity releases the destination back
    /// to a balance and moves it off Shielded, which no single transition
    /// reaches from an identity.
    func selectStandaloneSource(_ source: TransferSource) {
        switch source {
        case .balance(let network):
            isIdentitySource = false
            if isIdentityDestination {
                // Top-up mode: every balance is a valid funding source, and
                // the TO side is the identity, so there is no collision to
                // sanitise.
                self.source = network
            } else {
                selectStandaloneSource(network)
            }
        case .identity:
            isIdentityDestination = false
            isIdentitySource = true
            sendTarget = Self.sanitizedWithdrawalTarget(sendTarget)
            refreshIdentitySnapshot()
        }
    }

    /// The standalone destination as the screen and the confirm flow see it.
    ///
    /// With the identity as the source it is `resolvedWithdrawalTarget`, not
    /// `resolvedSendTarget`: the latter sanitises against `source`, which is
    /// a stale balance while the overlay is on, and would name a target the
    /// transfer does not use.
    var destination: TransferDestination {
        if isIdentityDestination { return .identity }
        if isIdentitySource { return .balance(resolvedWithdrawalTarget.network) }
        return .balance(resolvedSendTarget)
    }

    /// The standalone source as the screen and the confirm flow see it.
    var transferSource: TransferSource {
        isIdentitySource ? .identity : .balance(source)
    }

    /// The TO selection while the identity is the source: `sendTarget`
    /// guarded onto a balance a withdrawal can actually reach.
    var resolvedWithdrawalTarget: IdentityWithdrawalTarget {
        IdentityWithdrawalTarget(Self.sanitizedWithdrawalTarget(sendTarget)) ?? .transparent
    }

    /// Shielded is unreachable from an identity, so it falls back to
    /// Transparent — the target a withdrawal always supports.
    private static func sanitizedWithdrawalTarget(_ proposed: ChainNetwork) -> ChainNetwork {
        IdentityWithdrawalTarget(proposed) == nil ? .core : proposed
    }

    /// Confirm-flow input for the Identity source. `nil` unless the source
    /// is Identity AND an identity exists (`canContinue` has already refused
    /// the transfer otherwise).
    var identityWithdrawalTransfer: IdentityWithdrawalTransfer? {
        guard isIdentitySource, let identityId else { return nil }
        return IdentityWithdrawalTransfer(
            identityId: identityId,
            target: resolvedWithdrawalTarget)
    }

    /// Confirm-sheet input for the Identity destination. `nil` unless the
    /// destination is Identity AND an identity exists (`canContinue` has
    /// already refused the transfer otherwise).
    var identityTopUpTransfer: IdentityTopUpTransfer? {
        guard isIdentityDestination, let identityId else { return nil }
        return IdentityTopUpTransfer(identityId: identityId, source: source)
    }

    /// Whether the two endpoints can trade places.
    ///
    /// False for exactly one pair: Shielded → Identity. Its reverse would be
    /// Identity → Shielded, which no single transition performs, so the
    /// screen shows the static arrow instead of a swap the tap could not
    /// honour. Every other pair reverses into a transfer that exists.
    var canSwapEndpoints: Bool {
        if isIdentitySource { return true }
        if isIdentityDestination { return IdentityWithdrawalTarget(source) != nil }
        return true
    }

    /// Standalone screen: exchange the two endpoints. Assigned directly rather
    /// than through `selectStandaloneSource`/`Target` — those sanitise the
    /// opposite side away from a collision, and a swap can't collide.
    func swapStandaloneEndpoints() {
        guard canSwapEndpoints else { return }

        if isIdentitySource {
            // Withdrawal → top-up: the target balance becomes the funding
            // source. Read the target before clearing the overlay, since
            // `resolvedWithdrawalTarget` is only meaningful while it is on.
            let fundingSource = resolvedWithdrawalTarget.network
            isIdentitySource = false
            isIdentityDestination = true
            source = fundingSource
            refreshIdentitySnapshot()
            return
        }

        if isIdentityDestination {
            // Top-up → withdrawal: the funding balance becomes the payout
            // target. `canSwapEndpoints` has already ruled out Shielded.
            let payoutTarget = source
            isIdentityDestination = false
            isIdentitySource = true
            sendTarget = Self.sanitizedWithdrawalTarget(payoutTarget)
            refreshIdentitySnapshot()
            return
        }

        let newSource = resolvedSendTarget
        let newTarget = source
        source = newSource
        sendTarget = newTarget
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

    /// The balances a transfer may touch right now.
    var availableNetworks: [ChainNetwork] {
        isAdvancedMode ? ChainNetwork.allCases : [.core, .shielded]
    }

    /// The identity is a Platform surface, so it comes and goes with the rest
    /// of them rather than having a rule of its own.
    var offersIdentityEndpoints: Bool { isAdvancedMode }

    /// Pull every endpoint back inside what the mode now allows.
    ///
    /// Only ever narrows. Turning the mode ON leaves the current pair alone —
    /// it was already legal — while turning it OFF has to move a selection that
    /// has just become unreachable, or the screen would sit on a route it is no
    /// longer allowed to execute.
    ///
    /// The pinned variants (`sendSource`, `receiveTarget`) are deliberately not
    /// touched: they are entered from a balance row that still exists, and
    /// rewriting the endpoint the user tapped would be a different bug.
    private func applyAdvancedMode() {
        isAdvancedMode = DWGlobalOptions.sharedInstance().advancedModeEnabled
        guard !isAdvancedMode else { return }

        isIdentitySource = false
        isIdentityDestination = false

        if source == .platform {
            source = .core
        }
        if sendTarget == .platform {
            sendTarget = Self.defaultDestination(for: source)
        }
        if receiveSource == .platform {
            receiveSource = .shielded
        }
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
    /// input-selection envelope. While the destination is Identity, `route`
    /// is a stale balance pair, so the route preflights stay down and the
    /// identity ceiling refreshes instead.
    private func routeDidChange() {
        clearMaxSelection()
        refreshShieldedSpendCeiling()
        refreshIdentityPlatformCeiling()

        // With the identity as the source, no balance route is active at all:
        // `route` is a stale pair, so every route preflight stays down.
        guard !isIdentitySource else {
            withdrawalPreflightTask?.cancel()
            withdrawalPreflightTask = nil
            withdrawalPreflight = nil
            cancelPlatformShieldPreflight()
            return
        }

        if !isIdentityDestination, route == .platformToCore {
            startWithdrawalPreflightIfNeeded()
        } else {
            withdrawalPreflightTask?.cancel()
            withdrawalPreflightTask = nil
            withdrawalPreflight = nil
        }

        if !isIdentityDestination, route == .platformToShielded {
            refreshPlatformShieldPreflight()
        } else {
            cancelPlatformShieldPreflight()
        }
    }

    /// Loads the identity the Identity destination would top up, plus its
    /// displayed credit balance. A missing identity is left `nil` — the
    /// amount validation names that state.
    private func refreshIdentitySnapshot() {
        #if DEBUG
        if isPreviewInstance { return }
        #endif
        identityId = DWCurrentUserIdentityInfo.shared.identityId
        if let identityId, let container = SwiftDashSDKHost.shared.modelContainer {
            identityBalanceCredits = UsernameMarketplaceService.identityBalanceCredits(
                identityId: identityId,
                container: container)
        } else {
            identityBalanceCredits = 0
        }
    }

    /// Recomputes `platformIdentityFundableDuffs` from the persisted
    /// Platform-address candidates. Only meaningful while the Identity
    /// destination spends the Platform balance; `nil` otherwise.
    private func refreshIdentityPlatformCeiling() {
        #if DEBUG
        if isPreviewInstance { return }
        #endif
        guard isIdentityDestination, source == .platform else {
            platformIdentityFundableDuffs = nil
            return
        }
        guard let candidates = try? PlatformPaymentIdentityFundingPolicy.currentCandidates() else {
            platformIdentityFundableDuffs = nil
            return
        }
        platformIdentityFundableDuffs =
            PlatformPaymentIdentityFundingPolicy.maxFundableDuffs(candidates: candidates)
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
    ///
    /// Seeded from the monitor in `init()` rather than here: a property default
    /// runs in EVERY initializer, and the preview initializer must not spin up
    /// the sync monitor singleton.
    @Published private(set) var isChainSynced = false

    private var cancellables = Set<AnyCancellable>()

    #if DEBUG
    /// Stands in for `DWGlobalOptions.isResyncingWallet` in a canvas.
    private var previewIsResyncingWallet: Bool?

    /// True only for `makeForPreview` instances. They never registered with the
    /// sync monitor, so `deinit` must not reach for that singleton to
    /// unregister — building it inside a preview process starts reachability
    /// and SPV observation this instance never wanted.
    private var isPreviewInstance = false
    #endif

    deinit {
        #if DEBUG
        if isPreviewInstance { return }
        #endif
        // The monitor holds observers strongly — remove or leak the VM.
        SyncingActivityMonitor.shared.remove(observer: self)
    }

    init() {
        SyncingActivityMonitor.shared.add(observer: self)

        NotificationCenter.default.publisher(for: .advancedModeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyAdvancedMode() }
            .store(in: &cancellables)

        isChainSynced = SyncingActivityMonitor.shared.state == .syncDone
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
                if self.isIdentityDestination {
                    // A fresh Platform snapshot moves the identity top-up's
                    // planner ceiling, not the route preflights.
                    self.refreshIdentityPlatformCeiling()
                } else if self.route == .platformToShielded {
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

        // Eager, not deferred to the first Identity pick: the destination
        // picker lists the identity's balance alongside the other three, so
        // the number has to be there before the destination is selected.
        refreshIdentitySnapshot()
    }

    #if DEBUG
    /// Lightweight initializer used only by SwiftUI previews. Assigns the
    /// balances and the endpoint selection directly and skips the wallet /
    /// sync / preflight wiring the real `init()` sets up.
    ///
    /// Property observers do not fire during initialization, so assigning the
    /// endpoints here also skips `routeDidChange()` — no preflight task is
    /// started and no SwiftData note read happens.
    private init(
        previewSource: ChainNetwork,
        previewTarget: ChainNetwork,
        previewSendFrom: ChainNetwork?,
        previewReceiveInto: ChainNetwork?,
        previewIdentityDestination: Bool,
        previewIdentitySource: Bool,
        previewIdentityCredits: UInt64,
        previewAmountText: String,
        previewCoreDuffs: UInt64,
        previewPlatformCredits: UInt64,
        previewShieldedCredits: UInt64,
        previewIsChainSynced: Bool,
        previewIsResyncingWallet: Bool
    ) {
        isPreviewInstance = true
        source = previewSource
        sendTarget = previewTarget
        receiveSource = previewSource
        sendSource = previewSendFrom
        receiveTarget = previewReceiveInto
        amountText = previewAmountText
        coreBalanceDuffs = previewCoreDuffs
        // No fee reserve to subtract without a wallet — previews want the
        // whole balance to read as spendable so Max and Continue behave.
        coreSpendableDuffs = previewCoreDuffs
        platformCredits = previewPlatformCredits
        shieldedBalance = previewShieldedCredits
        isChainSynced = previewIsChainSynced
        self.previewIsResyncingWallet = previewIsResyncingWallet
        if previewIdentityDestination {
            isIdentityDestination = true
            identityId = Data(repeating: 0x07, count: 32)
            identityBalanceCredits = previewIdentityCredits
            // Stands in for the planner ceiling the real instance derives
            // from the persisted Platform-address candidates.
            platformIdentityFundableDuffs = previewPlatformCredits / 1000
        }
        if previewIdentitySource {
            isIdentitySource = true
            identityId = Data(repeating: 0x07, count: 32)
            identityBalanceCredits = previewIdentityCredits
            // Shielded is unreachable from an identity, so a preview asking
            // for it would render a target the real screen never allows.
            sendTarget = Self.sanitizedWithdrawalTarget(previewTarget)
        }
    }

    /// Preview view model with stubbed balances.
    ///
    /// Balances are in their published units: Core in duffs (1e8 per DASH),
    /// Platform and Shielded in credits (1e11 per DASH). Defaults are
    /// 2.45 / 1.2 / 0.785 DASH.
    ///
    /// Routes that spend the shielded pool (and `.coreToShielded`) ask the
    /// SDK for a fee estimate while rendering; without a wallet those return
    /// `nil` and the screen falls back to its "fee unavailable" state. Pick a
    /// `.coreToPlatform` pair to preview an enabled Continue button.
    static func makeForPreview(
        source: ChainNetwork = .core,
        target: ChainNetwork = .platform,
        sendFrom: ChainNetwork? = nil,
        receiveInto: ChainNetwork? = nil,
        identityDestination: Bool = false,
        identitySource: Bool = false,
        identityCredits: UInt64 = 25_000_000_000,
        amountText: String = "0",
        coreDuffs: UInt64 = 245_000_000,
        platformCredits: UInt64 = 120_000_000_000,
        shieldedCredits: UInt64 = 78_500_000_000,
        isChainSynced: Bool = true,
        isResyncingWallet: Bool = false
    ) -> InternalTransferViewModel {
        InternalTransferViewModel(
            previewSource: source,
            previewTarget: target,
            previewSendFrom: sendFrom,
            previewReceiveInto: receiveInto,
            previewIdentityDestination: identityDestination,
            previewIdentitySource: identitySource,
            previewIdentityCredits: identityCredits,
            previewAmountText: amountText,
            previewCoreDuffs: coreDuffs,
            previewPlatformCredits: platformCredits,
            previewShieldedCredits: shieldedCredits,
            previewIsChainSynced: isChainSynced,
            previewIsResyncingWallet: isResyncingWallet)
    }
    #endif

    /// Fee kind for the pool-spending routes; `nil` for every other route.
    private func shieldedFeeKind(for route: InternalTransferRoute) -> PlatformWalletManager.ShieldedFeeKind? {
        switch route {
        case .shieldedToCore: return .withdrawal
        case .shieldedToPlatform: return .unshield
        default: return nil
        }
    }

    /// Fee kind of the shielded spend the CURRENT selection would execute.
    /// The Identity destination's shielded funding starts with an unshield to
    /// the wallet's own Platform address, so it prices exactly like the
    /// Shielded → Platform route.
    private var activeShieldedFeeKind: PlatformWalletManager.ShieldedFeeKind? {
        if isIdentityDestination {
            return source == .shielded ? .unshield : nil
        }
        return shieldedFeeKind(for: route)
    }

    /// Recomputes `shieldedSpendCeilingCredits` from the current note set.
    /// Cached rather than computed per keystroke — it reads SwiftData.
    private func refreshShieldedSpendCeiling() {
        guard let feeKind = activeShieldedFeeKind else {
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
    /// Only Core-funded transfers during a restored wallet's first sync
    /// block — including an identity top-up spending the Core balance,
    /// which is the same asset-lock L1 spend.
    var isBlockedBySync: Bool {
        let spendsCore: Bool
        if isIdentitySource {
            // Credits leave the identity; the payout is produced by the
            // network, not by an L1 spend of this wallet's UTXOs, so the
            // restore gate has nothing to protect here.
            spendsCore = false
        } else if isIdentityDestination {
            spendsCore = source == .core
        } else {
            spendsCore = route.source == .core
        }
        guard spendsCore else { return false }
        return WalletSendService.isBlockedByInitialRestoreSync(
            isResyncingWallet: isResyncingWallet,
            isChainSynced: isChainSynced)
    }

    /// The restore marker, read live so the gate lifts as soon as it clears.
    ///
    /// A preview can override it: the real one lives in `NSUserDefaults` and is
    /// false in a canvas, so a sync-gate preview could otherwise never show the
    /// gate — the gate needs a restored wallet AND an unfinished sync.
    private var isResyncingWallet: Bool {
        #if DEBUG
        if let previewIsResyncingWallet { return previewIsResyncingWallet }
        #endif
        return DWGlobalOptions.sharedInstance().isResyncingWallet
    }

    /// Inline, user-facing explanation for an amount rejected before Confirm.
    /// Zero stays quiet while the user has not entered an amount; a
    /// fee-estimation failure fails closed with a generic retry.
    var amountValidationMessage: String? {
        if let maxNotice { return maxNotice }
        guard dashDuffsUnsigned > 0 else { return nil }

        if isIdentitySource { return identityWithdrawalValidationMessage }
        if isIdentityDestination { return identityAmountValidationMessage }

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
            // This asset-lock route carves its processing fee from the locked
            // value, but the funding transaction is still an L1 spend — only
            // confirmed UTXOs, and the miner fee comes off the top.
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedDuffs: dashDuffsUnsigned,
                spendableDuffs: coreSpendableDuffs)

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
            return shieldedSpendValidationMessage(reserveCredits: feeReserveCredits)

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

    /// The shielded-pool "doesn't fit" line shared by the Shielded → balance
    /// routes and the Identity destination (whose funding starts with the
    /// same unshield): balance overrun first, then the note-priced ceiling,
    /// then the flat worst-case reserve as the fallback while notes are
    /// reconciling. `nil` when the amount fits.
    private func shieldedSpendValidationMessage(reserveCredits: UInt64?) -> String? {
        let balanceName = ChainNetwork.shielded.balanceName
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
        guard let reserve = reserveCredits else {
            return Self.feeEstimateUnavailableMessage
        }
        return TransferSpendAmountPolicy.insufficientBalanceMessage(
            balanceName: balanceName,
            requestedCredits: creditsPreview,
            balanceCredits: shieldedBalance,
            feeReserveCredits: reserve)
    }

    /// Amount-affordability of a shielded-pool spend, mirroring
    /// `shieldedSpendValidationMessage` gate for gate.
    private func canAffordShieldedSpend(reserveCredits: UInt64?) -> Bool {
        if let ceiling = shieldedSpendCeilingCredits {
            return creditsPreview <= ceiling
        }
        guard let reserve = reserveCredits else { return false }
        return shieldedBalance >= reserve
            && creditsPreview <= shieldedBalance - reserve
    }

    /// The Identity destination's inline rejection, mirroring
    /// `canContinueToIdentity` gate for gate so a disabled Continue is never
    /// unexplained: no identity, below the top-up floor, or over the
    /// source's envelope.
    private var identityAmountValidationMessage: String? {
        guard identityId != nil else { return Self.noIdentityMessage }
        if dashDuffsUnsigned < IdentityTopUpViewModel.customMinimumDuffs {
            return Self.identityMinimumMessage
        }
        switch source {
        case .core:
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: source.balanceName,
                requestedDuffs: dashDuffsUnsigned,
                spendableDuffs: coreSpendableDuffs)
        case .platform:
            guard let ceiling = platformIdentityFundableDuffs else {
                return Self.feeEstimateUnavailableMessage
            }
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: source.balanceName,
                requestedDuffs: dashDuffsUnsigned,
                spendableDuffs: ceiling)
        case .shielded:
            return shieldedSpendValidationMessage(reserveCredits: feeReserveCredits)
        }
    }

    /// The Identity source's inline rejection, mirroring
    /// `canContinueFromIdentity` gate for gate: no identity, below the
    /// consensus withdrawal floor, or over what the credit balance can send
    /// once the fee reserve is held back.
    private var identityWithdrawalValidationMessage: String? {
        guard identityId != nil else { return Self.noIdentityToWithdrawFromMessage }
        if resolvedWithdrawalTarget == .transparent,
           creditsPreview < IdentityWithdrawViewModel.minimumWithdrawalCredits {
            return Self.identityWithdrawalMinimumMessage
        }
        let spendable = IdentityWithdrawViewModel.spendableCredits(
            balanceCredits: identityBalanceCredits)
        guard creditsPreview > spendable else { return nil }
        return TransferSpendAmountPolicy.insufficientBalanceMessage(
            balanceName: Self.identityBalanceName,
            requestedDuffs: creditsPreview / 1000,
            spendableDuffs: spendable / 1000)
    }

    private static let noIdentityMessage = NSLocalizedString(
        "You need a DashPay identity before you can top up its balance.",
        comment: "Identity transfer destination without a registered identity")

    private static let noIdentityToWithdrawFromMessage = NSLocalizedString(
        "You need a DashPay identity before you can move credits out of it.",
        comment: "Identity transfer source without a registered identity")

    /// The consensus floor, not a product choice: below it the withdrawal's
    /// Core output would be dust and the network rejects the transition.
    private static let identityWithdrawalMinimumMessage = String.localizedStringWithFormat(
        NSLocalizedString(
            "Enter at least %@ DASH",
            comment: "Identity top-up sheet — custom amount below the floor"),
        (IdentityWithdrawViewModel.minimumWithdrawalCredits / 1000).dashAmount
            .formattedDashAmountWithoutCurrencySymbol)

    /// Card-length name for the identity's credit balance, matching how
    /// `ChainNetwork.balanceName` labels the other three.
    static let identityBalanceName = NSLocalizedString("Identity", comment: "Payments")

    /// Same floor (and nearly the same wording) as the top-up sheet's custom
    /// amount field — both feed `IdentityTopUpViewModel.topUp`.
    private static let identityMinimumMessage = String.localizedStringWithFormat(
        NSLocalizedString(
            "Enter at least %@ DASH",
            comment: "Identity top-up sheet — custom amount below the floor"),
        IdentityTopUpViewModel.customMinimumDuffs.dashAmount
            .formattedDashAmountWithoutCurrencySymbol)

    private static let feeEstimateUnavailableMessage = NSLocalizedString(
        "There was an error, please try again later",
        comment: "Internal transfer fee estimate unavailable")

    var canContinue: Bool {
        // Gate on duffs, not raw DASH: a sub-duff amount (e.g. 1e-9 DASH)
        // renders as 0 in the confirm sheet, so it must not enable Continue —
        // otherwise the credit routes would submit a nonzero amount while the
        // UI shows 0.
        guard dashDuffsUnsigned > 0, !isBlockedBySync else { return false }
        if isIdentitySource { return canContinueFromIdentity }
        if isIdentityDestination { return canContinueToIdentity }
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
            // This asset-lock route carves its processing fee from the locked
            // value rather than charging it on top. What still bounds it is
            // the funding spend itself — confirmed UTXOs minus the L1 fee
            // reserve, which is exactly `coreSpendableDuffs`.
            return dashDuffsUnsigned <= coreSpendableDuffs
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
            // cover amount + fee. Fails closed if the reserve is unavailable.
            return canAffordShieldedSpend(reserveCredits: feeReserveCredits)
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

    /// Continue gate for the Identity destination. Each funding source
    /// carries the envelope its executor really enforces:
    /// - Core: an asset lock that carves its processing fee from the locked
    ///   value — bounded by the fee-aware spendable balance, exactly like
    ///   Core → Platform.
    /// - Platform: the executor's own planner ceiling
    ///   (`platformIdentityFundableDuffs`); `nil` fails closed.
    /// - Shielded: the funding's first step is an unshield with its fee on
    ///   top, so the Shielded → Platform envelope applies verbatim.
    /// The floor is the top-up executor's own minimum; the executor's plan
    /// remains the final authority at Confirm and surfaces its own error.
    /// Continue gate for the Identity source: an identity exists, the amount
    /// clears the consensus withdrawal floor (transparent payouts only), and
    /// it fits under the credit balance less the fee reserve the transition
    /// is charged on top. The executor's own failure remains the final
    /// authority at Confirm.
    private var canContinueFromIdentity: Bool {
        guard identityId != nil else { return false }
        if resolvedWithdrawalTarget == .transparent,
           creditsPreview < IdentityWithdrawViewModel.minimumWithdrawalCredits {
            return false
        }
        return creditsPreview <= IdentityWithdrawViewModel.spendableCredits(
            balanceCredits: identityBalanceCredits)
    }

    private var canContinueToIdentity: Bool {
        guard identityId != nil,
              dashDuffsUnsigned >= IdentityTopUpViewModel.customMinimumDuffs
        else { return false }
        switch source {
        case .core:
            return dashDuffsUnsigned <= coreSpendableDuffs
        case .platform:
            guard let ceiling = platformIdentityFundableDuffs else { return false }
            return dashDuffsUnsigned <= ceiling
        case .shielded:
            return canAffordShieldedSpend(reserveCredits: feeReserveCredits)
        }
    }

    /// Fee/selection headroom (credits) the SDK requires ON TOP of the amount
    /// for the active route, used by `canContinue` and Max. `nil` means the
    /// requirement is currently unavailable for a fee-reserved route → callers
    /// fail closed (block). A literal `0` (the asset-lock route) is NOT `nil` —
    /// that route reserves nothing from the source balance.
    private var feeReserveCredits: UInt64? {
        if isIdentitySource {
            // Charged to the identity on top of the amount, and unpriced by
            // the SDK — the conservative reserve is what bounds the spend.
            return IdentityWithdrawViewModel.feeHeadroomCredits
        }
        if isIdentityDestination {
            switch source {
            case .core:
                // Asset lock — the processing fee is carved from the locked
                // value, nothing is reserved from the source balance.
                return 0
            case .platform:
                // Governed by the funding planner's own headroom, already
                // folded into `platformIdentityFundableDuffs`.
                return nil
            case .shielded:
                // The funding unshield's fee scales with the spent notes —
                // reserve the worst case, same as the Shielded → Platform
                // route below.
                return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(
                    kind: .unshield,
                    numActions: ShieldedActionBudget.maxActionsPerTransition)
            }
        }
        switch route {
        case .coreToShielded, .coreToPlatform:
            // Core→Shielded's pool fee is duff-denominated and enforced in
            // the route branches (`canContinue`, Max) directly; Core→Platform
            // carves its fee from the locked value. Neither reserves credits
            // from the source balance here.
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

    /// Formatted identity credit balance as DASH for the destination picker's
    /// Identity row (max 5 fraction digits). Reads zero until
    /// `refreshIdentitySnapshot` has run, which `init` does eagerly so the row
    /// is right before the destination is ever selected.
    var identityBalanceFormatted: String {
        Self.cardBalanceString(duffs: identityBalanceCredits / 1000)
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
        if isIdentitySource {
            fillIdentityWithdrawalMax()
            return
        }
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
            // Fee-aware max: spendable minus the send fee reserve (mirrors
            // DSAccount.maxOutputAmount), never the raw total — the asset-lock
            // spends core UTXOs and still needs room for the L1 fee.
            sourceDuffs = coreSpendableDuffs
            if sourceDuffs == 0 {
                maxNotice = Self.coreZeroMaxMessage(
                    totalDuffs: coreBalanceDuffs,
                    confirmedSpendableDuffs: SwiftDashSDKWalletState.shared.balance?.spendable ?? 0)
            } else if sourceDuffs < coreBalanceDuffs {
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

    /// Identity Max: the credit balance less the fee reserve the transition
    /// is charged on top. Unlike the balance routes there is no preflight to
    /// wait on — the reserve is a fixed bound — so this always resolves.
    private func fillIdentityWithdrawalMax() {
        clearMaxSelection()
        let spendable = IdentityWithdrawViewModel.spendableCredits(
            balanceCredits: identityBalanceCredits)
        if spendable == 0 {
            maxNotice = Self.feeReserveExceedsIdentityBalanceMessage
        } else {
            // The card shows the whole credit balance, so a Max that lands
            // below it reads as a bug unless the reserve is accounted for.
            maxNotice = Self.identityHeldBackMessage(
                identityBalanceCredits - spendable)
        }

        isApplyingMax = true
        defer { isApplyingMax = false }
        applyMaxAmountText(spendable / 1000)
    }

    private static let feeReserveExceedsIdentityBalanceMessage = NSLocalizedString(
        "Your Identity balance is too low to cover the transfer fee.",
        comment: "Identity withdrawal — balance below the fee reserve")

    private static func identityHeldBackMessage(_ heldBackCredits: UInt64) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(
                "%@ DASH is held back to cover the transfer fee.",
                comment: "Identity withdrawal — Max reserve note"),
            (heldBackCredits / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol)
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

    private static let platformShieldPreflightLoadingMessage = NSLocalizedString(
        "Checking how much of your Platform balance can be moved…",
        comment: "Platform to Shielded preflight in progress")

    private static let platformShieldPreflightUnavailableMessage = NSLocalizedString(
        "Could not check the available Platform balance. Sync and try again.",
        comment: "Platform to Shielded preflight failed")

    private static let platformShieldCapacityRefreshRequiredMessage = NSLocalizedString(
        "Your available Platform balance changed, but the new maximum could not be checked. The amount was not changed. Sync and try again.",
        comment: "Platform Shield capacity changed but refresh failed")

    private static let platformShieldResyncInProgressMessage = NSLocalizedString(
        "Refreshing your Platform balance before checking the new maximum…",
        comment: "Platform Shield manual resync in progress")

    private static let platformShieldHeadroomUnavailableMessage = NSLocalizedString(
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
