import XCTest
@testable import dashpay
@testable import SwiftDashSDK

final class PlatformDashConnectDataSourceTests: XCTestCase {
    func testSelectDocumentSigningKeyIdPrefersHighOverMaster() throws {
        let selected = try PlatformDashConnectDataSource.selectDocumentSigningKeyId(
            from: [
                makeSigningCandidate(keyId: 1, securityLevel: .master),
                makeSigningCandidate(keyId: 2, securityLevel: .high),
            ]
        )

        XCTAssertEqual(selected, 2)
    }

    func testSelectDocumentSigningKeyIdFallsBackToCriticalWhenHighMissing() throws {
        let selected = try PlatformDashConnectDataSource.selectDocumentSigningKeyId(
            from: [
                makeSigningCandidate(keyId: 1, securityLevel: .master),
                makeSigningCandidate(keyId: 3, securityLevel: .critical),
            ]
        )

        XCTAssertEqual(selected, 3)
    }

    func testSelectDocumentSigningKeyIdPrefersHighOverCritical() throws {
        let selected = try PlatformDashConnectDataSource.selectDocumentSigningKeyId(
            from: [
                makeSigningCandidate(keyId: 1, securityLevel: .master),
                makeSigningCandidate(keyId: 4, securityLevel: .critical),
                makeSigningCandidate(keyId: 5, securityLevel: .high),
            ]
        )

        XCTAssertEqual(selected, 5)
    }

