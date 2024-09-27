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
    case finished
    case error
    
    var isInProgress: Bool {
        get {
            return self == .mixing || self == .paused || self == .error
        }
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
            case .finished:
                NSLocalizedString("Fully mixed", comment: "CoinJoin")
            case .error:
                NSLocalizedString("Error ·", comment: "CoinJoin")
            }
        }
    }
}

enum CoinJoinMode: Int {
    case none
    case intermediate
    case advanced
}

private let kDefaultMultisession = false // for stability, need to investigate
private let kDefaultRounds: Int32 = 4
private let kDefaultSessions: Int32 = 6
private let kDefaultDenominationGoal: Int32 = 50
private let kDefaultDenominationHardcap: Int32 = 300
private let kCoinJoinMainnetMode = "coinJoinModeMainnetKey"
private let kCoinJoinTestnetMode = "coinJoinModeTestnetKey"

class CoinJoinService: NSObject {
    static let shared: CoinJoinService = {
        return CoinJoinService()
    }()
    
    private var permanentBag = Set<AnyCancellable>()
    private var cancellableBag = Set<AnyCancellable>()
    private let updateMutex = NSLock()
    private let updateMixingStateMutex = NSLock()
    private var coinJoinManager: DSCoinJoinManager? = nil
    private var hasAnonymizableBalance: Bool = false
    private var networkStatus: NetworkStatus = .online
    
    private var chainModeKey: String {
        get {
            DWEnvironment.sharedInstance().currentChain.isMainnet() ? kCoinJoinMainnetMode : kCoinJoinTestnetMode
        }
    }
    
    private var savedMode: Int {
        get {
            let key = chainModeKey
            return UserDefaults.standard.integer(forKey: key)
        }
        set(value) { UserDefaults.standard.set(value, forKey: chainModeKey) }
    }
    
    @Published private(set) var mode: CoinJoinMode = .none {
        didSet {
            savedMode = mode.rawValue
        }
    }
    
    @Published var mixingState: MixingStatus = .notStarted
    @Published private(set) var progress = CoinJoinProgress(progress: 0.0, totalBalance: 0, coinJoinBalance: 0)
    @Published private(set) var activeSessions: Int = 0
    
    override init() {
        super.init()
        
        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .sink { [weak self] _ in
                self?.coinJoinManager = nil
                self?.restoreMode()
            }
            .store(in: &permanentBag)
        
        restoreMode()
    }
    
    func updateMode(mode: CoinJoinMode) {
        self.coinJoinManager?.updateOptions(withEnabled: mode != .none)
        let account = DWEnvironment.sharedInstance().currentAccount
        let balance = account.balance
        
        if mode != .none && self.mode == .none {
            configureMixing(amount: balance)
            configureObservers()
        } else if mode == .none {
            cancellableBag.removeAll()
        }
        
        updateBalance(balance: balance)
        // TODO: timeskew
        updateState(balance: balance, mode: mode, timeSkew: TimeInterval(0), hasAnonymizableBalance: self.hasAnonymizableBalance, networkStatus: self.networkStatus, chain: DWEnvironment.sharedInstance().currentChain)
    }
    
    private func prepareMixing() {
        guard let coinJoinManager = self.coinJoinManager ?? createCoinJoinManager() else { return }
     
        coinJoinManager.managerDelegate = self
        coinJoinManager.setStopOnNothingToDo(true)
        coinJoinManager.start()
    }
    
    private func startMixing() {
        guard let coinJoinManager = self.coinJoinManager else { return }
        
        if !coinJoinManager.startMixing() {
            print("[SW] CoinJoin: Mixing has been started already.")
        } else {
            coinJoinManager.refreshUnusedKeys()
            coinJoinManager.initMasternodeGroup()
            coinJoinManager.doAutomaticDenominating()
            
            DSLogger.log("[SW] CoinJoin: Mixing \(coinJoinManager.startMixing() ? "started successfully" : "start failed, will retry")") // TODO: failed statuses: \(coinJoinManager.statuses)
        }
    }
    
    private func configureMixing(amount: UInt64) {
        guard let coinJoinManager = self.coinJoinManager ?? createCoinJoinManager() else { return }
        
        let rounds: Int32
        switch mode {
        case .none:
            return
        case .intermediate:
            rounds = kDefaultRounds
        case .advanced:
            rounds = kDefaultRounds * 2
        }
        
        coinJoinManager.configureMixing(withAmount: amount, rounds: rounds, sessions: kDefaultSessions, withMultisession: kDefaultMultisession, denominationGoal: kDefaultDenominationGoal, denominationHardCap: kDefaultDenominationHardcap)
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
        self.coinJoinManager = DSCoinJoinManager.sharedInstance(for: DWEnvironment().currentChain)
        coinJoinManager?.managerDelegate = self
        return self.coinJoinManager
    }
    
