//
//  SwiftDashSDKWalletRuntime.swift
//  DashWallet
//
//  Central owner of the SwiftDashSDK runtime lifecycle. Coordinates network
//  switching, host startup, wallet state clearing, and SPV coordinator
//  start/stop.
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
            performFullReset(lastError: "Key migration not complete; SwiftDashSDK runtime cannot start.")
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
                guard chain.hasAWallet else {
                    Self.logger.info("🧭 RUNTIME :: no wallet on \(network.rawValue, privacy: .public); leaving runtime stopped")
                    return
                }

                let startResult = waitForCoordinatorStart(for: network)
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

    private func performFullReset(lastError: String?, forWipe: Bool = false) {
        if forWipe {
            PlatformAddressSyncCoordinator.stopForWipe()
        } else {
            PlatformAddressSyncCoordinator.stop()
        }
        waitForCoordinatorStop(lastError: lastError)
        SwiftDashSDKWalletState.shared.clearAllState()

        // Tear down the shared `PlatformWalletManager` last. Both BLAST and
        // Core SPV consume `SwiftDashSDKHost.shared`; releasing the FFI
        // handle while either tokio task is still running would be a
        // use-after-free. By the time we get here, both have been stopped
        // (BLAST via `PlatformAddressSyncCoordinator.stop*` above, Core SPV
        // via `waitForCoordinatorStop`).
        waitForHostStop()
    }

    private func waitForSeedMigratorIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.seedMigratorDoneKey) != nil {
            return true
        }

        let deadline = Date().addingTimeInterval(Self.seedMigratorWaitTimeout)
        while defaults.string(forKey: Self.seedMigratorDoneKey) == nil {
            if Self.seedMigratorDeferredKeys.contains(where: { defaults.object(forKey: $0) != nil }) {
                Self.logger.warning("🧭 RUNTIME :: key migrator deferred; continuing runtime refresh without migrated wallet material")
                return true
            }
            if Date() >= deadline {
                Self.logger.error("🧭 RUNTIME :: key migrator did not complete within \(Self.seedMigratorWaitTimeout, privacy: .public)s")
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

    private func waitForCoordinatorStart(for network: AppNetwork) -> Result<Void, Error> {
        let group = DispatchGroup()
        var startResult: Result<Void, Error> = .success(())

        group.enter()
        SwiftDashSDKSPVCoordinator.shared.start(for: network) { result in
            startResult = result
            group.leave()
        }
        group.wait()

        return startResult
    }

    private func waitForHostStop() {
        let group = DispatchGroup()
        group.enter()
        Task { @MainActor in
            SwiftDashSDKHost.shared.stop()
            group.leave()
        }
        group.wait()
    }

    private enum RefreshTrigger: String {
        case startIfReady
        case networkDidChange
        case walletMaterialChanged
    }

    enum RuntimeError: LocalizedError {
        case unsupportedCurrentNetwork(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedCurrentNetwork(let name):
                return "SwiftDashSDK runtime does not support \(name)"
            }
        }
    }
}
