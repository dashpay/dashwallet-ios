//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import Foundation
import Combine

// MARK: - BalanceModel

final class BalanceModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    
    @Published private(set) var state = SyncingActivityMonitor.shared.state
    /// `nil` until the selected wallet's balance has been read. A known zero
    /// is an amount; an unavailable snapshot uses the same placeholder as the
    /// other Home balance rows.
    @Published private(set) var value: UInt64?
    /// Part of `value` that a payment cannot use until the network confirms
    /// it (`SwiftDashSDKWalletSource.awaitingConfirmationDuffs()`); nil while
    /// not known — before the first read and after a wallet or network
    /// switch until the new wallet's read lands; a failed read keeps the last
    /// known value (`PendingBalanceFollower`).
    @Published private(set) var awaitingConfirmationDuffs: UInt64?
    private let pendingBalance = PendingBalanceFollower(
        signals: .live, read: { SwiftDashSDKWalletSource.awaitingConfirmationDuffs() })
    /// Badge text for the home header while the wallet runs on a test
    /// network ("TESTNET"/"DEVNET"), so test funds can't be mistaken for
    /// real Dash; nil on mainnet.
    @Published private(set) var networkBadgeText: String? = BalanceModel.badgeText()
    @Published var isBalanceHidden: Bool {
        didSet {
            DWGlobalOptions.sharedInstance().balanceHidden = isBalanceHidden
        }
    }
    
    var shouldShowTapToHideBalance: Bool {
        get { !DWGlobalOptions.sharedInstance().tapToHideBalanceShown }
        set(value) {
            DWGlobalOptions.sharedInstance().tapToHideBalanceShown = !value
        }
    }

    init() {
        isBalanceHidden = DWGlobalOptions.sharedInstance().balanceHidden
        SyncingActivityMonitor.shared.add(observer: self)

        // Wallet state publishes and clears on the main queue. Consume the
        // emitted snapshot directly: another run-loop hop delays the restored
        // amount behind startup work, and rereading `shared.balance` here sees
        // the old value because @Published emits from willSet.
        SwiftDashSDKWalletState.shared.$balance
            .sink { [weak self] snapshot in
                self?.applyBalance(snapshot)
            }
            .store(in: &cancellableBag)

        pendingBalance.$duffs
            .sink { [weak self] duffs in
                self?.awaitingConfirmationDuffs = duffs
            }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.networkBadgeText = BalanceModel.badgeText()
            }
            .store(in: &cancellableBag)

        reloadBalance()
        observeAppLifecycle()
    }

    private static func badgeText() -> String? {
        switch WalletEnvironment.networkKind {
        case .mainnet:
            return nil
        case .testnet:
            return NSLocalizedString("TESTNET", comment: "Badge on the home balance while the wallet runs on testnet")
        case .devnet:
            return NSLocalizedString("DEVNET", comment: "Badge on the home balance while the wallet runs on a devnet")
        }
    }

    func hideBalanceIfNeeded() {
        if DWGlobalOptions.sharedInstance().balanceHidden {
            isBalanceHidden = true
        }
    }

    func reloadBalance() {
        applyBalance(SwiftDashSDKWalletState.shared.balance)
    }

    private func applyBalance(_ walletBalance: WalletBalance?) {
        // Source from SwiftDashSDKWalletState instead of
        // DWEnvironment.sharedInstance().currentWallet.balance. After M6
        // (commit 86ed72706), DashSync's SPV no longer runs and
        // DSWallet.balance is frozen — SwiftDashSDK is the authoritative
        // source. `WalletBalance.total` sums every bucket — confirmed,
        // unconfirmed, immature and locked — matching the "everything
        // user-visible" semantic dashwallet's UI displays.
        // Function #5 of the DashSync migration.
        let balanceValue = walletBalance?.total

        if let balanceValue, let previousValue = value,
            balanceValue > previousValue &&
            previousValue > 0 &&
            UIApplication.shared.applicationState != .background &&
            SyncingActivityMonitor.shared.progress > 0.995 {
            UIDevice.current.dw_playCoinSound()
        }

        value = balanceValue

        let options = DWGlobalOptions.sharedInstance()
        if let balanceValue, balanceValue > 0
            && options.walletNeedsBackup
            && (options.balanceChangedDate == nil) {
            options.balanceChangedDate = Date()
        }

        // Only write when the balance is actually known. `userHasBalance` is
        // persisted per wallet and is an input to the default shortcut bar, so
        // writing `false` for a not-yet-loaded balance let a single launch
        // before the wallet was bound permanently drop a shortcut from a funded
        // wallet's bar. `nil` means "not known yet", never "empty".
        if let total = walletBalance?.total {
            options.userHasBalance = total > 0
        }
        isBalanceHidden = DWGlobalOptions.sharedInstance().balanceHidden
    }
    
    func toggleBalanceVisibility() {
        isBalanceHidden = !isBalanceHidden
        shouldShowTapToHideBalance = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        SyncingActivityMonitor.shared.remove(observer: self)
    }
}

extension BalanceModel {
    func observeAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.hideBalanceIfNeeded()
            }
            .store(in: &cancellableBag)
    }
}

// MARK: - PendingBalanceFollower

