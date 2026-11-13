import CryptoKit
import Foundation
import XCTest
@testable import dashpay
@testable import SwiftDashSDK

/// The App Connect request v2 rules between decoding a request and
/// registering its keys (`AppConnectV2Login.swift`).
final class AppConnectV2LoginTests: XCTestCase {
    /// Yappr's published request vector (`vendor/platform-auth/src/app-connect/vectors.json`):
    /// a CRITICAL group binding (0.5 DASH, 90 days), a DashPay `profile`
    /// binding (0.01 DASH, 90 days), an encryption binding on the app id,
    /// a connection id and a callback.
    private static let requestUri = "dash-key:2fAANHHASdojyjV9Sqa2wf2nwZE8kLLqmeHpZWa8sBfaGsddVqyMG2ZVte7xJkTKsXvmFYbXzXbNnMo7bJQBxNcf79N8YWi7pLKyb39Rqv6b1KUmxw9UeJGYz2CV9hFGNUQtcyMYVq2Fg6vAxtxpYays61H8gLMcWqaG8TfgGA3H7setGAYiBsM5YmdZgeuCdGAHSwfNfav5cfFjXNDkPWv37UNSgFxj6o58jfXc3kCLKqLJtc5ZPjm1thEGYxK8HVYBi8fRQeEVy76n27DXGrVTyHz94CfJRuMnH76xGYbMgeuvurxjJMLrQgWUu53cjocYyzzNWdJrgs2D5?n=d&v=2&cb=https%3A%2F%2Fyap.pr%2Fconnect%3Fr%3Dd77dc0da9df83a47755a15c42c5d9db9d7a7fd62"
    private static let appEphemeralPubKey = Data(hex: "03e83cb927e85f96ae50a95ca3be21cc7a3755139a941b15d99b01af4fecf0d270")!
    private static let appId = Data(hex: "f8833c7a2d58ab816c24ae915fe2aa94676588b467ba1e9f2b24c1a3df7fdb78")!
    private static let groupId = Data(hex: "b0590e59269c6885acf71d27ddfce85187e2cc9736c42e958127cd35be6d38e8")!
    private static let dashpayContractId = Data(hex: "a2a1b4ac6fef22ea2a1a68e8123644b357875f6b412c18109281c146e7b271bc")!
    private static let createdAt: UInt64 = 1_791_676_800_000
    private static let expiresAt: UInt64 = 1_799_452_800_000
    private static let appOwner = Data(repeating: 0x0A, count: 32)
    private static let dayMilliseconds: UInt64 = 24 * 60 * 60 * 1000

    /// The proved block time one minute after the vector's request was made.
    private static let blockTimeMs = createdAt + 60_000

    private static func vectorUri() throws -> AppConnectUri {
        try DashConnectUri.parseAppConnectRequest(requestUri)
    }

    private static func vectorPlan() throws -> AppConnect.GrantPlan {
        try AppConnect.grantPlan(for: vectorUri(), blockTimeMs: blockTimeMs)
    }

    /// The vector's request with its bindings replaced.
    private static func uri(
        authBindings: [AppConnectRequest.AuthBinding],
        encryptionBindings: [AppConnectRequest.EncryptionBinding] = [],
        createdAt: UInt64 = createdAt
    ) -> AppConnectUri {
        AppConnectUri(
            request: AppConnectRequest(
                appEphemeralPubKey: appEphemeralPubKey,
                appId: appId,
                label: "Yappr",
                identityHint: nil,
                authBindings: authBindings,
                connectionId: nil,
                encryptionBindings: encryptionBindings,
                isRenewal: false,
                createdAt: createdAt),
            network: .devnet,
            callback: nil)
    }

    private static func groupBinding(
        level: AppConnectRequest.SecurityLevel = .critical,
        budget: UInt64? = 50_000_000_000,
        expiresAt: UInt64? = expiresAt
    ) -> AppConnectRequest.AuthBinding {
        .init(kind: .contractGroup, securityLevel: level, id: groupId,
              totalBudget: budget, expiresAt: expiresAt, documentTypeName: nil)
    }

    private static func key(
        _ keyId: UInt32,
        purpose: KeyPurpose = .authentication,
        level: SecurityLevel = .high,
        type: KeyType = .ecdsaHash160,
        data: Data? = nil,
        disabled: Bool = false
    ) -> ManagedIdentity.IdentityPublicKeyInfo {
        ManagedIdentity.IdentityPublicKeyInfo(
            keyId: Int32(bitPattern: keyId),
            purpose: purpose,
            securityLevel: level,
            keyType: type,
            readOnly: false,
            disabledAt: disabled ? 1 : nil,
            data: data ?? Data(repeating: UInt8(truncatingIfNeeded: keyId), count: type == .ecdsaSecp256k1 ? 33 : 20),
            totalBudget: nil,
            expiresAt: nil)
    }

    // MARK: - Derivation

    func testEachBindingDerivesFromItsOwnLeafAndTheLeafIsStable() {
        let leaves = (0 ..< AppConnectRequest.maxAuthBindings).map {
            AppConnect.authKeyLeaf(appEphemeralPubKey: Self.appEphemeralPubKey, bindingIndex: $0)
        }
        XCTAssertEqual(Set(leaves).count, leaves.count, "every binding gets a distinct key")
        XCTAssertTrue(leaves.allSatisfy { $0.count == 32 })
        // A retry of the same request derives the same keys.
        XCTAssertEqual(
            leaves,
            (0 ..< AppConnectRequest.maxAuthBindings).map {
                AppConnect.authKeyLeaf(appEphemeralPubKey: Self.appEphemeralPubKey, bindingIndex: $0)
            })
        // Never the leaf of the v1 session key of the same ephemeral key.
        XCTAssertFalse(leaves.contains(hash256(Self.appEphemeralPubKey)))
        // hash256(appEphPub ‖ 0x00)
        XCTAssertEqual(leaves[0], hash256(Self.appEphemeralPubKey + Data([0])))
        // Another request derives other keys.
        var other = Self.appEphemeralPubKey
        other[other.count - 1] ^= 0x01
        XCTAssertNotEqual(AppConnect.authKeyLeaf(appEphemeralPubKey: other, bindingIndex: 0), leaves[0])
    }

    private func hash256(_ data: Data) -> Data {
        Data(SHA256.hash(data: Data(SHA256.hash(data: data))))
    }

    func testAuthKeysAreRegisteredWithTheirBindingLevelAndLimits() throws {
        let plan = try Self.vectorPlan()
        let hash = Data(repeating: 0x11, count: 20)

        let group = AppConnect.authIdentityPubkey(plan.auth[0], keyId: 7, publicKeyHash160: hash)
        XCTAssertEqual(group.keyId, 7)
        XCTAssertEqual(group.keyType, .ecdsaHash160)
        XCTAssertEqual(group.purpose, .authentication)
        XCTAssertEqual(group.securityLevel, .critical)
        XCTAssertEqual(group.pubkeyBytes, hash)
        XCTAssertEqual(group.contractBounds, .contractGroup(id: Self.groupId))
        XCTAssertEqual(group.totalBudget, 50_000_000_000)
        XCTAssertEqual(group.expiresAt, Self.expiresAt)

        let profile = AppConnect.authIdentityPubkey(plan.auth[1], keyId: 8, publicKeyHash160: hash)
        XCTAssertEqual(profile.securityLevel, .high)
        XCTAssertEqual(
            profile.contractBounds,
            .singleContractDocumentType(id: Self.dashpayContractId, documentTypeName: "profile"))
        XCTAssertEqual(profile.totalBudget, 1_000_000_000)
        XCTAssertEqual(profile.expiresAt, Self.expiresAt)
    }

