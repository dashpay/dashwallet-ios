//
//  SwiftDashSDKWalletRuntime.swift
//  DashWallet
//
//  Central owner of the SwiftDashSDK runtime lifecycle. Coordinates network
//  switching, host startup, wallet state clearing, and SPV coordinator
//  start/stop.
//
//  Lifecycle shape: every Obj-C / Swift entrypoint enqueues a single async
//  operation onto an internal task chain that serializes lifecycle work
//  end-to-end. The two real operations are `refresh(trigger:)` and
//  `fullReset(lastError:forWipe:)`, both `@MainActor`, both awaitable —
//  no `DispatchGroup`, no `Thread.sleep`, no fire-and-forget Tasks
//  inside lifecycle work. Stop order is BLAST → SPV → wallet state →
//  host; start order is host (via SPV) → SPV → BLAST.
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKWalletRuntime)
@MainActor
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

    static let shared = SwiftDashSDKWalletRuntime()

    private var observerToken: NSObjectProtocol?
    private var currentLifecycleTask: Task<Void, Never>?
    private var currentNetwork: Network?

    private override init() {
        super.init()
    }

    // MARK: - Obj-C / Swift entrypoints
    //
    // All public entrypoints are fire-and-forget at the caller boundary —
    // they enqueue a single op onto the serial task chain and return.

    @objc(startIfReady)
    nonisolated static func startIfReady() {
        Task { @MainActor in
            shared.enqueueRefresh(trigger: .startIfReady)
        }
    }

    @objc(stop)
    nonisolated static func stop() {
        Task { @MainActor in
            shared.enqueueFullReset(lastError: nil, forWipe: false)
        }
    }

    @objc(startObservingNetworkChanges)
    nonisolated static func startObservingNetworkChanges() {
        Task { @MainActor in
            shared.installNetworkObserver()
        }
    }

    @objc(handleWalletMaterialChanged)
    nonisolated static func handleWalletMaterialChanged() {
        Task { @MainActor in
            shared.enqueueRefresh(trigger: .walletMaterialChanged)
        }
    }

    @objc(handleWalletWiped)
    nonisolated static func handleWalletWiped() {
        Task { @MainActor in
            shared.enqueueFullReset(lastError: nil, forWipe: true)
        }
    }

    // MARK: - Serial lifecycle pipeline

    /// Append a lifecycle operation to the serial task chain. Every new op
    /// awaits the previous task before running, so two callers in quick
    /// succession (e.g. `stop()` then `startIfReady()` from the diagnostic
    /// Restart button) are processed strictly in order.
    private func enqueue(_ op: @escaping @MainActor () async -> Void) {
        let previous = currentLifecycleTask
        currentLifecycleTask = Task { @MainActor in
            await previous?.value
            await op()
        }
    }

    private func enqueueRefresh(trigger: RefreshTrigger) {
        enqueue { [weak self] in
            await self?.refresh(trigger: trigger)
        }
    }

    private func enqueueFullReset(lastError: String?, forWipe: Bool) {
        enqueue { [weak self] in
            await self?.fullReset(lastError: lastError, forWipe: forWipe)
        }
    }

    // MARK: - Core lifecycle

    private func refresh(trigger: RefreshTrigger) async {
        Self.logger.info("🧭 RUNTIME :: refreshing runtime for \(trigger.rawValue, privacy: .public)")

        guard await waitForSeedMigratorIfNeeded() else {
            await fullReset(lastError: "Key migration not complete; SwiftDashSDK runtime cannot start.", forWipe: false)
            return
        }

        switch resolveCurrentNetwork() {
        case .failure(let error):
            await fullReset(lastError: error.localizedDescription, forWipe: false)
        case .success(let network):
            if shouldSkipRefresh(for: network, trigger: trigger) {
                Self.logger.info("🧭 RUNTIME :: refresh is already satisfied for \(network.rawValue, privacy: .public)")
                return
            }

            await fullReset(lastError: nil, forWipe: false)

            guard DWEnvironment.sharedInstance().currentChain.hasAWallet else {
                Self.logger.info("🧭 RUNTIME :: no wallet on \(network.rawValue, privacy: .public); leaving runtime stopped")
                return
            }

            do {
                try await SwiftDashSDKSPVCoordinator.shared.startAsync(for: network)
                await PlatformAddressSyncCoordinator.shared.startAsync(for: network)
                currentNetwork = network
            } catch {
                Self.logger.error("🧭 RUNTIME :: start failed: \(String(describing: error), privacy: .public)")
                await fullReset(lastError: error.localizedDescription, forWipe: false)
            }
        }
    }

    /// Deterministic teardown: BLAST → SPV → wallet state → host.
    /// Both BLAST and Core SPV consume `SwiftDashSDKHost.shared`; releasing
    /// the FFI handle while either tokio task is still running would be a
    /// use-after-free, so the host stop happens strictly after both
    /// coordinators have settled.
    private func fullReset(lastError: String?, forWipe: Bool) async {
        if forWipe {
            await PlatformAddressSyncCoordinator.stopForWipeAsync()
        } else {
            await PlatformAddressSyncCoordinator.shared.stopAsync()
        }
        await SwiftDashSDKSPVCoordinator.shared.stopAsync(lastError: lastError)
        SwiftDashSDKWalletState.shared.clearAllState()
        SwiftDashSDKHost.shared.stop()
        currentNetwork = nil
    }

    // MARK: - Helpers

    private func shouldSkipRefresh(for network: Network, trigger: RefreshTrigger) -> Bool {
        switch trigger {
        case .walletMaterialChanged:
            return false
        case .startIfReady, .networkDidChange:
            return currentNetwork == network
        }
    }

    private func resolveCurrentNetwork() -> Result<Network, RuntimeError> {
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

    private func waitForSeedMigratorIfNeeded() async -> Bool {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.seedMigratorDoneKey) != nil {
            return true
        }

        let deadline = Date().addingTimeInterval(Self.seedMigratorWaitTimeout)
        let sleepNanos = UInt64(Self.seedMigratorPollInterval * 1_000_000_000)
        while defaults.string(forKey: Self.seedMigratorDoneKey) == nil {
            if Self.seedMigratorDeferredKeys.contains(where: { defaults.object(forKey: $0) != nil }) {
                Self.logger.warning("🧭 RUNTIME :: key migrator deferred; continuing runtime refresh without migrated wallet material")
                return true
            }
            if Date() >= deadline {
                Self.logger.error("🧭 RUNTIME :: key migrator did not complete within \(Self.seedMigratorWaitTimeout, privacy: .public)s")
                return false
            }
            try? await Task.sleep(nanoseconds: sleepNanos)
        }

        return true
    }

    private func installNetworkObserver() {
        guard observerToken == nil else { return }

        observerToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.DWCurrentNetworkDidChange,
            object: nil,
            queue: nil
        ) { _ in
            Task { @MainActor in
                Self.shared.enqueueRefresh(trigger: .networkDidChange)
            }
        }

        Self.logger.info("🧭 RUNTIME :: registered DWCurrentNetworkDidChangeNotification observer")
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
