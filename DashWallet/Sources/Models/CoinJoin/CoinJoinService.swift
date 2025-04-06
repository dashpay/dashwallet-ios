//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

enum MixingStatus: Int {
    case notStarted
    case mixing
    case paused
    case finishing
    case finished
    case error
    
    var isInProgress: Bool {
        self == .mixing || self == .paused || self == .error || self == .finishing
    }
    
    var localizedValue: String {
        get {
            switch self {
            case .notStarted:
                NSLocalizedString("Not started", comment: "CoinJoin")
            case .mixing:
                NSLocalizedString("Mixing ·", comment: "CoinJoin")
            case .paused:
                NSLocalizedString("Mixing Paused ·", comment: "CoinJoin")
            case .finishing:
                NSLocalizedString("Mixing Finishing…", comment: "CoinJoin")
            case .finished:
                NSLocalizedString("Fully mixed", comment: "CoinJoin")
            case .error:
                NSLocalizedString("Error ·", comment: "CoinJoin")
            }
        }
    }
}

@objc
enum CoinJoinMode: Int {
    case none
    case intermediate
    case advanced
}

private let kDefaultMultisession = false // (android comment) for stability, need to investigate
private let kDefaultRounds: Int32 = 4
private let kDefaultSessions: Int32 = 6
private let kDefaultDenominationGoal: Int32 = 50
private let kDefaultDenominationHardcap: Int32 = 300
private let kCoinJoinMainnetMode = "coinJoinModeMainnetKey"
private let kCoinJoinTestnetMode = "coinJoinModeTestnetKey"
let kMaxAllowedAheadTimeskew: TimeInterval = 5
let kMaxAllowedBehindTimeskew: TimeInterval = 20


@objc
public class CoinJoinServiceWrapper: NSObject {
    @objc class func mode() -> CoinJoinMode {
        return CoinJoinService.shared.mode
    }
}

class CoinJoinService: NSObject, NetworkReachabilityHandling {
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!
    
    static let shared: CoinJoinService = {
        return CoinJoinService()
    }()
    
    private var permanentBag = Set<AnyCancellable>()
    private var cancellableBag = Set<AnyCancellable>()
    private let updateMutex = NSLock()
    private let updateMixingStateMutex = NSLock()
    private var coinJoinManager: DSCoinJoinManager? = nil
    private var hasAnonymizableBalance: Bool = false
    private var timeSkew: TimeInterval = 0
    private var savedBalance: UInt64 = 0
    private var workingChain: DSChain
    private var currentSyncState: SyncingActivityMonitor.State = .unknown

    private var chainModeKey: String {
        get {
            DWEnvironment.sharedInstance().currentChain.isMainnet() ? kCoinJoinMainnetMode : kCoinJoinTestnetMode
        }
    }
    
    private var currentMode: CoinJoinMode {
        get {
            let final = CoinJoinMode(rawValue: UserDefaults.standard.integer(forKey: chainModeKey)) ?? .none
            
            if self.mode != final {
                self.mode = final
            }
            
            return final
        }
        set(value) {
            DSLogger.log("[SW] CoinJoin: set currentMode: \(value)")
            self.mode = value
            UserDefaults.standard.set(value.rawValue, forKey: chainModeKey)
        }
    }
    
    @Published private(set) var mode: CoinJoinMode = .none
    @Published var mixingState: MixingStatus = .notStarted
    @Published private(set) var progress = CoinJoinProgress(progress: 0.0, totalBalance: 0, coinJoinBalance: 0)
    @Published private(set) var networkStatus: NetworkStatus = .online
    
    override init() {
        workingChain = DWEnvironment.sharedInstance().currentChain
        super.init()
        
        networkStatusDidChange = { [weak self] state in
            self?.updateNetworkState(newState: state)
        }
        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .sink { [weak self] _ in
                DSLogger.log("CoinJoin: change of network to \(DWEnvironment.sharedInstance().currentChain.name), resetting")
                self?.workingChain = DWEnvironment.sharedInstance().currentChain
                self?.restoreMode()
            }
            .store(in: &permanentBag)
        
        restoreMode()
        startNetworkMonitoring()
    }
    
