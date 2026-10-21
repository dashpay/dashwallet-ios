import Combine
import Foundation

/// Presentation snapshot only. Rust owns proof verification and write admission.
struct WalletProtocolCompatibility: Equatable, Sendable {
    enum Status: String, Sendable {
        case unavailable, checking, supported, unsupported
    }

    let generation: UInt64
    let status: Status
    let verifiedVersion: UInt32?
    let effectiveVersion: UInt32?
    let maximumSupportedVersion: UInt32?

    static func blockingMessage(for snapshot: Self?) -> String? {
        switch snapshot?.status {
        case .supported: return nil
        case .unsupported:
            return NSLocalizedString("This network requires a newer version of Dash Wallet.", comment: "Protocol compatibility")
        case .checking:
            return NSLocalizedString("Checking Platform compatibility…", comment: "Protocol compatibility")
        case .unavailable, nil:
            return NSLocalizedString("Platform compatibility could not be checked. Try again before continuing.", comment: "Protocol compatibility")
        }
    }
}

protocol WalletProtocolCompatibilityClient: Sendable {
    func beginCheck() throws -> UInt64
    func refresh(generation: UInt64) throws -> WalletProtocolCompatibility
    func snapshot() throws -> WalletProtocolCompatibility
}

/// Owned by the SDK host, with a separate binding for every runtime incarnation.
/// A failed compatibility check does not fail opening the local Core wallet.
@MainActor
final class WalletProtocolCompatibilityController: ObservableObject {
    typealias Execute = @Sendable (any WalletProtocolCompatibilityClient, UInt64) async throws -> WalletProtocolCompatibility

    @Published private(set) var snapshot: WalletProtocolCompatibility?
    @Published private(set) var network: String?
    @Published private(set) var isRuntimeReady = false
    private(set) var runtimeID: UUID?
    private var client: (any WalletProtocolCompatibilityClient)?
    private var pending: Task<Void, Never>?
    private var requestID: UUID?
    private let execute: Execute
    private let log: (String) -> Void

    init(
        execute: @escaping Execute = { client, generation in
            try await WalletProtocolCompatibilityController.executeOffMain(client: client, generation: generation)
        },
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.execute = execute
        self.log = log
    }

    @discardableResult
    func attach(
        client: any WalletProtocolCompatibilityClient, network: String, runtimeID: UUID
    ) -> Task<Void, Never> {
        detach()
        self.client = client
        self.network = network
        self.runtimeID = runtimeID
        return refresh()
    }

    func detach() {
        // Invalidate Rust admission synchronously, including outstanding handles.
        if let client { _ = try? client.beginCheck() }
        pending?.cancel()
        pending = nil
        requestID = nil
        isRuntimeReady = false
        client = nil
        snapshot = nil
        network = nil
        runtimeID = nil
    }

    /// The host publishes its wallet/SDK only after local setup has finished.
    func markRuntimeReady(runtimeID: UUID) {
        guard self.runtimeID == runtimeID else { return }
        isRuntimeReady = true
    }

    /// Called on actual background → foreground, never on didBecomeActive/Face ID.
    @discardableResult
    func willEnterForeground() -> Task<Void, Never> {
        // A native result may have completed while suspended, before its Swift
        // continuation ran. Every real foreground needs a fresh admission token.
        pending?.cancel()
        pending = nil
        return refresh()
    }

    /// Repeated manual requests share the current attempt.
    /// `beginCheck` closes the native write gate before any asynchronous dispatch.
    @discardableResult
    func refresh() -> Task<Void, Never> {
        if let pending { return pending }
        guard let client, let runtimeID, let network else { return Task {} }
        let requestID = UUID()
        self.requestID = requestID
        let started = Date()
        let generation: UInt64
        do {
            generation = try client.beginCheck()
            sample()
        } catch {
            recordUnavailable()
            log("PROTOCOL network=\(network) autodetect=true begin error=\(error)")
            return Task {}
        }
        let execute = self.execute
        let task = Task { [weak self] in
            do {
                let result = try await execute(client, generation)
                guard let self, self.runtimeID == runtimeID,
                      self.requestID == requestID, !Task.isCancelled else { return }
                defer { self.pending = nil }
                guard result.generation == generation else {
                    self.sample()
                    return
                }
                // A verified background read may have advanced the native
                // state after refresh returned. Never overwrite it with a stale DTO.
                self.sample()
                let current = self.snapshot ?? result
                self.log("PROTOCOL network=\(network) autodetect=true generation=\(generation) duration_ms=\(Int(Date().timeIntervalSince(started) * 1000)) status=\(current.status.rawValue) maximum_supported_version=\(current.maximumSupportedVersion.map(String.init) ?? "none") sdk_version=\(current.effectiveVersion.map(String.init) ?? "none") verified_version=\(current.verifiedVersion.map(String.init) ?? "none")")
            } catch {
                guard let self, self.runtimeID == runtimeID,
                      self.requestID == requestID, !Task.isCancelled else { return }
                self.pending = nil
                self.recordUnavailable()
                self.log("PROTOCOL network=\(network) autodetect=true generation=\(generation) duration_ms=\(Int(Date().timeIntervalSince(started) * 1000)) error=\(error)")
            }
        }
        pending = task
        return task
    }

    /// A cheap local read also observes incompatibility learned by ordinary SDK reads.
    func sample() {
        guard let client else { return }
        do {
            let current = try client.snapshot()
            if snapshot != current { snapshot = current }
        } catch {
            recordUnavailable()
        }
    }

    private func recordUnavailable() {
        // A bridge failure must never erase already authenticated incompatibility.
        guard snapshot?.status != .unsupported else { return }
        snapshot = WalletProtocolCompatibility(
            generation: snapshot?.generation ?? 0, status: .unavailable,
            verifiedVersion: snapshot?.verifiedVersion,
            effectiveVersion: snapshot?.effectiveVersion,
            maximumSupportedVersion: snapshot?.maximumSupportedVersion)
    }

    nonisolated private static let refreshQueue = DispatchQueue(
        label: "org.dashfoundation.dash.protocol-compatibility", qos: .userInitiated,
        attributes: .concurrent)

    nonisolated static func executeOffMain(
        client: any WalletProtocolCompatibilityClient, generation: UInt64
    ) async throws -> WalletProtocolCompatibility {
        try await withCheckedThrowingContinuation { continuation in
            refreshQueue.async {
                continuation.resume(with: Result { try client.refresh(generation: generation) })
            }
        }
    }
}