    func testTheEncryptionKeyIsAMediumPointBoundToTheApp() throws {
        let plan = try Self.vectorPlan()
        let point = Data([0x02] + [UInt8](repeating: 0x44, count: 32))
        let key = AppConnect.encryptionIdentityPubkey(plan.encryption[0], keyId: 9, publicKey: point)
        XCTAssertEqual(key.keyType, .ecdsaSecp256k1)
        XCTAssertEqual(key.purpose, .encryption)
        XCTAssertEqual(key.securityLevel, .medium)
        XCTAssertEqual(key.pubkeyBytes, point)
        XCTAssertEqual(key.contractBounds, .singleContract(id: Self.appId))
        XCTAssertNil(key.totalBudget)
        XCTAssertNil(key.expiresAt)
    }

    // MARK: - Plan and limits

    func testThePlanGrantsEveryBindingOfTheVector() throws {
        let plan = try Self.vectorPlan()
        XCTAssertEqual(plan.appId, Self.appId)
        XCTAssertEqual(plan.appEphemeralPubKeyHash.toHexString(), "d77dc0da9df83a47755a15c42c5d9db9d7a7fd62")
        XCTAssertEqual(plan.auth.map(\.bindingIndex), [0, 1])
        XCTAssertEqual(plan.auth.map(\.binding.kind), [.contractGroup, .documentType])
        XCTAssertEqual(plan.encryption.map(\.binding.contractId), [Self.appId])
        XCTAssertEqual(plan.connectionId?.toHexString(), "a69b1b4f666681453dec3734667a5ab2")
        XCTAssertEqual(plan.callbackHost, "yap.pr")
    }

    func testProposalsAboveTheCapsAreClampedAndNoLimitIsDropped() throws {
        let tooMuch = Self.groupBinding(
            budget: 10 * PlatformCreditsFormatter.creditsPerDash,
            expiresAt: Self.createdAt + 2 * 365 * Self.dayMilliseconds)
        let plan = try AppConnect.grantPlan(for: Self.uri(authBindings: [tooMuch]), blockTimeMs: Self.blockTimeMs)
        XCTAssertEqual(plan.auth[0].totalBudget, AppConnect.v2BudgetCapCredits)
        XCTAssertEqual(plan.auth[0].expiresAt, Self.blockTimeMs + UInt64(AppConnect.v2LifetimeCap * 1000))
    }

    func testABindingWithoutLimitsGetsTheDefaultLifetimeAndNoBudget() throws {
        let unlimited = AppConnectRequest.AuthBinding(
            kind: .singleContract, securityLevel: .high, id: Self.appId,
            totalBudget: nil, expiresAt: nil, documentTypeName: nil)
        let plan = try AppConnect.grantPlan(for: Self.uri(authBindings: [unlimited]), blockTimeMs: Self.blockTimeMs)
        XCTAssertNil(plan.auth[0].totalBudget, "a budget the app did not ask for is not added")
        XCTAssertEqual(plan.auth[0].expiresAt, Self.blockTimeMs + UInt64(AppConnect.v2DefaultLifetime * 1000))
    }

    func testAProposalBelowTheCapsIsKeptAsItIs() throws {
        let plan = try AppConnect.grantPlan(for: Self.uri(authBindings: [Self.groupBinding()]), blockTimeMs: Self.blockTimeMs)
        XCTAssertEqual(plan.auth[0].totalBudget, 50_000_000_000)
        XCTAssertEqual(plan.auth[0].expiresAt, Self.expiresAt)
    }

    // MARK: - Refusals

    func testAStaleOrFutureRequestIsRefusedAsStale() throws {
        let uri = try Self.vectorUri()
        XCTAssertThrowsError(try AppConnect.grantPlan(
            for: uri, blockTimeMs: Self.createdAt + 11 * 60_000)) {
            XCTAssertEqual(($0 as? AppConnect.Refusal)?.status, .stale)
        }
        XCTAssertThrowsError(try AppConnect.grantPlan(
            for: uri, blockTimeMs: Self.createdAt - 3 * 60_000)) {
            XCTAssertEqual(($0 as? AppConnect.Refusal)?.status, .stale)
        }
    }

    /// R12a / AC-09: a future-dated request asks the app for a new code; it
    /// does not blame the phone's clock, which plays no part in the age.
    func testAFutureDatedRequestIsRefusedAskingForANewCodeWithoutBlamingTheClock() throws {
        let uri = try Self.vectorUri()
        XCTAssertThrowsError(try AppConnect.grantPlan(
            for: uri, blockTimeMs: Self.createdAt - 3 * 60_000)) {
            let refusal = $0 as? AppConnect.Refusal
            XCTAssertEqual(refusal?.status, .stale)
            let text = refusal?.reason.lowercased() ?? ""
            XCTAssertFalse(text.contains("clock"), text)
            XCTAssertFalse(text.contains("device"), text)
            XCTAssertTrue(text.contains("new"), "it asks the app for a new code: \(text)")
            XCTAssertFalse(text.contains("expired"), text)
            XCTAssertTrue(text.contains("ahead"), "it gives the reason, the request is dated ahead: \(text)")
            XCTAssertTrue(text.contains("network"), "it names the network's time: \(text)")
        }
    }

    /// The edges of the window, by block time: 10 minutes old and 2 minutes
    /// ahead are answered, a millisecond more is refused.
    func testTheAgeWindowIsJudgedByBlockTimeToTheMillisecond() throws {
        let uri = try Self.vectorUri()
        let minute: UInt64 = 60_000
        for blockTimeMs in [Self.createdAt + 10 * minute, Self.createdAt - 2 * minute] {
            XCTAssertNoThrow(
                try AppConnect.grantPlan(for: uri, blockTimeMs: blockTimeMs), "\(blockTimeMs)")
        }
        for blockTimeMs in [Self.createdAt + 10 * minute + 1, Self.createdAt - 2 * minute - 1] {
            XCTAssertThrowsError(
                try AppConnect.grantPlan(for: uri, blockTimeMs: blockTimeMs), "\(blockTimeMs)") {
                XCTAssertEqual(($0 as? AppConnect.Refusal)?.status, .stale)
            }
        }
    }

