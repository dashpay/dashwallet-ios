//
//  ConnectionsViewModel.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import Combine
import Foundation

struct ConnectionsScreenMessage: Identifiable, Equatable {
    enum Kind: String {
        case error
        case success
    }

    let kind: Kind
    let text: String

    var id: String {
        "\(kind.rawValue):\(text)"
    }

    var title: String {
        switch kind {
        case .error:
            return NSLocalizedString("Error", comment: "")
        case .success:
            return NSLocalizedString("Success", comment: "DashConnect")
        }
    }
}

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var connections: [DAppConnection] = []
    @Published private(set) var featureUnavailable: Bool
    @Published var pendingRequest: ConnectionRequest?
    @Published var isApproving = false
    @Published var isProcessingKeyRegistration = false
    @Published var message: ConnectionsScreenMessage?
    /// Failure of the last approve attempt, rendered **inside** the approve sheet.
    /// A screen-level `.alert` cannot appear over a presented sheet, so routing this
    /// through `message` would leave the user with no feedback at all.
    @Published var approveError: String?

    private let dataSource: any DashConnectDataSource
    private var pendingLoginRequest: DashKeyRequest?
    private var cancellables = Set<AnyCancellable>()

    /// Serializes inbound requests.
    ///
    /// A QR scan arrives one at a time, but a deep link does not: any installed
    /// app can open `dash-key:` / `dash-st:` whenever it likes, and each one used
    /// to start its own untracked task. `pendingLoginRequest` was published
    /// BEFORE the Platform metadata lookup that builds the sheet's contents, so
    /// a second request landing inside that await replaced it while the first
    /// went on to publish the sheet — the user then approved what B asked for
    /// while reading what A said, and the login credential was encrypted to B's
    /// ephemeral key. Every request now takes a generation, and only the newest
    /// one is allowed to publish anything.
    private var requestGeneration = 0

    /// Whether a request is mid-flight. A newer request may supersede one that
    /// is still resolving, but nothing may interrupt an approval or a key
    /// registration, which are already committing to the network.
    private var isResolvingRequest = false

    init(
        dataSource: (any DashConnectDataSource)? = nil,
        featureUnavailable: Bool? = nil
    ) {
        let computedFeatureUnavailable = featureUnavailable ?? !WalletEnvironment.isTestnet
        self.featureUnavailable = computedFeatureUnavailable
        self.dataSource = dataSource ?? Self.defaultDataSource(featureUnavailable: computedFeatureUnavailable)

        self.dataSource.connections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.connections = $0.sorted(by: { $0.updatedAt > $1.updatedAt })
            }
            .store(in: &cancellables)
    }

    func onQRScanned(_ content: String) {
        guard !featureUnavailable else { return }

        // Work that is already committing to the network owns the screen until
        // it finishes. Dropping the newcomer with a visible message beats
        // silently reshuffling state underneath an approval the user is
        // partway through. Each branch reports where the user is actually
        // looking: the approve sheet covers the screen, so a screen-level
        // `.alert` would only be seen after the sheet is gone.
        guard !isApproving else {
            approveError = NSLocalizedString("Another DashConnect request arrived. Finish this one first, then try again.",
                                             comment: "DashConnect: a second request arrived while one was being approved")
            return
        }

        guard !isProcessingKeyRegistration else {
            message = ConnectionsScreenMessage(
                kind: .error,
                text: NSLocalizedString("Finish the current DashConnect request first, then try again.",
                                        comment: "DashConnect: a second request arrived during key registration")
            )
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        isResolvingRequest = true

        Task {
            defer { if generation == requestGeneration { isResolvingRequest = false } }
            do {
                pendingRequest = nil
                pendingLoginRequest = nil

                switch try await dataSource.parseQR(content) {
                case let .login(request):
                    // Resolve first, publish second, and publish the pair
                    // together. Between these two lines a newer request may
                    // have arrived; if it has, this one is stale and must
                    // publish nothing — the sheet and the key it authorizes
                    // have to describe the same request.
                    let connectionRequest = await dataSource.makeConnectionRequest(from: request)
                    guard generation == requestGeneration else { return }
                    pendingLoginRequest = request
                    pendingRequest = connectionRequest
                case let .keyRegistration(request):
                    guard generation == requestGeneration else { return }
                    isProcessingKeyRegistration = true
                    defer { isProcessingKeyRegistration = false }

                    try await dataSource.completeKeyRegistration(request)
                    message = ConnectionsScreenMessage(
                        kind: .success,
                        text: NSLocalizedString("DashConnect key registration completed.", comment: "DashConnect")
                    )
                }
            } catch {
                guard generation == requestGeneration else { return }
                message = ConnectionsScreenMessage(
                    kind: .error,
                    text: String(
                        format: NSLocalizedString("Could not complete the DashConnect request: %@", comment: "DashConnect"),
                        error.localizedDescription
                    )
                )
            }
        }
    }

    /// A `dash-key:` / `dash-st:` link opened by an app running on this phone.
    /// It carries exactly what the QR code encodes, so it takes the same path.
    func onURIReceived(_ uri: String) {
        onQRScanned(uri)
    }

    func approvePendingRequest() {
        // `isResolvingRequest` guards the window where a newer request has been
        // accepted but has not published yet: approving during it would
        // authorize the request on screen moments before it is replaced.
        guard pendingRequest != nil, let pendingLoginRequest, !isApproving, !isResolvingRequest else { return }

        isApproving = true
        approveError = nil

        Task {
            defer { isApproving = false }

            do {
                _ = try await dataSource.approveLogin(pendingLoginRequest)
                self.pendingRequest = nil
                self.pendingLoginRequest = nil
                self.approveError = nil
            } catch {
                // Keep the sheet up so the user can retry without rescanning the QR.
                self.approveError = String(
                    format: NSLocalizedString("Could not complete the DashConnect request: %@", comment: "DashConnect"),
                    error.localizedDescription
                )
            }
        }
    }

    func denyPendingRequest() {
        guard !isApproving else { return }
        pendingRequest = nil
        pendingLoginRequest = nil
        approveError = nil
    }

    func disconnect(_ connection: DAppConnection) {
        Task {
            await dataSource.disconnect(id: connection.id)
        }
    }

    func removeConnection(_ connection: DAppConnection) {
        Task {
            await dataSource.remove(id: connection.id)
        }
    }

    private static func defaultDataSource(featureUnavailable: Bool) -> any DashConnectDataSource {
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isPreview || featureUnavailable {
            return MockDashConnectDataSource()
        }

        assert(
            WalletEnvironment.isTestnet,
            "DashConnect real data source must only run on testnet."
        )
        return PlatformDashConnectDataSource()
    }
}
