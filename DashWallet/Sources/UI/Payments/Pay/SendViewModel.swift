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
        /// recipient's Orchard address. The pool fee rides on top: the
        /// coordinator locks `amount + pool_fee`, so the recipient receives
        /// the full typed amount.
        case coreToShielded
        case platformToPlatform
        case platformToCore
        /// Platform Payment credits → Type 15 shield note assigned to the
        /// recipient's Orchard address (`shieldedShieldToRecipient`). Same
        /// input selection and flat fee as the internal shield; the note
        /// funds the RECIPIENT's pool.
        case platformToShielded
        case shieldedToCore
        case shieldedToPlatform
        case shieldedToShielded
    }

    @Published var addressText: String = "" {
        didSet { destinationDidChange() }
    }
    @Published private(set) var destination: DestinationKind? = nil
    #if DASHPAY
    /// The DashPay contact this send pays, when the flow was opened from the
    /// contact picker instead of the address field.
    ///
    /// Mutually exclusive with `addressText`: a contact payment has no address
    /// to type, so `trimmedAddress` stays empty for this send's whole life and
    /// the recipient is rendered from the contact instead.
    @Published private(set) var contactRecipient: ContactItem?
    /// True while `sendToContact()` is in flight — the amount step's Send
    /// button shows progress, and `canContinue` refuses a second tap.
    @Published private(set) var isSendingToContact = false
    /// Failure from the last contact send, surfaced by
    /// `amountValidationMessage`. A cancelled PIN prompt never lands here.
    @Published private(set) var contactSendError: String?
    #endif
    /// The balance the user is sending FROM. Constrained to
    /// `validSources`; re-picked automatically when the destination changes.
    @Published var source: ChainNetwork = .core {
        didSet { sourceDidChange() }
    }
    /// True once the From step has been changed by the user. Until then the
    /// source is derived from the destination on every address change: the
    /// initial `.core` is a placeholder, not a decision, and treating it as
    /// one is what left a pasted shielded address funded from the
    /// transparent balance.
    private var userPickedSource = false
    /// Set while `destinationDidChange` derives the source, so its write to
    /// `source` isn't mistaken for a user pick.
    private var isDerivingSource = false
    private var isApplyingMax = false
    @Published var amountText: String = "0" {
        didSet {
            #if DASHPAY
            // A new amount is a new attempt — including one Max filled in, so
            // this precedes the guard below. The previous failure described an
            // amount that is no longer on screen, and it is read ahead of
            // every affordability check in `amountValidationMessage`.
            contactSendError = nil
            #endif
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
    /// One token per address form that currently wants automatic reads. A set
    /// rather than a flag because a host with animated tabs keeps the outgoing
    /// form alive after the incoming one appeared: both are registered at
    /// once, and the outgoing one's removal drops only its own registration.
    private var clipboardMonitors: Set<UUID> = []
    /// The "Send to Address" shortcut's intent, held until a read this screen
    /// was actually allowed to make has run — a deferred or denied read must
    /// not silently consume it.
    private var appliesClipboardSuggestionWhenAvailable = false
    /// Granted by the host for as long as its send surface is on screen.
    /// Closed by default: a host that never opts in must not have the user's
    /// pasteboard read behind its back.
    var isClipboardReadAllowed: () -> Bool = { false }

    // Balances — same feeds as `InternalTransferViewModel` (BIP44 duffs,
    // DIP-17 credits, Orchard credits).
    @Published private(set) var coreBalanceDuffs: UInt64 = 0

    /// L1-fee-aware spendable Core balance — the same envelope Max fills.
    /// Core → Shielded validation checks the fee-inclusive lock against this,
    /// mirroring the internal transfer's `coreSpendableDuffs`.
    var coreSpendableDuffs: UInt64 {
        SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
    }
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
    /// True when the last withdrawal preflight ATTEMPT failed (threw), as
    /// opposed to still resolving — the same distinction
    /// `shieldPreflightFailed` draws below, and for the same reason: a
    /// permanently failed preflight left the amount screen silent, so a
    /// disabled Continue had nothing explaining it. An empty Platform
    /// balance is the ordinary way to get there (`preflightWithdrawal`
    /// throws `noFundedAddress` when no address holds credits).
    @Published private(set) var withdrawalPreflightFailed = false
    private var preflightTask: Task<Void, Never>?

    /// Live result of `preflightShield()` for the Platform → Shielded route —
    /// the SDK's account/address-aware capacity (the aggregate Platform
    /// balance is NOT the authority). `nil` while unknown; affordability
    /// fails closed.
    @Published private(set) var platformShieldCapacity: PlatformShieldCapacity?
    /// True when the last shield preflight ATTEMPT failed (threw), as
    /// opposed to still resolving — distinguishes "checking…" (quiet)
    /// from "could not check" (explained inline).
    @Published private(set) var shieldPreflightFailed = false
    private var shieldPreflightTask: Task<Void, Never>?

    /// Drives the one-time restore gate reactively. A normal catch-up may set
    /// this to false, but it only blocks while the recovery marker is active.
    ///
    /// Seeded from the monitor in `init()` rather than here: a property default
    /// runs in EVERY initializer, and the preview initializer must not spin up
    /// the sync monitor singleton.
    @Published private(set) var isChainSynced = false

    private var cancellables = Set<AnyCancellable>()

    #if DEBUG
    /// True only for `makeForPreview` instances — see the guard in `deinit`.
    private var isPreviewInstance = false
    #endif

    /// Set by the balance-row send sheet: the source is fixed to the tapped
    /// balance instead of being user-pickable, and an address whose type
    /// that balance can't pay surfaces as a mismatch (`pinnedSourceMismatch`)
    /// rather than silently re-picking the source.
    let pinnedSource: ChainNetwork?

    deinit {
        #if DEBUG
        // Preview instances never registered — building the monitor here just
        // to unregister would start reachability inside the canvas.
        if isPreviewInstance { return }
        #endif
        // The monitor holds observers strongly — without this the VM (and
        // its Combine pipelines) outlive the screen.
        SyncingActivityMonitor.shared.remove(observer: self)
    }

    init(pinnedSource: ChainNetwork? = nil) {
        self.pinnedSource = pinnedSource
        if let pinnedSource {
            source = pinnedSource
        }
        SyncingActivityMonitor.shared.add(observer: self)
        isChainSynced = SyncingActivityMonitor.shared.state == .syncDone

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
                guard let self else { return }
                // Only a CHANGED balance restarts the shield preflight —
                // the publisher re-emits on every sync pass, and a restart
                // clears the capacity (fails closed), which would flicker
                // and could starve the preflight of time to resolve.
                let changed = self.platformCredits != credits
                self.platformCredits = credits
                if changed { self.restartShieldPreflightOnBalanceChange() }
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

    #if DEBUG
    /// Lightweight initializer used only by SwiftUI previews. Sets the balances
    /// and the typed destination directly and skips the sync-monitor,
    /// pasteboard and wallet-state wiring the real `init()` sets up.
    ///
    /// Property observers do not fire during initialization, so assigning
    /// `addressText` here also skips the destination parse and preflight the
    /// real screen would run on every keystroke.
    private init(
        previewPinnedSource: ChainNetwork?,
        previewSource: ChainNetwork,
        previewAddressText: String,
        previewAmountText: String,
        previewCoreDuffs: UInt64,
        previewPlatformCredits: UInt64,
        previewShieldedCredits: UInt64,
        previewIsChainSynced: Bool
    ) {
        pinnedSource = previewPinnedSource
        isPreviewInstance = true
        source = previewSource
        addressText = previewAddressText
        amountText = previewAmountText
        coreBalanceDuffs = previewCoreDuffs
        platformCredits = previewPlatformCredits
        shieldedBalance = previewShieldedCredits
        isChainSynced = previewIsChainSynced
    }

    /// Preview view model with stubbed balances. Core is in duffs (1e8 per
    /// DASH), Platform and Shielded in credits (1e11 per DASH); the defaults
    /// are 2.45 / 1.2 / 0.785 DASH.
    ///
    /// `destination` stays `nil` because the address parse never runs here, so
    /// the screen renders its address-entry step rather than a resolved
    /// recipient.
    static func makeForPreview(
        pinnedSource: ChainNetwork? = nil,
        source: ChainNetwork = .core,
        addressText: String = "",
        amountText: String = "0",
        coreDuffs: UInt64 = 245_000_000,
        platformCredits: UInt64 = 120_000_000_000,
        shieldedCredits: UInt64 = 78_500_000_000,
        isChainSynced: Bool = true
    ) -> SendViewModel {
        SendViewModel(
            previewPinnedSource: pinnedSource,
            previewSource: source,
            previewAddressText: addressText,
            previewAmountText: amountText,
            previewCoreDuffs: coreDuffs,
            previewPlatformCredits: platformCredits,
            previewShieldedCredits: shieldedCredits,
            previewIsChainSynced: isChainSynced)
    }
    #endif

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
        #if DASHPAY
        // A contact send has no address. Its destination was set outright by
        // `setContactRecipient`, so it must not be re-derived from the empty
        // address field.
        if contactRecipient != nil { return }
        #endif
        let sanitized = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized != addressText {
            addressText = sanitized
            return // didSet re-enters with the sanitized text
        }
        let newDestination = Self.classify(addressText)
        guard newDestination != destination else { return }
        destination = newDestination

        // Keep an explicit user pick when it is still legal for the new
        // destination; otherwise derive the source from the destination —
        // the first valid source that has any balance, else the first valid
        // source. `validSources` is ordered by preference, so a shielded
        // address funds itself from the pool rather than from the standing
        // `.core` default (which is legal for it, and would therefore have
        // survived a "keep whatever is selected" rule and silently turned a
        // private transfer into an on-chain shield). A pinned source never
        // moves — an incompatible destination reads back as
        // `pinnedSourceMismatch`.
        let valid = validSources
        if pinnedSource == nil, !valid.isEmpty, !userPickedSource || !valid.contains(source) {
            let preferred = valid.first { balanceDuffs(of: $0) > 0 } ?? valid[0]
            if preferred != source {
                setSourceWithoutClaimingUserIntent(preferred)
            }
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
        // `balanceName` rather than a second copy of the same three strings:
        // simple mode renames the Core balance, and one of these lists would
        // have been forgotten.
        (pinnedSource ?? .core).balanceName
    }

    private func sourceDidChange() {
        if !isDerivingSource {
            userPickedSource = true
        }
        routeDidChange()
    }

    /// Move the source without recording it as the user's pick, so a later
    /// destination change is still free to re-derive it.
    private func setSourceWithoutClaimingUserIntent(_ network: ChainNetwork) {
        isDerivingSource = true
        defer { isDerivingSource = false }
        source = network
    }

    // MARK: - Contact recipient

    #if DASHPAY
    /// Open this send on a DashPay contact instead of an address. Called by
    /// the contact picker before the amount step is pushed; the address step
    /// and the From step are both skipped, because neither has anything left
    /// to ask.
    ///
    /// The destination is assigned rather than parsed — there is no text to
    /// parse — and the source is put on Core, the only balance
    /// `contactValidSources` admits.
    func setContactRecipient(_ contact: ContactItem) {
        contactRecipient = contact
        destination = .core
        // Not the user's pick: it is the only legal source, and recording it
        // as a pick would let it survive a later destination change.
        setSourceWithoutClaimingUserIntent(.core)
    }

    /// A contact payment can only be funded from the transparent balance.
    ///
    /// Not a property of DashPay but of the SDK seam as it stands:
    /// `sendDashPayPayment` derives the contact's DIP-15 receive address
    /// inside Rust and builds, signs and broadcasts the L1 transaction there —
    /// the address itself never crosses the FFI boundary. `platformToCore` and
    /// `shieldedToCore` both need a Core address to pay to, so there is
    /// nothing to hand them.
    ///
    /// TODO(dashpay-contact-address): when the SDK exposes the derived
    /// address, a contact becomes an ordinary Core destination — this list
    /// then matches the one `.core` addresses already get in `validSources`,
    /// and `route` stops needing its own contact branch.
    static let contactValidSources: [ChainNetwork] = [.core]

    /// The SDK gave up permanently on this contact's DIP-15 payment channel
    /// (`ContactItem.paymentChannelBroken`), so no amount can be sent on it.
    /// Only a fresh contact request from the CONTACT clears the flag.
    ///
    /// The picker refuses to open such a contact; this is what covers a flag
    /// that arrives from a background sync while the amount step is already up.
    var isContactPaymentUnavailable: Bool {
        contactRecipient?.paymentChannelBroken == true
    }

    /// Shown both on the picker row and in place of the amount validation, so
    /// the two say the same thing.
    static let contactPaymentsUnavailableMessage = NSLocalizedString(
        "Payments unavailable — ask them to send you a new contact request.",
        comment: "DashPay: contact whose payment channel could not be built")

    /// Execute the pay-to-contact spend.
    ///
    /// There is no prepare/confirm split on this path —
    /// `WalletSendService.sendToContact` runs the spend-auth gate and the
    /// SDK's single-shot build+sign+broadcast — so the Send tap on the amount
    /// step is the confirmation, and this is the only route the amount step
    /// executes itself rather than handing on to the L1 payment processor or
    /// `SendConfirmSheet`.
    ///
    /// - Returns: the broadcast transaction's wire-order txid on success;
    ///   `nil` when it failed or the user cancelled the PIN prompt. A
    ///   cancellation leaves `contactSendError` clear — backing out of the
    ///   prompt is not an error.
    /// Set when a contact broadcast came back with an unknown outcome. The
    /// send may have happened, so this screen must not offer it again.
    @Published private(set) var contactSendOutcomeIsUnknown = false

    static let contactSendUnknownOutcomeMessage = NSLocalizedString(
        "We couldn't confirm whether this payment went through. Don't send it again — wait for the wallet to finish synchronizing and check your history.",
        comment: "Send to contact: the broadcast outcome is unknown")

    func sendToContact() async -> Data? {
        guard let contact = contactRecipient,
              canContinue,
              // Re-asked here rather than trusting the gate: this is the value
              // that gets spent.
              let duffs = dashDuffsIfRepresentable
        else { return nil }
        isSendingToContact = true
        contactSendError = nil
        defer { isSendingToContact = false }

        do {
            let (txid, _) = try await WalletSendService.shared.sendToContact(
                contactIdentityId: contact.contactIdentityId,
                amount: duffs)
            // Project the freshly recorded Sent entry to SwiftData right away
            // — the entry lives only in Rust memory until a projection runs,
            // and an app kill before one would lose it permanently (the SDK
            // cannot re-derive sent history).
            SwiftDashSDKContactsService.shared.refreshPaymentsProjection()
            return txid
        } catch {
            let nsError = error as NSError
            if !WalletSendService.isAuthenticationCancelledError(nsError) {
                contactSendError = error.localizedDescription
            }
            // An ambiguous broadcast is terminal, not a failure to retry: the
            // request may well have reached the network and only its response
            // was lost. Leaving the button live invites a second, duplicate
            // payment for a spend that already happened, which no later
            // correction can undo. The message already says to wait for
            // synchronization rather than resend; this makes the screen agree
            // with it.
            if WalletSendService.isBroadcastUnknownError(nsError) {
                contactSendOutcomeIsUnknown = true
            }
            return nil
        }
    }
    #endif

    // MARK: - Sources & route

    /// Which balances can fund a send to the entered destination.
    /// Core addresses can be paid from any bucket; Platform addresses from
    /// Platform credits or the shielded pool (there is no external
    /// core → platform funding); shielded addresses from any bucket — the
    /// pool (`shieldedTransfer`), the Core balance (asset-lock shield), or
    /// Platform credits (`shieldedShieldToRecipient`).
    var validSources: [ChainNetwork] {
        #if DASHPAY
        if contactRecipient != nil { return Self.contactValidSources }
        #endif
        switch destination {
        case .core: return [.core, .platform, .shielded]
        case .platform: return [.platform, .shielded]
        case .shielded: return [.shielded, .core, .platform]
        case nil: return []
        }
    }

    var route: Route? {
        #if DASHPAY
        if contactRecipient != nil {
            // A contact payment is a transparent L1 spend; `contactValidSources`
            // admits nothing else, so any other source is not a route this flow
            // can execute.
            return source == .core ? .coreToCore : nil
        }
        #endif
        guard let destination else { return nil }
        switch (source, destination) {
        case (.core, .core): return .coreToCore
        case (.core, .shielded): return .coreToShielded
        case (.platform, .platform): return .platformToPlatform
        case (.platform, .core): return .platformToCore
        case (.platform, .shielded): return .platformToShielded
        case (.shielded, .core): return .shieldedToCore
        case (.shielded, .platform): return .shieldedToPlatform
        case (.shielded, .shielded): return .shieldedToShielded
        default: return nil
        }
    }

    /// Refreshes route-dependent async state — the Platform → Core route
    /// needs the withdrawal preflight (fee headroom + full-balance payout),
    /// Platform → Shielded the shield-capacity preflight.
    private func routeDidChange() {
        clearShieldedMaxSelection()
        refreshShieldedSpendCeiling()
        refreshWithdrawalPreflight()
        refreshShieldPreflight()
    }

    private func refreshWithdrawalPreflight() {
        guard route == .platformToCore else {
            preflightTask?.cancel()
            preflightTask = nil
            return
        }
        guard preflightTask == nil else { return }
        withdrawalPreflightFailed = false
        preflightTask = Task { [weak self] in
            let result = try? await PlatformAddressSyncCoordinator.shared.preflightWithdrawal()
            guard let self, !Task.isCancelled else { return }
            self.withdrawalPreflight = result
            self.withdrawalPreflightFailed = result == nil
            self.preflightTask = nil
        }
    }

    private func refreshShieldPreflight() {
        guard route == .platformToShielded else {
            shieldPreflightTask?.cancel()
            shieldPreflightTask = nil
            return
        }
        guard shieldPreflightTask == nil else { return }
        // Fail closed while resolving: a preflight only starts when the
        // cached capacity is suspect (route entry, balance change, Max
        // retry), so clear it rather than let `canContinue` accept a stale
        // ceiling — the same contract as the internal-transfer sibling.
        platformShieldCapacity = nil
        shieldPreflightFailed = false
        shieldPreflightTask = Task { [weak self] in
            let result = try? await PlatformAddressSyncCoordinator.shared.preflightShield()
            guard let self, !Task.isCancelled else { return }
            self.platformShieldCapacity = result.map(PlatformShieldCapacity.init)
            self.shieldPreflightFailed = result == nil
            self.shieldPreflightTask = nil
            // A Max tapped mid-flight parked a preflight notice; resolve it
            // rather than leave a "checking…" (or stale failure) up after
            // the outcome is known. The user re-taps Max for the fresh
            // ceiling — the amount is never auto-filled from a background
            // completion.
            let preflightNotices = [
                InternalTransferViewModel.platformShieldPreflightLoadingMessage,
                InternalTransferViewModel.platformShieldPreflightUnavailableMessage,
            ]
            if let notice = self.shieldedMaxNotice, preflightNotices.contains(notice) {
                self.shieldedMaxNotice = result == nil
                    ? InternalTransferViewModel.platformShieldPreflightUnavailableMessage
                    : nil
            }
        }
    }

    /// A fresh Platform balance can change shield capacity — re-run the
    /// preflight (clearing the cached capacity, so validation fails closed
    /// until the new ceiling lands) so validation and Max track it. (The
    /// coordinator revalidates against a live preflight at confirm time
    /// regardless.)
    private func restartShieldPreflightOnBalanceChange() {
        guard route == .platformToShielded else { return }
        shieldPreflightTask?.cancel()
        shieldPreflightTask = nil
        refreshShieldPreflight()
    }

    // MARK: - Clipboard

    struct ClipboardSuggestion: Equatable {
        let address: String
        let kind: DestinationKind
    }

    /// Only a visible address form registers for automatic reads. This model
    /// also exists behind Receive/Internal and is reused by later send steps.
    ///
    /// `token` identifies the registering form. Reads run while at least one
    /// registration stands, so a form being removed can never switch off the
    /// monitoring another form just switched on.
    func setClipboardMonitoring(_ enabled: Bool, token: UUID) {
        let wasMonitoring = !clipboardMonitors.isEmpty
        if enabled {
            clipboardMonitors.insert(token)
        } else {
            clipboardMonitors.remove(token)
        }

        if !clipboardMonitors.isEmpty {
            refreshClipboardSuggestion()
        } else if wasMonitoring {
            clipboardSuggestion = nil
            appliesClipboardSuggestionWhenAvailable = false
        }
    }

    /// The "Send to Address" shortcut: fill the address field from the
    /// clipboard as soon as a permitted read runs. The host calls this on
    /// appearance, before the form has registered, so the intent waits for
    /// that first read instead of being spent on a read that cannot happen.
    func applyClipboardSuggestionWhenAvailable() {
        appliesClipboardSuggestionWhenAvailable = true
        refreshClipboardSuggestion()
    }

    /// Refreshes when a host becomes visible or the clipboard changes. Both
    /// the form registration and the host's permission must allow the read.
    func refreshClipboardSuggestion() {
        guard !clipboardMonitors.isEmpty, isClipboardReadAllowed() else {
            // Not allowed to read is also not allowed to keep offering what an
            // earlier read found: the pasteboard may have changed since, and
            // the chip must not outlive the screen that produced it.
            clipboardSuggestion = nil
            return
        }

        if let raw = UIPasteboard.general.string {
            clipboardSuggestion = Self.detect(in: raw)
        } else {
            clipboardSuggestion = nil
        }

        guard appliesClipboardSuggestionWhenAvailable else { return }
        // Spent by the first permitted read, whatever it found — a denied
        // prompt or an empty clipboard has no retry to wait for.
        appliesClipboardSuggestionWhenAvailable = false
        // An explicit prefill (a scan-routed address, applied on load) wins
        // over the clipboard, as it did when both ran in `viewDidLoad`.
        guard trimmedAddress.isEmpty else { return }
        useClipboardSuggestion()
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

    /// The address a scanned input would put in the address field, or nil for
    /// one this form cannot hold.
    ///
    /// A BIP70 payment request is the nil case: it carries a fetched
    /// confirmation instead of an address, and belongs to the classic payment
    /// processor. Callers that open this screen for a scan check first —
    /// otherwise the scan lands on an empty form.
    static func scannedAddress(in paymentInput: DWPaymentInput) -> String? {
        // A verified payment request first, before anything is read out of the
        // input: its outputs and acknowledgment are the merchant's, and only
        // the classic processor honours them. Everything reachable from here
        // is merchant-controlled text — a memo or fallback line that happens to
        // classify as an address would otherwise become the destination, and
        // the form would pay it INSTEAD of the confirmed payment output.
        guard paymentInput.bip70Confirmation == nil else { return nil }
        if let address = paymentInput.parsedURI?.address, !address.isEmpty {
            return address
        }
        if let raw = paymentInput.userDetails, classify(raw) != nil {
            return raw
        }
        return nil
    }

    /// Scanned QR → address text. The classifier decides what it is; a
    /// BIP21 `dash:` URI contributes its address (and its amount when the
    /// screen's amount is still untouched).
    @discardableResult
    func ingestScannedInput(_ paymentInput: DWPaymentInput) -> Bool {
        guard let address = Self.scannedAddress(in: paymentInput) else { return false }
        addressText = address
        let scannedAmount = paymentInput.parsedURI?.amount ?? 0
        if scannedAmount > 0, dashDuffsUnsigned == 0 {
            unit = .dash
            amountText = scannedAmount.formattedDashAmountWithoutCurrencySymbol
        }
        return true
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

    /// The entered amount in duffs, or `nil` when it does not fit in `UInt64`.
    ///
    /// `plainDashAmount` scales by the duff factor and then takes
    /// `uint64Value`, which does not report a value that no longer fits — it
    /// wraps. An amount above `UInt64.max` duffs therefore arrives as a small
    /// number that passes an affordability check and is spent. Every gate on
    /// an amount the user typed should ask this instead.
    var dashDuffsIfRepresentable: UInt64? {
        let scaled = (parsedDashAmount * .duffs).whole
        guard scaled >= 0, scaled <= Decimal(UInt64.max) else { return nil }
        return NSDecimalNumber(decimal: scaled).uint64Value
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
        case .coreToCore, .coreToShielded, .platformToCore, .platformToShielded, nil:
            // L1 send fees are handled by the payment processor; the
            // asset-lock shield's pool fee is duff-denominated and enforced
            // in the route branches (`canContinue`, Max) directly, mirroring
            // the internal transfer; the full-balance platform withdrawal
            // nets its fee out of the preflighted payout; the platform
            // shield's headroom is governed by the SDK preflight
            // (`platformShieldCapacity`) in its route branches.
            return 0
        case .platformToPlatform:
            return Self.platformTransferFeeReserveCredits
        case .shieldedToCore:
            // Worst-case note selection for a bundle the size limit actually
            // admits — same reasoning as the internal transfer's reserve.
            return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(
                kind: .withdrawal,
                numActions: ShieldedActionBudget.maxActionsPerTransition)
        case .shieldedToPlatform:
            return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(
                kind: .unshield,
                numActions: ShieldedActionBudget.maxActionsPerTransition)
        case .shieldedToShielded:
            return try? SwiftDashSDKHost.shared.manager?.estimateShieldedFee(
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

    /// Inline explanation for an amount rejected before Confirm. Keep zero
    /// quiet until the user types.
    var amountValidationMessage: String? {
        #if DASHPAY
        // Both are independent of the amount: the first says nothing can ever
        // be sent on this channel, the second reports the attempt that just
        // failed (cleared the moment the amount changes, so it can't go stale).
        if isContactPaymentUnavailable { return Self.contactPaymentsUnavailableMessage }
        // Ahead of `contactSendError`, and NOT cleared when the amount
        // changes: an unknown outcome disables this screen for good, so the
        // reason has to outlive the next keystroke or the button reads as
        // dead for no stated reason.
        if contactSendOutcomeIsUnknown { return Self.contactSendUnknownOutcomeMessage }
        if let contactSendError { return contactSendError }
        #endif
        if let shieldedMaxNotice { return shieldedMaxNotice }
        guard dashDuffsUnsigned > 0, let route else { return nil }

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
    /// it spends. Mirrors `canContinue`'s envelope route by route so a Continue
    /// button disabled on affordability is never left unexplained.
    private var insufficientBalanceMessage: String? {
        guard let route else { return nil }
        let balanceName = source.balanceName

        switch route {
        case .coreToCore:
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedDuffs: dashDuffsUnsigned,
                spendableDuffs: coreToCoreSpendableDuffs)

        case .coreToShielded:
            // The pool fee rides on top of the amount, so the spendable
            // envelope shrinks by the fee. Mirrors `canContinue`:
            // requested > spendable − fee ⟺ requested + fee > spendable.
            guard let feeDuffs = CoreToShieldedAmountPolicy.currentPoolFeeDuffs else {
                return Self.feeEstimateUnavailableMessage
            }
            let spendableDuffs = coreSpendableDuffs
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedDuffs: dashDuffsUnsigned,
                spendableDuffs: spendableDuffs > feeDuffs
                    ? spendableDuffs - feeDuffs : 0)

        case .platformToPlatform:
            guard let reserve = feeReserveCredits else {
                return Self.feeEstimateUnavailableMessage
            }
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedCredits: creditsPreview,
                balanceCredits: platformCredits,
                feeReserveCredits: reserve)

        case .platformToShielded:
            // Stay quiet while the preflight is still resolving: Continue is
            // disabled, but the amount is not yet known to be unaffordable.
            // A FAILED preflight is named — never an unexplained dead button.
            guard let capacity = platformShieldCapacity else {
                return shieldPreflightFailed
                    ? InternalTransferViewModel.platformShieldPreflightUnavailableMessage
                    : nil
            }
            guard capacity.canShield else {
                return InternalTransferViewModel.platformShieldHeadroomUnavailableMessage
            }
            return TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedCredits: creditsPreview,
                balanceCredits: capacity.maxShieldableCredits,
                feeReserveCredits: 0)

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
            // The balance envelope first. A request the balance cannot cover
            // is unaffordable whatever the preflight would have said — and
            // with an EMPTY balance the preflight never says anything: it
            // throws `noFundedAddress`, because a zero balance leaves no
            // funded address to preflight. That is how asking to withdraw
            // from an empty Platform balance used to reach a disabled
            // Continue with nothing on screen explaining it.
            if let message = TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: balanceName,
                requestedCredits: creditsPreview,
                balanceCredits: platformCredits,
                feeReserveCredits: 0) {
                return message
            }
            // Stay quiet while the preflight is still RESOLVING: Continue is
            // disabled, but the amount is not yet known to be unaffordable.
            // An attempt that already failed is named instead — the same
            // rule the shield branch below follows.
            guard let preflight = withdrawalPreflight else {
                return withdrawalPreflightFailed
                    ? InternalTransferViewModel.platformWithdrawalPreflightUnavailableMessage
                    : nil
            }
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

    /// Affordability ceiling for the Core → Core route.
    ///
    /// A typed address rides the L1 payment processor, which rejects an
    /// unfundable send with its own error, so the raw balance is enough of a
    /// gate there. A contact payment has no such backstop —
    /// `sendDashPayPayment` builds, signs and broadcasts in one SDK call and
    /// charges the fee on top of the amount — so it is held to the fee-aware
    /// envelope, which is also the cap `WalletSendService.sendToContact`
    /// documents for its callers and the one Max already fills.
    private var coreToCoreSpendableDuffs: UInt64 {
        #if DASHPAY
        if contactRecipient != nil { return coreSpendableDuffs }
        #endif
        return coreBalanceDuffs
    }

    var canContinue: Bool {
        #if DASHPAY
        // Terminal for the rest of this screen's life: see `sendToContact`.
        if contactSendOutcomeIsUnknown { return false }
        #endif
        // An amount that cannot be represented in duffs is not spendable on
        // any route — checked before the routes, because the wrapped value the
        // conversion would otherwise produce is small enough to pass them.
        guard dashDuffsIfRepresentable != nil else { return false }
        #if DASHPAY
        if isSendingToContact || isContactPaymentUnavailable { return false }
        #endif
        guard dashDuffsUnsigned > 0, let route, !isBlockedBySync else { return false }
        switch route {
        case .coreToCore:
            return dashDuffsUnsigned <= coreToCoreSpendableDuffs
        case .coreToShielded:
            // Fee-on-top: the lock value is amount + pool fee, and the
            // asset-lock funding is an L1 spend — validate against the
            // fee-aware spendable envelope (same basis as Max), not the raw
            // balance. Fails closed when the estimate is unavailable or the
            // sum overflows — same policy as the internal transfer.
            guard let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits,
                  let lockDuffs = CoreToShieldedAmountPolicy.lockValueDuffs(
                      forAmountDuffs: dashDuffsUnsigned,
                      poolFeeCredits: poolFeeCredits)
            else { return false }
            return lockDuffs <= coreSpendableDuffs
        case .platformToPlatform:
            guard let reserve = feeReserveCredits else { return false }
            return platformCredits >= reserve
                && creditsPreview <= platformCredits - reserve
        case .platformToShielded:
            // The SDK preflight is the sole affordability authority (the
            // aggregate Platform balance is not); nil capacity fails closed.
            return PlatformShieldAmountPolicy.canSubmit(
                requestedCredits: creditsPreview,
                capacity: platformShieldCapacity)
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
        case .coreToCore, nil:
            // Fee-aware max: spendable minus the send fee reserve (mirrors
            // DSAccount.maxOutputAmount), never the raw total — which would
            // include unconfirmed/immature funds and leave no room for the fee.
            sourceDuffs = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
        case .coreToShielded:
            // Fee-on-top Max: the lock is amount + pool fee, so the largest
            // recipient amount is the L1-fee-aware spendable minus the pool
            // fee. Fails closed (fills 0) when the estimate is unavailable.
            let spendable = coreSpendableDuffs
            guard let feeDuffs = CoreToShieldedAmountPolicy.currentPoolFeeDuffs else {
                shieldedMaxNotice = Self.feeEstimateUnavailableMessage
                sourceDuffs = 0
                break
            }
            sourceDuffs = spendable > feeDuffs ? spendable - feeDuffs : 0
            if spendable > 0, sourceDuffs == 0 {
                shieldedMaxNotice = InternalTransferViewModel.feeReserveExceedsBalanceMessage(source)
            }
        case .platformToPlatform:
            sourceDuffs = creditsMinusFeeReserve(platformCredits) / 1000
        case .platformToShielded:
            // Max = the SDK preflight's executable capacity, floored to
            // whole duffs (never round a credit ceiling up to an amount the
            // transition cannot select).
            guard let capacity = platformShieldCapacity else {
                // Name a FAILED check instead of a perpetual "checking…",
                // and kick a fresh preflight either way — nothing else
                // retries until the route or balance changes. Compute the
                // notice first: the refresh clears `shieldPreflightFailed`.
                shieldedMaxNotice = shieldPreflightFailed
                    ? InternalTransferViewModel.platformShieldPreflightUnavailableMessage
                    : InternalTransferViewModel.platformShieldPreflightLoadingMessage
                refreshShieldPreflight()
                sourceDuffs = 0
                break
            }
            sourceDuffs = PlatformShieldAmountPolicy.maximumDuffs(capacity: capacity)
            if sourceDuffs == 0 {
                shieldedMaxNotice =
                    InternalTransferViewModel.platformShieldHeadroomUnavailableMessage
            }
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
                    shieldedMaxNotice = Self.shieldedRemainderMessage(
                        plan.remainingCredits,
                        followUpCredits: plan.followUpCredits)
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

    /// Why Max offered less than the balance card shows — `nil` when the answer
    /// is "tap Max again in a minute".
    ///
    /// A remainder a later sweep can move is not worth a line in the slot that
    /// carries errors; one that no sweep can ever move is, or the balance keeps
    /// promising what the wallet will never offer to send.
    private static func shieldedRemainderMessage(
        _ credits: UInt64,
        followUpCredits: UInt64
    ) -> String? {
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
        return nil
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