    /// A phone clock a year off neither refuses a fresh request nor admits a
    /// stale one: only the block time counts.
    /// The phone's clock is not an input: the age and both expiries of a
    /// granted key are told from the proved block time alone.
    func testTheAgeAndTheExpiriesAreToldFromTheBlockTime() throws {
        let yearLater = Self.createdAt + 365 * Self.dayMilliseconds
        let later = Self.groupBinding(expiresAt: yearLater + 2 * 365 * Self.dayMilliseconds)
        let unlimited = AppConnectRequest.AuthBinding(
            kind: .singleContract, securityLevel: .high, id: Self.appId,
            totalBudget: nil, expiresAt: nil, documentTypeName: nil)
        let plan = try AppConnect.grantPlan(
            for: Self.uri(authBindings: [later, unlimited], createdAt: yearLater), blockTimeMs: yearLater)
        XCTAssertEqual(plan.auth[0].expiresAt, yearLater + 365 * Self.dayMilliseconds)
        XCTAssertEqual(plan.auth[1].expiresAt, yearLater + 90 * Self.dayMilliseconds)
        XCTAssertThrowsError(try AppConnect.grantPlan(
            for: try Self.vectorUri(), blockTimeMs: Self.createdAt + 11 * 60_000)) {
            XCTAssertEqual(($0 as? AppConnect.Refusal)?.status, .stale)
        }
    }

    func testAnExpiryThatDoesNotFitIsTheLargestTime() {
        XCTAssertEqual(AppConnect.expiry(after: AppConnect.v2DefaultLifetime, from: .max - 1), .max)
    }

    /// No proved block time: the wallet cannot judge the age. This is not a
    /// refusal of the request, so the sheet offers to try again.
    func testARequestIsNotJudgedWithoutABlockTime() throws {
        let uri = try Self.vectorUri()
        XCTAssertThrowsError(try AppConnect.grantPlan(for: uri, blockTimeMs: nil)) {
            XCTAssertEqual($0 as? DashConnectPlatformError, .requestAgeUncheckable)
            XCTAssertNil($0 as? AppConnect.Refusal)
        }
    }

    func testAKeyThatWouldAlreadyBeExpiredIsRefused() {
        let expired = Self.groupBinding(expiresAt: Self.createdAt)
        XCTAssertThrowsError(try AppConnect.grantPlan(for: Self.uri(authBindings: [expired]), blockTimeMs: Self.blockTimeMs)) {
            XCTAssertEqual(($0 as? AppConnect.Refusal)?.status, .invalid)
        }
    }

    func testAnEncryptionKeyOnAnotherContractIsRefused() {
        let foreign = AppConnectRequest.EncryptionBinding(contractId: Self.groupId, purpose: .encryption)
        XCTAssertThrowsError(try AppConnect.grantPlan(
            for: Self.uri(authBindings: [Self.groupBinding()], encryptionBindings: [foreign]), blockTimeMs: Self.blockTimeMs)) {
            XCTAssertEqual(($0 as? AppConnect.Refusal)?.status, .invalid)
        }
    }

    func testBindingsMustBelongToTheAppsOwner() throws {
        let plan = try Self.vectorPlan()
        let stranger = Data(repeating: 0x0B, count: 32)
        func refusal(
            groupOwner: Data? = Self.appOwner,
            purposes: Set<KeyPurpose> = [.encryption]
        ) -> AppConnect.Refusal? {
            AppConnect.ownershipRefusal(
                for: plan,
                appOwnerId: Self.appOwner,
                groupOwners: groupOwner.map { [Self.groupId: $0] } ?? [:],
                contractOwners: [Self.appId: Self.appOwner],
                appBoundedKeyPurposes: purposes)
        }
        // The group is the app owner's and DashPay `profile` is allowlisted.
        XCTAssertNil(refusal())
        XCTAssertEqual(refusal(groupOwner: stranger)?.status, .invalid)
        XCTAssertEqual(refusal(groupOwner: nil)?.status, .invalid, "a group that does not exist")
        XCTAssertEqual(refusal(purposes: [])?.status, .invalid, "the app does not take bound encryption keys")
        // A requirement this build cannot read asks for an update, whatever
        // else the contract says.
        let unreadable = AppConnect.ownershipRefusal(
            for: plan, appOwnerId: Self.appOwner, groupOwners: [Self.groupId: Self.appOwner],
            contractOwners: [Self.appId: Self.appOwner], appBoundedKeyPurposes: [],
            appUnreadableKeyPurposes: [.encryption])
        XCTAssertEqual(unreadable?.status, .unsupported)
    }

    func testOnlyDashPayProfileIsAllowedOnAContractTheAppDoesNotOwn() throws {
        func plan(_ name: String) throws -> AppConnect.GrantPlan {
            try AppConnect.grantPlan(for: Self.uri(authBindings: [
                .init(kind: .documentType, securityLevel: .high, id: Self.dashpayContractId,
                      totalBudget: nil, expiresAt: nil, documentTypeName: name),
            ]), blockTimeMs: Self.blockTimeMs)
        }
        func refusal(_ plan: AppConnect.GrantPlan) -> AppConnect.Refusal? {
            AppConnect.ownershipRefusal(
                for: plan, appOwnerId: Self.appOwner, groupOwners: [:],
                contractOwners: [Self.dashpayContractId: Data(repeating: 0, count: 32)],
                appBoundedKeyPurposes: [])
        }
        XCTAssertNil(refusal(try plan("profile")))
        XCTAssertEqual(refusal(try plan("contactRequest"))?.status, .invalid)
    }

    func testAContractBindingMustBeOnTheAppOwnersContract() throws {
        let other = Data(repeating: 0x0C, count: 32)
        let plan = try AppConnect.grantPlan(for: Self.uri(authBindings: [
            .init(kind: .singleContract, securityLevel: .high, id: other,
                  totalBudget: nil, expiresAt: nil, documentTypeName: nil),
        ]), blockTimeMs: Self.blockTimeMs)
        func refusal(owner: Data) -> AppConnect.Refusal? {
            AppConnect.ownershipRefusal(
                for: plan, appOwnerId: Self.appOwner, groupOwners: [:],
                contractOwners: [other: owner], appBoundedKeyPurposes: [])
        }
        XCTAssertNil(refusal(owner: Self.appOwner))
        XCTAssertEqual(refusal(owner: Data(repeating: 0x0B, count: 32))?.status, .invalid)
    }

    func testAnAppContractTheNetworkProvesAbsentIsRefused() async throws {
        let plan = try Self.vectorPlan()
        let absent = try await PlatformDashConnectDataSource.appConnectOwnership(
            plan,
            readContract: { _ in throw SDKError.notFound("no contract") },
            readGroup: { _ in throw SDKError.notFound("no group") })
        XCTAssertEqual(absent.refusal?.status, .invalid)

        do {
            _ = try await PlatformDashConnectDataSource.appConnectOwnership(
                plan,
                readContract: { _ in throw SDKError.timeout("slow") },
                readGroup: { _ in throw SDKError.timeout("slow") })
            XCTFail("A failed read is not an absent contract")
        } catch SDKError.timeout {}
    }

