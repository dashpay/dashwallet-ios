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

        Task {
            do {
                pendingRequest = nil
                pendingLoginRequest = nil

                switch try await dataSource.parseQR(content) {
                case let .login(request):
                    pendingLoginRequest = request
                    pendingRequest = await dataSource.makeConnectionRequest(from: request)
                case let .keyRegistration(request):
                    isProcessingKeyRegistration = true
                    defer { isProcessingKeyRegistration = false }

                    try await dataSource.completeKeyRegistration(request)
                    message = ConnectionsScreenMessage(
                        kind: .success,
                        text: NSLocalizedString("DashConnect key registration completed.", comment: "DashConnect")
                    )
                }
            } catch {
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
        guard pendingRequest != nil, let pendingLoginRequest, !isApproving else { return }

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