/// Follows the part of the balance that waits for confirmation: read from
/// the saved coins in one fetch, off the main thread, after a balance event
/// or a save that touched them (the coins are saved a moment after the
/// balance moves), at most once per `interval`. The newest read wins.
///
/// Another wallet's (or network's) waiting coins are not this one's. Two
/// signals bound a switch, and they are not the same moment:
/// - `networkWillChange` comes before the runtime tears the old wallet down:
///   the value is cleared, and no read counts until the next wallet is up.
/// - `walletDidBind` comes after the destination wallet is bound and its
///   balance already published (`SwiftDashSDKWalletRuntime` posts
///   `activeWalletDidChangeNotification` after the refresh): the value is
///   cleared and a read for that wallet is scheduled — on an idle or offline
///   switch no later balance event or save would start one.
///
/// A rebuild that posts no `walletDidBind` (a plain restart after a failed
/// switch) is taken as up at its first known balance.
final class PendingBalanceFollower {
    struct Signals {
        /// A balance was published; true when it is a known amount (false
        /// for the cleared, not-known state of a teardown).
        let balanceEvents: AnyPublisher<Bool, Never>
        let coinSaves: AnyPublisher<Void, Never>
        let networkWillChange: AnyPublisher<Void, Never>
        let walletDidBind: AnyPublisher<Void, Never>

        static var live: Signals {
            let center = NotificationCenter.default
            return Signals(
                balanceEvents: SwiftDashSDKWalletState.shared.$balance.map { $0 != nil }.eraseToAnyPublisher(),
                coinSaves: center.publisher(for: .NSManagedObjectContextDidSave)
                    .filter { HomeViewModel.saveTouchesFeedRows($0) }
                    .map { _ in () }
                    .eraseToAnyPublisher(),
                networkWillChange: center.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
                    .map { _ in () }
                    .eraseToAnyPublisher(),
                walletDidBind: center.publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
                    .map { _ in () }
                    .eraseToAnyPublisher())
        }
    }

    /// Nil while not known: before the first read, and from a switch until
    /// the new wallet's read lands. A failed read keeps the last value.
    @Published private(set) var duffs: UInt64?

    /// Bumped on every switch signal; a read started for an earlier one is
    /// another wallet's (main queue only).
    private var generation = 0
    /// Between `networkWillChange` and the next wallet being up, the host may
    /// still serve the old wallet: no read counts (main queue only).
    private var awaitingWallet = false
    private var cancellables = Set<AnyCancellable>()

    /// - Parameter read: the waiting duffs of the wallet bound now, nil when
    ///   they could not be read; called off the main thread.
    init(signals: Signals, interval: DispatchQueue.SchedulerTimeType.Stride = .seconds(1), read: @escaping () -> UInt64?) {
        let main = DispatchQueue.main
        let willChange = signals.networkWillChange
            .receive(on: main)
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.generation += 1
                self?.awaitingWallet = true
            })
            .share()
        let didBind = signals.walletDidBind
            .receive(on: main)
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.generation += 1
                self?.awaitingWallet = false
            })
            .share()
        let balanceEvents = signals.balanceEvents
            .receive(on: main)
            .handleEvents(receiveOutput: { [weak self] isKnown in
                if isKnown { self?.awaitingWallet = false }
            })
            .map { _ in () }
        let reads = balanceEvents
            .merge(with: signals.coinSaves, didBind)
            .throttle(for: interval, scheduler: main, latest: true)
            .map { [weak self] _ in
                // Tagged with the generation it was started for: a read that
                // lands after a switch is the old wallet's.
                let generation = (self?.awaitingWallet ?? true) ? -1 : (self?.generation ?? 0)
                return Future<(Int, UInt64?), Never> { promise in
                    DispatchQueue.global(qos: .utility).async {
                        promise(.success((generation, read())))
                    }
                }
            }
            .switchToLatest()
            .receive(on: main)
            .compactMap { [weak self] generation, duffs -> UInt64? in
                // A read that failed (host unbound, fetch error) keeps the last
                // known value rather than claiming nothing is waiting.
                guard generation == self?.generation else { return nil }
                return duffs
            }
        reads
            .map { Optional($0) }
            .merge(with: willChange.map { _ in UInt64?.none }, didBind.map { _ in UInt64?.none })
            .removeDuplicates()
            .sink { [weak self] duffs in
                self?.duffs = duffs
            }
            .store(in: &cancellables)
    }
}

// MARK: BalanceViewDataSource

extension BalanceModel: BalanceViewDataSource {
    var mainAmountString: String {
        value?.formattedDashAmount ?? "—"
    }

    var supplementaryAmountString: String {
        fiatAmountString()
    }
}

// MARK: SyncingActivityMonitorObserver

extension BalanceModel: SyncingActivityMonitorObserver {
    func syncingActivityMonitorProgressDidChange(_ progress: Double) {
        // NOP
    }

    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        self.state = state
        reloadBalance()
    }
}

extension BalanceModel {
    func dashAmountStringWithFont(_ font: UIFont, tintColor: UIColor) -> NSAttributedString {
        guard let value else {
            return NSAttributedString(string: "—", attributes: [.font: font, .foregroundColor: tintColor])
        }
        return NSAttributedString.dashAttributedString(for: value, tintColor: tintColor, font: font)
    }

    func fiatAmountString() -> String {
        guard let value else { return "—" }
        return CurrencyExchanger.shared.fiatAmountString(for: value.dashAmount)
    }

    /// Fiat string for an arbitrary duff amount — used by the balance
    /// breakdown rows (transparent / platform / shielded) and the
    /// combined-total hero, which aggregate more than `value`.
    func fiatString(forDuffs duffs: UInt64) -> String {
        CurrencyExchanger.shared.fiatAmountString(for: duffs.dashAmount)
    }
}
