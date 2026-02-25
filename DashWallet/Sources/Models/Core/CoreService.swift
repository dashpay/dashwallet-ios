//
//  CoreService.swift
//  dashwallet
//
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
import SwiftDashSDK

// MARK: - CoreSyncState

/// Sync state for CoreService, bridged to ObjC
@objc enum CoreSyncState: Int {
    case unknown = 0
    case initializing = 1
    case waitingForConnections = 2
    case syncing = 3
    case synced = 4
    case error = 5
    case idle = 6

    init(spvState: SPVSyncState) {
        switch spvState {
        case .initializing: self = .initializing
        case .waitingForConnections: self = .waitingForConnections
        case .waitForEvents: self = .waitingForConnections
        case .syncing: self = .syncing
        case .synced: self = .synced
        case .error: self = .error
        case .idle: self = .idle
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}

// MARK: - CoreWalletTransaction

/// ObjC-compatible wrapper around SwiftDashSDK WalletTransaction
@objc class CoreWalletTransaction: NSObject {
    @objc let txid: String
    @objc let netAmount: Int64
    @objc let height: UInt32
    @objc let blockHash: String?
    @objc let timestamp: UInt64
    @objc let fee: UInt64
    @objc let confirmations: Int
    /// "received", "sent", or "self"
    @objc let type: String
    @objc let isOurs: Bool
    @objc let date: Date
    @objc let isConfirmed: Bool

    init(walletTransaction tx: WalletTransaction) {
        self.txid = tx.txid
        self.netAmount = tx.netAmount
        self.height = tx.height ?? 0
        self.blockHash = tx.blockHash
        self.timestamp = tx.timestamp
        self.fee = tx.fee ?? 0
        self.confirmations = tx.confirmations
        self.type = tx.type
        self.isOurs = tx.isOurs
        self.date = tx.date
        self.isConfirmed = tx.isConfirmed
        super.init()
    }
}

// MARK: - CoreServiceError

@objc enum CoreServiceError: Int, Error {
    case notInitialized
    case walletNotFound
}

// MARK: - CoreService

/// Central L1 service wrapping SwiftDashSDK SPVClient for blockchain operations.
/// Posts DashSync-compatible notifications for backward compatibility during dual-engine transition.
@objc class CoreService: NSObject {

    // MARK: - Singleton

    @objc static let shared = CoreService()

    // MARK: - SDK Components

    private var spvClient: SPVClient?
    private var walletManager: WalletManager?
    private var currentWalletId: Data?

    // MARK: - State

    @objc private(set) var isInitialized: Bool = false

    @objc dynamic private(set) var syncProgress: Double = 0
    @objc dynamic private(set) var syncState: CoreSyncState = .unknown
    @objc dynamic private(set) var connectedPeers: Int = 0
    @objc dynamic private(set) var bestPeerHeight: UInt32 = 0

    // MARK: - Balance

    @objc dynamic private(set) var balanceConfirmed: UInt64 = 0
    @objc dynamic private(set) var balanceUnconfirmed: UInt64 = 0
    @objc dynamic private(set) var balanceImmature: UInt64 = 0
    @objc dynamic private(set) var balanceLocked: UInt64 = 0
    @objc dynamic private(set) var balanceTotal: UInt64 = 0

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Initialize SPV client and wallet from mnemonic.
    /// Call startSync() separately to begin blockchain synchronization.
    @objc func initialize(mnemonic: String, isTestnet: Bool, completion: @escaping (Bool, Error?) -> Void) {
        initializeInternal(mnemonic: mnemonic, isTestnet: isTestnet, completion: completion)
    }

    /// Initialize SPV client using an existing wallet (no mnemonic needed).
    /// Returns false if no wallet has been created yet (call initialize(mnemonic:...) first).
    @objc func initializeIfWalletExists(isTestnet: Bool, completion: @escaping (Bool, Error?) -> Void) {
        initializeInternal(mnemonic: nil, isTestnet: isTestnet, completion: completion)
    }

    private func initializeInternal(mnemonic: String?, isTestnet: Bool, completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                let network: DashSDKNetwork = isTestnet
                    ? DashSDKNetwork(rawValue: 1)
                    : DashSDKNetwork(rawValue: 0)

                let dataDir = Self.spvDataDirectory(isTestnet: isTestnet)

                let client = try SPVClient(network: network, dataDir: dataDir, startHeight: 0)
                self.spvClient = client

                // Event handlers before wallet setup
                client.setProgressUpdateEventHandler(self)
                client.setSyncEventsHandler(self)
                client.setNetworkEventsHandler(self)
                client.setWalletEventsHandler(self)

                // Wallet
                let wm = try client.getWalletManager()
                self.walletManager = wm

                var existingIds: [Data] = []
                do {
                    existingIds = try wm.getWalletIds()
                } catch {
                    // getWalletIds() throws when no wallet database exists yet — treat as empty
                }

                if let existingId = existingIds.first {
                    self.currentWalletId = existingId
                } else if let mnemonic = mnemonic {
                    let walletId = try wm.addWallet(mnemonic: mnemonic)
                    self.currentWalletId = walletId
                } else {
                    self.spvClient = nil
                    self.walletManager = nil
                    await MainActor.run {
                        completion(false, nil)
                    }
                    return
                }

                self.isInitialized = true

                // Read initial balance
                self.refreshBalance()

                await MainActor.run {
                    completion(true, nil)
                }
            } catch {
                await MainActor.run {
                    completion(false, error)
                }
            }
        }
    }