    private func updateBalance(balance: UInt64) {
        guard let coinJoinManager = self.coinJoinManager else { return }
        
        coinJoinManager.updateOptions(withAmount: balance)
        DSLogger.log("[SW] CoinJoin: total balance: \(balance)")
        let canDenominate = coinJoinManager.doAutomaticDenominating(withDryRun: true)

        let coinJoinBalance = coinJoinManager.getBalance()
        DSLogger.log("[SW] CoinJoin: mixed balance: \(coinJoinBalance.anonymized)")

        let anonBalance = coinJoinManager.getAnonymizableBalance(withSkipDenominated: false, skipUnconfirmed: false)
        DSLogger.log("[SW] CoinJoin: anonymizable balance \(anonBalance)")

        let smallestDenomination = coinJoinManager.getSmallestDenomination()
        let hasPartiallyMixedCoins = (coinJoinBalance.denominatedTrusted - coinJoinBalance.anonymized) > 0
        let hasAnonymizableBalance = anonBalance > smallestDenomination
        let hasBalanceLeftToMix: Bool
        
        if hasPartiallyMixedCoins {
            hasBalanceLeftToMix = true
        } else if hasAnonymizableBalance && canDenominate {
            hasBalanceLeftToMix = true
        } else {
            hasBalanceLeftToMix = false
        }

        DSLogger.log("[SW] CoinJoin: can mix balance: \(hasBalanceLeftToMix) = balance: (\(anonBalance > smallestDenomination) && canDenominate: \(canDenominate)) || partially-mixed: \(hasPartiallyMixedCoins)")

        updateState(
            balance: balance,
            mode: self.mode,
            timeSkew: TimeInterval(0), // TODO
            hasAnonymizableBalance: hasBalanceLeftToMix,
            networkStatus: self.networkStatus,
            chain: DWEnvironment.sharedInstance().currentChain
        )
    }
    
    private func stopMixing() {
        self.coinJoinManager?.managerDelegate = nil
        self.coinJoinManager?.stop()
    }

    private func updateState(
        balance: UInt64,
        mode: CoinJoinMode,
        timeSkew: TimeInterval,
        hasAnonymizableBalance: Bool,
        networkStatus: NetworkStatus,
        chain: DSChain
    ) {
        synchronized(self.updateMutex) {
            DSLogger.log("[SW] CoinJoin: \(mode), \(timeSkew) ms, \(hasAnonymizableBalance), \(networkStatus), synced: \(chain.chainManager!.isSynced)")
            
            self.networkStatus = networkStatus
            self.hasAnonymizableBalance = hasAnonymizableBalance
            self.mode = mode
            //        self.timeSkew = timeSkew
            
            if mode == .none /*|| !isInsideTimeSkewBounds(timeSkew) || blockchainState.replaying*/ { // TODO
                updateMixingState(state: .notStarted)
            } else {
                configureMixing(amount: balance)
                
                if hasAnonymizableBalance {
                    if networkStatus == .online && chain.chainManager!.isSynced {
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
            let previousMixingStatus = self.mixingState
            DSLogger.log("[SW] CoinJoin: \(previousMixingStatus) -> \(state)")
            
            if previousMixingStatus == .paused && state != .paused {
                DSLogger.log("[SW] CoinJoin: moving from paused to \(state)")
            }
            
            self.mixingState = state

            if state == .mixing && previousMixingStatus != .mixing {
                // start mixing
                prepareMixing()
                startMixing()
            } else if previousMixingStatus == .mixing && state != .mixing {
                // finish mixing
                stopMixing()
            }
        }
    }
    
    private func restoreMode() {
        let mode = CoinJoinMode(rawValue: savedMode) ?? .none
        
        if mode != self.mode {
            updateMode(mode: mode)
        }
    }
    
    private func configureObservers() {
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in
                self?.updateBalance(balance:  DWEnvironment.sharedInstance().currentAccount.balance)
            }
            .store(in: &cancellableBag)
        
        NotificationCenter.default.publisher(for: NSNotification.Name.DSChainManagerSyncStateDidChange)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateState(
                    balance: DWEnvironment.sharedInstance().currentAccount.balance,
                    mode: self.mode,
                    timeSkew: TimeInterval(0), // TODO
                    hasAnonymizableBalance: self.hasAnonymizableBalance,
                    networkStatus: self.networkStatus,
                    chain: DWEnvironment.sharedInstance().currentChain
                )
            }
            .store(in: &cancellableBag)
    }
    
    private func synchronized(_ lock: NSLock, closure: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        closure()
    }
}

extension CoinJoinService: DSCoinJoinManagerDelegate {
    func sessionStarted(withId baseId: Int32, clientSessionId clientId: UInt256, denomination denom: UInt32, poolState state: PoolState, poolMessage message: PoolMessage, ipAddress address: UInt128, isJoined joined: Bool) {
        updateActiveSessions()
    }
    
    func sessionComplete(withId baseId: Int32, clientSessionId clientId: UInt256, denomination denom: UInt32, poolState state: PoolState, poolMessage message: PoolMessage, ipAddress address: UInt128, isJoined joined: Bool) {
        updateActiveSessions()
    }
    
    func mixingStarted() { }
    
    func mixingComplete(_ withError: Bool, isInterrupted: Bool) {
        if isInterrupted {
            DSLogger.log("[SW] CoinJoin: Mixing Interrupted. \(progress)")
            updateMixingState(state: .notStarted)
            return
        }
        
        if withError {
            DSLogger.log("[SW] CoinJoin: Mixing Error. \(progress)")
        } else {
            DSLogger.log("[SW] CoinJoin: Mixing Complete. \(progress)")
        }
        
        self.updateMixingState(state: withError ? .error : .finished) // TODO: paused?
    }
    
    func transactionProcessed(withId txId: UInt256, type: CoinJoinTransactionType) {
        self.updateProgress()
    }
    
    private func updateActiveSessions() {
        guard let coinJoinManager = self.coinJoinManager else { return }
        
        let activeSessions = coinJoinManager.getActiveSessionCount()
        self.activeSessions = Int(activeSessions)

        DSLogger.log("[SW] CoinJoin: Active sessions: \(activeSessions)")
    }
}

