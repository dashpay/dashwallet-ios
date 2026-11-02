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

/// What the Connections page lists for the active wallet, as published in
/// one value: its rows, its disconnected apps and the expiry check of its
/// rows, under the scope the rows name.
struct DashConnectListing: Equatable {
    /// The wallet, network and endpoint the rows were published for
    /// (`DAppConnection.scope`); `nil` with no wallet.
    let scope: String?
    let rows: [DAppConnection]
    /// The apps disconnected on that wallet, most recent first; `nil` when
    /// they cannot be read.
    let disconnected: [DisconnectedConnection]?
    /// The verdicts that hold for `rows`: each told for its row as it is
    /// published here.
    let expiries: ConnectionExpiries
}

protocol DashConnectDataSource {
    var listing: AnyPublisher<DashConnectListing, Never> { get }

    func parseQR(_ content: String) async throws -> DashConnectQr
    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest
    /// `consent` is the request as the approval sheet showed it. A login
    /// that would give the app something else, or act for another identity,
    /// wallet or network than it was resolved for, is refused.
    func approveLogin(_ request: DashKeyRequest, consent: ConnectionRequest) async throws -> DAppConnection
    /// Parses a scanned `dash-st:` payload and either completes key
    /// registration immediately or returns a token purchase that awaits
    /// explicit user approval via `approveTokenPurchase(_:)`. With
    /// `refusesTokenPurchase`, a token purchase throws
    /// `DashConnectPlatformError.tokenPurchaseNeedsUsername` once parsed,
    /// before anything about it is read from the network.
    func handleStateTransition(_ request: DashStRequest, refusesTokenPurchase: Bool) async throws -> DashConnectStAction
    /// Rebuilds, signs and submits a token purchase the user approved.
    ///
    /// Throws `DashConnectTokenPurchaseFailure`, which says whether the
    /// transition could already have reached Platform — the caller must not
    /// offer a retry when it could have.
    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws
    /// Turns a connection off. For a one-QR connection this disables the key
    /// the app was given on the identity and deletes the published response,
    /// and throws when the key could not be disabled — the connection then
    /// stays as it was. A disconnect that disables keys of the app's on the
    /// active identity, leaves none of the app's records waiting for their
    /// update, and is known not to be stopped by another identity holding
    /// the app, also disables the live DashPay profile keys of that identity
    /// that no grant record names: their bound does not say which app was
    /// given them. When those cannot be told apart, none is disabled and the
    /// app's own keys still are. The result says which. The connection also
    /// stays, and that is thrown, while the app holds a key on another
    /// identity of the wallet. For a two-QR
    /// connection with nothing else of the app's on the identity it only
    /// changes the local status: that login derives the same key every time
    /// and Platform never re-adds a disabled key, so disabling it would lock
    /// the app out for good. A two-QR row whose app also holds a one-QR
    /// grant there has that grant's keys disabled. Turning off a one-QR
    /// connection that replaced a two-QR one does disable those keys too.
    ///
    /// `scope` is the `DAppConnection.scope` of the row that was picked:
    /// both calls act only while it still names the wallet they would act
    /// on.
    ///
    /// `expecting` is what the user was told it does: a disconnect the
    /// records no longer describe so (`DashConnectDisconnectEffect.accepts`)
    /// throws `DashConnectPlatformError.disconnectEffectChanged` before the
    /// PIN prompt, and one whose row is gone throws
    /// `DashConnectPlatformError.connectionGone`; `connections` publishes
    /// the rows without it.
    @discardableResult
    func disconnect(id: String, scope: String?, expecting: DashConnectDisconnectEffect) async throws
        -> DashConnectDisconnectResult
    func remove(id: String, scope: String?) async
    /// What the connection sheet shows for the row `id`, from the grant
    /// records of the active identity; `nil` when there is no active wallet
    /// or `scope` is not its.
    func connectionDetails(id: String, scope: String?) async -> ConnectionDetails?
    /// What `disconnect(id:scope:expecting:)` would do, from the local
    /// records alone; `nil` when there is no active wallet, `scope` is not
    /// its, or it has no row `id`. Local and quick, so a question about it
    /// can be asked on the tap.
    @MainActor
    func disconnectEffect(id: String, scope: String?) -> DashConnectDisconnectEffect?
    /// The Connections page is on screen: reads whether the active rows'
    /// keys can still sign, and publishes the verdicts in `listing`, now and
    /// as they can change. Without `forcesRead`, a read made moments ago may
    /// be judged again instead. Returns at once.
    @MainActor
    func refreshConnectionExpiries(forcesRead: Bool)
    /// The Connections page left the screen: a read running for the check
    /// is cancelled, and nothing is read until
    /// `refreshConnectionExpiries(forcesRead:)` is called again.
    @MainActor
    func stopConnectionExpiryReads()
    /// The app came back to the foreground: the check's clocks may have
    /// moved on while the device slept.
    @MainActor
    func connectionExpiriesForegrounded()
    /// What an earlier approval of `loginRequest` recorded it would grant,
    /// read from this device's store; `nil` when there is none.
    func recordedGrantedAccess(for loginRequest: DashKeyRequest) async -> AppConnect.GrantedAccess?
}

extension DashConnectDataSource {
    /// The rows `listing` publishes.
    var connections: AnyPublisher<[DAppConnection], Never> {
        listing.map(\.rows).eraseToAnyPublisher()
    }

    func connectionDetails(id: String, scope: String?) async -> ConnectionDetails? { nil }
    func recordedGrantedAccess(for loginRequest: DashKeyRequest) async -> AppConnect.GrantedAccess? { nil }
}

