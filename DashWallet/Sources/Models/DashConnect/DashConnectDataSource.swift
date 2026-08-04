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

    func parseQR(_ content: String) async throws -> DashConnectQr
    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest
    func approveLogin(_ request: DashKeyRequest) async throws -> DAppConnection
    func completeKeyRegistration(_ request: DashStRequest) async throws
    func disconnect(id: String) async
    func remove(id: String) async
}

enum DashConnectMockError: LocalizedError, Equatable {
    case parseFailed
    case approveFailed
    case notDashConnectQrCode
    case unsupportedNetwork(expected: DashConnectNetwork, actual: DashConnectNetwork)
    case keyRegistrationNotSupported

    var errorDescription: String? {
        switch self {
        case .parseFailed:
            return "Invalid QR payload"
        case .approveFailed:
            return "Approval failed"
        case .notDashConnectQrCode:
            return "This QR code is not a DashConnect QR code."
        case let .unsupportedNetwork(expected, actual):
            return "This DashConnect QR is for \(Self.displayName(for: actual)), but this wallet currently supports \(Self.displayName(for: expected)) only."
        case .keyRegistrationNotSupported:
            return "Key registration is not supported by the mock."
        }
    }

    private static func displayName(for network: DashConnectNetwork) -> String {
        switch network {
        case .mainnet:
            return "Mainnet"
        case .testnet:
            return "Testnet"
        case .devnet:
            return "Devnet"
        }
    }
}

final class MockDashConnectDataSource: DashConnectDataSource {
    static let sampleLoginRequest = DashKeyRequest(
        appEphemeralPubKey: Data(hex: "031b84c5567b126440995d3ed5aaba0565d71e1834604819ff9c17f5e9d5dd078f")!,
        // Yappr's real testnet contract, so the sample resolves to Yappr branding and
        // matches `sample(_:)`'s id.
        contractId: Data([
            0xc8, 0xb1, 0x02, 0xb5, 0x6e, 0xa7, 0xbb, 0xac,
            0xf7, 0x72, 0xd8, 0x36, 0x23, 0xf8, 0xd1, 0x8c,
            0x53, 0xae, 0xf2, 0x07, 0x66, 0x59, 0x9a, 0xc6,
            0x82, 0xb6, 0xa0, 0x19, 0xf2, 0x9d, 0x35, 0x3e
        ]),
        label: "Login to Yappr",
        network: .testnet
    )
    static let sampleLoginQRCode = DashConnectSampleQR.keyUri(for: sampleLoginRequest)
    static let sampleRequest = ConnectionRequest(loginRequest: sampleLoginRequest)

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
        ])
    }
    #endif

    var shouldFailNextParse = false
    var shouldFailNextApprove = false

    private let supportedNetwork: DashConnectNetwork
    private let store: any DashConnectStore
    private let subject: CurrentValueSubject<[DAppConnection], Never>

    init(
        initial: [DAppConnection] = [],
        supportedNetwork: DashConnectNetwork = .testnet,
        store: (any DashConnectStore)? = nil
    ) {
        self.supportedNetwork = supportedNetwork
        self.store = store ?? UserDefaultsDashConnectStore(network: supportedNetwork)
        let restored = initial.isEmpty ? self.store.load() : initial
        self.subject = CurrentValueSubject(restored)
    }

    var connections: AnyPublisher<[DAppConnection], Never> {
        subject.eraseToAnyPublisher()
    }

    var connectionsSnapshot: [DAppConnection] {
        subject.value
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        if shouldFailNextParse {
            shouldFailNextParse = false
            throw DashConnectMockError.parseFailed
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if DashConnectUri.isKeyUri(trimmed) {
            let request = try DashConnectUri.parseKeyRequest(trimmed)
            try validateNetwork(request.network)
            return .login(request)
        }

        if DashConnectUri.isStUri(trimmed) {
            let request = try DashConnectUri.parseStRequest(trimmed)
            try validateNetwork(request.network)
            return .keyRegistration(request)
        }

        throw DashConnectMockError.notDashConnectQrCode
    }

    func approveLogin(_ request: DashKeyRequest) async throws -> DAppConnection {
        try await Task.sleep(nanoseconds: 400_000_000)

        if shouldFailNextApprove {
            shouldFailNextApprove = false
            throw DashConnectMockError.approveFailed
        }

        let connectionRequest = await makeConnectionRequest(from: request)
        let connection = DAppConnection(
            id: connectionRequest.appContractId,
            name: connectionRequest.appLabel.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : connectionRequest.appLabel,
            url: connectionRequest.appUrl,
            status: .approved,
            updatedAt: Date()
        )

        var current = subject.value.filter { $0.id != connection.id }
        current.append(connection)
        persistAndSend(current)
        return connection
    }

    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        let fallback = ConnectionRequest(loginRequest: loginRequest)
        return ConnectionRequest(
            loginRequest: loginRequest,
            appLabel: fallback.appLabel,
            appUrl: fallback.appUrl,
            walletUsername: nil,
            walletIdentityId: nil,
            existingConnection: existingConnection(for: fallback.appContractId)
        )
    }

    func completeKeyRegistration(_ request: DashStRequest) async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
        throw DashConnectMockError.keyRegistrationNotSupported
    }

    func disconnect(id: String) async {
        let disconnectedAt = Date()
        persistAndSend(subject.value.map { connection in
            guard connection.id == id else { return connection }
            return DAppConnection(
                id: connection.id,
                name: connection.name,
                url: connection.url,
                status: .approved,
                updatedAt: disconnectedAt
            )
        })
    }

    func remove(id: String) async {
        persistAndSend(subject.value.filter { $0.id != id })
    }

    private func validateNetwork(_ network: DashConnectNetwork) throws {
        guard network == supportedNetwork else {
            throw DashConnectMockError.unsupportedNetwork(expected: supportedNetwork, actual: network)
        }
    }

    private func persistAndSend(_ connections: [DAppConnection]) {
        let sorted = connections.sorted(by: { $0.updatedAt > $1.updatedAt })
        store.save(sorted)
        subject.send(sorted)
    }

    private func existingConnection(for contractId: String) -> DAppConnection? {
        subject.value.first { $0.id == contractId }
    }
}

private enum DashConnectSampleQR {
    static func keyUri(for request: DashKeyRequest) -> String {
        let labelData = Data(request.label.utf8)
        let payload = Data([0x01])
            + request.appEphemeralPubKey
            + request.contractId
            + Data([UInt8(labelData.count)])
            + labelData
        return "dash-key:\(base58Encode(payload))?n=\(request.network.rawValue)&v=1"
    }

    private static func base58Encode(_ data: Data) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
        let bytes = [UInt8](data)
        var leadingZeros = 0
        while leadingZeros < bytes.count, bytes[leadingZeros] == 0 {
            leadingZeros += 1
        }

        let size = (bytes.count - leadingZeros) * 138 / 100 + 1
        var buffer = [UInt8](repeating: 0, count: size)

        for i in leadingZeros ..< bytes.count {
            var carry = Int(bytes[i])
            for j in stride(from: size - 1, through: 0, by: -1) {
                carry += 256 * Int(buffer[j])
                buffer[j] = UInt8(carry % 58)
                carry /= 58
            }
        }

        var start = 0
        while start < size, buffer[start] == 0 {
            start += 1
        }

        var result = [UInt8]()
        result.reserveCapacity(leadingZeros + size - start)
        result.append(contentsOf: repeatElement(alphabet[0], count: leadingZeros))
        for i in start ..< size {
            result.append(alphabet[Int(buffer[i])])
        }
        return String(decoding: result, as: UTF8.self)
    }
}