    /// Shutdown and release all resources
    @objc func shutdown() {
        stopSync()
        spvClient?.clearProgressUpdateEventHandler()
        spvClient?.clearSyncEventsHandler()
        spvClient?.clearNetworkEventsHandler()
        spvClient?.clearWalletEventsHandler()
        spvClient?.destroy()
        spvClient = nil
        walletManager = nil
        currentWalletId = nil
        isInitialized = false
        syncState = .unknown
        syncProgress = 0
        connectedPeers = 0
        bestPeerHeight = 0
        balanceConfirmed = 0
        balanceUnconfirmed = 0
        balanceImmature = 0
        balanceLocked = 0
        balanceTotal = 0
    }

    /// Start SPV blockchain synchronization
    @objc func startSync() {
        guard let client = spvClient else { return }

        Task {
            do {
                try await client.startSync()
            } catch {
                NSLog("[CoreService] startSync failed: %@", error.localizedDescription)
            }
        }
    }

    /// Stop SPV blockchain synchronization
    @objc func stopSync() {
        spvClient?.stopSync()
    }

    // MARK: - Address

    /// Get the next unused receive address
    @objc func getReceiveAddress() throws -> String {
        guard let wm = walletManager, let walletId = currentWalletId else {
            throw CoreServiceError.notInitialized
        }
        return try wm.getReceiveAddress(walletId: walletId)
    }

    /// Get the next unused change address
    @objc func getChangeAddress() throws -> String {
        guard let wm = walletManager, let walletId = currentWalletId else {
            throw CoreServiceError.notInitialized
        }
        return try wm.getChangeAddress(walletId: walletId)
    }

    // MARK: - Transactions

    /// Get all transactions for the primary BIP44 account
    @objc func getTransactions() throws -> [CoreWalletTransaction] {
        guard let wm = walletManager, let walletId = currentWalletId else {
            throw CoreServiceError.notInitialized
        }
        let collection = try wm.getManagedAccountCollection(walletId: walletId)
        guard let account = collection.getBIP44Account(at: 0) else {
            return []
        }
        let height = try wm.currentHeight()
        let txs = try account.getTransactions(currentHeight: height)
        return txs.map { CoreWalletTransaction(walletTransaction: $0) }
    }

    /// Current best block height known to the wallet
    @objc func currentBlockHeightAndReturnError(_ error: NSErrorPointer) -> UInt32 {
        guard let wm = walletManager else {
            error?.pointee = NSError(domain: "CoreService", code: CoreServiceError.notInitialized.rawValue)
            return 0
        }
        do {
            return try wm.currentHeight()
        } catch let err {
            error?.pointee = err as NSError
            return 0
        }
    }

    /// Detailed sync progress from SPVClient
    @objc func getSyncProgress() -> Double {
        return spvClient?.getSyncProgress().percentage ?? 0
    }

    // MARK: - Private Helpers

