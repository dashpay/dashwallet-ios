//
//  SwiftDashSDKWalletRuntime.swift
//  DashWallet
//
//  Central owner of the SwiftDashSDK runtime lifecycle. Coordinates
//  descriptor readiness, network switching, provider invalidation, wallet
//  state clearing, and SPV coordinator start/stop.
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKWalletRuntime)
final class SwiftDashSDKWalletRuntime: NSObject {
    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-runtime")

    private static let seedMigratorDoneKey = "swiftSDKKeyMigration.v1.done"
    private static let seedMigratorDeferredKeys = [
        "swiftSDKKeyMigration.v1.deferredNoPIN",
        "swiftSDKKeyMigration.v1.deferredMultiWallet",
        "swiftSDKKeyMigration.v1.deferredUnknownChain",
    ]
    private static let seedMigratorWaitTimeout: TimeInterval = 30.0
    private static let seedMigratorPollInterval: TimeInterval = 0.1

    private static var observerToken: NSObjectProtocol?

    static let shared = SwiftDashSDKWalletRuntime()

    private let workQueue = DispatchQueue(
        label: "org.dashfoundation.dash.swift-sdk-wallet-runtime",
        qos: .userInitiated)
    private let runtimeWalletStore = SwiftDashSDKRuntimeWalletStore()
    private let descriptorFactory = SwiftDashSDKRuntimeDescriptorFactory()

    private override init() {
        super.init()
    }

    @objc(startIfReady)
    static func startIfReady() {
        shared.workQueue.async {
            shared.refreshRuntime(trigger: .startIfReady)
        }
    }

    @objc(stop)
    static func stop() {
        shared.workQueue.async {
            shared.performFullReset(lastError: nil)
        }
    }

    @objc(startObservingNetworkChanges)
    static func startObservingNetworkChanges() {
        guard observerToken == nil else { return }

        observerToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.DWCurrentNetworkDidChange,
            object: nil,
            queue: nil
        ) { _ in
            shared.workQueue.async {
                shared.refreshRuntime(trigger: .networkDidChange)
            }
        }

