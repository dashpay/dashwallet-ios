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

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published private(set) var connections: [DAppConnection] = []
    @Published private(set) var featureUnavailable: Bool
    @Published var pendingRequest: ConnectionRequest?
    @Published var isApproving = false
    @Published var errorMessage: String?

    private let dataSource: any DashConnectDataSource
    private var cancellables = Set<AnyCancellable>()

    init(
        dataSource: any DashConnectDataSource = MockDashConnectDataSource(),
        featureUnavailable: Bool? = nil
    ) {
        self.dataSource = dataSource
        self.featureUnavailable = featureUnavailable ?? (
            DWEnvironment.sharedInstance().currentChain.chainType.tag != ChainType_TestNet
        )

        dataSource.connections
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
                pendingRequest = try await dataSource.parseQR(content)
            } catch {
                errorMessage = String(
                    format: NSLocalizedString("Could not complete the DashConnect request: %@", comment: "DashConnect"),
                    error.localizedDescription
                )
            }
        }
    }

    func approvePendingRequest() {
        guard let pendingRequest, !isApproving else { return }

        isApproving = true

        Task {
            defer { isApproving = false }

            do {
                _ = try await dataSource.approve(pendingRequest)
                self.pendingRequest = nil
            } catch {
                errorMessage = String(
                    format: NSLocalizedString("Could not complete the DashConnect request: %@", comment: "DashConnect"),
                    error.localizedDescription
                )
            }
        }
    }

    func denyPendingRequest() {
        guard !isApproving else { return }
        pendingRequest = nil
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
}
