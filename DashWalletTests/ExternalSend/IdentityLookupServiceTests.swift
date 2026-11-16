//
//  Created by Roman Chornyi
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

@testable import dashpay
import SwiftDashSDK
import XCTest

/// The Identity ID lookup behind the Address screen (AC-12, AC-12b, AC-13, AC-13b): only the network edge
/// (`IdentityPlatformReading`) and the active wallet's Current identity (`CurrentIdentityProviding`) are scripted.
final class IdentityLookupServiceTests: XCTestCase {
    private let someID = "someone-elses-identity-id"
    private let ownID = "own-current-identity-id"
    private let siblingID = "another-identity-of-the-same-wallet"

    private final class FakePlatform: IdentityPlatformReading, @unchecked Sendable {
        var existing: Set<String> = []
        var usernames: [String: String] = [:]
        var fetchError: Error?
        var usernameError: Error?
        private(set) var fetchedIDs: [String] = []
        private(set) var fetchNetworks: [WalletEnvironment.NetworkKind] = []
        private(set) var usernameNetworks: [WalletEnvironment.NetworkKind] = []
        private(set) var calledOnMainThread: [Bool] = []

        func fetchIdentity(id: String, network: WalletEnvironment.NetworkKind) async throws {
            fetchedIDs.append(id)
            fetchNetworks.append(network)
            calledOnMainThread.append(Thread.isMainThread)
            if let fetchError { throw fetchError }
            if !existing.contains(id) { throw SDKError.notFound("Identity not found") }
        }

        func username(forIdentity id: String, network: WalletEnvironment.NetworkKind) async throws -> String? {
            usernameNetworks.append(network)
            if let usernameError { throw usernameError }
            return usernames[id]
        }
    }

    private struct FakeCurrentIdentity: CurrentIdentityProviding {
        var id: String?

        func currentIdentityID(on network: WalletEnvironment.NetworkKind) -> String? { id }
    }

    private func makeService(_ platform: FakePlatform, currentID: String? = nil) -> IdentityLookupService {
        IdentityLookupService(platform: platform, currentIdentity: FakeCurrentIdentity(id: currentID))
    }

    // MARK: AC-12

    func testFoundWithUsernameIsSomeoneElses() async {
        let platform = FakePlatform()
        platform.existing = [someID]
        platform.usernames[someID] = "alice"

        let result = await makeService(platform, currentID: ownID).lookup(id: someID, network: .testnet)

        XCTAssertEqual(result, .found(IdentityRecipient(id: someID, username: "alice", isOwnCurrentIdentity: false)))
    }

    func testFoundWithoutUsernameHasNilUsername() async {
        let platform = FakePlatform()
        platform.existing = [someID]

        let result = await makeService(platform, currentID: ownID).lookup(id: someID, network: .testnet)

        XCTAssertEqual(result, .found(IdentityRecipient(id: someID, username: nil, isOwnCurrentIdentity: false)))
    }

    func testFailedUsernameLookupStillFindsTheIdentityWithoutUsername() async {
        let platform = FakePlatform()
        platform.existing = [someID]
        platform.usernameError = SDKError.networkError("username lookup dropped")

        let result = await makeService(platform, currentID: ownID).lookup(id: someID, network: .testnet)

        XCTAssertEqual(result, .found(IdentityRecipient(id: someID, username: nil, isOwnCurrentIdentity: false)))
    }

    // MARK: AC-12b

    func testOwnCurrentIdentityIsDetected() async {
        let platform = FakePlatform()
        platform.existing = [ownID]
        platform.usernames[ownID] = "me"

        let result = await makeService(platform, currentID: ownID).lookup(id: ownID, network: .testnet)

        XCTAssertEqual(result, .found(IdentityRecipient(id: ownID, username: "me", isOwnCurrentIdentity: true)))
    }

    func testAnotherIdentityOfTheSameWalletIsSomeoneElses() async {
        let platform = FakePlatform()
        platform.existing = [siblingID]

        let result = await makeService(platform, currentID: ownID).lookup(id: siblingID, network: .testnet)

        XCTAssertEqual(result, .found(IdentityRecipient(id: siblingID, username: nil, isOwnCurrentIdentity: false)))
    }

