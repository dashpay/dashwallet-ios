//
//  PaymentsLandingViewModel.swift
//  DashWallet
//

import Combine
import Foundation
import SwiftDashSDK
import UIKit

enum PaymentsLandingTab: String, CaseIterable, Identifiable {
    case receive
    case internalTransfer
    case send

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receive: return String(localized: "Receive", comment: "")
        case .internalTransfer: return String(localized: "Internal", comment: "")
        case .send: return String(localized: "Send", comment: "")
        }
    }
}

enum CoreReceiptSettlementStatus: Int, Comparable {
    case mempool = 0
    case instantSend = 1
    case inBlock = 2
    case chainLocked = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .mempool:
            return String(localized: "Detected in mempool", comment: "Receive payment status")
        case .instantSend:
            return String(localized: "InstantSend confirmed", comment: "Receive payment status")
        case .inBlock:
            return String(localized: "Confirmed in block", comment: "Receive payment status")
        case .chainLocked:
            return String(localized: "ChainLocked", comment: "Receive payment status")
        }
    }
}

struct ReceiveReceipt: Identifiable, Equatable {
    let id: String
    let rail: ReceiveOption
    let amountDuffs: UInt64
    let receivedAt: Date
    let memo: String?
    let transactionId: Data?
    var coreStatus: CoreReceiptSettlementStatus?

    var statusTitle: String {
        coreStatus?.title ?? String(localized: "Received", comment: "Receive payment status")
    }
}

enum ReceiveReceiptPolicy {
    static func coreStatus(context: UInt32) -> CoreReceiptSettlementStatus? {
        CoreReceiptSettlementStatus(rawValue: Int(context))
    }

    /// Reorgs can move an in-block transaction back to mempool. The receive
    /// card keeps the strongest status already presented instead of visibly
    /// downgrading; ChainLocks are final.
    static func strongestStatus(
        current: CoreReceiptSettlementStatus,
        observed: CoreReceiptSettlementStatus
    ) -> CoreReceiptSettlementStatus {
        max(current, observed)
    }

    static func shouldProjectShieldedResult(
        success: Bool,
        cooldownSkip: Bool
    ) -> Bool {
        success && !cooldownSkip
    }

    static func canRefreshPlatform(
        isRunning: Bool,
        availability: PlatformAccountAvailability
    ) -> Bool {
        isRunning && availability == .available
    }
}

enum AttendedReceiveRefreshPolicy {
    /// Platform address BLAST passes are relatively light but still real DAPI
    /// work. Keep this named so testnet smoke results can tune it independently.
    static let platformInterval: TimeInterval = 5
    /// A forced Shielded pass walks notes and then rebuilds the projected
    /// activity list, so its cadence is independently tunable.
    static let shieldedInterval: TimeInterval = 5
}

/// What the Identity option's card shows: the Current identity's ID and the
/// username the wallet presents as its own. Nil without either, so a wallet
/// with no identity, no username yet or a registration in progress has none.
struct ReceiveIdentity: Equatable {
    /// The Identity ID in Base58 — the only content of the QR, the copied and
    /// the shared text (AC-03).
    let identityId: Data
    let identityIdBase58: String
    let username: String

    init?(identityId: Data?, username: String?) {
        guard let identityId, !identityId.isEmpty, let username, !username.isEmpty else { return nil }
        self.identityId = identityId
        identityIdBase58 = ScriptAddressCodec.base58Encode(identityId)
        self.username = username
    }
}

/// Where a Specify-amount request goes. Core keeps `DWReceiveModel`, which
/// follows the next unused address; every other option carries the address or
/// ID its card shows.
enum AmountRequestDestination: Equatable {
    case core
    case option(ReceiveOption, address: String)
}

enum ReceiveOptionPolicy {
    /// Which options the Receive tab offers.
    ///
    /// Core and Shielded are both ordinary destinations — a wallet can be paid
    /// privately without calling itself advanced. Platform is the one that
    /// needs the mode: it holds credits rather than spendable Dash, and
    /// offering it by default invites payments the payer cannot spend back.
    /// Identity needs the mode and a username, and is never offered on the
    /// lock screen's Quick Receive, which runs before unlock.
    static func options(isAdvancedMode: Bool, identity: ReceiveIdentity?, isQuickReceive: Bool) -> [ReceiveOption] {
        guard isAdvancedMode else { return [.core, .shielded] }
        guard identity != nil, !isQuickReceive else { return [.core, .shielded, .platform] }
        return [.core, .shielded, .platform, .identity]
    }
}

/// The shielded address of the current Receive session.
enum ShieldedReceiveSessionState: Equatable {
    /// No session asked for a shielded address yet.
    case idle
    /// A session began and its address is being derived; nothing is shown.
    case deriving
    /// The session's address — it stays until the next session begins.
    case ready(ShieldedReceiveAddress)
}

/// The active wallet as the receipt watchers see it.
struct ReceiptWalletContext {
    let walletId: Data
    /// The network the app is set to.
    let environment: Network
    /// Whether the SDK is running `environment`.
    let isRunning: Bool
}

/// What the receipt watchers read from the wallet for the session context
/// and the shielded rail. `live` reads the running wallet; tests inject
/// their own.
struct ReceiptWatchingSources {
    /// The active wallet; nil while there is none or no network is set.
    var walletContext: @MainActor () -> ReceiptWalletContext?
    /// Ids of the shielded activity rows persisted now; nil when they could
    /// not be read.
    var persistedShieldedActivityIds: () -> Set<String>?
    /// The shielded activity as the history projects it.
    var projectedShieldedActivity: @Sendable () -> [ShieldedActivityItem]
    /// Fires when a shielded sync of the wallet has results to project; nil
    /// while shielded sync is not running.
    var shieldedSyncResults: @MainActor (_ walletId: Data) -> AnyPublisher<Void, Never>?
    /// Asks for a shielded sync now.
    var requestShieldedRefresh: @MainActor () -> Void