    func testABindingContractTheNetworkProvesAbsentHasNoOwnerSoTheRequestIsRefused() async throws {
        let other = Data(repeating: 0x0C, count: 32)
        let plan = try AppConnect.grantPlan(for: Self.uri(authBindings: [
            .init(kind: .singleContract, securityLevel: .high, id: other,
                  totalBudget: nil, expiresAt: nil, documentTypeName: nil),
        ]), blockTimeMs: Self.blockTimeMs)
        func ownership(_ otherRead: @escaping () throws -> [String: Any]) async throws -> AppConnect.Refusal? {
            try await PlatformDashConnectDataSource.appConnectOwnership(
                plan,
                readContract: { id in
                    id == Self.appId
                        ? ["ownerId": Self.appOwner.toBase58String(), "config": [:] as [String: Any]]
                        : try otherRead()
                },
                readGroup: { _ in throw SDKError.notFound("no group") }).refusal
        }
        let absent = try await ownership { throw SDKError.notFound("no contract") }
        XCTAssertEqual(absent?.status, .invalid)

        do {
            _ = try await ownership { throw SDKError.timeout("slow") }
            XCTFail("A failed read is not an absent contract")
        } catch SDKError.timeout {}
    }

    func testADocumentTypeTheContractDoesNotDefineIsRefused() async throws {
        let other = Data(repeating: 0x0C, count: 32)
        func binding(_ id: Data, _ name: String) -> AppConnectRequest.AuthBinding {
            .init(kind: .documentType, securityLevel: .high, id: id,
                  totalBudget: nil, expiresAt: nil, documentTypeName: name)
        }
        func contract(_ schemas: [String: Any]?) -> [String: Any] {
            var contract: [String: Any] = ["ownerId": Self.appOwner.toBase58String(), "config": [:] as [String: Any]]
            contract["documentSchemas"] = schemas
            return contract
        }
        func refusal(
            _ bindings: [AppConnectRequest.AuthBinding],
            other otherSchemas: [String: Any]? = ["note": [:] as [String: Any]]
        ) async throws -> AppConnect.Refusal? {
            let plan = try AppConnect.grantPlan(for: Self.uri(authBindings: bindings), blockTimeMs: Self.blockTimeMs)
            return try await PlatformDashConnectDataSource.appConnectOwnership(
                plan,
                readContract: { id in
                    contract(id == Self.appId ? ["post": [:] as [String: Any]] : otherSchemas)
                },
                readGroup: { _ in throw SDKError.notFound("no group") }).refusal
        }

        // On the app's own contract, which is never read twice.
        let onApp = try await refusal([binding(Self.appId, "post")])
        XCTAssertNil(onApp)
        let undefinedOnApp = try await refusal([binding(Self.appId, "comment")])
        XCTAssertEqual(undefinedOnApp?.status, .invalid)
        // On another contract of the app's owner.
        let onOther = try await refusal([binding(other, "note")])
        XCTAssertNil(onOther)
        let undefinedOnOther = try await refusal([binding(other, "post")])
        XCTAssertEqual(undefinedOnOther?.status, .invalid)
        // A contract whose document types this build cannot read is not
        // proof the type is missing.
        let unreadable = try await refusal([binding(other, "note")], other: nil)
        XCTAssertEqual(unreadable?.status, .unsupported)
        // DashPay `profile` is allowlisted and never looked up.
        let profile = try await refusal([binding(Self.dashpayContractId, "profile")])
        XCTAssertNil(profile)
    }

    func testASystemContractIsNeverTheAppNorABindingTarget() throws {
        let dpns = try XCTUnwrap(Data.identifier(fromBase58: "GWRSAVFMjXx8HpQFaNJMqBV7MBgMK4br5UESsB4S31Ec"))
        // A request naming DPNS as its app, where DPNS's owner would pass as
        // the app's owner.
        let asApp = AppConnectUri(
            request: AppConnectRequest(
                appEphemeralPubKey: Self.appEphemeralPubKey, appId: dpns, label: "Yappr", identityHint: nil,
                authBindings: [.init(kind: .singleContract, securityLevel: .high, id: dpns,
                                     totalBudget: nil, expiresAt: nil, documentTypeName: nil)],
                connectionId: nil, encryptionBindings: [], isRenewal: false, createdAt: Self.createdAt),
            network: .devnet, callback: nil)
        let appPlan = try AppConnect.grantPlan(for: asApp, blockTimeMs: Self.blockTimeMs)
        XCTAssertEqual(
            AppConnect.ownershipRefusal(
                for: appPlan, appOwnerId: Self.appOwner, groupOwners: [:],
                contractOwners: [dpns: Self.appOwner], appBoundedKeyPurposes: [])?.status,
            .invalid)
        // A binding on DPNS from an app whose owner also owns DPNS's record.
        let bindingPlan = try AppConnect.grantPlan(for: Self.uri(authBindings: [
            .init(kind: .documentType, securityLevel: .high, id: dpns,
                  totalBudget: nil, expiresAt: nil, documentTypeName: "domain"),
        ]), blockTimeMs: Self.blockTimeMs)
        XCTAssertEqual(
            AppConnect.ownershipRefusal(
                for: bindingPlan, appOwnerId: Self.appOwner, groupOwners: [:],
                contractOwners: [dpns: Self.appOwner], appBoundedKeyPurposes: [])?.status,
            .invalid)
    }

    func testAnAppOwnedLikeASystemContractIsRefusedEvenWhenUnlisted() throws {
        // An app whose contract has the all-zero owner of every system
        // contract, as a protocol-15 contract missing from the list would.
        let zeroOwner = AppConnect.systemContractOwnerId
        let plan = try AppConnect.grantPlan(for: Self.uri(authBindings: [
            .init(kind: .documentType, securityLevel: .high, id: Self.appId,
                  totalBudget: nil, expiresAt: nil, documentTypeName: "post"),
        ]), blockTimeMs: Self.blockTimeMs)
        XCTAssertFalse(AppConnect.systemContractIds.contains(Self.appId.toBase58String()))
        XCTAssertEqual(
            AppConnect.ownershipRefusal(
                for: plan, appOwnerId: zeroOwner, groupOwners: [:],
                contractOwners: [Self.appId: zeroOwner], appBoundedKeyPurposes: [])?.status,
            .invalid)
        // The two protocol-15 system contracts are listed.
        XCTAssertTrue(AppConnect.systemContractIds.isSuperset(of: [
            "3iNyoNwjCTkb7XS3RHyWUtLx7pgC6AFAEQNNDHzxqngF", // decision proposals
            "AE6yYq65VdfGCg2MSyV9vV7cWGiFWjbwBuy7THesDh4e", // token market
        ]))
    }

    // MARK: - Re-sending an auth key

    /// A stored bound is read from the store's discriminant, ids and name.
    func testAStoredBoundIsReadFromTheStore() {
        let id = Data(repeating: 1, count: 32)
        XCTAssertEqual(AppConnect.storedBound(boundsKind: 1, boundIds: [id], documentTypeName: nil), .singleContract(id))
        XCTAssertEqual(
            AppConnect.storedBound(boundsKind: 2, boundIds: [id], documentTypeName: "profile"),
            .documentType(contractId: id, name: "profile"))
        XCTAssertEqual(AppConnect.storedBound(boundsKind: 3, boundIds: [id], documentTypeName: nil), .contractGroup(id))
        XCTAssertNil(AppConnect.storedBound(boundsKind: 0, boundIds: nil, documentTypeName: nil))
        XCTAssertNil(AppConnect.storedBound(boundsKind: 2, boundIds: [id], documentTypeName: nil))
        XCTAssertNil(AppConnect.storedBound(boundsKind: 1, boundIds: [Data([1])], documentTypeName: nil))
    }

