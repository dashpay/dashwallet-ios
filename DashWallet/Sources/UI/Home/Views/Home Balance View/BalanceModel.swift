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
    /// known value.
    @Published private(set) var awaitingConfirmationDuffs: UInt64?
    /// Bumped on every wallet or network switch (main queue only).
    private var walletGeneration = 0
    /// Set on a switch, cleared by the next balance event (main queue only).
    private var awaitingNewWalletBalance = false
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

        // Read from the saved coins in one fetch, off the main thread, after a
        // balance event or a save that touched them — the coins are saved a
        // moment after the balance moves. The newest read wins.
        let coinSaves = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { HomeViewModel.saveTouchesFeedRows($0) }
            .map { _ in () }
        // Another wallet's (or network's) waiting coins are not this one's:
        // cleared (nil, not known) at once; the new wallet's value comes with
        // the first read after its first balance event.
        let walletChanges = NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .merge(with: NotificationCenter.default.publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification))
            .receive(on: DispatchQueue.main)
            // Bumped before any subscriber sees the switch: reads started
            // earlier are the old wallet's. Until the new wallet's first
            // balance event the host may still serve the old wallet, so no
            // read counts before it either.
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.walletGeneration += 1
                self?.awaitingNewWalletBalance = true
            })
            .map { _ in () }
            .share()
        let balanceEvents = SwiftDashSDKWalletState.shared.$balance
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] _ in self?.awaitingNewWalletBalance = false })
            .map { _ in () }
        let reads = balanceEvents
            .merge(with: coinSaves)
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .map { [weak self] _ in
                // Tagged with the wallet generation it was started for: a read
                // that lands after a switch is the old wallet's.
                let generation = (self?.awaitingNewWalletBalance ?? true) ? -1 : (self?.walletGeneration ?? 0)
                return Future<(Int, UInt64?), Never> { promise in
                    DispatchQueue.global(qos: .utility).async {
                        promise(.success((generation, SwiftDashSDKWalletSource.awaitingConfirmationDuffs())))
                    }
                }
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .compactMap { [weak self] generation, duffs -> UInt64? in
                // A read that failed (host unbound, fetch error) keeps the last
                // known value rather than claiming nothing is waiting.
                guard generation == self?.walletGeneration else { return nil }
                return duffs
            }
        reads
            .map { Optional($0) }
            .merge(with: walletChanges.map { UInt64?.none })
            .removeDuplicates()
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