    static let live = ReceiptWatchingSources(
        walletContext: {
            guard let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
                  let environment = WalletEnvironment.network
            else { return nil }
            return ReceiptWalletContext(
                walletId: walletId,
                environment: environment,
                isRunning: SwiftDashSDKHost.shared.runningNetwork == environment)
        },
        persistedShieldedActivityIds: { SwiftDashSDKWalletSource.persistedShieldedActivityIds() },
        projectedShieldedActivity: {
            let coreTransactions = SwiftDashSDKWalletSource
                .fetchCurrentWalletSnapshot()?.transactions ?? []
            return SwiftDashSDKWalletSource.fetchShieldedActivity(
                coreTransactions: coreTransactions)
        },
        shieldedSyncResults: { walletId in
            guard PlatformAddressSyncCoordinator.shared.isShieldedRunning,
                  let manager = PlatformAddressSyncCoordinator.shared.platformWalletManager
            else { return nil }
            return manager.$lastShieldedSyncEvent
                .compactMap { event -> Void? in
                    guard let result = event?.result(for: walletId),
                          ReceiveReceiptPolicy.shouldProjectShieldedResult(
                              success: result.success,
                              cooldownSkip: result.cooldownSkip)
                    else { return nil }
                    return ()
                }
                .eraseToAnyPublisher()
        },
        requestShieldedRefresh: {
            guard let manager = PlatformAddressSyncCoordinator.shared.platformWalletManager else { return }
            PlatformAddressSyncCoordinator.shared.requestShieldedRefresh(
                using: manager,
                reason: "attended receive")
        })
}

@MainActor
final class PaymentsLandingViewModel: ObservableObject {

    /// Every set after `init` runs `activeTabDidChange`, including a set to
    /// the same tab from a tab-bar entry point.
    @Published var activeTab: PaymentsLandingTab {
        didSet { activeTabDidChange() }
    }
    /// Synchronous on purpose: the switch to Shielded begins its session in
    /// the same transaction, so the card slides in with the fresh QR.
    @Published var network: ReceiveOption = .core {
        didSet { networkDidChange() }
    }
    /// Which hero tabs this presentation offers. The full landing shows all
    /// three; the balance-row receive sheet narrows to Receive + Internal.
    let visibleTabs: [PaymentsLandingTab]
    /// Mirrors `DWGlobalOptions.advancedModeEnabled` so the Internal card can
    /// narrow to Shielded while the mode is off.
    ///
    /// Its own mirror rather than the transfer model's: that one is handed to
    /// the screen as a plain `var`, so observing it here would mean re-rendering
    /// the whole landing on every keystroke in the embedded amount field.
    @Published private(set) var isAdvancedMode = DWGlobalOptions.sharedInstance().advancedModeEnabled

    /// The Current identity the Identity option shows, re-read on every
    /// registration, wallet and network change; nil when it has no username.
    @Published private(set) var receiveIdentity: ReceiveIdentity?

    /// The username every Receive card shows and copies, whichever option is
    /// selected and whether Advanced Mode is on; nil without one (AC-15).
    var shownUsername: String? {
        receiveIdentity?.username
    }

    /// The lock screen's Quick Receive, which never offers Identity.
    let isQuickReceive: Bool

    /// Which options the Receive tab offers (`ReceiveOptionPolicy`).
    var receiveOptions: [ReceiveOption] {
        ReceiveOptionPolicy.options(
            isAdvancedMode: isAdvancedMode, identity: receiveIdentity, isQuickReceive: isQuickReceive)
    }

    /// Whether the Send tab offers "Send to username".
    ///
    /// Both halves are required: the row opens the contact book, which needs an
    /// identity to hold contacts, and a wallet that cannot name itself has
    /// nothing to send *from* in that flow. False everywhere DashPay is not
    /// built.
    @Published private(set) var canSendToUsername = false

    /// Whether the Send tab offers "Swap to other crypto".
    ///
    /// The same gate the Dash DEX shortcut is behind: the portal swaps real
    /// assets across real chains, which testnet coins cannot do, and it is
    /// useless without the SwapKit key. Fixed for the lifetime of the screen —
    /// both inputs need a relaunch to change.
    let canSwapToOtherCrypto = !WalletEnvironment.isTestnet && SwapKitConstants.isConfigured

    @Published private(set) var coreAddress: String? = nil
    @Published private(set) var platformAddress: String? = nil
    /// One shielded address per Receive session: set when a session begins
    /// (`beginReceiveSession`), never replaced while the session lasts.
    @Published private(set) var shieldedReceiveState: ShieldedReceiveSessionState = .idle
    @Published private(set) var displayedAddress: String? = nil
    @Published private(set) var receipt: ReceiveReceipt? = nil
    @Published private(set) var isWatchingForReceipt = false

    let allowsTransactionDetails: Bool

    /// What already existed on the rail when the session opened, so a receipt
    /// is only ever raised for something that arrived after.
    ///
    /// One case per rail rather than three flat fields: they were always
    /// mutually exclusive — two of them zero on every session — and nothing
    /// said so, which left every construction restating the two that did not
    /// apply.
    private enum ReceiptBaseline {
        case core(transactionIds: Set<Data>)
        case platform(activityCursor: Int64)
        case shielded(activityIds: Set<String>)
    }

    /// Everything about a session other than its baseline, captured before
    /// the baseline is read.
    private struct ReceiptSessionSeed {
        let generation: UInt64
        let rail: ReceiveOption
        let address: String
        let walletId: Data
        let environment: Network
        let startedAt: Date
    }

    private struct ReceiptSession {
        let seed: ReceiptSessionSeed
        let baseline: ReceiptBaseline