    func updateMode(mode: CoinJoinMode, force: Bool = false) async {
        if mode != .none && (force || mode != self.currentMode) {
            configureMixing(mode: mode)
            configureObservers()
        } else if mode == .none {
            removeObservers()
        }
        
        let account = DWEnvironment.sharedInstance().currentAccount
        await updateBalance(balance: account.balance)
        updateState(mode: mode, timeSkew: self.timeSkew, hasAnonymizableBalance: self.hasAnonymizableBalance, networkStatus: self.networkStatus, chain: DWEnvironment.sharedInstance().currentChain)
    }
    
    func updateTimeSkew(timeSkew: TimeInterval) {
        updateTimeSkewInternal(timeSkew: timeSkew)
    }
    
    private func prepareMixing() {
        guard let coinJoinManager = self.coinJoinManager ?? createCoinJoinManager() else { return }
     
        coinJoinManager.managerDelegate = self
        coinJoinManager.setStopOnNothingToDo(true)
        coinJoinManager.start()
    }
    
    private func startMixing() async {
        guard let coinJoinManager = self.coinJoinManager else { return }
        
        if !coinJoinManager.startMixing() {
            DSLogger.log("CoinJoin: Mixing has been started already.")
        } else {
            coinJoinManager.refreshUnusedKeys()
            coinJoinManager.initMasternodeGroup()
            await coinJoinManager.doAutomaticDenominating(withDryRun: false)
        }
    }
    
    private func configureMixing(mode: CoinJoinMode) {
        guard let coinJoinManager = self.coinJoinManager ?? createCoinJoinManager() else { return }
        
        let account = DWEnvironment.sharedInstance().currentAccount
        let rounds: Int32
        switch mode {
        case .none:
            return
        case .intermediate:
            rounds = kDefaultRounds
        case .advanced:
            rounds = kDefaultRounds * 2
        }
        
        coinJoinManager.configureMixing(withAmount: account.balance, rounds: rounds, sessions: kDefaultSessions, withMultisession: kDefaultMultisession, denominationGoal: kDefaultDenominationGoal, denominationHardCap: kDefaultDenominationHardcap)
    }
    
    private func updateProgress() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self, let coinJoinManager = self.coinJoinManager else { return }
            
            let progress = coinJoinManager.getMixingProgress()
            let coinJoinBalance = coinJoinManager.getBalance()
            let totalBalance = coinJoinBalance.myTrusted
            let anonymizedBalance = coinJoinBalance.anonymized
            
