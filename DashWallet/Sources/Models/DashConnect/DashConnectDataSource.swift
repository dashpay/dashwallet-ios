//
//  DashConnectDataSource.swift
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

protocol DashConnectDataSource {
    var connections: AnyPublisher<[DAppConnection], Never> { get }

    func parseQR(_ content: String) async throws -> ConnectionRequest
    func approve(_ request: ConnectionRequest) async throws -> DAppConnection
    func disconnect(id: String) async
    func remove(id: String) async
}

enum DashConnectMockError: LocalizedError {
    case parseFailed
    case approveFailed

    var errorDescription: String? {
        switch self {
        case .parseFailed:
            return "Invalid QR payload"
        case .approveFailed:
            return "Approval failed"
        }
    }
}

final class MockDashConnectDataSource: DashConnectDataSource {
    static let sampleRequest = ConnectionRequest(
        appLabel: "Yappr",
        appUrl: "yap.pr",
        appContractId: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
        walletUsername: "john.doe",
        walletIdentityId: "5DbLwAxEWR695MsqP4KybNQD5n7CUDWydJYNg63FzUo8"
    )

    static func sample(_ status: ConnectionStatus) -> DAppConnection {
        DAppConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            name: "Yappr",
            url: "yappr.io",
            status: status,
            updatedAt: Date(timeIntervalSince1970: 1_773_132_300)
        )
    }

    #if DEBUG
    static func previewMixed() -> MockDashConnectDataSource {
        MockDashConnectDataSource(initial: [
            sample(.approved),
            DAppConnection(
                id: "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234",
                name: "DashGet",
                url: "dashget.app",
                status: .active,
                updatedAt: Date(timeIntervalSince1970: 1_773_218_700)
            ),
            DAppConnection(
                id: "AaC695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg09Z",
                name: "PayKit",
                url: "paykit.dev",
                status: .disconnected,
                updatedAt: Date(timeIntervalSince1970: 1_773_305_100)
            ),
        ])
    }
    #endif

    var shouldFailNextParse = false
    var shouldFailNextApprove = false

    private let subject: CurrentValueSubject<[DAppConnection], Never>

    init(initial: [DAppConnection] = []) {
        self.subject = CurrentValueSubject(initial)
    }

    var connections: AnyPublisher<[DAppConnection], Never> {
        subject.eraseToAnyPublisher()
    }

    func parseQR(_ content: String) async throws -> ConnectionRequest {
        _ = content
        try await Task.sleep(nanoseconds: 400_000_000)

        if shouldFailNextParse {
            shouldFailNextParse = false
            throw DashConnectMockError.parseFailed
        }

        return Self.sampleRequest
    }

    func approve(_ request: ConnectionRequest) async throws -> DAppConnection {
        try await Task.sleep(nanoseconds: 400_000_000)

        if shouldFailNextApprove {
            shouldFailNextApprove = false
            throw DashConnectMockError.approveFailed
        }

        let connection = DAppConnection(
            id: request.appContractId,
            name: request.appLabel.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : request.appLabel,
            url: request.appUrl,
            status: .approved,
            updatedAt: Date()
        )

        var current = subject.value.filter { $0.id != connection.id }
        current.append(connection)
        subject.send(current.sorted(by: { $0.updatedAt > $1.updatedAt }))
        return connection
    }

    func disconnect(id: String) async {
        subject.send(
            subject.value.map { connection in
                guard connection.id == id else { return connection }
                return DAppConnection(
                    id: connection.id,
                    name: connection.name,
                    url: connection.url,
                    status: .disconnected,
                    updatedAt: Date()
                )
            }
        )
    }

    func remove(id: String) async {
        subject.send(subject.value.filter { $0.id != id })
    }
}