        var generation: UInt64 { seed.generation }
        var rail: ReceiveOption { seed.rail }
        var address: String { seed.address }
        var walletId: Data { seed.walletId }
        var environment: Network { seed.environment }
        var startedAt: Date { seed.startedAt }

        // Read by the rail's own watcher, which only runs when the baseline is
        // that rail's case; the empty fallbacks are unreachable in practice.
        var coreTransactionIds: Set<Data> {
            guard case .core(let ids) = baseline else { return [] }
            return ids
        }

        var platformActivityCursor: Int64 {
            guard case .platform(let cursor) = baseline else { return 0 }
            return cursor
        }

        var shieldedActivityIds: Set<String> {
            guard case .shielded(let ids) = baseline else { return [] }
            return ids
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var coreReceiptCancellable: AnyCancellable?
    private var platformReceiptCancellable: AnyCancellable?
    private var shieldedReceiptCancellable: AnyCancellable?
    private var attendedRefreshTask: Task<Void, Never>?
    private var shieldedProjectionTask: Task<Void, Never>?
    private var shieldedProjectionRefreshPending = false
    private var shieldedProjectionGeneration: UInt64 = 0
    private var session: ReceiptSession?
    /// Watches the Current identity's credits while the Identity option is on.
    private let identityWatcher: IdentityCreditsWatcher
    /// The active wallet and network an identity watch runs for; nil while
    /// the SDK host is not running the selected network.
    private let identityContext: () -> (walletId: Data, network: Network)?
    /// The Current identity Receive offers, re-read on every registration
    /// status update.
    private let receiveIdentitySource: () -> ReceiveIdentity?
    private var identityWatchSession: IdentityCreditsWatcher.Session?
    private var generation: UInt64 = 0
    private var surfaceIsVisible = false
    private var presentationIsObscuring = false
    private var appIsActive = UIApplication.shared.applicationState == .active
    private let shieldedAddressSource: ShieldedReceiveAddressSource
    private let activeWalletId: @MainActor () -> Data?
    private let receiptSources: ReceiptWatchingSources
    /// Bumped by every `beginReceiveSession` and when a session ends (Done,
    /// leaving Receive); a derivation applies its result only while its token
    /// is still the current one.
    private var shieldedSessionToken: UInt64 = 0

    init(activeTab: PaymentsLandingTab,
         network: ReceiveOption = .core,
         visibleTabs: [PaymentsLandingTab] = PaymentsLandingTab.allCases,
         allowsTransactionDetails: Bool = true,
         isQuickReceive: Bool = false,
         shieldedAddressSource: ShieldedReceiveAddressSource = SDKShieldedReceiveAddressSource(),
         activeWalletId: @escaping @MainActor () -> Data? = { SwiftDashSDKHost.shared.wallet?.walletId },
         receiptSources: ReceiptWatchingSources = .live,
         shieldedRunning: AnyPublisher<Bool, Never>? = nil) {
        identityWatcher = Self.makeIdentityWatcher()
        identityContext = Self.currentIdentityContext
        receiveIdentitySource = Self.currentReceiveIdentity
        self.activeTab = activeTab
        self.network = network
        self.visibleTabs = visibleTabs
        self.allowsTransactionDetails = allowsTransactionDetails
        self.isQuickReceive = isQuickReceive
        self.shieldedAddressSource = shieldedAddressSource
        self.activeWalletId = activeWalletId
        self.receiptSources = receiptSources
        identityWatcher.onStateChange = { [weak self] in self?.identityWatcherDidChange($0) }

        reloadCoreAddress()

        NotificationCenter.default.publisher(for: .advancedModeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Platform and Identity are the segments the mode takes away,
                // and either can be the selected one at that moment.
                self.updateReceiveState(
                    isAdvancedMode: DWGlobalOptions.sharedInstance().advancedModeEnabled,
                    identity: self.receiveIdentity)
            }
            .store(in: &cancellables)

        #if DASHPAY
        refreshCanSendToUsername()
        refreshReceiveIdentity()

        // The identity can be adopted while this landing is already up — a
        // registration finishing, or a recovery resolving one — and the row
        // has to appear without the user leaving the tab.
        NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.registrationStatusDidChange() }
            .store(in: &cancellables)
        #endif

        PlatformAddressSyncCoordinator.shared.$derivedAddresses
            .receive(on: RunLoop.main)
            .sink { [weak self] addresses in
                guard let self else { return }
                self.platformAddress = addresses.nextReceiveAddress?.address
                self.reconcileReceiptWatching()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            PlatformAddressSyncCoordinator.shared.$isRunning.removeDuplicates(),
            PlatformAddressSyncCoordinator.shared.$platformAccountAvailability.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.reconcileReceiptWatching() }
            .store(in: &cancellables)

        (shieldedRunning ?? PlatformAddressSyncCoordinator.shared.$isShieldedRunning.eraseToAnyPublisher())
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] running in
                guard let self else { return }
                // Use the delivered stop even if a fast restart has already
                // replaced the manager before this queued notification runs.
                if !running, self.session?.rail == .shielded {
                    self.suspendReceiptWatching()
                } else {
                    self.reconcileReceiptWatching()
                }
                // A session that found the shielded wallet not ready shows a
                // placeholder; the wallet starting is what it waits for. A
                // session still deriving begins again too: its answer may be
                // a «not ready» read before the start. Only a placeholder or
                // a pending derivation is replaced — never a shown address
                // (AC-03).
                if running, self.isWaitingForShieldedAddress {
                    self.beginReceiveSession()
                }
            }
            .store(in: &cancellables)