            DispatchQueue.main.async {
                self.progress = CoinJoinProgress(progress: progress, totalBalance: totalBalance, coinJoinBalance: anonymizedBalance)
            }
        }
    }
    
    private func createCoinJoinManager() -> DSCoinJoinManager? {
        self.coinJoinManager = DSCoinJoinManager.sharedInstance(for: DWEnvironment.sharedInstance().currentChain)
        coinJoinManager?.managerDelegate = self
        return self.coinJoinManager
    }
    
    private func updateBalance(balance: UInt64) async {
        guard let coinJoinManager = self.coinJoinManager else { return }
        
        self.savedBalance = balance
        coinJoinManager.updateOptions(withAmount: balance)
        DSLogger.log("CoinJoin: total balance: \(balance)")
        let canDenominate = await coinJoinManager.doAutomaticDenominating(withDryRun: true)
        let coinJoinBalance = coinJoinManager.getBalance()
        DSLogger.log("CoinJoin: mixed balance: \(coinJoinBalance.anonymized), denomTrusted: \(coinJoinBalance.denominatedTrusted)")
        let anonBalance = await coinJoinManager.calculateAnonymizableBalance(withSkipDenominated: false, skipUnconfirmed: false)
        let minValue = await coinJoinManager.minimumAnonymizableBalance()
        DSLogger.log("CoinJoin: anonymizable balance \(anonBalance), minValue: \(minValue)")
        let hasPartiallyMixedCoins = (coinJoinBalance.denominatedTrusted - coinJoinBalance.anonymized) > 0
        let hasAnonymizableBalance = anonBalance > minValue
        let hasBalanceLeftToMix: Bool
        
        if hasPartiallyMixedCoins {
            hasBalanceLeftToMix = true
        } else if hasAnonymizableBalance && canDenominate {
            hasBalanceLeftToMix = true
        } else {
            hasBalanceLeftToMix = false
        }

        DSLogger.log("CoinJoin: can mix balance: \(hasBalanceLeftToMix) = balance: (\(anonBalance > minValue) && canDenominate: \(canDenominate)) || partially-mixed: \(hasPartiallyMixedCoins)")

        updateState(
            mode: self.currentMode,
            timeSkew: self.timeSkew,
            hasAnonymizableBalance: hasBalanceLeftToMix,
            networkStatus: self.networkStatus,
            chain: DWEnvironment.sharedInstance().currentChain
        )
    }
    
    private func stopMixing() {
        self.coinJoinManager?.managerDelegate = nil
        self.coinJoinManager?.stop()
    }
    
    private func initiateShutdown() {
        self.coinJoinManager?.initiateShutdown()
    }

    private func updateState(
        mode: CoinJoinMode,
        timeSkew: TimeInterval,
        hasAnonymizableBalance: Bool,
        networkStatus: NetworkStatus,
        chain: DSChain
    ) {
        if !recheckCurrentChain() {
            return
        }
        
        synchronized(self.updateMutex) {
            DSLogger.log("CoinJoin updateState: \(mode), \(timeSkew)s, \(hasAnonymizableBalance), \(networkStatus), synced: \(SyncingActivityMonitor.shared.state == .syncDone)")
            
            self.networkStatus = networkStatus
            self.hasAnonymizableBalance = hasAnonymizableBalance
            self.currentMode = mode
            self.timeSkew = timeSkew
            
            if mode == .none || !isInsideTimeSkewBounds(timeSkew: timeSkew) || DWGlobalOptions.sharedInstance().isResyncingWallet {
                updateMixingState(state: self.mixingState == .mixing || self.mixingState == .finishing ? .finishing : .finished)
            } else {
                configureMixing(mode: mode)
                
                if hasAnonymizableBalance {
                    if networkStatus == .online && SyncingActivityMonitor.shared.state == .syncDone {
                        updateMixingState(state: .mixing)
                    } else {
                        updateMixingState(state: .paused)
                    }
                } else {
                    updateMixingState(state: .finished)
                }
            }
            
            updateProgress()
        }
    }
    
    private func updateMixingState(state: MixingStatus) {
        synchronized(self.updateMixingStateMutex) {
            if self.mixingState == state {
                return
            }
            
            let previousMixingStatus = self.mixingState
            DSLogger.log("CoinJoin: \(previousMixingStatus) -> \(state)")
            self.mixingState = state

            if state == .mixing && previousMixingStatus != .mixing {
                // start mixing
                prepareMixing()
                Task {
                    await startMixing()
                }
            } else if state == .finishing && previousMixingStatus != .finishing {
                initiateShutdown()
            } else if previousMixingStatus == .mixing && state != .mixing {
                // finish mixing
                stopMixing()
            }
        }
    }
    
    private func updateTimeSkewInternal(timeSkew: TimeInterval) {
        let chain = DWEnvironment.sharedInstance().currentChain
        updateState(mode: self.currentMode,
                    timeSkew: timeSkew,
                    hasAnonymizableBalance: self.hasAnonymizableBalance,
                    networkStatus: self.networkStatus,
                    chain: chain)
    }
    
    private func getCurrentTimeSkew() async -> TimeInterval {
        do {
            return try await TimeUtils.getTimeSkew()
        } catch {
            DSLogger.log("[SW] CoinJoin: getTimeSkew problem: \(error)")
            return 0.0
        }
    }
    
    private func restoreMode() {
        DSLogger.log("[SW] CoinJoin: restoreMode, self.currentMode: \(self.currentMode)")
        
        self.stopMixing()
        self.coinJoinManager = nil
        self.hasAnonymizableBalance = false
        Task {
            await updateMode(mode: self.currentMode, force: true)
            self.updateTimeSkewInternal(timeSkew: await getCurrentTimeSkew())
        }
    }

    private func isInsideTimeSkewBounds(timeSkew: TimeInterval) -> Bool {
        if timeSkew > 0 {
            return timeSkew < kMaxAllowedAheadTimeskew
        } else {
            return (-timeSkew) < kMaxAllowedBehindTimeskew
        }
    }
    
    private func recheckCurrentChain() -> Bool {
        let chain = DWEnvironment.sharedInstance().currentChain
        
        if self.workingChain != chain {
            DSLogger.log("[SW] CoinJoin: reset chain after recheck to type \(chain.name)")
            self.workingChain = chain
            restoreMode()
            return false
        }
        
        return true
    }
    
    private func configureObservers() {
        self.removeObservers()
        
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let balance = DWEnvironment.sharedInstance().currentAccount.balance
                
                if self.savedBalance != balance {
                    Task {
                        await self.updateBalance(balance: balance)
                    }
                }
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Time has changed, handle the change here
                DSLogger.log("[SW] CoinJoin: Time or Time Zone changed")
                Task {
                    self.updateTimeSkewInternal(timeSkew: await self.getCurrentTimeSkew())
                }
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: NSNotification.Name.DWWillWipeWallet)
            .sink { _ in
                UserDefaults.standard.set(CoinJoinMode.none.rawValue, forKey: kCoinJoinMainnetMode)
                UserDefaults.standard.set(CoinJoinMode.none.rawValue, forKey: kCoinJoinTestnetMode)
            }
            .store(in: &cancellableBag)
        
        SyncingActivityMonitor.shared.add(observer: self)
    }
    
    private func updateNetworkState(newState: NetworkStatus) {
        self.networkStatus = newState
        self.updateState(mode: mode, timeSkew: timeSkew, hasAnonymizableBalance: self.hasAnonymizableBalance, networkStatus: self.networkStatus, chain: DWEnvironment.sharedInstance().currentChain)
    }
    
    private func removeObservers() {
        cancellableBag.forEach { $0.cancel() }
        SyncingActivityMonitor.shared.remove(observer: self)
    }
    
    private func synchronized(_ lock: NSLock, closure: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        closure()
    }
}

