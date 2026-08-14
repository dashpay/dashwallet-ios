//
//  SendViewModel.swift
//  DashWallet
//

import Combine
import Foundation
import SwiftDashSDK
import UIKit

@MainActor
final class SendViewModel: ObservableObject {

    /// What the entered address IS — decoded from the text, never guessed.
    /// Shielded carries the recipient's raw 43-byte Orchard payload so the
    /// confirm flow doesn't have to re-decode the bech32m.
    enum DestinationKind: Equatable {
        case core
        case platform
        case shielded(raw43: Data)

        var network: ChainNetwork {
            switch self {
            case .core: return .core
            case .platform: return .platform
            case .shielded: return .shielded
            }
        }
    }

    /// Every (source balance → destination address type) leg the Send screen
    /// can execute. Core → Core rides the classic L1 payment processor; the
    /// rest run through `ShieldedTransferCoordinator` / the Platform seam.
    enum Route: Equatable {
        case coreToCore
        /// BIP44 UTXOs → asset lock → Type 18 shield note for the
        /// recipient's Orchard address (remainder semantics: they receive
        /// `lock_value − pool_fee`).
        case coreToShielded
        case platformToPlatform
        case platformToCore
        case shieldedToCore
        case shieldedToPlatform
        case shieldedToShielded
    }

    @Published var addressText: String = "" {
        didSet { destinationDidChange() }
    }
    @Published private(set) var destination: DestinationKind? = nil
    /// The balance the user is sending FROM. Constrained to
    /// `validSources`; re-picked automatically when the destination changes.
    @Published var source: ChainNetwork = .core {
        didSet { sourceDidChange() }
    }
    private var isApplyingMax = false
    @Published var amountText: String = "0" {
        didSet {
            guard !isApplyingMax else { return }
            clearShieldedMaxSelection()
        }
    }
    @Published private(set) var isFullShieldedSweep = false
    @Published private(set) var shieldedMaxNotice: String?
    /// Exact duff amount selected by Max. The two-decimal fiat value is only
    /// its display representation and must not be converted back for sending.
    private var maxAmountDuffs: UInt64?
    private var shieldedSweepAmountCredits: UInt64?
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
    @Published private(set) var clipboardSuggestion: ClipboardSuggestion? = nil

    // Balances — same feeds as `InternalTransferViewModel` (BIP44 duffs,
    // DIP-17 credits, Orchard credits).
    @Published private(set) var coreBalanceDuffs: UInt64 = 0
    @Published private(set) var platformCredits: UInt64 = 0
    @Published private(set) var shieldedBalance: UInt64 = 0

    /// Largest amount the pool can fund inside ONE transition — the same
    /// note-aware number Max produces. A typed amount above this needs more
    /// notes than `ShieldedActionBudget` admits, so the bundle would exceed the
    /// 20 KiB state-transition limit and be rejected at broadcast, after the
    /// proof was already built. `nil` while the note set is mid-reconcile
    /// (`sweepAvailability` is not `.ready`), in which case the amount screen
    /// falls back to the balance envelope alone.
    @Published private(set) var shieldedSpendCeilingCredits: UInt64?

    /// Live result of `preflightWithdrawal()` for the Platform → Core route —
    /// same semantics as the internal transfer's: `nil` while unknown,
    /// affordability fails closed.
    @Published private(set) var withdrawalPreflight: ManagedPlatformAddressWallet.WithdrawalPreflight?
    private var preflightTask: Task<Void, Never>?

    /// Drives the one-time restore gate reactively. A normal catch-up may set
    /// this to false, but it only blocks while the recovery marker is active.
    @Published private(set) var isChainSynced = SyncingActivityMonitor.shared.state == .syncDone

    private var cancellables = Set<AnyCancellable>()

    /// Set by the balance-row send sheet: the source is fixed to the tapped
    /// balance instead of being user-pickable, and an address whose type
    /// that balance can't pay surfaces as a mismatch (`pinnedSourceMismatch`)
    /// rather than silently re-picking the source.
    let pinnedSource: ChainNetwork?

    deinit {
        // The monitor holds observers strongly — without this the VM (and
        // its Combine pipelines) outlive the screen.
        SyncingActivityMonitor.shared.remove(observer: self)
    }

