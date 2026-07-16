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
    @Published var amountText: String = "0"
    @Published var unit: InternalTransferUnit = .dash {
        didSet {
            guard oldValue != unit else { return }
            convertAmountText(from: oldValue, to: unit)
        }
    }
    @Published private(set) var clipboardSuggestion: ClipboardSuggestion? = nil

    // Balances — same feeds as `InternalTransferViewModel` (BIP44 duffs,
    // DIP-17 credits, Orchard credits).
    @Published private(set) var coreBalanceDuffs: UInt64 = 0
    @Published private(set) var platformCredits: UInt64 = 0
    @Published private(set) var shieldedBalance: UInt64 = 0

    /// Live result of `preflightWithdrawal()` for the Platform → Core route —
    /// same semantics as the internal transfer's: `nil` while unknown,
    /// affordability fails closed.
    @Published private(set) var withdrawalPreflight: ManagedPlatformAddressWallet.WithdrawalPreflight?
    private var preflightTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    /// Set by the balance-row send sheet: the source is fixed to the tapped
    /// balance instead of being user-pickable, and an address whose type
    /// that balance can't pay surfaces as a mismatch (`pinnedSourceMismatch`)
    /// rather than silently re-picking the source.
    let pinnedSource: ChainNetwork?

    init(pinnedSource: ChainNetwork? = nil) {
        self.pinnedSource = pinnedSource
        if let pinnedSource {
            source = pinnedSource
        }
        refreshClipboardSuggestion()

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

        if let manager = SwiftDashSDKHost.shared.manager,
           let wallet = SwiftDashSDKHost.shared.wallet {
            let walletId = wallet.walletId
            shieldedBalance = manager.lastShieldedSyncEvent?
                .result(for: walletId)?
                .balance ?? 0

            manager.$lastShieldedSyncEvent
                .receive(on: RunLoop.main)
                .sink { [weak self] event in
                    guard let self else { return }
                    if let walletResult = event?.result(for: walletId),
                       walletResult.success,
                       !walletResult.cooldownSkip {
                        self.shieldedBalance = walletResult.balance
                    }
                }
                .store(in: &cancellables)
        }
    }

    // MARK: - Destination classification

    /// Decode `text` into what it actually is on the wire:
    /// - Base58Check L1 address (network-checked) → `.core`
    /// - bech32m HRP `dash`/`tdash` (current network), 21-byte payload with a
    ///   DIP-0018 wire type byte (0xb0 P2PKH / 0x80 P2SH) → `.platform`
    /// - bech32m, 44-byte payload `0x10` + 43 raw Orchard bytes → `.shielded`
    /// Anything else (wrong-network HRP included) → nil.
    static func classify(_ text: String) -> DestinationKind? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.isValidDashAddressForCurrentNetwork {
            return .core
        }

        guard let decoded = Bech32m.decode(trimmed.lowercased()) else { return nil }
        let expectedHrp = Bech32m.platformHrp(mainnet: !WalletEnvironment.isTestnet)
        guard decoded.hrp == expectedHrp else { return nil }

        if decoded.data.count == 21,
           decoded.data[0] == 0xb0 || decoded.data[0] == 0x80 {
            return .platform
        }
        // DIP-0018 shielded display form: 0x10 type byte + 43 raw Orchard
        // bytes (the encoding `PaymentsLandingViewModel.reloadShieldedAddress`
        // produces for our own address).
        if decoded.data.count == 44, decoded.data[0] == 0x10 {
            return .shielded(raw43: decoded.data.subdata(in: 1..<44))
        }
        return nil
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
        NSDecimalNumber(decimal: Decimal(dashDuffsUnsigned) * 1000).uint64Value
    }

    var fiatAmountString: String {
        CurrencyExchanger.shared.fiatAmountString(for: parsedDashAmount)
    }

    var primaryCurrencySymbol: String {
        NumberFormatter.fiatFormatter.currencySymbol ?? ""
    }

    var secondaryDisplayString: String {
        switch unit {
        case .dash:
            return CurrencyExchanger.shared.fiatAmountString(for: parsedDashAmount)
        case .fiat:
            return parsedDashAmount.formattedDashAmount
        }
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
            // Worst-case note selection (16 actions) — same reasoning as the
            // internal transfer's reserve.
            return try? PlatformWalletManager.estimateShieldedFee(kind: .withdrawal, numActions: 16)
        case .shieldedToPlatform:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .unshield, numActions: 16)
        case .shieldedToShielded:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .transfer, numActions: 16)
        }
    }

    private func creditsMinusFeeReserve(_ balanceCredits: UInt64) -> UInt64 {
        guard let fee = feeReserveCredits else { return 0 }
        return balanceCredits > fee ? balanceCredits - fee : 0
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

    var canContinue: Bool {
        guard dashDuffsUnsigned > 0, let route else { return false }
        switch route {
        case .coreToCore:
            // The L1 fee rides on top; the payment processor rejects an
            // unfundable send with its own error, so gate on the balance only.
            return dashDuffsUnsigned <= coreBalanceDuffs
        case .coreToShielded:
            // Asset-lock route: the pool fee is carved from the locked value
            // and the Rust side rejects an undersized lock — same envelope
            // as the internal Core → Shielded transfer.
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
            guard let reserve = feeReserveCredits else { return false }
            return shieldedBalance >= reserve
                && creditsPreview <= shieldedBalance - reserve
        }
    }

    // MARK: - Max

    /// Source-aware Max fill — same envelopes as the internal transfer.
    func fillMaxFromWallet() {
        let sourceDuffs: UInt64
        switch route {
        case .coreToCore, .coreToShielded, nil:
            sourceDuffs = coreBalanceDuffs
        case .platformToPlatform:
            sourceDuffs = creditsMinusFeeReserve(platformCredits) / 1000
        case .platformToCore:
            sourceDuffs = platformWithdrawableDuffs ?? 0
        case .shieldedToCore, .shieldedToPlatform, .shieldedToShielded:
            sourceDuffs = creditsMinusFeeReserve(shieldedBalance) / 1000
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
                amountText = InternalTransferViewModel.formatTyped(fiat, fractionDigits: 2)
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