extension CoinJoinService: DSCoinJoinManagerDelegate {
    func sessionStarted(withId baseId: Int32, clientSessionId clientId: UInt256, denomination denom: UInt32, poolState state: dash_spv_coinjoin_messages_pool_state_PoolState, poolMessage message: dash_spv_coinjoin_messages_pool_message_PoolMessage, poolStatus status: dash_spv_coinjoin_messages_pool_status_PoolStatus, ipAddress address: UInt128, isJoined joined: Bool) {
        
    }
    
    func sessionComplete(withId baseId: Int32, clientSessionId clientId: UInt256, denomination denom: UInt32, poolState state: dash_spv_coinjoin_messages_pool_state_PoolState, poolMessage message: dash_spv_coinjoin_messages_pool_message_PoolMessage, poolStatus status: dash_spv_coinjoin_messages_pool_status_PoolStatus, ipAddress address: UInt128, isJoined joined: Bool) {
        
    }
    func mixingStarted() { }
    
    func mixingComplete(_ withError: Bool, errorStatus: UnsafeMutablePointer<dash_spv_coinjoin_messages_pool_status_PoolStatus>, isInterrupted: Bool) {
        self.coinJoinManager?.updateOptions(withEnabled: false)
        
        if isInterrupted {
            DSLogger.log("CoinJoin: Mixing Interrupted. \(progress)")
            updateMixingState(state: .notStarted)
            return
        }
        
        if withError {
            DSLogger.log("CoinJoin: Mixing Error. status: \(errorStatus), progress: \(progress)")
        } else {
            DSLogger.log("CoinJoin: Mixing Complete. status: \(errorStatus), \(progress)")
        }

        self.updateMixingState(state: withError && !dash_spv_coinjoin_messages_pool_status_PoolStatus_is_err_not_enough_funds(errorStatus) ? .error : .finished)
    }
    func transactionProcessed(withId txId: UInt256, type: UnsafeMutablePointer<dash_spv_coinjoin_models_coinjoin_tx_type_CoinJoinTransactionType>) {
        self.updateProgress()
    }
}

extension CoinJoinService: SyncingActivityMonitorObserver {
    func syncingActivityMonitorProgressDidChange(_ progress: Double) { }
    
    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        if state != currentSyncState {
            currentSyncState = state
            self.updateState(
                mode: self.currentMode,
                timeSkew: self.timeSkew,
                hasAnonymizableBalance: self.hasAnonymizableBalance,
                networkStatus: self.networkStatus,
                chain: DWEnvironment.sharedInstance().currentChain
            )
        } else {
            Task {
                let balance = DWEnvironment.sharedInstance().currentAccount.balance
                await self.updateBalance(balance: balance)
            }
        }
    }
}