/// Why a token purchase failed, and — the part that decides what the UI may
/// offer next — whether the transition could already have reached Platform.
///
/// A purchase is not idempotent: each approval builds and signs a new direct
/// purchase against the identity's next nonce. Retrying after a failure that
/// only looked like a failure buys the tokens a second time and debits the
/// credits a second time, so "did this reach Platform?" has to survive as far
/// as the screen.
enum DashConnectTokenPurchaseFailure: LocalizedError {
    /// Refused before anything was signed or submitted — a wrong identity, a
    /// mismatched token id, a cancelled authentication, a missing runtime.
    /// Nothing was charged and approving again is safe.
    case beforeSubmission(Error)
    /// The transition was signed and handed to Platform, and the failure came
    /// out of that call. Platform may have accepted it anyway (a finality
    /// timeout, a dropped DAPI response), so the purchase must be treated as
    /// possibly complete.
    case outcomeUnknown(Error)

    var underlying: Error {
        switch self {
        case .beforeSubmission(let error), .outcomeUnknown(let error):
            return error
        }
    }

    var errorDescription: String? { underlying.localizedDescription }
}

enum DashConnectMockError: LocalizedError, Equatable {
    case parseFailed
    case approveFailed
    case notDashConnectQrCode
    case needsNewerWallet
    case unsupportedNetwork(expected: DashConnectNetwork, actual: DashConnectNetwork)
    case stateTransitionNotSupported

    var errorDescription: String? {
        switch self {
        case .parseFailed:
            return "Invalid QR payload"
        case .approveFailed:
            return "Approval failed"
        case .notDashConnectQrCode:
            return "This QR code is not a DashConnect QR code."
        case .needsNewerWallet:
            return "This link needs a newer version of the wallet."
        case let .unsupportedNetwork(expected, actual):
            return "This DashConnect QR is for \(Self.displayName(for: actual)), but this wallet currently supports \(Self.displayName(for: expected)) only."
        case .stateTransitionNotSupported:
            return "State transitions are not supported by the mock."
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
    static let sampleRequest: ConnectionRequest = {
        var request = ConnectionRequest(loginRequest: sampleLoginRequest)
        request.login = .twoQR
        return request
    }()

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
    /// Whether the check was asked for: the rows are then told, each as
    /// published, with nothing to judge.
    private let expiriesChecked = CurrentValueSubject<Bool, Never>(false)

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

    /// The mock keeps no history: no disconnected apps.
    var listing: AnyPublisher<DashConnectListing, Never> {
        subject.combineLatest(expiriesChecked)
            .map { rows, checked in
                guard checked else {
                    return DashConnectListing(scope: nil, rows: rows, disconnected: [], expiries: .notStarted)
                }
                let byApp = Dictionary(
                    rows.filter { $0.status == .active }.map { ($0.id, ConnectionExpiry(verdict: .notJudged, row: $0)) },
                    uniquingKeysWith: { first, _ in first })
                return DashConnectListing(
                    scope: nil, rows: rows, disconnected: [],
                    expiries: ConnectionExpiries(identityId: nil, check: .read, byApp: byApp))
            }
            .eraseToAnyPublisher()
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
            return .stateTransition(request)
        }

        throw DashConnectMockError.notDashConnectQrCode
    }

    func approveLogin(_ request: DashKeyRequest, consent: ConnectionRequest) async throws -> DAppConnection {
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
            existingConnection: existingConnection(for: fallback.appContractId),
            login: .twoQR
        )
    }

    func handleStateTransition(_ request: DashStRequest, refusesTokenPurchase: Bool) async throws -> DashConnectStAction {
        try await Task.sleep(nanoseconds: 400_000_000)
        throw DashConnectMockError.stateTransitionNotSupported
    }

    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        throw DashConnectTokenPurchaseFailure.beforeSubmission(
            DashConnectMockError.stateTransitionNotSupported)
    }

    @discardableResult
    func disconnect(
        id: String, scope: String?, expecting: DashConnectDisconnectEffect
    ) async throws -> DashConnectDisconnectResult {
        guard subject.value.contains(where: { $0.id == id && $0.scope == scope }) else {
            throw DashConnectPlatformError.connectionGone
        }
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
        return DashConnectDisconnectResult()
    }

    func remove(id: String, scope: String?) async {
        persistAndSend(subject.value.filter { $0.id != id })
    }

    /// The mock grants no keys: no details beyond the row.
    func connectionDetails(id: String, scope: String?) async -> ConnectionDetails? {
        guard subject.value.contains(where: { $0.id == id }) else { return nil }
        return ConnectionDetails(appId: id, identityId: nil, username: nil, access: nil)
    }

    /// The mock holds no keys: its disconnect only changes the row.
    @MainActor
    func disconnectEffect(id: String, scope: String?) -> DashConnectDisconnectEffect? {
        subject.value.contains { $0.id == id && $0.scope == scope } ? .localOnly : nil
    }

    /// The mock grants no keys: nothing of any active row's to judge, for
    /// every listing it publishes from now on.
    @MainActor
    func refreshConnectionExpiries(forcesRead: Bool) {
        expiriesChecked.send(true)
    }

    /// The mock reads only when asked: nothing runs to be stopped.
    @MainActor
    func stopConnectionExpiryReads() {}

    /// The mock's verdicts do not depend on the clocks.
    @MainActor
    func connectionExpiriesForegrounded() {}

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