        Self.logger.info("🧭 RUNTIME :: registered DWCurrentNetworkDidChangeNotification observer")
    }

    @objc(handleWalletMaterialChanged)
    static func handleWalletMaterialChanged() {
        shared.workQueue.async {
            shared.refreshRuntime(trigger: .walletMaterialChanged)
        }
    }

    @objc(handleWalletWiped)
    static func handleWalletWiped() {
        shared.workQueue.async {
            shared.performFullReset(lastError: nil, forWipe: true)
        }
    }

    private func refreshRuntime(trigger: RefreshTrigger) {
        Self.logger.info("🧭 RUNTIME :: refreshing runtime for \(trigger.rawValue, privacy: .public)")

        guard waitForSeedMigratorIfNeeded() else {
            performFullReset(lastError: "Seed migration not complete; SwiftDashSDK runtime cannot start.")
            return
        }

        switch resolveCurrentNetwork() {
        case .failure(let error):
            performFullReset(lastError: error.localizedDescription)
            return
        case .success(let network):
            if shouldSkipRefresh(for: network, trigger: trigger) {
                Self.logger.info("🧭 RUNTIME :: refresh is already satisfied for \(network.rawValue, privacy: .public)")
                return
            }

            performFullReset(lastError: nil)

            let chain = DWEnvironment.sharedInstance().currentChain
            do {
                try ensureDescriptorIfNeeded(for: network, chainHasWallet: chain.hasAWallet)
                guard chain.hasAWallet else {
                    Self.logger.info("🧭 RUNTIME :: no wallet on \(network.rawValue, privacy: .public); leaving runtime stopped")
                    return
                }

                let wallet = try SwiftDashSDKWalletProvider.shared.getWallet(for: network)
                let startResult = waitForCoordinatorStart(with: wallet)
                if case .failure(let error) = startResult {
                    Self.logger.error("🧭 RUNTIME :: coordinator start failed: \(String(describing: error), privacy: .public)")
                }
                PlatformAddressSyncCoordinator.shared.start(for: network)
            } catch {
                Self.logger.error("🧭 RUNTIME :: refresh failed: \(String(describing: error), privacy: .public)")
                performFullReset(lastError: error.localizedDescription)
            }
        }
    }

    private func shouldSkipRefresh(for network: AppNetwork, trigger: RefreshTrigger) -> Bool {
        switch trigger {
        case .walletMaterialChanged:
            return false
        case .startIfReady, .networkDidChange:
            return SwiftDashSDKSPVCoordinator.shared.isRunning(for: network)
        }
    }

    private func ensureDescriptorIfNeeded(for network: AppNetwork, chainHasWallet: Bool) throws {
        if try runtimeWalletStore.exists(for: network) {
            return
        }

        guard chainHasWallet else {
            return
        }

        let storage = WalletStorage()
        let mnemonic: String
        do {
            mnemonic = try storage.retrieveMnemonic()
        } catch {
            throw RuntimeError.missingMnemonicForDescriptorBootstrap(network: network, underlying: error)
        }

        let descriptor = try descriptorFactory.makeDescriptor(
            mnemonic: mnemonic,
            network: network,
            isImported: true)
        try runtimeWalletStore.store(descriptor, for: network)

        let storedDescriptor = try runtimeWalletStore.retrieve(for: network)
        guard storedDescriptor == descriptor else {
            throw RuntimeError.runtimeDescriptorRoundTripMismatch(network: network)
        }

        Self.logger.info("🧭 RUNTIME :: bootstrapped missing descriptor for \(network.rawValue, privacy: .public)")
    }

    private func performFullReset(lastError: String?, forWipe: Bool = false) {
        if forWipe {
            PlatformAddressSyncCoordinator.stopForWipe()
        } else {
            PlatformAddressSyncCoordinator.stop()
        }
        waitForCoordinatorStop(lastError: lastError)
        SwiftDashSDKWalletProvider.shared.invalidate()
        SwiftDashSDKWalletState.shared.clearAllState()
    }

    private func waitForSeedMigratorIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.seedMigratorDoneKey) != nil {
            return true
        }

        let deadline = Date().addingTimeInterval(Self.seedMigratorWaitTimeout)
        while defaults.string(forKey: Self.seedMigratorDoneKey) == nil {
            if Self.seedMigratorDeferredKeys.contains(where: { defaults.object(forKey: $0) != nil }) {
                Self.logger.warning("🧭 RUNTIME :: seed migrator deferred; continuing runtime refresh without migrated wallet material")
                return true
            }
            if Date() >= deadline {
                Self.logger.error("🧭 RUNTIME :: seed migrator did not complete within \(Self.seedMigratorWaitTimeout, privacy: .public)s")
                return false
            }
            Thread.sleep(forTimeInterval: Self.seedMigratorPollInterval)
        }

        return true
    }

    private func resolveCurrentNetwork() -> Result<AppNetwork, RuntimeError> {
        let chain = DWEnvironment.sharedInstance().currentChain
        if chain.isMainnet() {
            return .success(.mainnet)
        }
        if chain.isTestnet() {
            return .success(.testnet)
        }

        let name = chain.name.isEmpty ? "unsupported network" : chain.name
        return .failure(.unsupportedCurrentNetwork(name))
    }

    private func waitForCoordinatorStop(lastError: String?) {
        let group = DispatchGroup()
        group.enter()
        SwiftDashSDKSPVCoordinator.shared.stop(lastError: lastError) {
            group.leave()
        }
        group.wait()
    }

    private func waitForCoordinatorStart(with wallet: HDWallet) -> Result<Void, Error> {
        let group = DispatchGroup()
        var startResult: Result<Void, Error> = .success(())

        group.enter()
        SwiftDashSDKSPVCoordinator.shared.start(with: wallet) { result in
            startResult = result
            group.leave()
        }
        group.wait()

        return startResult
    }

    private enum RefreshTrigger: String {
        case startIfReady
        case networkDidChange
        case walletMaterialChanged
    }

    enum RuntimeError: LocalizedError {
        case unsupportedCurrentNetwork(String)
        case missingMnemonicForDescriptorBootstrap(network: AppNetwork, underlying: Error)
        case runtimeDescriptorRoundTripMismatch(network: AppNetwork)

        var errorDescription: String? {
            switch self {
            case .unsupportedCurrentNetwork(let name):
                return "SwiftDashSDK runtime does not support \(name)"
            case .missingMnemonicForDescriptorBootstrap(let network, let underlying):
                return "Cannot bootstrap \(network.rawValue) runtime descriptor without mnemonic: \(underlying.localizedDescription)"
            case .runtimeDescriptorRoundTripMismatch(let network):
                return "Runtime descriptor round-trip mismatch for \(network.rawValue)"
            }
        }
    }
}
