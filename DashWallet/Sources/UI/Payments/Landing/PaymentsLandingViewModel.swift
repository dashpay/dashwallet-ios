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
        case .receive: return NSLocalizedString("Receive", comment: "")
        case .internalTransfer: return NSLocalizedString("Internal", comment: "")
        case .send: return NSLocalizedString("Send", comment: "")
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
            return NSLocalizedString("Detected in mempool", comment: "Receive payment status")
        case .instantSend:
            return NSLocalizedString("InstantSend confirmed", comment: "Receive payment status")
        case .inBlock:
            return NSLocalizedString("Confirmed in block", comment: "Receive payment status")
        case .chainLocked:
            return NSLocalizedString("ChainLocked", comment: "Receive payment status")
        }
    }
}

struct ReceiveReceipt: Identifiable, Equatable {
    let id: String
    let rail: ChainNetwork
    let amountDuffs: UInt64
    let receivedAt: Date
    let memo: String?
    let transactionId: Data?
    var coreStatus: CoreReceiptSettlementStatus?

    var statusTitle: String {
        coreStatus?.title ?? NSLocalizedString("Received", comment: "Receive payment status")
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

@MainActor
final class PaymentsLandingViewModel: ObservableObject {

    @Published var activeTab: PaymentsLandingTab
    @Published var network: ChainNetwork = .core
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

    @Published private(set) var coreAddress: String? = nil
    @Published private(set) var platformAddress: String? = nil
    @Published private(set) var shieldedAddress: String? = nil
    @Published private(set) var displayedAddress: String? = nil
    @Published private(set) var receipt: ReceiveReceipt? = nil
    @Published private(set) var isWatchingForReceipt = false

    let allowsTransactionDetails: Bool

    private struct ReceiptSession {
        let generation: UInt64
        let rail: ChainNetwork
        let address: String
        let walletId: Data
        let environment: Network
        let startedAt: Date
        let coreTransactionIds: Set<Data>
        let platformActivityCursor: Int64
        let shieldedActivityIds: Set<String>
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
    private var generation: UInt64 = 0
    private var surfaceIsVisible = false
    private var presentationIsObscuring = false
    private var appIsActive = UIApplication.shared.applicationState == .active

    init(activeTab: PaymentsLandingTab,
         network: ChainNetwork = .core,
         visibleTabs: [PaymentsLandingTab] = PaymentsLandingTab.allCases,
         allowsTransactionDetails: Bool = true) {
        self.activeTab = activeTab
        self.network = network
        self.visibleTabs = visibleTabs
        self.allowsTransactionDetails = allowsTransactionDetails

        reloadCoreAddress()
        reloadShieldedAddress()

        NotificationCenter.default.publisher(for: .advancedModeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isAdvancedMode = DWGlobalOptions.sharedInstance().advancedModeEnabled
            }
            .store(in: &cancellables)

        PlatformAddressSyncCoordinator.shared.$derivedAddresses
            .receive(on: RunLoop.main)
            .sink { [weak self] addresses in
                guard let self else { return }
                self.platformAddress = addresses.nextReceiveAddress?.address
                // The shielded sub-wallet is bound by the same coordinator's
                // startup, so a derived-addresses tick is also the retry
                // signal for a shielded address that wasn't ready at init.
                self.reloadShieldedAddress()
                self.reconcileReceiptWatching()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            PlatformAddressSyncCoordinator.shared.$isRunning.removeDuplicates(),
            PlatformAddressSyncCoordinator.shared.$platformAccountAvailability.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.reconcileReceiptWatching() }
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

        $activeTab
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resetForRouteChange() }
            .store(in: &cancellables)

        $network
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resetForRouteChange() }
            .store(in: &cancellables)
    }

    #if DEBUG
    /// Lightweight initializer used only by SwiftUI previews: takes the
    /// addresses as literals instead of reading them from the wallet, and
    /// subscribes to nothing.
    private init(
        previewActiveTab: PaymentsLandingTab,
        previewNetwork: ChainNetwork,
        previewVisibleTabs: [PaymentsLandingTab],
        previewCoreAddress: String?,
        previewPlatformAddress: String?,
        previewShieldedAddress: String?
    ) {
        activeTab = previewActiveTab
        network = previewNetwork
        visibleTabs = previewVisibleTabs
        coreAddress = previewCoreAddress
        platformAddress = previewPlatformAddress
        shieldedAddress = previewShieldedAddress
        // A preview has no host to route to and no transaction to route with,
        // so the receipt's "View transaction" stays hidden rather than drawing
        // a control that could not do anything.
        allowsTransactionDetails = false
    }

    /// Preview view model. Pass `nil` for an address to preview that
    /// network's placeholder state instead of the QR card.
    static func makeForPreview(
        activeTab: PaymentsLandingTab = .internalTransfer,
        network: ChainNetwork = .core,
        visibleTabs: [PaymentsLandingTab] = PaymentsLandingTab.allCases,
        coreAddress: String? = "XyZ8kFqW3nR5tHmB2vJcL7pQaS4dEuG9wN",
        platformAddress: String? = "XmQ4rT7bN2vK9sD5xF8jH3kL6pW1aZcYuE",
        shieldedAddress: String? = nil
    ) -> PaymentsLandingViewModel {
        PaymentsLandingViewModel(
            previewActiveTab: activeTab,
            previewNetwork: network,
            previewVisibleTabs: visibleTabs,
            previewCoreAddress: coreAddress,
            previewPlatformAddress: platformAddress,
            previewShieldedAddress: shieldedAddress)
    }
    #endif

    var currentAddress: String? {
        if session?.rail == network, let displayedAddress {
            return displayedAddress
        }
        return candidateAddress(for: network)
    }

    var canViewTransaction: Bool {
        allowsTransactionDetails && receipt?.transactionId != nil
    }

    private func candidateAddress(for rail: ChainNetwork) -> String? {
        switch rail {
        case .core: return coreAddress
        case .platform: return platformAddress
        case .shielded: return shieldedAddress
        }
    }

    var platformIsReady: Bool {
        PlatformAddressSyncCoordinator.shared.isRunning
    }

    func copyCurrentAddressToPasteboard() {
        guard let address = currentAddress else { return }
        UIPasteboard.general.string = address
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

    func receiveAnother() {
        receipt = nil
        invalidateReceiptSession()
        reloadCoreAddress()
        platformAddress = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.nextReceiveAddress?.address
        shieldedAddress = nil
        reloadShieldedAddress()
        reconcileReceiptWatching()
    }

    private func reloadCoreAddress() {
        coreAddress = SwiftDashSDKReceiveAddressReader.receiveAddress()
    }

    /// Resolves the wallet's default Orchard payment address and encodes it
    /// for display. `shieldedDefaultAddress` returns nil until the shielded
    /// sub-wallet is bound (PlatformAddressSyncCoordinator does that at
    /// startup), so this is retried from the derived-addresses sink until it
    /// resolves; the address is deterministic, so no reset on later ticks.
    private func reloadShieldedAddress() {
        guard shieldedAddress == nil,
              let manager = SwiftDashSDKHost.shared.manager,
              let wallet = SwiftDashSDKHost.shared.wallet,
              let network = SwiftDashSDKHost.shared.runningNetwork,
              let raw = ((try? manager.shieldedDefaultAddress(walletId: wallet.walletId)) ?? nil)
        else { return }
        // DIP-0018 display form: HRP `dash`/`tdash`, payload = 0x10 type
        // byte + the 43 raw Orchard address bytes (see the SDK doc on
        // `shieldedDefaultAddress`).
        shieldedAddress = Bech32m.encode(
            hrp: Bech32m.platformHrp(mainnet: network == .mainnet),
            data: Data([0x10]) + raw)
    }

    private var canActivelyWatch: Bool {
        surfaceIsVisible &&
            !presentationIsObscuring &&
            appIsActive &&
            activeTab == .receive
    }

    private func reconcileReceiptWatching() {
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
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
              let environment = WalletEnvironment.network,
              SwiftDashSDKHost.shared.runningNetwork == environment
        else {
            displayedAddress = nil
            isWatchingForReceipt = false
            return
        }

        generation &+= 1
        let sessionGeneration = generation
        var coreTransactionIds = Set<Data>()
        var platformActivityCursor: Int64 = 0
        var shieldedActivityIds = Set<String>()

        switch network {
        case .core:
            coreTransactionIds = TransactionObserver.persistedTransactionIDs()
        case .platform:
            platformActivityCursor = PlatformAddressActivityDAO.shared.latestActivityId(
                walletId: walletId,
                networkRaw: Int64(environment.rawValue))
        case .shielded:
            shieldedActivityIds = Set(Self.projectedShieldedActivity().map(\.id))
        }

        session = ReceiptSession(
            generation: sessionGeneration,
            rail: network,
            address: address,
            walletId: walletId,
            environment: environment,
            startedAt: Date(),
            coreTransactionIds: coreTransactionIds,
            platformActivityCursor: platformActivityCursor,
            shieldedActivityIds: shieldedActivityIds)
        displayedAddress = address
        resumeReceiptWatching()
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
            guard PlatformAddressSyncCoordinator.shared.isRunning,
                  PlatformAddressSyncCoordinator.shared.platformWalletManager != nil else {
                isWatchingForReceipt = false
                return
            }
            isWatchingForReceipt = true
            attachShieldedObserverIfNeeded(session: session)
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

    private func attachShieldedObserverIfNeeded(session: ReceiptSession) {
        guard let manager = PlatformAddressSyncCoordinator.shared.platformWalletManager else { return }
        guard shieldedReceiptCancellable == nil else { return }
        shieldedReceiptCancellable = manager.$lastShieldedSyncEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let result = event?.result(for: session.walletId),
                      ReceiveReceiptPolicy.shouldProjectShieldedResult(
                          success: result.success,
                          cooldownSkip: result.cooldownSkip)
                else { return }
                self?.requestShieldedProjectionRefresh(session: session)
            }
        requestShieldedProjectionRefresh(session: session)
        PlatformAddressSyncCoordinator.shared.requestShieldedRefresh(
            using: manager,
            reason: "attended receive")
        startAttendedRefreshLoop(interval: AttendedReceiveRefreshPolicy.shieldedInterval) {
            [weak self, weak manager] in
            guard let self, let manager,
                  self.receipt == nil,
                  self.isSessionCurrent(session)
            else { return }
            PlatformAddressSyncCoordinator.shared.requestShieldedRefresh(
                using: manager,
                reason: "attended receive")
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
        shieldedProjectionTask = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) {
                Self.projectedShieldedActivity()
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

    nonisolated private static func projectedShieldedActivity() -> [ShieldedActivityItem] {
        let coreTransactions = SwiftDashSDKWalletSource
            .fetchCurrentWalletSnapshot()?.transactions ?? []
        return SwiftDashSDKWalletSource.fetchShieldedActivity(
            coreTransactions: coreTransactions)
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

    private func acceptReceipt(_ newReceipt: ReceiveReceipt) {
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
    }

    private func resetForRouteChange() {
        receipt = nil
        invalidateReceiptSession()
        reconcileReceiptWatching()
    }

    private func handleWalletOrEnvironmentChange() {
        receipt = nil
        invalidateReceiptSession()
        coreAddress = nil
        platformAddress = nil
        shieldedAddress = nil
        reloadCoreAddress()
        platformAddress = PlatformAddressSyncCoordinator.shared
            .derivedAddresses.nextReceiveAddress?.address
        reloadShieldedAddress()
        reconcileReceiptWatching()
    }

    private func isSessionCurrent(_ candidate: ReceiptSession) -> Bool {
        session?.generation == candidate.generation &&
            generation == candidate.generation &&
            network == candidate.rail &&
            SwiftDashSDKHost.shared.wallet?.walletId == candidate.walletId &&
            WalletEnvironment.network == candidate.environment
    }

}