    private static func spvDataDirectory(isTestnet: Bool) -> String {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let subdir = isTestnet ? "SwiftDashSDK/testnet" : "SwiftDashSDK/mainnet"
        let path = (documentsPath as NSString).appendingPathComponent(subdir)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// Post a DashSync-compatible notification with the current chain in userInfo for backward compatibility.
    /// SyncingActivityMonitor and other observers filter by DSChainManagerNotificationChainKey.
    /// Safe to call from any thread (dispatches to main queue).
    private func postNotification(_ name: String) {
        DispatchQueue.main.async {
            let chain = DWEnvironment.sharedInstance().currentChain
            let userInfo: [String: Any] = ["DSChainManagerNotificationChainKey": chain as Any]
            NotificationCenter.default.post(
                name: Notification.Name(rawValue: name),
                object: nil,
                userInfo: userInfo
            )
        }
    }

    private func refreshBalance() {
        guard let wm = walletManager, let walletId = currentWalletId else { return }
        do {
            let balance = try wm.getWalletBalance(walletId: walletId)
            DispatchQueue.main.async {
                self.balanceConfirmed = balance.confirmed
                self.balanceUnconfirmed = balance.unconfirmed
                self.balanceTotal = balance.confirmed + balance.unconfirmed
            }
        } catch {
            NSLog("[CoreService] refreshBalance failed: %@", error.localizedDescription)
        }
    }
}

// MARK: - SPVProgressUpdateEventHandler

extension CoreService: SPVProgressUpdateEventHandler {
    func onProgressUpdate(_ progress: SPVSyncProgress) {
        DispatchQueue.main.async {
            self.syncProgress = progress.percentage
            self.syncState = CoreSyncState(spvState: progress.state)
        }
    }
}

// MARK: - SPVSyncEventsHandler

extension CoreService: SPVSyncEventsHandler {
    func onStart(_ manager: SPVSyncManager) {
        DispatchQueue.main.async {
            self.syncState = .syncing
        }
        postNotification("DSChainManagerSyncWillStartNotification")
    }

    func onComplete(_ headerTip: UInt32) {
        DispatchQueue.main.async {
            self.syncState = .synced
            self.syncProgress = 1.0
        }
        postNotification("DSChainManagerSyncFinishedNotification")
    }

    func onBlockHeadersStored(_ tipHeight: UInt32) {}
    func onBlockHeadersSyncCompleted(_ tipHeight: UInt32) {}
    func onFilterHeadersStored(_ startHeight: UInt32, _ endHeight: UInt32, _ tipHeight: UInt32) {}
    func onFilterHeadersSyncCompleted(_ tipHeight: UInt32) {}
    func onFilterStored(_ startHeight: UInt32, _ endHeight: UInt32) {}
    func onFilterSyncCompleted(_ tipHeight: UInt32) {}
    func onBlocksNeeded(_ height: UInt32, _ hash: Data, _ count: UInt32) {}
    func onBlocksProcessed(_ height: UInt32, _ hash: Data, _ newAddressCount: UInt32) {}
    func onMasternodeStateUpdated(_ height: UInt32) {}
    func onChainLockReceived(_ height: UInt32, _ hash: Data, _ signature: Data, _ validated: Bool) {}
    func onInstantLockReceived(_ txid: Data, _ instantLockData: Data, _ validated: Bool) {}

    func onSyncManagerError(_ manager: SPVSyncManager, _ errorMsg: String) {
        NSLog("[CoreService] sync error: %@", errorMsg)
        DispatchQueue.main.async {
            self.syncState = .error
        }
        postNotification("DSChainManagerSyncFailedNotification")
    }
}

// MARK: - SPVNetworkEventsHandler

extension CoreService: SPVNetworkEventsHandler {
    func onPeerConnected(_ address: String) {}
    func onPeerDisconnected(_ address: String) {}

    func onPeersUpdated(_ connectedCount: UInt32, _ bestHeight: UInt32) {
        DispatchQueue.main.async {
            self.connectedPeers = Int(connectedCount)
            self.bestPeerHeight = bestHeight
        }
        postNotification("DSPeerManagerConnectedPeersDidChangeNotification")
    }
}

// MARK: - SPVWalletEventsHandler

extension CoreService: SPVWalletEventsHandler {
    func onTransactionReceived(
        _ walletId: String,
        _ accountIndex: UInt32,
        _ txid: Data,
        _ amount: Int64,
        _ addresses: [String]
    ) {
        // Don't call refreshBalance() here — this callback runs on a Rust FFI thread
        // that holds a lock. Calling back into FFI (getWalletBalance) would deadlock/panic.
        // Balance will be updated via onBalanceUpdated() callback from the SDK.
        postNotification("DSTransactionManagerTransactionStatusDidChangeNotification")
    }

    func onBalanceUpdated(
        _ walletId: String,
        _ spendable: UInt64,
        _ unconfirmed: UInt64,
        _ immature: UInt64,
        _ locked: UInt64
    ) {
        DispatchQueue.main.async {
            self.balanceConfirmed = spendable
            self.balanceUnconfirmed = unconfirmed
            self.balanceImmature = immature
            self.balanceLocked = locked
            self.balanceTotal = spendable + unconfirmed
        }
        postNotification("DSWalletBalanceChangedNotification")
    }
}