    func testNoCurrentIdentityMeansNothingIsOwn() async {
        let platform = FakePlatform()
        platform.existing = [ownID]

        let result = await makeService(platform, currentID: nil).lookup(id: ownID, network: .testnet)

        XCTAssertEqual(result, .found(IdentityRecipient(id: ownID, username: nil, isOwnCurrentIdentity: false)))
    }

    // MARK: AC-13

    func testProvenAbsentIdentityIsNotFound() async {
        let platform = FakePlatform()

        let result = await makeService(platform, currentID: ownID).lookup(id: someID, network: .testnet)

        XCTAssertEqual(result, .notFound)
    }

    // MARK: AC-13b

    func testTransportErrorIsCouldNotCheckNeverNotFound() async {
        let errors: [Error] = [
            SDKError.networkError("no connection"),
            SDKError.timeout("Platform did not answer"),
            SDKError.internalError("unexpected"),
            URLError(.notConnectedToInternet),
        ]
        for error in errors {
            let platform = FakePlatform()
            platform.existing = [someID]
            platform.fetchError = error

            let result = await makeService(platform, currentID: ownID).lookup(id: someID, network: .testnet)

            XCTAssertEqual(result, .couldNotCheck, "\(error)")
        }
    }

    func testRetryAfterCouldNotCheckCanFind() async {
        let platform = FakePlatform()
        platform.existing = [someID]
        platform.fetchError = SDKError.timeout("Platform did not answer")
        let service = makeService(platform, currentID: ownID)

        let first = await service.lookup(id: someID, network: .testnet)
        platform.fetchError = nil
        let second = await service.lookup(id: someID, network: .testnet)

        XCTAssertEqual(first, .couldNotCheck)
        XCTAssertEqual(second, .found(IdentityRecipient(id: someID, username: nil, isOwnCurrentIdentity: false)))
    }

    // MARK: Selected network, concurrency

    func testLookupUsesTheGivenNetworkForFetchAndUsername() async {
        for network in [WalletEnvironment.NetworkKind.mainnet, .testnet] {
            let platform = FakePlatform()
            platform.existing = [someID]

            _ = await makeService(platform).lookup(id: someID, network: network)

            XCTAssertEqual(platform.fetchedIDs, [someID])
            XCTAssertEqual(platform.fetchNetworks, [network])
            XCTAssertEqual(platform.usernameNetworks, [network])
        }
    }

    @MainActor
    func testPlatformCallRunsOffTheMainActorWhenCalledFromIt() async {
        let platform = FakePlatform()
        platform.existing = [someID]

        _ = await makeService(platform).lookup(id: someID, network: .testnet)

        XCTAssertEqual(platform.calledOnMainThread, [false])
    }

    /// Stands for the SDK reads, which block their thread on the network inside Rust.
    private final class BlockingSDK: IdentitySDKReading, @unchecked Sendable {
        private(set) var onMainThread: [Bool] = []

        func identityGet(identityId: String) async throws -> [String: Any] {
            onMainThread.append(Thread.isMainThread)
            Thread.sleep(forTimeInterval: 0.3)
            return ["id": identityId]
        }

        func dpnsGetUsername(identityId: String, limit: UInt32?) async throws -> [[String: Any]] {
            onMainThread.append(Thread.isMainThread)
            Thread.sleep(forTimeInterval: 0.3)
            return [["label": "alice"]]
        }
    }

    /// The main actor keeps running while the live reader waits on a blocking fetch and username read: a main-actor
    /// heartbeat ticks every 10 ms through the 600 ms the reads block, which it cannot while they hold the main thread.
    @MainActor
    func testLiveReaderKeepsTheMainActorFreeDuringTheSDKReads() async throws {
        let sdk = BlockingSDK()
        let reader = SwiftDashSDKIdentityPlatformReader(sdk: { _ in sdk })
        var ticks = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                ticks += 1
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        try await reader.fetchIdentity(id: someID, network: .testnet)
        let username = try await reader.username(forIdentity: someID, network: .testnet)
        heartbeat.cancel()

        XCTAssertEqual(sdk.onMainThread, [false, false])
        XCTAssertGreaterThan(ticks, 20, "the main actor stalled during the SDK reads")
        XCTAssertEqual(username, "alice")
    }
}