    func testSelectDocumentSigningKeyIdThrowsWhenOnlyMasterExists() {
        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.selectDocumentSigningKeyId(
                from: [makeSigningCandidate(keyId: 1, securityLevel: .master)]
            )
        ) { error in
            XCTAssertEqual(error as? DashConnectPlatformError, .noAuthenticationKey)
        }
    }

    func testSelectDocumentSigningKeyIdIgnoresDisabledEligibleKeys() throws {
        let selected = try PlatformDashConnectDataSource.selectDocumentSigningKeyId(
            from: [
                makeSigningCandidate(keyId: 1, securityLevel: .high, disabledAt: 123),
                makeSigningCandidate(keyId: 2, securityLevel: .critical),
            ]
        )

        XCTAssertEqual(selected, 2)
    }

    func testSelectDocumentSigningKeyIdBreaksTiesByLowestKeyId() throws {
        let selected = try PlatformDashConnectDataSource.selectDocumentSigningKeyId(
            from: [
                makeSigningCandidate(keyId: 9, securityLevel: .high),
                makeSigningCandidate(keyId: 4, securityLevel: .high),
                makeSigningCandidate(keyId: 7, securityLevel: .high),
            ]
        )

        XCTAssertEqual(selected, 4)
    }

    func testMakeConnectionRequestCarriesExistingConnectionForMatchingContract() async {
        let existing = DAppConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            name: "Yappr",
            url: "yap.pr",
            status: .active,
            updatedAt: Date(timeIntervalSince1970: 1_773_132_300)
        )
        let dataSource = PlatformDashConnectDataSource(
            store: TestDashConnectStore(initialConnections: [existing])
        )

        let request = await dataSource.makeConnectionRequest(from: MockDashConnectDataSource.sampleLoginRequest)

        XCTAssertEqual(request.existingConnection, existing)
        XCTAssertEqual(request.appContractId, existing.id)
    }

    func testMakeConnectionRequestCarriesApprovedConnection() async {
        let existing = DAppConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            name: "Yappr",
            url: "yap.pr",
            status: .approved,
            updatedAt: Date(timeIntervalSince1970: 1_773_132_300)
        )
        let dataSource = PlatformDashConnectDataSource(
            store: TestDashConnectStore(initialConnections: [existing])
        )

        let request = await dataSource.makeConnectionRequest(from: MockDashConnectDataSource.sampleLoginRequest)

        XCTAssertEqual(request.existingConnection, existing)
    }

    func testMakeConnectionRequestReturnsNilForUnknownContract() async throws {
        let existing = DAppConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            name: "Yappr",
            url: "yap.pr",
            status: .active,
            updatedAt: Date(timeIntervalSince1970: 1_773_132_300)
        )
        let dataSource = PlatformDashConnectDataSource(
            store: TestDashConnectStore(initialConnections: [existing])
        )
        let request = try makeLoginRequest(
            contractId: Data(repeating: 0x44, count: 32),
            label: "Something else"
        )

        let connectionRequest = await dataSource.makeConnectionRequest(from: request)

        XCTAssertNil(connectionRequest.existingConnection)
    }

    func testRealKeyRegistrationFixtureParsesWithNilContractBounds() throws {
        let wallet = ManagedPlatformWallet(handle: 0, walletId: Data(repeating: 0x00, count: 32))
        let bytes = try XCTUnwrap(Data(hex: Self.realKeyRegistrationFixtureHex))
        let expectedIdentityId = try XCTUnwrap(
            Data(hex: "89fd6ddba75136a4fea02dc7d89ef0ca5bcc32ccf12fb8da6a1a03740567ae72")
        )
        let expectedAuthHash160 = try XCTUnwrap(
            Data(hex: "5e24e38a86e720f61757647996957e322686abb7")
        )
        let expectedEncryptionPublicKey = try XCTUnwrap(
            Data(hex: "035e8cfb0785b54e8902a3dc17bdaad8a5738c6019a18ebc527f79d1c64a27826a")
        )

        let parsed = try wallet.parseIdentityUpdateTransition(bytes)

        XCTAssertEqual(parsed.identityId, expectedIdentityId)
        XCTAssertEqual(parsed.disablePublicKeyIds, [])
        XCTAssertEqual(parsed.addPublicKeys.count, 2)

        let authKey = parsed.addPublicKeys[0]
        XCTAssertEqual(authKey.keyId, 6)
        XCTAssertEqual(authKey.purpose, .authentication)
        XCTAssertEqual(authKey.securityLevel, .high)
        XCTAssertEqual(authKey.keyType, .ecdsaHash160)
        XCTAssertNil(authKey.contractBounds)
        XCTAssertEqual(authKey.pubkeyBytes, expectedAuthHash160)

        let encryptionKey = parsed.addPublicKeys[1]
        XCTAssertEqual(encryptionKey.keyId, 7)
        XCTAssertEqual(encryptionKey.purpose, .encryption)
        XCTAssertEqual(encryptionKey.securityLevel, .medium)
        XCTAssertEqual(encryptionKey.keyType, .ecdsaSecp256k1)
        XCTAssertNil(encryptionKey.contractBounds)
        XCTAssertEqual(encryptionKey.pubkeyBytes, expectedEncryptionPublicKey)
    }

    func testPlatformWalletParserRoundTripsTaggedAndTaglessIdentityUpdateTransition() throws {
        let wallet = ManagedPlatformWallet(handle: 0, walletId: Data(repeating: 0x00, count: 32))
        let taggedBytes = try XCTUnwrap(Data(base64Encoded: Self.taggedIdentityUpdateFixtureBase64))
        let taglessBytes = try XCTUnwrap(Data(base64Encoded: Self.taglessIdentityUpdateFixtureBase64))

        let tagged = try wallet.parseIdentityUpdateTransition(taggedBytes)
        let tagless = try wallet.parseIdentityUpdateTransition(taglessBytes)

        XCTAssertEqual(tagged.identityId, Data(repeating: 0x11, count: 32))
        XCTAssertEqual(tagged.addPublicKeys.map(\.keyId), [17, 18])
        XCTAssertEqual(tagged.disablePublicKeyIds, [4, 8])
        XCTAssertEqual(tagged.addPublicKeys[0].purpose, .authentication)
        XCTAssertEqual(tagged.addPublicKeys[1].purpose, .encryption)
        XCTAssertEqual(
            tagged.addPublicKeys[1].contractBounds,
            .singleContractDocumentType(
                id: Data(repeating: 0x44, count: 32),
                documentTypeName: "profile"
            )
        )

        XCTAssertEqual(tagless.identityId, tagged.identityId)
        XCTAssertEqual(tagless.addPublicKeys.map(\.keyId), tagged.addPublicKeys.map(\.keyId))
        XCTAssertEqual(tagless.disablePublicKeyIds, tagged.disablePublicKeyIds)

        let appParser = PlatformWalletDashConnectKeyRegistrationParser { bytes in
            try wallet.parseIdentityUpdateTransition(bytes)
        }
        let appTransition = try appParser.parse(taglessBytes)
        XCTAssertEqual(appTransition.identityId, tagged.identityId)
        XCTAssertEqual(appTransition.addPublicKeys.map(\.keyId), [17, 18])
        XCTAssertEqual(appTransition.disablePublicKeyIds, [4, 8])
    }

    func testBuildLoginKeyResponseDraftProducesExactFieldsAndWipesEphemeralPrivateKey() throws {
        let loginKey = Data(repeating: 0x11, count: 32)
        let appContractId = Data(repeating: 0xcd, count: 32)
        let appEphemeralPubKey = try Secp256k1.compressedPublicKey(privateKey: Data(repeating: 0x01, count: 32))
        var walletEphemeralPrivateKey = Data(repeating: 0x02, count: 32)
        let fixedPayload = Data(repeating: 0xaa, count: 60)

        let draft = try PlatformDashConnectDataSource.buildLoginKeyResponseDraft(
            loginKey: loginKey,
            appContractId: appContractId,
            appEphemeralPubKey: appEphemeralPubKey,
            walletEphemeralPrivateKey: &walletEphemeralPrivateKey,
            encryptLoginKey: { loginKeyArg, walletPrivArg, appPubArg in
                XCTAssertEqual(loginKeyArg, loginKey)
                XCTAssertEqual(walletPrivArg, Data(repeating: 0x02, count: 32))
                XCTAssertEqual(appPubArg, appEphemeralPubKey)
                return fixedPayload
            }
        )

        XCTAssertEqual(
            draft.properties["contractId"]?.base as? String,
            appContractId.toBase58String()
        )
        XCTAssertEqual(
            draft.properties["appEphemeralPubKeyHash"]?.base as? String,
            KeyExchangeCrypto.hash160(appEphemeralPubKey).toHexString()
        )
        XCTAssertEqual(
            draft.properties["walletEphemeralPubKey"]?.base as? String,
            try Secp256k1.compressedPublicKey(privateKey: Data(repeating: 0x02, count: 32)).toHexString()
        )
        XCTAssertEqual(
            draft.properties["encryptedPayload"]?.base as? String,
            fixedPayload.toHexString()
        )
        XCTAssertEqual(draft.properties["keyIndex"]?.base as? Int, LoginKeyDerivation.defaultKeyIndex)
        XCTAssertEqual(draft.encryptedPayload.count, 60)
        XCTAssertEqual(walletEphemeralPrivateKey, Data(repeating: 0x00, count: 32))
    }

    func testValidateKeyRegistrationRejectsTransitionForDifferentIdentity() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        let transition = try makeValidTransition(
            identityId: Data(repeating: 0x55, count: 32),
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )

        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.validateKeyRegistration(
                transition,
                chainKeyPrivateBytes: chainKey,
                identityId: identityId,
                appContractId: appContractId
            )
        ) { error in
            guard let error = error as? DashConnectPlatformError,
                  case .keyRegistrationWrongIdentity = error else {
                return XCTFail("Expected wrong identity error, got \(error)")
            }
        }
    }

    func testValidateKeyRegistrationRejectsAttackerAddedKey() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        var transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )

        let attackerPublicKey = try Secp256k1.compressedPublicKey(privateKey: Data(repeating: 0x66, count: 32))
        transition = DashConnectKeyRegistrationTransition(
            identityId: transition.identityId,
            addPublicKeys: [
                DashConnectKeyRegistrationKey(
                    keyId: transition.addPublicKeys[0].keyId,
                    keyType: transition.addPublicKeys[0].keyType,
                    purpose: transition.addPublicKeys[0].purpose,
                    securityLevel: transition.addPublicKeys[0].securityLevel,
                    publicKeyData: KeyExchangeCrypto.hash160(attackerPublicKey),
                    contractBounds: transition.addPublicKeys[0].contractBounds
                ),
                transition.addPublicKeys[1],
            ],
            disablePublicKeyIds: []
        )

        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.validateKeyRegistration(
                transition,
                chainKeyPrivateBytes: chainKey,
                identityId: identityId,
                appContractId: appContractId
            )
        ) { error in
            guard let error = error as? DashConnectPlatformError,
                  case .keyRegistrationMismatchedDerivedKey(.authentication) = error else {
                return XCTFail("Expected mismatched authentication key error, got \(error)")
            }
        }
    }

    func testValidateKeyRegistrationAcceptsNilContractBoundsWhenDerivedKeysMatch() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        let transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )

        let validated = try PlatformDashConnectDataSource.validateKeyRegistration(
            transition,
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        XCTAssertEqual(validated.authenticationKey, transition.addPublicKeys[0])
        XCTAssertEqual(validated.encryptionKey, transition.addPublicKeys[1])
    }

    func testValidateKeyRegistrationRejectsDerivedKeysForDifferentContract() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let transitionContractId = Data(repeating: 0x44, count: 32)
        let actualContractId = Data(repeating: 0x55, count: 32)
        let transition = try makeValidTransition(
            identityId: identityId,
            appContractId: transitionContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )

        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.validateKeyRegistration(
                transition,
                chainKeyPrivateBytes: chainKey,
                identityId: identityId,
                appContractId: actualContractId
            )
        ) { error in
            guard let error = error as? DashConnectPlatformError,
                  case .keyRegistrationMismatchedDerivedKey = error else {
                return XCTFail("Expected mismatched derived key error, got \(error)")
            }
        }
    }

    func testValidateKeyRegistrationRejectsAuthenticationKeyUsingRawSecp256k1Encoding() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        var transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )

        let loginKey = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )
        let authPrivateKey = try KeyExchangeCrypto.deriveAuthPrivateKey(loginKey: loginKey, identityId: identityId)
        let authPublicKey = try Secp256k1.compressedPublicKey(privateKey: authPrivateKey)
        transition = DashConnectKeyRegistrationTransition(
            identityId: transition.identityId,
            addPublicKeys: [
                DashConnectKeyRegistrationKey(
                    keyId: transition.addPublicKeys[0].keyId,
                    keyType: .ecdsaSecp256k1,
                    purpose: .authentication,
                    securityLevel: .high,
                    publicKeyData: authPublicKey,
                    contractBounds: nil
                ),
                transition.addPublicKeys[1],
            ],
            disablePublicKeyIds: []
        )

        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.validateKeyRegistration(
                transition,
                chainKeyPrivateBytes: chainKey,
                identityId: identityId,
                appContractId: appContractId
            )
        ) { error in
            guard let error = error as? DashConnectPlatformError,
                  case .keyRegistrationMismatchedDerivedKey(.authentication) = error else {
                return XCTFail("Expected authentication mismatch error, got \(error)")
            }
        }
    }

    func testValidateKeyRegistrationRejectsAuthenticationKeyUsingRawPublicKeyData() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        var transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )

        let loginKey = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )
        let authPrivateKey = try KeyExchangeCrypto.deriveAuthPrivateKey(loginKey: loginKey, identityId: identityId)
        let authPublicKey = try Secp256k1.compressedPublicKey(privateKey: authPrivateKey)
        transition = DashConnectKeyRegistrationTransition(
            identityId: transition.identityId,
            addPublicKeys: [
                DashConnectKeyRegistrationKey(
                    keyId: transition.addPublicKeys[0].keyId,
                    keyType: .ecdsaHash160,
                    purpose: .authentication,
                    securityLevel: .high,
                    publicKeyData: authPublicKey,
                    contractBounds: nil
                ),
                transition.addPublicKeys[1],
            ],
            disablePublicKeyIds: []
        )

        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.validateKeyRegistration(
                transition,
                chainKeyPrivateBytes: chainKey,
                identityId: identityId,
                appContractId: appContractId
            )
        ) { error in
            guard let error = error as? DashConnectPlatformError,
                  case .keyRegistrationMismatchedDerivedKey(.authentication) = error else {
                return XCTFail("Expected authentication mismatch error, got \(error)")
            }
        }
    }

    func testPendingApprovedConnectionThrowsWhenNothingAwaitsKeyRegistration() {
        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.pendingApprovedConnectionForKeyRegistration(
                in: [
                    DAppConnection(
                        id: "A",
                        name: "Active App",
                        url: "active.app",
                        status: .active,
                        updatedAt: Date(timeIntervalSince1970: 10)
                    ),
                    DAppConnection(
                        id: "B",
                        name: "Another Active App",
                        url: "active-two.app",
                        status: .active,
                        updatedAt: Date(timeIntervalSince1970: 20)
                    ),
                ],
                boundContractId: nil
            )
        ) { error in
            XCTAssertEqual(error as? DashConnectPlatformError, .noApprovedConnectionAwaitingKeyRegistration)
        }
    }

    func testPendingApprovedConnectionErrorTellsUserToScanLoginQrFirst() {
        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.pendingApprovedConnectionForKeyRegistration(in: [], boundContractId: nil)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "There is no login awaiting key registration — scan the app's login QR first."
            )
        }
    }

    private static let appAId = "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F"
    private static let appBId = "7W6u4NgW63FPUuW8EnTbYzD4KybNQD5n7CUDWydJY234"

    private func approvedPair() -> (appA: DAppConnection, appB: DAppConnection, active: DAppConnection) {
        (
            DAppConnection(
                id: Self.appAId,
                name: "App A",
                url: "a.app",
                status: .approved,
                updatedAt: Date(timeIntervalSince1970: 10)
            ),
            DAppConnection(
                id: Self.appBId,
                name: "App B",
                url: "b.app",
                status: .approved,
                // Approved after A, so recency alone would always pick B.
                updatedAt: Date(timeIntervalSince1970: 30)
            ),
            DAppConnection(
                id: "active",
                name: "Active",
                url: "active.app",
                status: .active,
                updatedAt: Date(timeIntervalSince1970: 40)
            )
        )
    }

    /// Scanning app A's transition while app B is the newer approval used to
    /// derive B's keys and reject A. The contract bounds name A, so A wins.
    func testPendingApprovedConnectionFollowsContractBoundsNotRecency() throws {
        let (appA, appB, active) = approvedPair()
        let boundToA = try XCTUnwrap(Data.identifier(fromBase58: Self.appAId))

        let selected = try PlatformDashConnectDataSource.pendingApprovedConnectionForKeyRegistration(
            in: [appA, active, appB],
            boundContractId: boundToA
        )

        XCTAssertEqual(selected, appA)
    }

    func testPendingApprovedConnectionRejectsBoundsMatchingNoApprovedConnection() throws {
        let (appA, appB, _) = approvedPair()
        let unrelated = Data(repeating: 0x77, count: 32)

        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.pendingApprovedConnectionForKeyRegistration(
                in: [appA, appB],
                boundContractId: unrelated
            )
        ) { error in
            XCTAssertEqual(error as? DashConnectPlatformError, .noApprovedConnectionAwaitingKeyRegistration)
        }
    }

    /// An unbounded transition identifies no app, so with two approvals there is
    /// nothing to choose on — guessing is what produced the wrong-key failure.
    func testPendingApprovedConnectionRejectsAmbiguousUnboundedTransition() throws {
        let (appA, appB, active) = approvedPair()

        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.pendingApprovedConnectionForKeyRegistration(
                in: [appA, active, appB],
                boundContractId: nil
            )
        ) { error in
            XCTAssertEqual(error as? DashConnectPlatformError, .ambiguousKeyRegistrationConnection)
        }
    }

    func testPendingApprovedConnectionTakesTheOnlyApprovalWhenUnbounded() throws {
        let (appA, _, active) = approvedPair()

        let selected = try PlatformDashConnectDataSource.pendingApprovedConnectionForKeyRegistration(
            in: [appA, active],
            boundContractId: nil
        )

        XCTAssertEqual(selected, appA)
    }

    func testMissingKeyRegistrationKeysReturnsEmptyWhenBothKeysAlreadyRegistered() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        let transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )
        let validated = try PlatformDashConnectDataSource.validateKeyRegistration(
            transition,
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        let currentKeys = [
            makeIdentityPublicKeyInfo(
                keyId: 100,
                purpose: .authentication,
                securityLevel: .high,
                keyType: .ecdsaHash160,
                data: validated.authenticationKey.publicKeyData
            ),
            makeIdentityPublicKeyInfo(
                keyId: 101,
                purpose: .encryption,
                securityLevel: .medium,
                keyType: .ecdsaSecp256k1,
                data: validated.encryptionKey.publicKeyData
            ),
        ]

        XCTAssertEqual(
            PlatformDashConnectDataSource.missingKeyRegistrationKeys(
                validated,
                currentIdentityPublicKeys: currentKeys
            ),
            []
        )
    }

    func testHasRegisteredLoginKeysReturnsTrueWhenBothKeysAreRegistered() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        let transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )
        let validated = try PlatformDashConnectDataSource.validateKeyRegistration(
            transition,
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        let currentKeys = [
            makeIdentityPublicKeyInfo(
                keyId: 100,
                purpose: .authentication,
                securityLevel: .high,
                keyType: .ecdsaHash160,
                data: validated.authenticationKey.publicKeyData
            ),
            makeIdentityPublicKeyInfo(
                keyId: 101,
                purpose: .encryption,
                securityLevel: .medium,
                keyType: .ecdsaSecp256k1,
                data: validated.encryptionKey.publicKeyData
            ),
        ]

        XCTAssertTrue(
            PlatformDashConnectDataSource.hasRegisteredLoginKeys(
                authenticationPublicKeyHash160: validated.authenticationKey.publicKeyData,
                encryptionPublicKey: validated.encryptionKey.publicKeyData,
                currentIdentityPublicKeys: currentKeys
            )
        )
    }

    func testMissingKeyRegistrationKeysReturnsOnlyMissingEncryptionKey() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        let transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )
        let validated = try PlatformDashConnectDataSource.validateKeyRegistration(
            transition,
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        let currentKeys = [
            makeIdentityPublicKeyInfo(
                keyId: 100,
                purpose: .authentication,
                securityLevel: .high,
                keyType: .ecdsaHash160,
                data: validated.authenticationKey.publicKeyData
            )
        ]

        XCTAssertEqual(
            PlatformDashConnectDataSource.missingKeyRegistrationKeys(
                validated,
                currentIdentityPublicKeys: currentKeys
            ),
            [validated.encryptionKey]
        )
    }

    func testHasRegisteredLoginKeysReturnsFalseWhenAuthenticationKeyIsMissing() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        let transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )
        let validated = try PlatformDashConnectDataSource.validateKeyRegistration(
            transition,
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        let currentKeys = [
            makeIdentityPublicKeyInfo(
                keyId: 101,
                purpose: .encryption,
                securityLevel: .medium,
                keyType: .ecdsaSecp256k1,
                data: validated.encryptionKey.publicKeyData
            ),
        ]

        XCTAssertFalse(
            PlatformDashConnectDataSource.hasRegisteredLoginKeys(
                authenticationPublicKeyHash160: validated.authenticationKey.publicKeyData,
                encryptionPublicKey: validated.encryptionKey.publicKeyData,
                currentIdentityPublicKeys: currentKeys
            )
        )
    }

    func testMissingKeyRegistrationKeysTreatsDisabledMatchingKeyAsMissing() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        let transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )
        let validated = try PlatformDashConnectDataSource.validateKeyRegistration(
            transition,
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        let currentKeys = [
            makeIdentityPublicKeyInfo(
                keyId: 100,
                purpose: .authentication,
                securityLevel: .high,
                keyType: .ecdsaHash160,
                data: validated.authenticationKey.publicKeyData,
                disabledAt: 123
            ),
            makeIdentityPublicKeyInfo(
                keyId: 101,
                purpose: .encryption,
                securityLevel: .medium,
                keyType: .ecdsaSecp256k1,
                data: validated.encryptionKey.publicKeyData
            ),
        ]

        XCTAssertEqual(
            PlatformDashConnectDataSource.missingKeyRegistrationKeys(
                validated,
                currentIdentityPublicKeys: currentKeys
            ),
            [validated.authenticationKey]
        )
    }

    func testHasRegisteredLoginKeysReturnsFalseWhenEncryptionKeyIsMissing() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        let transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )
        let validated = try PlatformDashConnectDataSource.validateKeyRegistration(
            transition,
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        let currentKeys = [
            makeIdentityPublicKeyInfo(
                keyId: 100,
                purpose: .authentication,
                securityLevel: .high,
                keyType: .ecdsaHash160,
                data: validated.authenticationKey.publicKeyData
            ),
        ]

        XCTAssertFalse(
            PlatformDashConnectDataSource.hasRegisteredLoginKeys(
                authenticationPublicKeyHash160: validated.authenticationKey.publicKeyData,
                encryptionPublicKey: validated.encryptionKey.publicKeyData,
                currentIdentityPublicKeys: currentKeys
            )
        )
    }

    func testHasRegisteredLoginKeysReturnsFalseWhenMatchingKeyIsDisabled() throws {
        let chainKey = Data(repeating: 0x22, count: 32)
        let identityId = Data(repeating: 0x33, count: 32)
        let appContractId = Data(repeating: 0x44, count: 32)
        let transition = try makeValidTransition(
            identityId: identityId,
            appContractId: appContractId,
            chainKey: chainKey,
            walletIdentityId: identityId
        )
        let validated = try PlatformDashConnectDataSource.validateKeyRegistration(
            transition,
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        let currentKeys = [
            makeIdentityPublicKeyInfo(
                keyId: 100,
                purpose: .authentication,
                securityLevel: .high,
                keyType: .ecdsaHash160,
                data: validated.authenticationKey.publicKeyData,
                disabledAt: 123
            ),
            makeIdentityPublicKeyInfo(
                keyId: 101,
                purpose: .encryption,
                securityLevel: .medium,
                keyType: .ecdsaSecp256k1,
                data: validated.encryptionKey.publicKeyData
            ),
        ]

        XCTAssertFalse(
            PlatformDashConnectDataSource.hasRegisteredLoginKeys(
                authenticationPublicKeyHash160: validated.authenticationKey.publicKeyData,
                encryptionPublicKey: validated.encryptionKey.publicKeyData,
                currentIdentityPublicKeys: currentKeys
            )
        )
    }

    private func makeValidTransition(
        identityId: Data,
        appContractId: Data,
        chainKey: Data,
        walletIdentityId: Data
    ) throws -> DashConnectKeyRegistrationTransition {
        let loginKey = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: walletIdentityId,
            appContractId: appContractId
        )
        let authPrivateKey = try KeyExchangeCrypto.deriveAuthPrivateKey(loginKey: loginKey, identityId: walletIdentityId)
        let encryptionPrivateKey = try KeyExchangeCrypto.deriveEncryptionPrivateKey(loginKey: loginKey, identityId: walletIdentityId)
        let authPublicKey = try Secp256k1.compressedPublicKey(privateKey: authPrivateKey)

        return DashConnectKeyRegistrationTransition(
            identityId: identityId,
            addPublicKeys: [
                DashConnectKeyRegistrationKey(
                    keyId: 6,
                    keyType: .ecdsaHash160,
                    purpose: .authentication,
                    securityLevel: .high,
                    publicKeyData: KeyExchangeCrypto.hash160(authPublicKey),
                    contractBounds: nil
                ),
                DashConnectKeyRegistrationKey(
                    keyId: 7,
                    keyType: .ecdsaSecp256k1,
                    purpose: .encryption,
                    securityLevel: .medium,
                    publicKeyData: try Secp256k1.compressedPublicKey(privateKey: encryptionPrivateKey),
                    contractBounds: nil
                ),
            ],
            disablePublicKeyIds: []
        )
    }

    private func makeLoginRequest(contractId: Data, label: String) throws -> DashKeyRequest {
        DashKeyRequest(
            appEphemeralPubKey: try Secp256k1.compressedPublicKey(privateKey: Data(repeating: 0x01, count: 32)),
            contractId: contractId,
            label: label,
            network: .testnet
        )
    }

    private func makeSigningCandidate(
        keyId: UInt32,
        securityLevel: SecurityLevel,
        purpose: KeyPurpose = .authentication,
        keyType: KeyType = .ecdsaSecp256k1,
        disabledAt: Int64? = nil
    ) -> PlatformDashConnectDataSource.DocumentSigningKeyCandidate {
        PlatformDashConnectDataSource.DocumentSigningKeyCandidate(
            keyId: keyId,
            purpose: purpose,
            securityLevel: securityLevel,
            keyType: keyType,
            disabledAt: disabledAt
        )
    }

    private func makeIdentityPublicKeyInfo(
        keyId: UInt32,
        purpose: KeyPurpose,
        securityLevel: SecurityLevel,
        keyType: KeyType,
        data: Data,
        disabledAt: UInt64? = nil
    ) -> ManagedIdentity.IdentityPublicKeyInfo {
        ManagedIdentity.IdentityPublicKeyInfo(
            keyId: Int32(bitPattern: keyId),
            purpose: purpose,
            securityLevel: securityLevel,
            keyType: keyType,
            readOnly: false,
            disabledAt: disabledAt.map { Int64(bitPattern: $0) },
            data: data
        )
    }

    private static let taggedIdentityUpdateFixtureBase64 =
        "BgAREREREREREREREREREREREREREREREREREREREREREQcJAgARAAACAAAhAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICQaqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqABIAAQIBAUREREREREREREREREREREREREREREREREREREREREREB3Byb2ZpbGUBIQMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA0G7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7uwIECAIDQZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZ"

    private static let taglessIdentityUpdateFixtureBase64 =
        "ABERERERERERERERERERERERERERERERERERERERERERBwkCABEAAAIAACECAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgJBqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqoAEgABAgEBREREREREREREREREREREREREREREREREREREREREREQHcHJvZmlsZQEhAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDQbu7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7AgQIAgNBmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZk="

    private static let realKeyRegistrationFixtureHex =
        "0089fd6ddba75136a4fea02dc7d89ef0ca5bcc32ccf12fb8da6a1a03740567ae7201010200060200020000145e24e38a86e720f61757647996957e322686abb7000007000103000021035e8cfb0785b54e8902a3dc17bdaad8a5738c6019a18ebc527f79d1c64a27826a4120dc911df1d1e6cccf8c95ec0d423c928433397933de6dd9ad006bc40dc0334d6d270d50c6d5e2dcdc5560e40487ddfe28bd1066d0729fad4b26f92ae33f12a04b00000000"
}

private final class TestDashConnectStore: DashConnectStore {
    private var connections: [DAppConnection]

    init(initialConnections: [DAppConnection] = []) {
        self.connections = initialConnections
    }

    func load() -> [DAppConnection] {
        connections
    }

    func save(_ connections: [DAppConnection]) {
        self.connections = connections
    }
}