    // MARK: - Encryption key (wallet rule 7)

    private static let derivedPoint = Data([0x03] + [UInt8](repeating: 0x55, count: 32))

    private func encryptionState(
        _ keys: [ManagedIdentity.IdentityPublicKeyInfo],
        rule: AppConnect.CurrentKeyRule = .latest,
        current: AppConnect.CurrentContractKey?,
        bindings: [AppConnect.KeyBinding]
    ) -> AppConnect.EncryptionKeyState {
        AppConnect.encryptionKeyState(
            derivedPublicKeys: [Self.derivedPoint],
            purpose: .encryption,
            contractId: Self.appId,
            rule: rule,
            currentKey: current,
            currentIdentityPublicKeys: keys,
            bindings: bindings)
    }

    private static func current(_ keyId: UInt32, data: Data, disabled: Bool = false) -> AppConnect.CurrentContractKey {
        AppConnect.CurrentContractKey(keyId: keyId, keyType: .ecdsaSecp256k1, data: data, isDisabled: disabled)
    }

    private static func encryptionKey(_ keyId: UInt32, data: Data, disabled: Bool = false) -> ManagedIdentity.IdentityPublicKeyInfo {
        key(keyId, purpose: .encryption, level: .medium, type: .ecdsaSecp256k1, data: data, disabled: disabled)
    }

    func testTheCurrentKeyIsSentAgainWhenThisWalletMadeIt() {
        let mine = Self.encryptionKey(5, data: Self.derivedPoint)
        XCTAssertEqual(
            encryptionState(
                [mine], current: Self.current(5, data: Self.derivedPoint),
                bindings: [.init(keyId: 5, data: Self.derivedPoint, singleContractId: Self.appId)]),
            .current(keyId: 5))
        // Fetched keys that do not show it yet are behind Platform.
        XCTAssertEqual(encryptionState([], current: Self.current(5, data: Self.derivedPoint), bindings: []), .outOfDate)
    }

    func testTheKeyIsRegisteredWhenTheIdentityHasNoneForTheApp() {
        let elsewhere = Self.encryptionKey(5, data: Data(repeating: 0x66, count: 33))
        let other = Data(repeating: 0x0C, count: 32)
        XCTAssertEqual(encryptionState([], current: nil, bindings: []), .absent)
        // A key bound to another contract is not the app's.
        XCTAssertEqual(
            encryptionState(
                [elsewhere], current: nil,
                bindings: [.init(keyId: 5, data: elsewhere.data, singleContractId: other)]),
            .absent)
        // A disabled current key of another wallet's is a key for the app
        // with none live (DIP rule 2): nothing is registered beside it.
        let disabledTheirs = Self.encryptionKey(9, data: Data(repeating: 0x77, count: 33), disabled: true)
        XCTAssertEqual(
            encryptionState([disabledTheirs], current: Self.current(9, data: disabledTheirs.data, disabled: true), bindings: []),
            .notThisWallets)
    }

    func testAnotherWalletsKeyIsNeitherSentNorReplaced() {
        let theirs = Self.encryptionKey(5, data: Data(repeating: 0x66, count: 33))
        XCTAssertEqual(
            encryptionState(
                [theirs], current: Self.current(5, data: theirs.data),
                bindings: [.init(keyId: 5, data: theirs.data, singleContractId: Self.appId)]),
            .notThisWallets)
        // One the fetched keys do not show yet stops the login.
        XCTAssertEqual(encryptionState([], current: Self.current(5, data: theirs.data), bindings: []), .outOfDate)
        // Behind a disabled current key nothing is registered (DIP rule 2);
        // a live key the store cannot place may be a later one with
        // Platform's read behind, so a later read confirms it.
        let disabledCurrent = Self.encryptionKey(9, data: Data(repeating: 0x77, count: 33), disabled: true)
        XCTAssertEqual(
            encryptionState(
                [theirs, disabledCurrent], current: Self.current(9, data: disabledCurrent.data, disabled: true),
                bindings: []),
            .notThisWalletsIfSettled)
        // With no current key at all, a key bound to the app would be it: a
        // key the store cannot place is bound elsewhere, once a later read
        // agrees.
        XCTAssertEqual(encryptionState([theirs], current: nil, bindings: []), .absentIfSettled)
        // A disabled one the store cannot place is weighed the same way.
        let disabledUnplaced = Self.encryptionKey(7, data: Data(repeating: 0x99, count: 33), disabled: true)
        XCTAssertEqual(encryptionState([disabledUnplaced], rule: .unique, current: nil, bindings: []), .absentIfSettled)
        // Rotating is never part of a login: a disabled key of this wallet's
        // cannot be added again, and is not replaced either.
        let disabledMine = Self.encryptionKey(6, data: Self.derivedPoint, disabled: true)
        XCTAssertEqual(
            encryptionState(
                [disabledMine], current: Self.current(6, data: Self.derivedPoint, disabled: true),
                bindings: [.init(keyId: 6, data: Self.derivedPoint, singleContractId: Self.appId)]),
            .notThisWallets)
    }

    func testThisWalletsKeyIsNotSentOnceANewerKeyIsCurrent() {
        let mine = Self.encryptionKey(5, data: Self.derivedPoint)
        let newer = Self.encryptionKey(9, data: Data(repeating: 0x66, count: 33))
        XCTAssertEqual(
            encryptionState([mine, newer], current: Self.current(9, data: newer.data), bindings: [
                .init(keyId: 5, data: Self.derivedPoint, singleContractId: Self.appId),
                .init(keyId: 9, data: newer.data, singleContractId: Self.appId),
            ]),
            .notThisWalletsIfSettled, "or Platform's read is behind this wallet's key")
    }

    /// Platform keeps naming the last key registered after it is disabled.
    /// This wallet's older live key is not current then, and the app's
    /// verifier would refuse it.
    func testThisWalletsKeyIsNotSentWhenTheLatestKeyWasDisabled() {
        let mine = Self.encryptionKey(5, data: Self.derivedPoint)
        let disabled = Self.encryptionKey(9, data: Data(repeating: 0x66, count: 33), disabled: true)
        let bindings: [AppConnect.KeyBinding] = [
            .init(keyId: 5, data: Self.derivedPoint, singleContractId: Self.appId),
            .init(keyId: 9, data: disabled.data, singleContractId: Self.appId),
        ]
        XCTAssertEqual(
            encryptionState([mine, disabled], current: Self.current(9, data: disabled.data, disabled: true), bindings: bindings),
            .notThisWalletsIfSettled, "registered before the disabled key, or after it with Platform's read behind")
    }