    init(pinnedSource: ChainNetwork? = nil) {
        self.pinnedSource = pinnedSource
        if let pinnedSource {
            source = pinnedSource
        }
        refreshClipboardSuggestion()
        SyncingActivityMonitor.shared.add(observer: self)

        NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshClipboardSuggestion() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshClipboardSuggestion() }
            .store(in: &cancellables)

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
                self?.refreshShieldedSpendCeiling()
            }
            .store(in: &cancellables)
    }

    /// Fee kind for the pool-spending routes; `nil` for every other route.
    private func shieldedFeeKind(for route: Route?) -> PlatformWalletManager.ShieldedFeeKind? {
        switch route {
        case .shieldedToCore: return .withdrawal
        case .shieldedToPlatform: return .unshield
        case .shieldedToShielded: return .transfer
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

    // MARK: - Destination classification

    /// Forwards to `DashAddressClassifier` — the single wire-form decoder,
    /// shared with the QR scan gate (which classifies off-main).
    static func classify(_ text: String) -> DestinationKind? {
        switch DashAddressClassifier.classify(text) {
        case .core: return .core
        case .platform: return .platform
        case .shielded(let raw43): return .shielded(raw43: raw43)
        case nil: return nil
        }
    }

    /// The trimmed entered address (what execution should use).
    var trimmedAddress: String {
        addressText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when there's enough text to judge and it doesn't decode to any
    /// known address form — drives the inline error label.
    var showsInvalidAddress: Bool {
        destination == nil && trimmedAddress.count >= 20
    }

    private func destinationDidChange() {
        let sanitized = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized != addressText {
            addressText = sanitized
            return // didSet re-enters with the sanitized text
        }
        let newDestination = Self.classify(addressText)
        guard newDestination != destination else { return }
        destination = newDestination

        // Keep the source legal for the new destination; prefer keeping the
        // user's pick, else the first valid source that has any balance,
        // else the first valid source. A pinned source never moves — an
        // incompatible destination reads back as `pinnedSourceMismatch`.
        let valid = validSources
        if pinnedSource == nil, !valid.isEmpty, !valid.contains(source) {
            source = valid.first { balanceDuffs(of: $0) > 0 } ?? valid[0]
        }
        routeDidChange()
    }

    /// True when the entered address is valid but its type can't be paid
    /// from the pinned source (e.g. a Platform address while sending from
    /// the Transparent balance) — drives the inline mismatch label.
    var pinnedSourceMismatch: Bool {
        pinnedSource != nil && destination != nil && route == nil
    }

    /// Localized name of the pinned source balance, for the mismatch label.
    var pinnedSourceTitle: String {
        switch pinnedSource {
        case .core, nil:
            return NSLocalizedString("Transparent", comment: "Balance breakdown")
        case .platform:
            return NSLocalizedString("Platform", comment: "Dash Platform chain")
        case .shielded:
            return NSLocalizedString("Shielded", comment: "")
        }
    }

    private func sourceDidChange() {
        routeDidChange()
    }

    // MARK: - Sources & route

    /// Which balances can fund a send to the entered destination.
    /// Core addresses can be paid from any bucket; Platform addresses from
    /// Platform credits or the shielded pool (there is no external
    /// core → platform funding); shielded addresses from the pool or the
    /// Core balance (asset-lock shield — `shieldedShield` has no recipient
    /// parameter, so Platform credits can't pay an external shielded
    /// address).
    var validSources: [ChainNetwork] {
        switch destination {
        case .core: return [.core, .platform, .shielded]
        case .platform: return [.platform, .shielded]
        case .shielded: return [.shielded, .core]
        case nil: return []
        }
    }

    var route: Route? {
        guard let destination else { return nil }
        switch (source, destination) {
        case (.core, .core): return .coreToCore
        case (.core, .shielded): return .coreToShielded
        case (.platform, .platform): return .platformToPlatform
        case (.platform, .core): return .platformToCore
        case (.shielded, .core): return .shieldedToCore
        case (.shielded, .platform): return .shieldedToPlatform
        case (.shielded, .shielded): return .shieldedToShielded
        default: return nil
        }
    }

    /// Refreshes route-dependent async state — the Platform → Core route
    /// needs the withdrawal preflight (fee headroom + full-balance payout).
    private func routeDidChange() {
        clearShieldedMaxSelection()
        refreshShieldedSpendCeiling()
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

    // MARK: - Clipboard

    struct ClipboardSuggestion: Equatable {
        let address: String
        let kind: DestinationKind
    }

    func refreshClipboardSuggestion() {
        guard let raw = UIPasteboard.general.string else {
            clipboardSuggestion = nil
            return
        }
        clipboardSuggestion = Self.detect(in: raw)
    }

    func useClipboardSuggestion() {
        guard let suggestion = clipboardSuggestion else { return }
        addressText = suggestion.address
    }

    private static func detect(in raw: String) -> ClipboardSuggestion? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        for candidate in trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(candidate)
            if let kind = classify(word) {
                return ClipboardSuggestion(address: word, kind: kind)
            }
        }
        return nil
    }

    /// Scanned QR → address text. The classifier decides what it is; a
    /// BIP21 `dash:` URI contributes its address (and its amount when the
    /// screen's amount is still untouched).
    func ingestScannedInput(_ paymentInput: DWPaymentInput) {
        if let address = paymentInput.parsedURI?.address, !address.isEmpty {
            addressText = address
            let scannedAmount = paymentInput.parsedURI?.amount ?? 0
            if scannedAmount > 0, dashDuffsUnsigned == 0 {
                unit = .dash
                amountText = scannedAmount.formattedDashAmountWithoutCurrencySymbol
            }
            return
        }
        if let raw = paymentInput.userDetails, Self.classify(raw) != nil {
            addressText = raw
        }
    }

    // MARK: - Amount

    /// The raw numeric value the user has typed, locale comma normalised.
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

    var dashDuffs: Int64 {
        Int64(parsedDashAmount.plainDashAmount)
    }

    var dashDuffsUnsigned: UInt64 {
        parsedDashAmount.plainDashAmount
    }

    /// Credit amount handed to the SDK, aligned to duff precision (1 duff =
    /// 1000 credits) — same rationale as the internal transfer's.
    var creditsPreview: UInt64 {
        if isFullShieldedSweep, let shieldedSweepAmountCredits {
            return shieldedSweepAmountCredits
        }
        return NSDecimalNumber(decimal: Decimal(dashDuffsUnsigned) * 1000).uint64Value
    }

    var fiatAmountString: String {
        CurrencyExchanger.shared.fiatAmountString(for: parsedDashAmount)
    }

    var fiatCurrencyCode: String {
        App.fiatCurrency
    }

    // MARK: - Balance cards

    var coreBalanceFormatted: String {
        InternalTransferViewModel.cardBalanceString(duffs: coreBalanceDuffs)
    }

    var platformCreditsFormatted: String {
        InternalTransferViewModel.cardBalanceString(duffs: platformCredits / 1000)
    }

    var shieldedBalanceFormatted: String {
        InternalTransferViewModel.cardBalanceString(duffs: shieldedBalance / 1000)
    }

    /// A source's balance normalised to duffs, for the "first source with
    /// funds" auto-pick.
    private func balanceDuffs(of network: ChainNetwork) -> UInt64 {
        switch network {
        case .core: return coreBalanceDuffs
        case .platform: return platformCredits / 1000
        case .shielded: return shieldedBalance / 1000
        }
    }

    // MARK: - Validation

    /// Fixed selection reserve mirrored from the internal transfer (Rust
    /// `FEE_RESERVE_CREDITS`) — see `InternalTransferViewModel`.
    private static let shieldSelectionReserveCredits: UInt64 = 1_000_000_000

    /// Conservative Platform credit-transfer fee headroom, matching the
    /// "Max fee: ~0.001 DASH" the transfer executor states (0.001 DASH =
    /// 1e8 credits). The metered fee is deducted from the source balance on
    /// top of the sent amount.
    private static let platformTransferFeeReserveCredits: UInt64 = 100_000_000

    /// Fee/selection headroom (credits) the route requires ON TOP of the
    /// amount. `nil` = requirement unavailable → callers fail closed.
    private var feeReserveCredits: UInt64? {
        switch route {
        case .coreToCore, .coreToShielded, .platformToCore, nil:
            // L1 send fees are handled by the payment processor; the
            // asset-lock shield carves its pool fee from the locked value
            // (nothing reserved from the Core balance, mirroring the
            // internal transfer); the full-balance platform withdrawal
            // nets its fee out of the preflighted payout.
            return 0
        case .platformToPlatform:
            return Self.platformTransferFeeReserveCredits
        case .shieldedToCore:
            // Worst-case note selection for a bundle the size limit actually
            // admits — same reasoning as the internal transfer's reserve.
            return try? PlatformWalletManager.estimateShieldedFee(
                kind: .withdrawal,
                numActions: ShieldedActionBudget.maxActionsPerTransition)
        case .shieldedToPlatform:
            return try? PlatformWalletManager.estimateShieldedFee(
                kind: .unshield,
                numActions: ShieldedActionBudget.maxActionsPerTransition)
        case .shieldedToShielded:
            return try? PlatformWalletManager.estimateShieldedFee(
                kind: .transfer,
                numActions: ShieldedActionBudget.maxActionsPerTransition)
        }
    }

    private func creditsMinusFeeReserve(_ balanceCredits: UInt64) -> UInt64 {
        guard let fee = feeReserveCredits else { return 0 }
        return TransferSpendAmountPolicy.spendableCredits(
            balanceCredits: balanceCredits,
            feeReserveCredits: fee)
    }

    /// Net payout of the full-balance Platform → Core withdrawal (duffs);
    /// `nil` until the preflight resolves positively.
    var platformWithdrawableDuffs: UInt64? {
        guard let preflight = withdrawalPreflight, preflight.canWithdraw else { return nil }
        return preflight.netWithdrawable / 1000
    }

    /// Upper bound (credits) for a PARTIAL Platform → Core withdrawal —
    /// mirrors the internal transfer's single-input cap.
    var partialWithdrawCapCredits: UInt64 {
        guard let preflight = withdrawalPreflight, preflight.canWithdraw else { return 0 }
        let largest = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.map(\.balance).max() ?? 0
        return largest > preflight.estimatedFee ? largest - preflight.estimatedFee : 0
    }

    /// True when the typed amount is exactly the full-balance net payout —
    /// confirm then runs the AUTO (all-addresses) withdrawal.
    var isFullPlatformWithdrawal: Bool {
        route == .platformToCore
            && platformWithdrawableDuffs != nil
            && dashDuffsUnsigned == platformWithdrawableDuffs
    }

    /// Only Core-funded routes during a restored wallet's first sync block.
    var isBlockedBySync: Bool {
        guard let route else { return false }
        switch route {
        case .coreToCore, .coreToShielded:
            return WalletSendService.isBlockedByInitialRestoreSync(
                isResyncingWallet: DWGlobalOptions.sharedInstance().isResyncingWallet,
                isChainSynced: isChainSynced)
        default:
            return false
        }
    }

    /// Type-18's pool fee is carved out of the one-time asset-lock value.
    /// Reuse the internal-transfer policy so external sends to a shielded
    /// address cannot reach Confirm with an amount the SDK must reject.
    var coreToShieldedMinimumAmountDuffs: UInt64? {
        guard route == .coreToShielded,
              let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits
        else { return nil }
        return CoreToShieldedAmountPolicy.minimumAmountDuffs(
            poolFeeCredits: poolFeeCredits)
    }

    /// Inline explanation for an amount rejected before Confirm. Keep zero
    /// quiet until the user types.
    var amountValidationMessage: String? {
        if let shieldedMaxNotice { return shieldedMaxNotice }
        guard dashDuffsUnsigned > 0, let route else { return nil }

        // Route minimum first: below the Type-18 pool fee the SDK refuses the
        // asset lock however much Core balance backs it.
        if route == .coreToShielded {
            guard let minimumDuffs = coreToShieldedMinimumAmountDuffs else {
                return Self.feeEstimateUnavailableMessage
            }
            if dashDuffsUnsigned < minimumDuffs {
                let formattedMinimum =
                    "\(minimumDuffs.formattedDashAmountWithoutCurrencySymbol) DASH"
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "The minimum amount you can send is %@",
                        comment: "External shielded send minimum amount"),
                    formattedMinimum)
            }
        }

        return insufficientBalanceMessage
    }

    /// "You don't have that much" for the ACTIVE route, named after the balance
    /// it spends. Mirrors `canContinue`'s envelope route by route so a Continue
    /// button disabled on affordability is never left unexplained.
    private var insufficientBalanceMessage: String? {
        guard let route else { return nil }
        let balanceName = source.balanceName

        switch route {
        case .coreToCore, .coreToShielded:
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedDuffs: dashDuffsUnsigned,
                spendableDuffs: coreBalanceDuffs)

        case .platformToPlatform:
            guard let reserve = feeReserveCredits else {
                return Self.feeEstimateUnavailableMessage
            }
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedCredits: creditsPreview,
                balanceCredits: platformCredits,
                feeReserveCredits: reserve)

        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
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
        comment: "External send fee estimate unavailable")

    /// Gate for advancing from the address step to the amount step: the
    /// entered address decodes to a known destination and — on the balance-row
    /// send sheet — the pinned source can actually pay that destination type.
    /// The amount, balance, and sync checks live on the amount step
    /// (`canContinue`).
    var canAdvanceToAmount: Bool {
        destination != nil && !pinnedSourceMismatch
    }

    var canContinue: Bool {
        guard dashDuffsUnsigned > 0, let route, !isBlockedBySync else { return false }
        switch route {
        case .coreToCore:
            // The L1 fee rides on top; the payment processor rejects an
            // unfundable send with its own error, so gate on the balance only.
            return dashDuffsUnsigned <= coreBalanceDuffs
        case .coreToShielded:
            // Asset-lock route: the pool fee is carved from the locked value
            // and the Rust side rejects an undersized lock. Enforce the same
            // strict minimum as the internal Core → Shielded transfer before
            // opening Confirm.
            guard let minimumDuffs = coreToShieldedMinimumAmountDuffs,
                  dashDuffsUnsigned >= minimumDuffs
            else { return false }
            return dashDuffsUnsigned <= coreBalanceDuffs
        case .platformToPlatform:
            guard let reserve = feeReserveCredits else { return false }
            return platformCredits >= reserve
                && creditsPreview <= platformCredits - reserve
        case .platformToCore:
            guard withdrawalPreflight?.canWithdraw == true else { return false }
            if isFullPlatformWithdrawal { return true }
            return creditsPreview <= partialWithdrawCapCredits
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
            if isFullShieldedSweep {
                return shieldedSweepAmountCredits != nil
            }
            if let ceiling = shieldedSpendCeilingCredits {
                return creditsPreview <= ceiling
            }
            guard let reserve = feeReserveCredits else { return false }
            return shieldedBalance >= reserve
                && creditsPreview <= shieldedBalance - reserve
        }
    }

    // MARK: - Max

    /// Source-aware Max fill — same envelopes as the internal transfer.
    func fillMaxFromWallet() {
        clearShieldedMaxSelection()
        let sourceDuffs: UInt64
        switch route {
        case .coreToCore, .coreToShielded, nil:
            // Fee-aware max: spendable minus the send fee reserve (mirrors
            // DSAccount.maxOutputAmount), never the raw total — which would
            // include unconfirmed/immature funds and leave no room for the fee.
            sourceDuffs = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
        case .platformToPlatform:
            sourceDuffs = creditsMinusFeeReserve(platformCredits) / 1000
        case .platformToCore:
            sourceDuffs = platformWithdrawableDuffs ?? 0
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
            // All three spend the pool, so all three plan Max against the real
            // note set. A flat reserve here would price a full-size bundle and
            // hand the unspent difference back as a change note.
            guard let feeKind = shieldedFeeKind(for: route) else { return }
            switch ShieldedTransferCoordinator.sweepAvailability(feeKind: feeKind) {
            case .ready(let plan):
                isFullShieldedSweep = true
                shieldedSweepAmountCredits = plan.amountCredits
                if plan.remainingCredits > 0 {
                    shieldedMaxNotice = Self.shieldedRemainderMessage(plan.remainingCredits)
                }
                sourceDuffs = plan.amountCredits / 1000
            case .waitingForConfirmation(let credits):
                shieldedMaxNotice = Self.shieldedConfirmingMessage(credits)
                sourceDuffs = 0
            case .unavailable:
                shieldedMaxNotice = NSLocalizedString(
                    "Your Shielded balance is not ready to spend. Sync and try Max again.",
                    comment: "Shielded Max unavailable")
                sourceDuffs = 0
            }
        }

        isApplyingMax = true
        defer { isApplyingMax = false }
        applyMaxAmountText(sourceDuffs)
    }

    /// Keep the selected Max amount exact in duffs while rendering either
    /// DASH or an approximate two-decimal fiat value.
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
                amountText = InternalTransferViewModel.formatTyped(fiat, fractionDigits: 2)
            } else {
                maxAmountDuffs = nil
                amountText = "0"
            }
        }
    }

    private func clearShieldedMaxSelection() {
        maxAmountDuffs = nil
        isFullShieldedSweep = false
        shieldedSweepAmountCredits = nil
        shieldedMaxNotice = nil
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

    private static func shieldedRemainderMessage(_ credits: UInt64) -> String {
        let formatted = (credits / 1000).formattedDashAmountWithoutCurrencySymbol
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
                amountText = InternalTransferViewModel.formatTyped(fiat, fractionDigits: 2)
            case (.fiat, .dash):
                let dash = try CurrencyExchanger.shared.convertToDash(amount: raw, currency: currency)
                amountText = InternalTransferViewModel.formatTyped(dash, fractionDigits: 8)
            default:
                break
            }
        } catch {
            // Rate fetch failed — leave `amountText` as-is so the user can re-type.
        }
    }
}


// MARK: - SyncingActivityMonitorObserver

extension SendViewModel: SyncingActivityMonitorObserver {
    nonisolated func syncingActivityMonitorProgressDidChange(_ progress: Double) {}

    nonisolated func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State,
                                                          state: SyncingActivityMonitor.State) {
        Task { @MainActor in
            self.isChainSynced = state == .syncDone
        }
    }
}
