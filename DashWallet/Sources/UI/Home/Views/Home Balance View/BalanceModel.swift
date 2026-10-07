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
    /// it (`SwiftDashSDKWalletSource.awaitingConfirmation()`); nil while
    /// not known — before the first read and after a wallet or network
    /// switch until the new wallet's read lands; a failed read keeps the last
    /// known value (`PendingBalanceFollower`).
    @Published private(set) var awaitingConfirmationDuffs: UInt64?
    private let pendingBalance = PendingBalanceFollower(
        signals: .live,
        boundScope: { SwiftDashSDKWalletSource.boundPendingBalanceScope() },
        read: { SwiftDashSDKWalletSource.awaitingConfirmation() })
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
/// Another wallet's (or network's) waiting coins are not this one's, so a
/// value is tied to the wallet it was read for, not to the order of the
/// switch notifications:
/// - every read comes back with the `Scope` it read (the bound wallet and
///   its store), and counts only if that is still what is bound when it
///   lands;
/// - while the balance itself is not known (a teardown clears it), the part
///   of it that waits is not known either: cleared, and no read is made;
/// - `walletDidChange` (`activeWalletDidChangeNotification`: posted once a
///   switch has bound its wallet, and after a wallet is removed) clears a
///   value that is not the bound wallet's and starts a read. On an idle or
///   offline switch the destination's balance is published before that
///   notification and nothing follows it, so this read is the one that
///   brings the caption up if the earlier one did not.
final class PendingBalanceFollower {
    /// What a value was read for: a wallet in the store the host had bound.
    /// A network switch or a rebuild binds another store.
    struct Scope: Equatable {
        let store: ObjectIdentifier
        let walletId: Data
    }

    struct Reading {
        let scope: Scope
        let duffs: UInt64
    }

    struct Signals {
        /// A balance was published; true when it is a known amount (false
        /// for the cleared, not-known state of a teardown).
        let balanceEvents: AnyPublisher<Bool, Never>
        let coinSaves: AnyPublisher<Void, Never>
        let walletDidChange: AnyPublisher<Void, Never>

        static var live: Signals {
            let center = NotificationCenter.default
            return Signals(
                balanceEvents: SwiftDashSDKWalletState.shared.$balance.map { $0 != nil }.eraseToAnyPublisher(),
                coinSaves: center.publisher(for: .NSManagedObjectContextDidSave)
                    .filter { HomeViewModel.saveTouchesFeedRows($0) }
                    .map { _ in () }
                    .eraseToAnyPublisher(),
                walletDidChange: center.publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
                    .map { _ in () }
                    .eraseToAnyPublisher())
        }
    }

    /// Nil while not known: before the first read, while the balance is not
    /// known, and from a switch until the new wallet's read lands. A failed
    /// read keeps the last value.
    @Published private(set) var duffs: UInt64?

    /// What `duffs` was read for (main queue only).
    private var shownScope: Scope?
    /// The last balance event was a known amount (main queue only).
    private var isBalanceKnown = false
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - boundScope: what the host has bound now, nil when nothing is;
    ///     called on the main queue.
    ///   - read: the waiting duffs of what is bound when it runs, with its
    ///     scope; nil when they could not be read. Called off the main
    ///     thread.
    init(
        signals: Signals,
        interval: DispatchQueue.SchedulerTimeType.Stride = .seconds(1),
        boundScope: @escaping () -> Scope?,
        read: @escaping () -> Reading?
    ) {
        let main = DispatchQueue.main
        let balanceEvents = signals.balanceEvents
            .receive(on: main)
            .handleEvents(receiveOutput: { [weak self] isKnown in
                self?.isBalanceKnown = isKnown
                if !isKnown { self?.clear() }
            })
            .map { _ in () }
        let walletChanges = signals.walletDidChange
            .receive(on: main)
            .handleEvents(receiveOutput: { [weak self] _ in
                guard let self, self.shownScope != boundScope() else { return }
                self.clear()
            })
        balanceEvents
            .merge(with: signals.coinSaves, walletChanges)
            .throttle(for: interval, scheduler: main, latest: true)
            .map { [weak self] _ -> AnyPublisher<Reading?, Never> in
                // Nothing to read for while the balance is not known.
                guard self?.isBalanceKnown == true else { return Empty<Reading?, Never>().eraseToAnyPublisher() }
                return Future<Reading?, Never> { promise in
                    DispatchQueue.global(qos: .utility).async { promise(.success(read())) }
                }
                .eraseToAnyPublisher()
            }
            .switchToLatest()
            .receive(on: main)
            .sink { [weak self] reading in
                // A read that failed (host unbound, fetch error) keeps the last
                // known value rather than claiming nothing is waiting. One
                // that lands after a switch or a teardown is not this
                // wallet's.
                guard let self, let reading, self.isBalanceKnown, reading.scope == boundScope() else { return }
                self.shownScope = reading.scope
                if self.duffs != reading.duffs { self.duffs = reading.duffs }
            }
            .store(in: &cancellables)
    }

    private func clear() {
        shownScope = nil
        if duffs != nil { duffs = nil }
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