    /// A live current key beside another live key of the app's may be a
    /// read from before that one was registered.
    func testALiveCurrentKeyBesideAnotherKeyOfTheAppsWaitsOnALaterRead() {
        let mine = Self.encryptionKey(5, data: Self.derivedPoint)
        let other = Self.encryptionKey(9, data: Data(repeating: 0x66, count: 33))
        let bindings: [AppConnect.KeyBinding] = [
            .init(keyId: 5, data: Self.derivedPoint, singleContractId: Self.appId),
            .init(keyId: 9, data: other.data, singleContractId: Self.appId),
        ]
        XCTAssertEqual(
            encryptionState([mine, other], current: Self.current(5, data: Self.derivedPoint), bindings: bindings),
            .currentIfSettled(keyId: 5))
        XCTAssertEqual(
            encryptionState([mine, other], current: Self.current(9, data: other.data), bindings: bindings),
            .notThisWalletsIfSettled)
        // So does a disabled one: it may be the key registered last.
        let disabledOther = Self.encryptionKey(9, data: other.data, disabled: true)
        XCTAssertEqual(
            encryptionState([mine, disabledOther], current: Self.current(5, data: Self.derivedPoint), bindings: bindings),
            .currentIfSettled(keyId: 5))
        // Under `unique` there is no second key of the app's to wait on.
        XCTAssertEqual(
            encryptionState([mine, other], rule: .unique, current: Self.current(5, data: Self.derivedPoint), bindings: bindings),
            .current(keyId: 5))
    }

    /// The current key is the one registered last, not the one with the
    /// highest id.
    func testTheCurrentKeyIsTheLastRegisteredNotTheHighestId() {
        let theirs = Self.encryptionKey(9, data: Data(repeating: 0x66, count: 33))
        let mineLower = Self.encryptionKey(3, data: Self.derivedPoint)
        let bindings: [AppConnect.KeyBinding] = [
            .init(keyId: 3, data: Self.derivedPoint, singleContractId: Self.appId),
            .init(keyId: 9, data: theirs.data, singleContractId: Self.appId),
        ]
        XCTAssertEqual(
            encryptionState([theirs, mineLower], current: Self.current(3, data: Self.derivedPoint), bindings: bindings),
            .currentIfSettled(keyId: 3), "the higher id need not be the later key; a later read confirms")
        let mineHigher = Self.encryptionKey(9, data: Self.derivedPoint)
        let theirsLower = Self.encryptionKey(3, data: Data(repeating: 0x66, count: 33))
        XCTAssertEqual(
            encryptionState(
                [mineHigher, theirsLower], current: Self.current(3, data: theirsLower.data),
                bindings: [
                    .init(keyId: 9, data: Self.derivedPoint, singleContractId: Self.appId),
                    .init(keyId: 3, data: theirsLower.data, singleContractId: Self.appId),
                ]),
            .notThisWalletsIfSettled)
    }

    /// The fetched keys and Platform's current key are two reads, and either
    /// can be behind. The login goes ahead only when they agree.
    func testTheFetchedKeysMustAgreeWithPlatformsCurrentKey() {
        let mine = Self.encryptionKey(5, data: Self.derivedPoint)
        let mineBinding = AppConnect.KeyBinding(keyId: 5, data: Self.derivedPoint, singleContractId: Self.appId)
        // This wallet's live key bound to the app, and no current key: a
        // registration Platform's read does not show yet.
        XCTAssertEqual(encryptionState([mine], current: nil, bindings: [mineBinding]), .outOfDate)
        // Platform shows it live, the fetched keys disabled; or the reverse.
        XCTAssertEqual(
            encryptionState(
                [Self.encryptionKey(5, data: Self.derivedPoint, disabled: true)],
                current: Self.current(5, data: Self.derivedPoint), bindings: [mineBinding]),
            .outOfDate)
        XCTAssertEqual(
            encryptionState([mine], current: Self.current(5, data: Self.derivedPoint, disabled: true), bindings: [mineBinding]),
            .outOfDate)
        // The same id with other data.
        XCTAssertEqual(
            encryptionState(
                [Self.encryptionKey(5, data: Data(repeating: 0x66, count: 33))],
                current: Self.current(5, data: Self.derivedPoint), bindings: []),
            .outOfDate)
        // This wallet's key on the identity with no current key at all: it
        // is derived for the app's contract, so Platform's read is behind.
        XCTAssertEqual(encryptionState([mine], current: nil, bindings: []), .outOfDate)
        // So is a disabled key the store places on the app.
        let disabledTheirs = Self.encryptionKey(9, data: Data(repeating: 0x66, count: 33), disabled: true)
        XCTAssertEqual(
            encryptionState(
                [disabledTheirs], rule: .unique, current: nil,
                bindings: [.init(keyId: 9, data: disabledTheirs.data, singleContractId: Self.appId)]),
            .outOfDate)
        // This wallet's key, current and disabled, before the fetched keys
        // show it: never registered again.
        XCTAssertEqual(
            encryptionState([], current: Self.current(6, data: Self.derivedPoint, disabled: true), bindings: []),
            .outOfDate)
    }

    /// A state that holds only if Platform's read is not behind comes to
    /// its plain form once a later read says the same.
    func testAStateThatWaitsOnALaterReadSettles() {
        XCTAssertEqual(AppConnect.EncryptionKeyState.absentIfSettled.settled, .absent)
        XCTAssertEqual(AppConnect.EncryptionKeyState.notThisWalletsIfSettled.settled, .notThisWallets)
        for state: AppConnect.EncryptionKeyState in [.current(keyId: 3), .absent, .notThisWallets, .outOfDate] {
            XCTAssertEqual(state.settled, state)
            XCTAssertFalse(state.needsSettling)
        }
        XCTAssertTrue(AppConnect.EncryptionKeyState.absentIfSettled.needsSettling)
    }

    func testARequirementThisBuildCannotReadIsToldApart() {
        for unreadable: Any in [NSNumber(value: 3), "2", NSNumber(value: 1.5), NSNumber(value: true)] {
            XCTAssertEqual(AppConnect.keyRequirement(unreadable), .unreadable, "\(unreadable)")
        }
    }

    /// Platform never takes a current-key reference away and never gives a
    /// disabled key back: a read that does is behind.
    func testALaterReadThatLosesAKeyIsBehind() {
        let live = Self.current(9, data: Self.derivedPoint)
        let disabled = Self.current(9, data: Self.derivedPoint, disabled: true)
        let other = Self.current(12, data: Data(repeating: 0x66, count: 33))
        XCTAssertEqual(AppConnect.compare(earlier: [.encryption: live], later: [.encryption: live]), .same)
        XCTAssertEqual(AppConnect.compare(earlier: [.encryption: live], later: [:]), .behind)
        XCTAssertEqual(AppConnect.compare(earlier: [.encryption: disabled], later: [.encryption: live]), .behind)
        XCTAssertEqual(AppConnect.compare(earlier: [:], later: [.encryption: live]), .newer([.encryption: live]))
        XCTAssertEqual(AppConnect.compare(earlier: [.encryption: live], later: [.encryption: disabled]), .newer([.encryption: disabled]))
        // Key ids say nothing of order.
        XCTAssertEqual(AppConnect.compare(earlier: [.encryption: live], later: [.encryption: other]), .conflict)
        // Behind for one purpose, newer for another: the earlier key stays.
        XCTAssertEqual(
            AppConnect.compare(earlier: [.encryption: live], later: [.decryption: other]),
            .newer([.encryption: live, .decryption: other]))
    }