        platformAddress = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.nextReceiveAddress?.address

        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleWalletOrEnvironmentChange() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleWalletOrEnvironmentChange() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.appIsActive = true
                self?.reconcileReceiptWatching()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.appIsActive = false
                self?.suspendReceiptWatching()
            }
            .store(in: &cancellables)

    }

    private func networkDidChange() {
        resetForRouteChange()
        // Switching back to Shielded is a gain of focus for its address — the
        // one that originates inside the view model. Switching away ends the
        // shielded session.
        beginReceiveSession()
    }

    #if DEBUG
    /// Lightweight initializer used only by SwiftUI previews: takes the
    /// addresses as literals instead of reading them from the wallet, and
    /// subscribes to nothing.
    private init(
        previewActiveTab: PaymentsLandingTab,
        previewNetwork: ReceiveOption,
        previewVisibleTabs: [PaymentsLandingTab],
        previewCoreAddress: String?,
        previewPlatformAddress: String?,
        previewIsQuickReceive: Bool,
        previewIdentityWatcher: IdentityCreditsWatcher?,
        previewIdentityContext: @escaping () -> (walletId: Data, network: Network)?,
        previewReceiveIdentitySource: @escaping () -> ReceiveIdentity?,
        previewIsWatching: Bool,
        previewShieldedState: ShieldedReceiveSessionState
    ) {
        isWatchingForReceipt = previewIsWatching
        isQuickReceive = previewIsQuickReceive
        #if DASHPAY
        identityWatcher = previewIdentityWatcher
            ?? IdentityCreditsWatcher(read: { _ in .failure(IdentityBalanceRefresh.Superseded()) })
        #else
        identityWatcher = previewIdentityWatcher ?? Self.makeIdentityWatcher()
        #endif
        identityContext = previewIdentityContext
        receiveIdentitySource = previewReceiveIdentitySource
        appIsActive = true
        activeTab = previewActiveTab
        network = previewNetwork
        visibleTabs = previewVisibleTabs
        coreAddress = previewCoreAddress
        platformAddress = previewPlatformAddress
        shieldedReceiveState = previewShieldedState
        shieldedAddressSource = SDKShieldedReceiveAddressSource()
        activeWalletId = { nil }
        receiptSources = .live
        // A preview has no host to route to and no transaction to route with,
        // so the receipt's "View transaction" stays hidden rather than drawing
        // a control that could not do anything.
        allowsTransactionDetails = false
        identityWatcher.onStateChange = { [weak self] in self?.identityWatcherDidChange($0) }
    }

    /// Preview view model. Pass `nil` for an address to preview that
    /// network's placeholder state instead of the QR card.
    static func makeForPreview(
        activeTab: PaymentsLandingTab = .internalTransfer,
        network: ReceiveOption = .core,
        visibleTabs: [PaymentsLandingTab] = PaymentsLandingTab.allCases,
        coreAddress: String? = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN",
        platformAddress: String? = "XmQ4rT7bN2vK9sD5xF8jH3kL6pW1aZcYuE",
        isQuickReceive: Bool = false,
        identityWatcher: IdentityCreditsWatcher? = nil,
        identityContext: @escaping () -> (walletId: Data, network: Network)? = { nil },
        receiveIdentitySource: @escaping () -> ReceiveIdentity? = { nil },
        isWatching: Bool = false,
        shieldedState: ShieldedReceiveSessionState = .ready(.notReady)
    ) -> PaymentsLandingViewModel {
        PaymentsLandingViewModel(
            previewActiveTab: activeTab,
            previewNetwork: network,
            previewVisibleTabs: visibleTabs,
            previewCoreAddress: coreAddress,
            previewPlatformAddress: platformAddress,
            previewIsQuickReceive: isQuickReceive,
            previewIdentityWatcher: identityWatcher,
            previewIdentityContext: identityContext,
            previewReceiveIdentitySource: receiveIdentitySource,
            previewIsWatching: isWatching,
            previewShieldedState: shieldedState)
    }
    #endif

    /// What the card encodes in its QR, copies and shares: the address of the
    /// selected chain option, or on Identity the bare Base58 Identity ID.
    var currentAddress: String? {
        if network == .identity {
            return receiveIdentity?.identityIdBase58
        }
        // The shielded address belongs to the Receive session, not to the
        // receipt session: a gain of focus replaces it even while a receipt
        // window started under an earlier address stays open.
        if network == .shielded {
            return shieldedSessionAddress
        }
        if session?.rail == network, let displayedAddress {
            return displayedAddress
        }
        return candidateAddress(for: network)
    }

    /// Specify amount is offered on every option that has an address or ID to
    /// put the amount on.
    var canSpecifyAmount: Bool {
        amountRequestDestination != nil
    }

    /// Where a Specify-amount request for the selected option goes, or nil when
    /// the option has no address or ID.
    var amountRequestDestination: AmountRequestDestination? {
        guard let address = currentAddress else { return nil }
        return network == .core ? .core : .option(network, address: address)
    }

    var canViewTransaction: Bool {
        allowsTransactionDetails && receipt?.transactionId != nil
    }

    private func candidateAddress(for rail: ReceiveOption) -> String? {
        switch rail {
        case .core: return coreAddress
        case .platform: return platformAddress
        case .shielded: return shieldedSessionAddress
        // The Identity card shows the Identity ID, not an address.
        case .identity: return nil
        }
    }

    /// The address of the current Receive session, when it has one to show.
    private var shieldedSessionAddress: String? {
        switch shieldedReceiveState {
        case .ready(.fresh(let address)), .ready(.fallback(let address)): return address
        case .idle, .deriving, .ready(.notReady), .ready(.unavailable): return nil
        }
    }

    private var isWaitingForShieldedAddress: Bool {
        switch shieldedReceiveState {
        case .deriving, .ready(.notReady), .ready(.unavailable): return true
        case .idle, .ready(.fresh), .ready(.fallback): return false
        }
    }

    /// True while the session shows the default shielded address because a
    /// fresh one could not be derived; the screen shows the linkability
    /// warning for exactly as long as this holds (AC-07).
    var isShowingShieldedFallback: Bool {
        if case .ready(.fallback) = shieldedReceiveState { return true }
        return false
    }

    /// Begins a Receive session: with Shielded selected, derives one fresh
    /// shielded address for it. Called on every gain of focus and by
    /// «Receive another»; nothing else replaces the session's address.
    ///
    /// Ignored while a payment receipt is shown: the receipt stays and no new
    /// address is derived. It never touches the receipt window either — only
    /// opening Receive, «Receive another», a route change and Done do.
    func beginReceiveSession() {
        guard receipt == nil else { return }
        shieldedSessionToken &+= 1
        guard activeTab == .receive, network == .shielded else {
            shieldedReceiveState = .idle
            return
        }
        guard let walletId = activeWalletId() else {
            shieldedReceiveState = .ready(.unavailable)
            return
        }
        if let immediate = shieldedAddressSource as? ImmediateShieldedReceiveAddressSource {
            shieldedReceiveState = .ready(immediate.receiveAddressNow(walletId: walletId))
            reconcileReceiptWatching()
            return
        }
        shieldedReceiveState = .deriving
        let token = shieldedSessionToken
        let source = shieldedAddressSource
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = await source.receiveAddress(walletId: walletId)
            await self?.applyShieldedAddress(result, token: token)
        }
    }

    /// A derivation still in flight belongs to a session that has ended; its
    /// result is dropped when it arrives.
    private func invalidateShieldedDerivation() {
        shieldedSessionToken &+= 1
    }

    private func applyShieldedAddress(_ result: ShieldedReceiveAddress, token: UInt64) {
        guard token == shieldedSessionToken else { return }
        shieldedReceiveState = .ready(result)
        reconcileReceiptWatching()
    }

    var platformIsReady: Bool {
        PlatformAddressSyncCoordinator.shared.isRunning
    }

    func copyCurrentAddressToPasteboard() {
        guard let address = currentAddress else { return }
        UIPasteboard.general.string = address
    }

    func copyUsernameToPasteboard() {
        guard let username = shownUsername else { return }
        UIPasteboard.general.string = username
    }

    func setReceiveSurfaceVisible(_ visible: Bool) {
        surfaceIsVisible = visible
        if visible {
            reconcileReceiptWatching()
        } else {
            suspendReceiptWatching()
        }
    }

    func setReceiptWatchingObscured(_ obscured: Bool) {
        presentationIsObscuring = obscured
        if obscured {
            suspendReceiptWatching()
        } else {
            reconcileReceiptWatching()
        }
    }

    /// The user is finished with this receipt and leaving. Unlike
    /// `receiveAnother`, no new session is armed and no address is re-derived —
    /// coming back should start from a clean receive screen rather than the
    /// receipt of a payment already dealt with.
    func finishReceiving() {
        // No reconcile: that would see a nil session and start a fresh one,
        // which is the opposite of what Done means. Leaving the screen is what
        // stops the watcher, and returning is what starts the next session.
        receipt = nil
        invalidateReceiptSession()
        invalidateShieldedDerivation()
    }

    /// Receive is no longer on screen. Pushing a step of the receive flow is
    /// not a leave: the receipt and its window stay. Otherwise the owner left
    /// for another tab or screen and the receipt window ends with it (AC-10),
    /// shown receipt included, so a payment that lands while they are away is
    /// not raised as new when they come back. Returning opens a new window and
    /// a new Receive session.
    func receiveDidDisappear(pushingReceiveStep: Bool) {
        guard !pushingReceiveStep else { return }
        receipt = nil
        invalidateReceiptSession()
        // Idle, not the last state: a placeholder left behind would make the
        // shielded wallet starting derive an address while Receive is away.
        invalidateShieldedDerivation()
        shieldedReceiveState = .idle
    }

    func receiveAnother() {
        receipt = nil
        invalidateReceiptSession()
        reloadCoreAddress()
        platformAddress = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.nextReceiveAddress?.address
        beginReceiveSession()
        reconcileReceiptWatching()
    }

    private func reloadCoreAddress() {
        coreAddress = SwiftDashSDKReceiveAddressReader.receiveAddress()
    }

    #if DASHPAY
    func registrationStatusDidChange() {
        refreshCanSendToUsername()
        refreshReceiveIdentity()
    }

    /// Reads the network-scoped SDK truth, the same source
    /// `JoinDashPayRegistrationPolicy` treats as authoritative. The legacy
    /// `DWGlobalOptions` username mirror is global and cleared on every network
    /// switch, so it would offer the row on a network with no identity.
    private func refreshCanSendToUsername() {
        let identity = DWCurrentUserIdentityInfo.shared
        canSendToUsername = identity.hasIdentity && identity.username?.isEmpty == false
    }

    /// The snapshot is empty while the SDK host has not rebound to the selected
    /// network, so a switch clears the previous identity before any new one.
    private func refreshReceiveIdentity() {
        updateReceiveState(isAdvancedMode: isAdvancedMode, identity: receiveIdentitySource())
    }
    #endif

    /// Applies Advanced Mode and the Current identity, and moves the selection
    /// to Core when the selected option is no longer offered. An option that
    /// appears never moves the selection.
    func updateReceiveState(isAdvancedMode: Bool, identity: ReceiveIdentity?) {
        self.isAdvancedMode = isAdvancedMode
        receiveIdentity = identity
        if !receiveOptions.contains(network) {
            network = .core
        }
        reconcileIdentityWatch()
    }

    #if DASHPAY
    /// The watcher's read: `refresh` runs only while `activeContext` is the
    /// session's wallet and network; otherwise the read fails as superseded.
    static func identityBalanceRead(
        activeContext: @escaping @MainActor () -> (walletId: Data, network: Network?)?,
        refresh: @escaping @MainActor (IdentityCreditsWatcher.Session) async -> Result<UInt64, Error>
    ) -> IdentityCreditsWatcher.Read {
        { session in
            guard let context = activeContext(),
                  context.walletId == session.walletId,
                  context.network == session.network
            else { return .failure(IdentityBalanceRefresh.Superseded()) }
            return await refresh(session)
        }
    }

    /// Reads through the same refresh as the Identities screen, so a read
    /// persists the balance and notifies open screens (AC-07).
    private static func makeIdentityWatcher() -> IdentityCreditsWatcher {
        IdentityCreditsWatcher(read: identityBalanceRead(
            activeContext: {
                let host = SwiftDashSDKHost.shared
                return host.wallet.map { ($0.walletId, host.runningNetwork) }
            },
            refresh: { session in
                guard let wallet = SwiftDashSDKHost.shared.wallet else {
                    return .failure(IdentityBalanceRefresh.Superseded())
                }
                return await DWCurrentUserIdentityInfo.shared.refreshBalanceFromNetwork(
                    identityId: session.identityId, wallet: wallet, network: session.network)
            }))
    }
    #else
    /// Without DASHPAY there is no Current identity, so Receive never offers
    /// Identity (`currentReceiveIdentity` is nil) and this watcher never starts.
    private static func makeIdentityWatcher() -> IdentityCreditsWatcher {
        IdentityCreditsWatcher(read: { _ in .failure(CancellationError()) })
    }
    #endif

    private static func currentReceiveIdentity() -> ReceiveIdentity? {
        #if DASHPAY
        let identity = DWCurrentUserIdentityInfo.shared
        return ReceiveIdentity(identityId: identity.snapshotForReading.identityId, username: identity.username)
        #else
        return nil
        #endif
    }

    private static func currentIdentityContext() -> (walletId: Data, network: Network)? {
        guard let wallet = SwiftDashSDKHost.shared.wallet,
              let network = SwiftDashSDKHost.shared.runningNetwork,
              WalletEnvironment.network == network
        else { return nil }
        return (wallet.walletId, network)
    }

    /// Runs one watch per (wallet, network, identity) while Identity is the
    /// selected option, and keeps it across everything else — a username
    /// change or a balance notification never resets its Starting balance.
    /// While a Receipt is up the finished session is kept, so nothing restarts
    /// until Receive another, another option, or a wallet or network change
    /// (`invalidateReceiptSession`).
    private func reconcileIdentityWatch() {
        let wanted: IdentityCreditsWatcher.Session?
        if receipt != nil {
            wanted = identityWatchSession
        } else if network == .identity, receiveOptions.contains(.identity),
                  let identity = receiveIdentity, let context = identityContext() {
            wanted = IdentityCreditsWatcher.Session(
                walletId: context.walletId, network: context.network, identityId: identity.identityId)
        } else {
            wanted = nil
        }
        if wanted != identityWatchSession {
            identityWatchSession = wanted
            if let wanted {
                identityWatcher.start(wanted)
            } else {
                identityWatcher.stop()
            }
        }
        identityWatcher.setGateOpen(canActivelyWatch)
        if network == .identity, receipt == nil {
            isWatchingForReceipt = canActivelyWatch && identityWatcher.state == .watching
        }
    }

    private func identityWatcherDidChange(_ state: IdentityCreditsWatcher.State) {
        guard network == .identity, identityWatchSession != nil else { return }
        switch state {
        case .received(let duffs):
            acceptReceipt(ReceiveReceipt(
                id: "identity-\(UUID().uuidString)",
                rail: .identity,
                amountDuffs: duffs,
                receivedAt: Date(),
                memo: nil,
                transactionId: nil))
        case .watching, .notWatching:
            if receipt == nil {
                isWatchingForReceipt = canActivelyWatch && state == .watching
            }
        }
    }

    private var canActivelyWatch: Bool {
        surfaceIsVisible &&
            !presentationIsObscuring &&
            appIsActive &&
            activeTab == .receive
    }

    private func reconcileReceiptWatching() {
        defer { reconcileIdentityWatch() }
        guard canActivelyWatch else {
            suspendReceiptWatching()
            return
        }

        if receipt != nil {
            isWatchingForReceipt = false
            if session?.rail == .core {
                attachCoreObserverIfNeeded()
            }
            return
        }

        if session == nil {
            startReceiptSession()
        } else {
            resumeReceiptWatching()
        }
    }

    private func startReceiptSession() {
        guard let address = candidateAddress(for: network),
              let context = receiptSources.walletContext(),
              context.isRunning
        else {
            displayedAddress = nil
            isWatchingForReceipt = false
            return
        }
        let walletId = context.walletId
        let environment = context.environment

        // Stamped once, above the baseline read rather than below it. Both
        // the Core snapshot's floor and the subscription's own floor derive
        // from it, and a transaction persisted between two separately-stamped
        // instants would land in neither.
        let startedAt = Date()

        // Fail closed. An unreadable baseline must not stand in as an empty
        // one — that would present everything already on the rail as a new
        // payment. With no session there is no watcher, so the worst case is
        // a receipt that never shows; the next reconcile tries again.
        guard let baseline = readReceiptBaseline(
            for: network, walletId: walletId, environment: environment, startedAt: startedAt)
        else {
            isWatchingForReceipt = false
            return
        }

        generation &+= 1
        let seed = ReceiptSessionSeed(
            generation: generation,
            rail: network,
            address: address,
            walletId: walletId,
            environment: environment,
            startedAt: startedAt)
        session = ReceiptSession(seed: seed, baseline: baseline)
        displayedAddress = address
        resumeReceiptWatching()
    }

    /// What already exists on `rail`, or nil when it could not be read.
    ///
    /// Every rail's baseline is a cheap read, so the session exists before
    /// the address can be acted on and nothing is ever withheld waiting for
    /// one.
    private func readReceiptBaseline(
        for rail: ReceiveOption,
        walletId: Data,
        environment: Network,
        startedAt: Date
    ) -> ReceiptBaseline? {
        switch rail {
        case .core:
            // Bounded by the floor the subscription will scan from: anything
            // older cannot be emitted, so it does not need excluding.
            return TransactionObserver.persistedTransactionIDs(
                firstSeenAtOrAfter: TransactionObserver.matchFloor(after: startedAt))
                .map { .core(transactionIds: $0) }
        case .platform:
            return PlatformAddressActivityDAO.shared.latestActivityId(
                walletId: walletId,
                networkRaw: Int64(environment.rawValue))
                .map { .platform(activityCursor: $0) }
        case .shielded:
            // The persisted rows' ids, not the projected activity list: the
            // projection materializes the wallet's whole Core history to
            // reconcile against. A row that exists now is not a new payment
            // whatever the projection later makes of it, so the unprojected
            // superset is the right thing to exclude.
            return receiptSources.persistedShieldedActivityIds()
                .map { .shielded(activityIds: $0) }
        case .identity:
            // Identity has no address, so no session reaches this read.
            return nil
        }
    }

    private func resumeReceiptWatching() {
        guard let session, isSessionCurrent(session) else {
            invalidateReceiptSession()
            startReceiptSession()
            return
        }

        switch session.rail {
        case .core:
            isWatchingForReceipt = receipt == nil
            attachCoreObserverIfNeeded()
        case .platform:
            guard ReceiveReceiptPolicy.canRefreshPlatform(
                isRunning: PlatformAddressSyncCoordinator.shared.isRunning,
                availability: PlatformAddressSyncCoordinator.shared.platformAccountAvailability)
            else {
                isWatchingForReceipt = false
                return
            }
            isWatchingForReceipt = true
            attachPlatformObserverIfNeeded(session: session)
        case .shielded:
            guard let syncResults = receiptSources.shieldedSyncResults(session.walletId) else {
                suspendReceiptWatching()
                return
            }
            isWatchingForReceipt = true
            attachShieldedObserverIfNeeded(session: session, syncResults: syncResults)
        case .identity:
            // No Identity session exists: Identity has no address to start one on.
            isWatchingForReceipt = false
        }
    }

    private func attachCoreObserverIfNeeded() {
        guard coreReceiptCancellable == nil, let session, session.rail == .core else { return }
        let filter = ReceivedAtAddressTransactionFilter(address: session.address)
        coreReceiptCancellable = TransactionObserver()
            .observeUpdates(
                filters: [filter],
                after: session.startedAt,
                excludingTxids: session.coreTransactionIds)
            .sink { [weak self] transaction in
                self?.handleCoreTransaction(transaction, session: session)
            }
    }

    private func handleCoreTransaction(
        _ transaction: ObservedTransaction,
        session: ReceiptSession
    ) {
        guard canActivelyWatch,
              isSessionCurrent(session),
              let status = ReceiveReceiptPolicy.coreStatus(context: transaction.context)
        else { return }

        if var existing = receipt, existing.transactionId == transaction.txid {
            guard let current = existing.coreStatus else { return }
            let strongest = ReceiveReceiptPolicy.strongestStatus(current: current, observed: status)
            guard strongest != current else { return }
            existing.coreStatus = strongest
            receipt = existing
            return
        }
        guard receipt == nil else { return }

        let amount = transaction.outputs
            .filter { $0.address == session.address }
            .reduce(UInt64(0)) { partial, output in
                let (sum, overflow) = partial.addingReportingOverflow(output.amount)
                return overflow ? UInt64.max : sum
            }
        guard amount > 0 else { return }
        acceptReceipt(ReceiveReceipt(
            id: "core-\(transaction.txidHexDisplay)",
            rail: .core,
            amountDuffs: amount,
            receivedAt: transaction.timestamp ?? Date(),
            memo: nil,
            transactionId: transaction.txid,
            coreStatus: status))
    }

    private func attachPlatformObserverIfNeeded(session: ReceiptSession) {
        guard platformReceiptCancellable == nil else { return }
        platformReceiptCancellable = NotificationCenter.default
            .publisher(for: .platformAddressActivityRecorded)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.checkPlatformActivity(session: session) }
        checkPlatformActivity(session: session)
        requestPlatformRefresh(session: session)
        startAttendedRefreshLoop(interval: AttendedReceiveRefreshPolicy.platformInterval) { [weak self] in
            self?.requestPlatformRefresh(session: session)
        }
    }

    private func checkPlatformActivity(session: ReceiptSession) {
        guard canActivelyWatch, receipt == nil, isSessionCurrent(session) else { return }
        guard let record = PlatformAddressActivityDAO.shared.activities(
            walletId: session.walletId,
            networkRaw: Int64(session.environment.rawValue),
            address: session.address,
            afterId: session.platformActivityCursor).first,
            record.amountDuffs > 0
        else { return }

        acceptReceipt(ReceiveReceipt(
            id: "platform-\(record.id)",
            rail: .platform,
            amountDuffs: UInt64(record.amountDuffs),
            receivedAt: record.observedAt,
            memo: nil,
            transactionId: nil,
            coreStatus: nil))
    }

    private func requestPlatformRefresh(session: ReceiptSession) {
        guard receipt == nil,
              isSessionCurrent(session),
              ReceiveReceiptPolicy.canRefreshPlatform(
                  isRunning: PlatformAddressSyncCoordinator.shared.isRunning,
                  availability: PlatformAddressSyncCoordinator.shared.platformAccountAvailability)
        else { return }
        Task { [weak self] in
            await PlatformAddressSyncCoordinator.shared.syncNow()
            guard let self else { return }
            self.checkPlatformActivity(session: session)
        }
    }

    private func attachShieldedObserverIfNeeded(
        session: ReceiptSession,
        syncResults: AnyPublisher<Void, Never>
    ) {
        guard shieldedReceiptCancellable == nil else { return }
        shieldedReceiptCancellable = syncResults
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.requestShieldedProjectionRefresh(session: session)
            }
        requestShieldedProjectionRefresh(session: session)
        receiptSources.requestShieldedRefresh()
        startAttendedRefreshLoop(interval: AttendedReceiveRefreshPolicy.shieldedInterval) {
            [weak self] in
            guard let self,
                  self.receipt == nil,
                  self.isSessionCurrent(session)
            else { return }
            self.receiptSources.requestShieldedRefresh()
        }
    }

    private func requestShieldedProjectionRefresh(session: ReceiptSession) {
        guard canActivelyWatch, receipt == nil, isSessionCurrent(session) else { return }
        guard shieldedProjectionTask == nil else {
            shieldedProjectionRefreshPending = true
            return
        }

        shieldedProjectionGeneration &+= 1
        let projectionGeneration = shieldedProjectionGeneration
        let project = receiptSources.projectedShieldedActivity
        shieldedProjectionTask = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) {
                project()
            }.value
            guard let self else { return }
            guard self.shieldedProjectionGeneration == projectionGeneration else { return }
            self.shieldedProjectionTask = nil
            guard !Task.isCancelled,
                  self.canActivelyWatch,
                  self.receipt == nil,
                  self.isSessionCurrent(session)
            else { return }

            let received = items
                .filter {
                    $0.kind == .received &&
                        !session.shieldedActivityIds.contains($0.id)
                }
                .min {
                    if $0.date == $1.date { return $0.id < $1.id }
                    return $0.date < $1.date
                }
            if let received {
                self.acceptReceipt(ReceiveReceipt(
                    id: received.id,
                    rail: .shielded,
                    amountDuffs: received.amountDuffs,
                    receivedAt: received.hasKnownDate ? received.date : Date(),
                    memo: received.memoText,
                    transactionId: nil,
                    coreStatus: nil))
                return
            }

            if self.shieldedProjectionRefreshPending {
                self.shieldedProjectionRefreshPending = false
                self.requestShieldedProjectionRefresh(session: session)
            }
        }
    }

    private func startAttendedRefreshLoop(
        interval: TimeInterval,
        refresh: @escaping @MainActor () -> Void
    ) {
        guard attendedRefreshTask == nil else { return }
        attendedRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                guard let self, self.canActivelyWatch else { return }
                refresh()
            }
        }
    }

    /// Shows `newReceipt` unless one is already shown. Called by the rail
    /// watchers; internal so tests can raise a receipt.
    func acceptReceipt(_ newReceipt: ReceiveReceipt) {
        guard receipt == nil else { return }
        receipt = newReceipt
        isWatchingForReceipt = false
        attendedRefreshTask?.cancel()
        attendedRefreshTask = nil
        platformReceiptCancellable?.cancel()
        platformReceiptCancellable = nil
        shieldedReceiptCancellable?.cancel()
        shieldedReceiptCancellable = nil
        shieldedProjectionTask?.cancel()
        shieldedProjectionTask = nil
        shieldedProjectionGeneration &+= 1
        shieldedProjectionRefreshPending = false
    }

    private func suspendReceiptWatching() {
        isWatchingForReceipt = false
        identityWatcher.setGateOpen(false)
        coreReceiptCancellable?.cancel()
        coreReceiptCancellable = nil
        platformReceiptCancellable?.cancel()
        platformReceiptCancellable = nil
        shieldedReceiptCancellable?.cancel()
        shieldedReceiptCancellable = nil
        attendedRefreshTask?.cancel()
        attendedRefreshTask = nil
        shieldedProjectionTask?.cancel()
        shieldedProjectionTask = nil
        shieldedProjectionGeneration &+= 1
        shieldedProjectionRefreshPending = false
    }

    private func invalidateReceiptSession() {
        suspendReceiptWatching()
        generation &+= 1
        session = nil
        displayedAddress = nil
        identityWatchSession = nil
        identityWatcher.stop()
    }

    /// A trip to another tab keeps a running Identity watch: only its gate
    /// closes, so credits that land meanwhile raise a Receipt on return and an
    /// own top-up meanwhile still moves the Starting balance (AC-08).
    private func activeTabDidChange() {
        if network == .identity, receipt == nil {
            reconcileReceiptWatching()
        } else {
            resetForRouteChange()
        }
        // Opening the Receive tab is a gain of focus; leaving it ends the
        // shielded session.
        beginReceiveSession()
    }

    private func resetForRouteChange() {
        receipt = nil
        invalidateReceiptSession()
        reconcileReceiptWatching()
    }

    /// A wallet or network change ends the Receive session: the next
    /// address must belong to the new wallet and network.
    func handleWalletOrEnvironmentChange() {
        receipt = nil
        invalidateReceiptSession()
        coreAddress = nil
        platformAddress = nil
        reloadCoreAddress()
        platformAddress = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.nextReceiveAddress?.address
        beginReceiveSession()
        #if DASHPAY
        // The identity is network-scoped, so a network switch can invalidate
        // the Send tab's username row exactly as a registration change does.
        refreshCanSendToUsername()
        refreshReceiveIdentity()
        #endif
        reconcileReceiptWatching()
    }

    private func isSessionCurrent(_ candidate: ReceiptSession) -> Bool {
        let context = receiptSources.walletContext()
        return session?.generation == candidate.generation &&
            generation == candidate.generation &&
            network == candidate.rail &&
            context?.walletId == candidate.walletId &&
            context?.environment == candidate.environment
    }

}
