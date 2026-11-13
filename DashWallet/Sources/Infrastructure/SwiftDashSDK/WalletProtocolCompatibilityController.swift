import Combine
import Foundation
import SwiftDashSDK

@MainActor
protocol WalletProtocolCompatibilityClient {
    func queryEpoch() async throws
    func protocolVersionInfo() throws -> ProtocolVersionInfo
}

/// An advisory observation owned by the host. No operation depends on this task.
@MainActor
final class WalletProtocolCompatibilityController: ObservableObject {
    @Published private(set) var snapshot: ProtocolVersionInfo?
    private(set) var runtimeID: UUID?
    private var client: (any WalletProtocolCompatibilityClient)?
    private var network: String?
    private var pending: Task<Void, Never>?
    private var foregroundSubscription: AnyCancellable?
    private let log: (String) -> Void

    init(
        foregroundNotification: Notification.Name,
        notificationCenter: NotificationCenter = .default,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.log = log
        // Only the host-supplied willEnterForeground event. Dismissing Face ID
        // emits didBecomeActive, which must not start another network query.
        foregroundSubscription = notificationCenter.publisher(for: foregroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
    }

    @discardableResult
    func attach(client: any WalletProtocolCompatibilityClient, network: String) -> Task<Void, Never> {
        detach()
        runtimeID = UUID()
        self.client = client
        self.network = network
        return refresh()
    }

    func detach() {
        pending?.cancel()
        pending = nil
        client = nil
        runtimeID = nil
        network = nil
        snapshot = nil
    }

    @discardableResult
    func refresh() -> Task<Void, Never> {
        if let pending { return pending }
        guard let client, let runtimeID, let network else { return Task {} }
        let task = Task { [weak self] in
            let started = Date()
            var outcome = "success"
            do { try await client.queryEpoch() }
            catch { outcome = "query failed: \(error)" }
            // The SDK may retain a verified observation even if this query
            // failed. An error must not erase an earlier warning.
            let observation = Result { try client.protocolVersionInfo() }
            guard let self, self.runtimeID == runtimeID else { return }
            self.pending = nil
            switch observation {
            case .success(let info): self.snapshot = info
            case .failure(let error): outcome += "; snapshot failed: \(error)"
            }
            self.log("Protocol version network=\(network) runtime=\(runtimeID) elapsed=\(Date().timeIntervalSince(started)) outcome=\(outcome) info=\(String(describing: self.snapshot))")
        }
        pending = task
        return task
    }
}