    func testAStateThatWaitsSettlesOnlyOnAReadThatSaysTheSame() async throws {
        let theirs = Self.encryptionKey(5, data: Data(repeating: 0x66, count: 33))
        let disabledCurrent = Self.encryptionKey(9, data: Data(repeating: 0x77, count: 33), disabled: true)
        let current = Self.current(9, data: disabledCurrent.data, disabled: true)
        func states(_ keys: [KeyPurpose: AppConnect.CurrentContractKey]) -> [AppConnect.EncryptionKeyState] {
            [encryptionState([theirs, disabledCurrent], current: keys[.encryption], bindings: [])]
        }
        func settle(_ reads: [[KeyPurpose: AppConnect.CurrentContractKey]]) async throws -> [AppConnect.EncryptionKeyState] {
            var reads = reads
            var pauses = 0
            let result = try await AppConnect.settle(
                currentKeys: [.encryption: current], states: states,
                reread: { reads.removeFirst() }, pause: { _ in pauses += 1 })
            XCTAssertLessThanOrEqual(pauses, 3)
            return result
        }
        // Behind a disabled current key the slot is left out (DIP rule 2),
        // once a later read agrees that no newer key is current.
        let agreed = try await settle([[.encryption: current]])
        XCTAssertEqual(agreed, [.notThisWallets])
        // A lagging node that has lost the disabled key does not settle the
        // answer.
        let lagging = try await settle([[:], [:], [:]])
        XCTAssertEqual(lagging, [.outOfDate])
        let caughtUp = try await settle([[:], [.encryption: current]])
        XCTAssertEqual(caughtUp, [.notThisWallets])
        // A read that conflicts makes the answer out of date, even if a
        // later one agrees with the first.
        let unknown = Self.current(11, data: Data(repeating: 0x88, count: 33))
        let conflicting = try await settle([[.encryption: unknown], [.encryption: current]])
        XCTAssertEqual(conflicting, [.outOfDate])
        // A read that fails is set aside.
        var reads: [[KeyPurpose: AppConnect.CurrentContractKey]?] = [nil, [.encryption: current]]
        let afterAFailedRead = try await AppConnect.settle(
            currentKeys: [.encryption: current], states: states,
            reread: {
                guard let read = reads.removeFirst() else { throw SDKError.timeout("read") }
                return read
            },
            pause: { _ in })
        XCTAssertEqual(afterAFailedRead, [.notThisWallets])
        // When no read answers, the failure is thrown.
        do {
            _ = try await AppConnect.settle(
                currentKeys: [.encryption: current], states: states,
                reread: { throw SDKError.timeout("read") }, pause: { _ in })
            XCTFail("expected the read failure")
        } catch SDKError.timeout {
        }
        // A failure called final is thrown at once.
        var finalReads = 0
        do {
            _ = try await AppConnect.settle(
                currentKeys: [.encryption: current], states: states,
                reread: { finalReads += 1; throw SDKError.serializationError("unreadable") }, pause: { _ in },
                isFinal: { _ in true })
            XCTFail("expected the final failure")
        } catch SDKError.serializationError {
        }
        XCTAssertEqual(finalReads, 1)
    }

    /// An answer a newer read gives has to be confirmed by a later one.
    func testAnAnswerFromANewerReadNeedsASecondRead() async throws {
        let mine = Self.encryptionKey(5, data: Self.derivedPoint)
        let mineBinding = AppConnect.KeyBinding(keyId: 5, data: Self.derivedPoint, singleContractId: Self.appId)
        let current = Self.current(5, data: Self.derivedPoint)
        func states(_ keys: [KeyPurpose: AppConnect.CurrentContractKey]) -> [AppConnect.EncryptionKeyState] {
            [encryptionState([mine], current: keys[.encryption], bindings: [mineBinding])]
        }
        func settle(_ reads: [[KeyPurpose: AppConnect.CurrentContractKey]]) async throws -> [AppConnect.EncryptionKeyState] {
            var reads = reads
            return try await AppConnect.settle(
                currentKeys: [:], states: states, reread: { reads.removeFirst() }, pause: { _ in })
        }
        // The first read is behind this wallet's registration.
        let confirmed = try await settle([[.encryption: current], [.encryption: current]])
        XCTAssertEqual(confirmed, [.current(keyId: 5)])
        let unconfirmed = try await settle([[.encryption: current], [:], [:]])
        XCTAssertEqual(unconfirmed, [.outOfDate])
        // An answer the first read gives is taken as it is.
        let taken = try await AppConnect.settle(
            currentKeys: [.encryption: current], states: states, reread: { XCTFail("no reread"); return [:] }, pause: { _ in })
        XCTAssertEqual(taken, [.current(keyId: 5)])
    }

    func testOnlyARequirementThatKeepsACurrentKeyTakesALogin() {
        XCTAssertEqual(AppConnect.keyRequirement(NSNumber(value: 0)), .currentKey(.unique))
        XCTAssertEqual(AppConnect.keyRequirement(NSNumber(value: 2)), .currentKey(.latest))
        XCTAssertEqual(AppConnect.keyRequirement(NSNumber(value: 1)), .noCurrentKey, "Multiple")
        XCTAssertEqual(AppConnect.keyRequirement(NSNull()), .noCurrentKey)
        XCTAssertEqual(AppConnect.keyRequirement(nil), .noCurrentKey)
    }

    /// Under `Unique` the first key registered stays current for good, and
    /// no second key can be added.
    func testAUniqueRequirementNeverTakesASecondKey() {
        let theirs = Self.encryptionKey(4, data: Data(repeating: 0x66, count: 33), disabled: true)
        XCTAssertEqual(
            encryptionState([theirs], rule: .unique, current: Self.current(4, data: theirs.data, disabled: true), bindings: []),
            .notThisWallets)
        let disabledMine = Self.encryptionKey(4, data: Self.derivedPoint, disabled: true)
        XCTAssertEqual(
            encryptionState(
                [disabledMine], rule: .unique, current: Self.current(4, data: Self.derivedPoint, disabled: true), bindings: []),
            .notThisWallets)
        let mine = Self.encryptionKey(4, data: Self.derivedPoint)
        XCTAssertEqual(
            encryptionState([mine], rule: .unique, current: Self.current(4, data: Self.derivedPoint), bindings: []),
            .current(keyId: 4))
        XCTAssertEqual(encryptionState([], rule: .unique, current: nil, bindings: []), .absent)
    }

