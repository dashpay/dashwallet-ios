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
/// one value: its rows and its disconnected apps, under the scope the rows
/// name.
struct DashConnectListing: Equatable {
    /// The wallet, network and endpoint the rows were published for
    /// (`DAppConnection.scope`); `nil` with no wallet.
    let scope: String?
    let rows: [DAppConnection]
    /// The apps disconnected on that wallet, most recent first.
    let disconnected: [DisconnectedConnection]
}

/// An app disconnected on this wallet, as the Connections page lists it
/// under Disconnected: worked out from the intents a disconnect marked
/// (ADR 0013), for as long as the wallet keeps them. A later connection of
/// the app takes its place.
struct DisconnectedConnection: Equatable, Identifiable {
    /// The app's contract id (Base58).
    let id: String
    let name: String
    let url: String
    let identityId: String?
    let username: String?
    let disconnectedAt: Date
    /// What the connection gave the app when it was disconnected.
    let access: ConnectionAccess?
    /// When the connection was made.
    var connectedAt: Date? = nil
}

protocol DashConnectDataSource {
    var listing: AnyPublisher<DashConnectListing, Never> { get }

    func parseQR(_ content: String) async throws -> DashConnectQr
    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest
    /// `consent` is the request as the approval sheet showed it. A login
    /// that would give the app something else, or act for another identity,
    /// wallet or network than it was resolved for, is refused.
    func approveLogin(_ request: DashKeyRequest, consent: ConnectionRequest) async throws -> DAppConnection
    /// Parses a scanned `dash-st:` payload and returns the token purchase it
    /// carries, which awaits explicit user approval via
    /// `approveTokenPurchase(_:)`. Any other transition is refused.
    func handleStateTransition(_ request: DashStRequest) async throws -> DashConnectStAction
    /// Rebuilds, signs and submits a token purchase the user approved.
    ///
    /// Throws `DashConnectTokenPurchaseFailure`, which says whether the
    /// transition could already have reached Platform — the caller must not
    /// offer a retry when it could have.
    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws
    /// Turns a connection off. For an App Connect connection this turns off
    /// every key the wallet's approvals of the app gave on the active
    /// identity, puts a key of the wallet's own under each id an approval
    /// may still land on so it never does, and deletes the published
    /// responses. It also turns off, with no further question, the live keys
    /// bound to the app's contracts that no approval of this wallet names
    /// (from another device or from before a restore), the live keys on the
    /// other contracts and contract groups of the app's owner it can
    /// attribute to the app by owner, and every DashPay profile key no
    /// approval names. An update that fails stops it: the result says how
    /// many keys are still live, and the connection stays. Keys whose bound
    /// the wallet cannot tell yet, or whose owner, the app's owner or another
    /// app's owner here could not be read, are not turned off and are counted
    /// as not checked; keys of the app's owner that another app here has too
    /// are not turned off and are counted as not attributable. The
    /// connection also stays, and that is thrown, while an approval of the
    /// app on another identity of the wallet is not done.
    ///
    /// `scope` is the `DAppConnection.scope` of the row that was picked:
    /// both calls act only while it still names the wallet they would act
    /// on.
    @discardableResult
    func disconnect(id: String, scope: String?) async throws -> DashConnectDisconnectResult
    /// Hides a row. For an App Connect connection that Platform refused for
    /// good it records the remove date on the connection's refused approvals,
    /// without a PIN and without writing to Platform; a connection that does
    /// not show Refused is left as it is.
    func remove(id: String, scope: String?) async
    /// Puts the App Connect rows in step with the active identity's keys on
    /// Platform. Best effort: a failed read leaves the rows as they were.
    func refreshConnections() async
    /// What the connection sheet shows for the row `id`, from the active
    /// identity's intents for the app; `nil` when there is no active wallet
    /// or `scope` is not its.
    func connectionDetails(id: String, scope: String?) async -> ConnectionDetails?
    /// What is left of the budgets of the row `id`'s keys, read after its
    /// details and apart from them, so the sheet shows them first.
    func connectionFunding(id: String, scope: String?) async -> ConnectionFundingRead
}

extension DashConnectDataSource {
    func refreshConnections() async {}
    /// The rows `listing` publishes.
    var connections: AnyPublisher<[DAppConnection], Never> {
        listing.map(\.rows).eraseToAnyPublisher()
    }

    func connectionDetails(id: String, scope: String?) async -> ConnectionDetails? { nil }
    func connectionFunding(id: String, scope: String?) async -> ConnectionFundingRead { .notRead }
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
            return NSLocalizedString("This link needs a newer version of the wallet.", comment: "DashConnect")
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
        request.login = .appConnect(AppConnect.GrantPlan(
            appId: sampleLoginRequest.contractId, appEphemeralPubKeyHash: Data(repeating: 0, count: 20),
            auth: [], encryption: [], connectionId: nil, identityHint: nil, createdAt: 0, callbackHost: nil))
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
            sample(.confirming),
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

    /// The mock keeps no history: no disconnected apps.
    var listing: AnyPublisher<DashConnectListing, Never> {
        subject.map { DashConnectListing(scope: nil, rows: $0, disconnected: []) }.eraseToAnyPublisher()
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
            throw AppConnect.v1Refusal
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
        guard consent.login.isApprovable else { throw DashConnectPlatformError.approvalOutOfDate }

        let connectionRequest = await makeConnectionRequest(from: request)
        let connection = DAppConnection(
            id: connectionRequest.appContractId,
            name: connectionRequest.appLabel.isEmpty ? NSLocalizedString("Unknown app", comment: "DashConnect") : connectionRequest.appLabel,
            url: connectionRequest.appUrl,
            status: .active,
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
            login: .refused(AppConnect.v1Refusal)
        )
    }

    func handleStateTransition(_ request: DashStRequest) async throws -> DashConnectStAction {
        try await Task.sleep(nanoseconds: 400_000_000)
        throw DashConnectMockError.stateTransitionNotSupported
    }

    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        throw DashConnectTokenPurchaseFailure.beforeSubmission(
            DashConnectMockError.stateTransitionNotSupported)
    }

    @discardableResult
    func disconnect(id: String, scope: String?) async throws -> DashConnectDisconnectResult {
        persistAndSend(subject.value.filter { $0.id != id })
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