    func testTheCurrentKeyIsReadFromTheContractKeysResponse() throws {
        let identityId = "identity"
        func read(_ response: [String: Any], _ purpose: KeyPurpose = .encryption) throws -> AppConnect.CurrentContractKey? {
            try AppConnect.currentContractKey(from: response, identityId: identityId, purpose: purpose)
        }
        let key: [String: Any] = [
            "id": 9, "type": 0, "data": Self.derivedPoint.toHexString(), "purpose": 1,
            "security_level": 2, "read_only": false, "disabled_at": NSNull(),
        ]
        XCTAssertEqual(
            try read([identityId: ["encryption": key]]),
            AppConnect.CurrentContractKey(keyId: 9, keyType: .ecdsaSecp256k1, data: Self.derivedPoint, isDisabled: false))
        var disabled = key
        disabled["disabled_at"] = 1_700_000_000_000
        XCTAssertEqual(try read([identityId: ["encryption": disabled]])?.isDisabled, true)
        XCTAssertNil(try read([identityId: ["encryption": NSNull()]]), "proved absent")
        XCTAssertEqual(try read([identityId: ["decryption": key]], .decryption)?.keyId, 9)
        // A response that leaves the identity or the purpose out says nothing.
        XCTAssertThrowsError(try read([:]))
        XCTAssertThrowsError(try read([identityId: [:] as [String: Any]]))
        XCTAssertThrowsError(try read([identityId: ["decryption": key]]))
        var unreadable = key
        unreadable["data"] = "zz"
        XCTAssertThrowsError(try read([identityId: ["encryption": unreadable]]))
        XCTAssertThrowsError(try read([identityId: ["authentication": key]], .authentication))
        // Numbers are read only when exact.
        for (field, value) in [("type", 256), ("id", -1), ("id", 4_294_967_301)] as [(String, Any)] {
            var wrong = key
            wrong[field] = value
            XCTAssertThrowsError(try read([identityId: ["encryption": wrong]]), "\(field) = \(value)")
        }
        var fractional = key
        fractional["id"] = 1.5
        XCTAssertThrowsError(try read([identityId: ["encryption": fractional]]))
        var boolean = key
        boolean["id"] = true
        XCTAssertThrowsError(try read([identityId: ["encryption": boolean]]))
    }

    /// The response as the SDK's JSON text decodes, not as Swift literals.
    func testTheCurrentKeyIsReadFromTheSDKsJSONText() throws {
        let text = """
        {"identity":{"encryption":{"id":9,"type":0,"data":"\(Self.derivedPoint.toHexString())","purpose":1,\
        "security_level":2,"read_only":false,"disabled_at":null},"decryption":null}}
        """
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(
            try AppConnect.currentContractKey(from: response, identityId: "identity", purpose: .encryption),
            AppConnect.CurrentContractKey(keyId: 9, keyType: .ecdsaSecp256k1, data: Self.derivedPoint, isDisabled: false))
        XCTAssertNil(try AppConnect.currentContractKey(from: response, identityId: "identity", purpose: .decryption))
    }

    // MARK: - URI and callback

    func testOnlyAVersionTwoKeyUriIsAnAppConnectRequest() {
        XCTAssertTrue(DashConnectUri.isAppConnectUri(Self.requestUri))
        XCTAssertFalse(DashConnectUri.isAppConnectUri("dash-key:abc?n=d&v=1"))
        XCTAssertFalse(DashConnectUri.isAppConnectUri("dash-st:abc?n=d&v=2"))
        XCTAssertFalse(DashConnectUri.isAppConnectUri("dash-key:abc?n=d&v=22"))
        // Read as the v2 parser reads the query: form-decoded.
        XCTAssertTrue(DashConnectUri.isAppConnectUri("dash-key:abc?n=d&v=%32"))
        XCTAssertTrue(DashConnectUri.isAppConnectUri("dash-key:abc?n=d&%76=2"))
        XCTAssertFalse(DashConnectUri.isAppConnectUri("dash-key:abc?n=d&v"))
    }

    /// The brand map only names an app: a known app's request that returns
    /// to a host the app does not have is accepted with a warning, like one
    /// without a callback or one for an app the wallet does not know.
    func testAKnownAppsRequestThatReturnsElsewhereIsWarnedAbout() {
        XCTAssertEqual(
            AppConnect.originWarning(callbackHost: "yap.pr.example.com", brandHost: "yap.pr"),
            .returnsElsewhere(callbackHost: "yap.pr.example.com"))
        XCTAssertEqual(
            AppConnect.originWarning(callbackHost: "notyap.pr", brandHost: "yap.pr"),
            .returnsElsewhere(callbackHost: "notyap.pr"))
        XCTAssertNil(AppConnect.originWarning(callbackHost: "yap.pr", brandHost: "yap.pr"))
        XCTAssertNil(AppConnect.originWarning(callbackHost: "www.yap.pr", brandHost: "yap.pr"))
        XCTAssertEqual(AppConnect.originWarning(callbackHost: nil, brandHost: "yap.pr"), .noCallback(website: "yap.pr"))
        XCTAssertEqual(AppConnect.originWarning(callbackHost: "example.com", brandHost: nil), .unknownApp)
        XCTAssertEqual(
            DashConnectFallbackAppMetadata.brandHost(contractId: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F"), "yap.pr")
        XCTAssertNil(DashConnectFallbackAppMetadata.brandHost(contractId: "GWRSAVFMjXx8HpQFaNJMqBV7MBgMK4br5UESsB4S31Ec"))
    }

    func testTheCallbackKeepsItsQueryAndAddsTheStatus() throws {
        let callback = try XCTUnwrap(Self.vectorUri().callback)
        XCTAssertEqual(
            AppConnect.callbackURL(callback, status: .ok)?.absoluteString,
            "https://yap.pr/connect?r=d77dc0da9df83a47755a15c42c5d9db9d7a7fd62&ac=ok")
        XCTAssertEqual(
            AppConnect.callbackURL(try XCTUnwrap(URL(string: "https://yap.pr/connect")), status: .declined)?.absoluteString,
            "https://yap.pr/connect?ac=declined")
    }

    func testARefusalKeepsTheDecodersStatus() {
        XCTAssertEqual(AppConnect.Refusal(.unsupported("binding kind 3")).status, .unsupported)
        XCTAssertEqual(AppConnect.Refusal(.invalid("label")).status, .invalid)
    }

    func testOnlyAGrantPlanCanBeApproved() throws {
        XCTAssertTrue(AppConnect.Login.appConnect(try Self.vectorPlan()).isApprovable)
        XCTAssertFalse(AppConnect.Login.unresolved.isApprovable)
        XCTAssertFalse(AppConnect.Login.refused(.init(.stale, "old")).isApprovable)
    }

    /// Before an approval the wallet does not know yet whether it can give
    /// the app a key for messages (the current key may not be this
    /// wallet's, or none is live): the approve sheet says it may.
    func testTheApproveSheetSaysMessagesMayBeGivenNotThatTheyAre() throws {
        let plan = try Self.vectorPlan()
        XCTAssertFalse(plan.encryption.isEmpty)
        let lines = DashConnectPermissionText.requested(plan, appLabel: "App")
        XCTAssertTrue(lines.contains(DashConnectPermissionText.mayReceiveMessages(appLabel: "App")))
        XCTAssertFalse(lines.contains(DashConnectPermissionText.receivesMessages(appLabel: "App")))
        let noMessages = try AppConnect.grantPlan(for: Self.uri(authBindings: [Self.groupBinding()]), blockTimeMs: Self.blockTimeMs)
        XCTAssertFalse(DashConnectPermissionText.requested(noMessages, appLabel: "App")
            .contains(DashConnectPermissionText.mayReceiveMessages(appLabel: "App")))
    }
}

private extension AppConnect.KeyBinding {
    func disabled() -> AppConnect.KeyBinding {
        var binding = self
        binding.isDisabled = true
        return binding
    }
}
