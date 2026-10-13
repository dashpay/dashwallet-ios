import Combine
import Foundation
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
            // Explicit: the default follows the app's current network, and on
            // a fresh install that is mainnet, which the initializer rejects.
            supportedNetwork: .testnet,
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
            // Explicit: the default follows the app's current network, and on
            // a fresh install that is mainnet, which the initializer rejects.
            supportedNetwork: .testnet,
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
            // Explicit: the default follows the app's current network, and on
            // a fresh install that is mainnet, which the initializer rejects.
            supportedNetwork: .testnet,
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

        let appParser = PlatformWalletDashConnectStateTransitionParser { bytes in
            Self.parsed(.identityUpdate(try wallet.parseIdentityUpdateTransition(bytes)))
        }
        guard case let .keyRegistration(appTransition) = try appParser.parse(taglessBytes) else {
            return XCTFail("Expected a key-registration transition")
        }
        XCTAssertEqual(appTransition.identityId, tagged.identityId)
        XCTAssertEqual(appTransition.addPublicKeys.map(\.keyId), [17, 18])
        XCTAssertEqual(appTransition.disablePublicKeyIds, [4, 8])
    }

    func testParserMapsATokenPurchaseTransition() throws {
        let ownerId = Data(repeating: 0x21, count: 32)
        let contractId = Data(repeating: 0x22, count: 32)
        let tokenId = Data(repeating: 0x23, count: 32)
        let parser = PlatformWalletDashConnectStateTransitionParser { _ in
            Self.parsed(.batch(.init(ownerId: ownerId, transitions: [
                Self.tokenRow(contractId: contractId, tokenId: tokenId)
            ])))
        }

        guard case let .tokenPurchase(purchase) = try parser.parse(Data([0x00])) else {
            return XCTFail("Expected a token purchase")
        }
        XCTAssertEqual(purchase.ownerId, ownerId)
        XCTAssertEqual(purchase.dataContractId, contractId)
        XCTAssertEqual(purchase.tokenId, tokenId)
        XCTAssertEqual(purchase.tokenContractPosition, 3)
        XCTAssertEqual(purchase.tokenCount, 100)
        XCTAssertEqual(purchase.totalAgreedPrice, 100_000_000)
    }

    func testParserRejectsContractGroupKeysInsteadOfDroppingTheirRestriction() throws {
        let parser = PlatformWalletDashConnectStateTransitionParser { _ in
            Self.parsed(.identityUpdate(.init(
                identityId: Data(repeating: 0x21, count: 32),
                addPublicKeys: [.init(
                    keyId: 1, keyType: .ecdsaSecp256k1, purpose: .authentication,
                    securityLevel: .high, pubkeyBytes: Data(repeating: 0x22, count: 33),
                    contractBounds: .contractGroup(id: Data(repeating: 0x23, count: 32)))],
                disablePublicKeyIds: [])))
        }
        XCTAssertThrowsError(try parser.parse(Data([0]))) {
            XCTAssertEqual($0 as? DashConnectPlatformError, .keyRegistrationUnexpectedMutation)
        }
    }

    func testParserKeepsTheLimitsAScannedKeyRegistrationCarries() throws {
        let parser = PlatformWalletDashConnectStateTransitionParser { _ in
            Self.parsed(.identityUpdate(.init(
                identityId: Data(repeating: 0x21, count: 32),
                addPublicKeys: [
                    .init(
                        keyId: 1, keyType: .ecdsaHash160, purpose: .authentication,
                        securityLevel: .high, pubkeyBytes: Data(repeating: 0x22, count: 20),
                        totalBudget: 7, expiresAt: 9),
                    .init(
                        keyId: 2, keyType: .ecdsaSecp256k1, purpose: .encryption,
                        securityLevel: .medium, pubkeyBytes: Data(repeating: 0x23, count: 33)),
                ],
                disablePublicKeyIds: [])))
        }
        guard case let .keyRegistration(transition) = try parser.parse(Data([0])) else {
            return XCTFail("Expected a key-registration transition")
        }
        XCTAssertEqual(transition.addPublicKeys.map(\.totalBudget), [7, nil])
        XCTAssertEqual(transition.addPublicKeys.map(\.expiresAt), [9, nil])
    }

    func testParserRefusesABatchThatIsNotALoneCompleteTokenPurchase() {
        let ownerId = Data(repeating: 0x21, count: 32)
        let contractId = Data(repeating: 0x22, count: 32)
        let tokenId = Data(repeating: 0x23, count: 32)
        let purchase = Self.tokenRow(contractId: contractId, tokenId: tokenId)
        let refused: [(String, ManagedPlatformWallet.ParsedStateTransition)] = [
            ("two rows", Self.parsed(.batch(.init(ownerId: ownerId, transitions: [purchase, purchase])))),
            ("no rows", Self.parsed(.batch(.init(ownerId: ownerId, transitions: [])))),
            ("another token action", Self.parsed(.batch(.init(ownerId: ownerId, transitions: [
                Self.tokenRow(contractId: contractId, tokenId: tokenId, action: "Transfer")
            ])))),
            ("an incomplete row", Self.parsed(.batch(.init(ownerId: ownerId, transitions: [
                Self.tokenRow(contractId: contractId, tokenId: tokenId, complete: false)
            ])))),
            ("an incomplete transition", Self.parsed(
                .batch(.init(ownerId: ownerId, transitions: [purchase])), complete: false)),
            ("a missing price", Self.parsed(.batch(.init(ownerId: ownerId, transitions: [
                Self.tokenRow(contractId: contractId, tokenId: tokenId, amount: nil)
            ])))),
            ("a document row", Self.parsed(.batch(.init(ownerId: ownerId, transitions: [
                .document(.init(
                    dataContractId: contractId, documentType: "note",
                    documentId: Data(repeating: 0x24, count: 32), action: "Delete",
                    amount: nil, recipientId: nil, complete: true, details: nil))
            ])))),
            ("another kind", Self.parsed(.other)),
        ]
        for (name, transition) in refused {
            let parser = PlatformWalletDashConnectStateTransitionParser { _ in transition }
            XCTAssertThrowsError(try parser.parse(Data([0])), name) {
                XCTAssertEqual(
                    $0 as? DashConnectPlatformError,
                    .unsupportedStateTransition("TestKind"),
                    name)
            }
        }
    }

    private static func parsed(
        _ kind: ManagedPlatformWallet.ParsedStateTransitionKind,
        complete: Bool = true
    ) -> ManagedPlatformWallet.ParsedStateTransition {
        .init(
            kindName: "TestKind", ownerId: nil, isSigned: false, userFeeIncrease: 0,
            complete: complete, serialized: Data(), details: nil, kind: kind)
    }

    private static func tokenRow(
        contractId: Data,
        tokenId: Data,
        action: String = "DirectPurchase",
        amount: UInt64? = 100_000_000,
        complete: Bool = true
    ) -> ManagedPlatformWallet.ParsedBatchedTransition {
        .token(.init(
            dataContractId: contractId, tokenId: tokenId, tokenContractPosition: 3,
            action: action, amount: amount, recipientId: nil, tokenCount: 100,
            complete: complete, details: complete ? nil : "note"))
    }

    func testTokenPurchasePriceConvertsCreditsToDash() {
        // 1e11 credits = 1 DASH; 1e3 credits = 1 duff.
        XCTAssertEqual(Self.purchaseRequest(credits: 0).totalPriceDash, 0)
        XCTAssertEqual(Self.purchaseRequest(credits: 100_000_000_000).totalPriceDash, 1)
        XCTAssertEqual(
            Self.purchaseRequest(credits: 100_000).totalPriceDash,
            Decimal(string: "0.000001"))
        // Sub-duff precision survives: 1 credit is a thousandth of a duff,
        // which an eight-decimal rendering would round away even though it
        // is charged.
        XCTAssertEqual(
            Self.purchaseRequest(credits: 1).totalPriceDash,
            Decimal(string: "0.00000000001"))
    }

    // MARK: - Approval-sheet price text

    private static let enUS = Locale(identifier: "en_US")

    func testPriceTextRendersWholeAndSubDuffAmounts() {
        XCTAssertEqual(Self.purchaseRequest(credits: 0).totalPriceDashText(locale: Self.enUS), "0 DASH")
        XCTAssertEqual(Self.purchaseRequest(credits: 100_000_000_000).totalPriceDashText(locale: Self.enUS), "1 DASH")
        XCTAssertEqual(Self.purchaseRequest(credits: 1).totalPriceDashText(locale: Self.enUS), "0.00000000001 DASH")
        XCTAssertEqual(Self.purchaseRequest(credits: 150_000_000_000).totalPriceDashText(locale: Self.enUS), "1.5 DASH")
    }

    func testPriceTextKeepsFullPrecisionAboveTwoToTheFiftyThird() {
        // Values a `Double` cannot represent exactly: the text must name the
        // same integer that is passed as `expectedTotalCost`.
        XCTAssertEqual(
            Self.purchaseRequest(credits: 10_000_000_000_000_001).totalPriceDashText(locale: Self.enUS),
            "100000.00000000001 DASH")
        XCTAssertEqual(
            Self.purchaseRequest(credits: 9_007_199_254_740_993).totalPriceDashText(locale: Self.enUS),
            "90071.99254740993 DASH")
    }

    func testPriceTextUsesTheLocalesDecimalSeparatorWithoutGrouping() {
        XCTAssertEqual(
            Self.purchaseRequest(credits: 123_456_700_000_000).totalPriceDashText(locale: Locale(identifier: "uk_UA")),
            "1234,567 DASH")
    }

    fileprivate static func purchaseRequest(
        credits: UInt64,
        tokenCount: UInt64 = 1,
        tokenDecimals: Int? = nil
    ) -> DashConnectTokenPurchaseRequest {
        DashConnectTokenPurchaseRequest(
            appName: nil,
            ownerId: Data(repeating: 0x21, count: 32),
            dataContractId: Data(repeating: 0x22, count: 32),
            tokenId: Data(repeating: 0x23, count: 32),
            tokenContractPosition: 0,
            tokenCount: tokenCount,
            tokenDecimals: tokenDecimals,
            tokenName: nil,
            totalAgreedPriceCredits: credits,
            walletUsername: nil,
            walletIdentityId: "identity"
        )
    }

    // MARK: - Token quantity denomination

    func testAQuantityIsScaledByTheContractsDecimals() {
        // 100,000,000 base units of an eight-decimal token is one token — the
        // number the user is authorizing.
        let request = Self.purchaseRequest(credits: 1, tokenCount: 100_000_000, tokenDecimals: 8)
        XCTAssertEqual(request.tokenQuantity(locale: Self.enUS).text, "1")
        XCTAssertFalse(request.tokenQuantity(locale: Self.enUS).isBaseUnits)
    }

    func testAZeroDecimalTokenReadsAsAWholeCount() {
        let request = Self.purchaseRequest(credits: 1, tokenCount: 250, tokenDecimals: 0)
        XCTAssertEqual(request.tokenQuantity(locale: Self.enUS).text, "250")
        XCTAssertFalse(request.tokenQuantity(locale: Self.enUS).isBaseUnits)
    }

    func testAnUnknownDenominationIsReportedAsBaseUnits() {
        // The wallet does not hold the contract, so it cannot scale. Assuming
        // zero decimals here would overstate an eight-decimal token by 1e8 on
        // a money-authorization screen.
        let request = Self.purchaseRequest(credits: 1, tokenCount: 100_000_000, tokenDecimals: nil)
        // Ungrouped in a grouping locale too: every branch renders the same way.
        XCTAssertEqual(request.tokenQuantity(locale: Self.enUS).text, "100000000")
        XCTAssertTrue(request.tokenQuantity(locale: Self.enUS).isBaseUnits)
    }

    func testAWholeCountIsUngroupedInAGroupingLocale() {
        let request = Self.purchaseRequest(credits: 1, tokenCount: 1_000_000, tokenDecimals: 0)
        XCTAssertEqual(request.tokenQuantity(locale: Self.enUS).text, "1000000")
    }

    func testAFractionalQuantityKeepsItsDeclaredPrecision() {
        let request = Self.purchaseRequest(credits: 1, tokenCount: 150_000_000, tokenDecimals: 8)
        XCTAssertEqual(request.tokenQuantity(locale: Self.enUS).text, "1.5")
        XCTAssertEqual(request.tokenQuantity(locale: Locale(identifier: "uk_UA")).text, "1,5")
        XCTAssertFalse(request.tokenQuantity(locale: Self.enUS).isBaseUnits)
    }

    /// The quantity on the sheet must be the quantity `tokenPurchase` submits.
    /// A `NumberFormatter` rendering keeps ~15 significant digits, so this
    /// 16-decimal amount came out as 0.900719925474099 — three base units
    /// short of what the user would have been charged for.
    func testAQuantityKeepsEveryDeclaredDigitAboveTwoToTheFiftyThird() {
        let request = Self.purchaseRequest(
            credits: 1,
            tokenCount: 9_007_199_254_740_993,
            tokenDecimals: 16
        )

        XCTAssertEqual(request.tokenQuantity(locale: Self.enUS).text, "0.9007199254740993")
        XCTAssertEqual(
            request.tokenQuantity(locale: Locale(identifier: "uk_UA")).text,
            "0,9007199254740993"
        )
        XCTAssertFalse(request.tokenQuantity(locale: Self.enUS).isBaseUnits)
    }

    /// Fewer base units than the scale: the leading zero and every declared
    /// place survive.
    func testAQuantitySmallerThanOneTokenKeepsItsLeadingZeros() {
        let request = Self.purchaseRequest(credits: 1, tokenCount: 1, tokenDecimals: 18)

        XCTAssertEqual(request.tokenQuantity(locale: Self.enUS).text, "0.000000000000000001")
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
            try KeyExchangeCrypto.hash160(appEphemeralPubKey).toHexString()
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
                    publicKeyData: try KeyExchangeCrypto.hash160(attackerPublicKey),
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

    /// Turning off a one-QR connection that replaced a two-QR one disables
    /// what is left of the two-QR login's keys as well.
    func testADisconnectFindsTheLiveTwoQrLoginKeysByTheirDerivedPayload() {
        let authentication = Data(repeating: 0x51, count: 20)
        let encryption = Data(repeating: 0x52, count: 33)
        func live(_ keys: [ManagedIdentity.IdentityPublicKeyInfo]) -> [UInt32] {
            PlatformDashConnectDataSource.liveLoginKeyIds(
                authenticationPublicKeyHash160: authentication,
                encryptionPublicKey: encryption,
                currentIdentityPublicKeys: keys)
        }
        let authenticationKey = makeIdentityPublicKeyInfo(
            keyId: 100, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160, data: authentication)
        let encryptionKey = makeIdentityPublicKeyInfo(
            keyId: 101, purpose: .encryption, securityLevel: .medium, keyType: .ecdsaSecp256k1, data: encryption)
        let disabledAuthenticationKey = makeIdentityPublicKeyInfo(
            keyId: 100, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: authentication, disabledAt: 1)
        // A one-QR session key: same kind as the two-QR authentication key,
        // another payload.
        let sessionKey = makeIdentityPublicKeyInfo(
            keyId: 102, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: 0x53, count: 20))

        XCTAssertEqual(live([encryptionKey, sessionKey, authenticationKey]), [100, 101])
        XCTAssertEqual(live([disabledAuthenticationKey, encryptionKey]), [101])
        XCTAssertEqual(live([disabledAuthenticationKey, sessionKey]), [])
        XCTAssertEqual(live([]), [])
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
                    publicKeyData: try KeyExchangeCrypto.hash160(authPublicKey),
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
            data: data,
            // Protocol 14 key limits (platform#4798). These fixtures describe
            // the keys the QR login flow derives, which carry neither.
            totalBudget: nil,
            expiresAt: nil
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

/// What the approval sheet may offer after a failed token purchase.
///
/// A purchase is not idempotent, so the rule under test is a money rule: a
/// failure that never reached Platform stays retryable, an unknown outcome
/// does not, and a second tap while the first is in flight buys nothing.
@MainActor
final class ConnectionsViewModelPurchaseTests: XCTestCase {
    func testAFailureBeforeSubmissionKeepsThePurchasePendingForRetry() async {
        let spy = PurchaseApprovalSpy()
        spy.failure = DashConnectTokenPurchaseFailure.beforeSubmission(PurchaseSpyError.refused)
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        let purchase = PlatformDashConnectDataSourceTests.purchaseRequest(credits: 1)
        viewModel.pendingTokenPurchase = purchase

        viewModel.approvePendingTokenPurchase()
        await waitUntil { !viewModel.isApprovingPurchase }

        // Nothing was signed or sent, so the sheet stays up carrying the
        // reason, and approving again costs no second rescan.
        XCTAssertEqual(viewModel.pendingTokenPurchase, purchase)
        XCTAssertEqual(viewModel.purchaseApproveError?.contains("spy refused"), true)
        XCTAssertNil(viewModel.message)
        XCTAssertEqual(spy.approveCallCount, 1)
    }

    func testAnUnknownOutcomeClosesTheSheetAndWarnsInsteadOfOfferingRetry() async {
        let spy = PurchaseApprovalSpy()
        spy.failure = DashConnectTokenPurchaseFailure.outcomeUnknown(PurchaseSpyError.refused)
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        viewModel.pendingTokenPurchase = PlatformDashConnectDataSourceTests.purchaseRequest(credits: 1)

        viewModel.approvePendingTokenPurchase()
        await waitUntil { !viewModel.isApprovingPurchase }

        // The transition may already be on Platform: no retry is offered, and
        // the warning names what to check before buying again.
        XCTAssertNil(viewModel.pendingTokenPurchase)
        XCTAssertNil(viewModel.purchaseApproveError)
        XCTAssertEqual(viewModel.message?.kind, .error)
        XCTAssertEqual(viewModel.message?.text.contains("spy refused"), true)
        XCTAssertEqual(spy.approveCallCount, 1)
    }

    func testASecondApproveWhileTheFirstIsInFlightSubmitsOnlyOnce() async {
        let spy = PurchaseApprovalSpy()
        spy.suspendsUntilReleased = true
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        viewModel.pendingTokenPurchase = PlatformDashConnectDataSourceTests.purchaseRequest(credits: 1)

        viewModel.approvePendingTokenPurchase()
        await waitUntil { spy.isSuspended }
        XCTAssertTrue(spy.isSuspended, "the first approval never reached the data source")

        // The double tap the in-flight guard exists for: a second signed
        // purchase on the next nonce would debit the identity twice.
        viewModel.approvePendingTokenPurchase()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(spy.approveCallCount, 1)

        spy.release()
        await waitUntil { !viewModel.isApprovingPurchase }

        XCTAssertEqual(spy.approveCallCount, 1)
        XCTAssertNil(viewModel.pendingTokenPurchase)
        XCTAssertEqual(viewModel.message?.kind, .success)
    }

    /// Polls `condition` until it holds or `timeout` elapses.
    ///
    /// `approvePendingTokenPurchase` works in an unstructured `Task` and the
    /// data source runs off the main actor, so there is no handle to await.
    func testAFailedDisconnectIsReportedInsteadOfLookingLikeASuccess() async {
        let spy = PurchaseApprovalSpy()
        spy.disconnectFailure = PurchaseSpyError.refused
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        viewModel.disconnect(Self.connection)
        XCTAssertTrue(viewModel.isDisconnecting)
        // A second tap while the first is still out must not start another.
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting }

        XCTAssertEqual(spy.disconnectedIds, [Self.connection.id])
        XCTAssertEqual(viewModel.message?.kind, .error)
        XCTAssertEqual(viewModel.message?.text.contains("spy refused"), true)
    }

    func testASuccessfulDisconnectReportsNothing() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting }

        XCTAssertEqual(spy.disconnectedIds, [Self.connection.id])
        XCTAssertNil(viewModel.message)
    }

    /// With the login unresolved the sheet's action asks again and approves
    /// nothing.
    func testAnUnresolvedLoginIsAskedForAgainInsteadOfApproved() async {
        let unresolved = ConnectionRequest(loginRequest: MockDashConnectDataSource.sampleLoginRequest)
        let resolved = Self.consent(identityId: "identity-a", terms: .current)
        let spy = LoginApprovalSpy(shown: [unresolved, resolved])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        viewModel.onQRScanned("login")
        await waitUntil { viewModel.pendingRequest != nil }
        XCTAssertEqual(viewModel.pendingRequest?.login, .unresolved)
        viewModel.approvePendingRequest()
        XCTAssertFalse(viewModel.isApproving, "an unresolved login cannot be approved")
        viewModel.retryPendingRequest()
        await waitUntil { !viewModel.isApproving }

        XCTAssertEqual(viewModel.pendingRequest, resolved)
        XCTAssertEqual(spy.approvedConsents, [])
        XCTAssertNil(viewModel.approveError)
    }

    func testApprovingALoginPassesTheRequestAsTheSheetShowedIt() async {
        let shown = Self.consent(identityId: "identity-a", terms: .current)
        let spy = LoginApprovalSpy(shown: [shown])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        viewModel.onQRScanned("login")
        await waitUntil { viewModel.pendingRequest != nil }
        viewModel.approvePendingRequest()
        await waitUntil { viewModel.pendingRequest == nil }

        XCTAssertEqual(spy.approvedConsents, [shown])
        XCTAssertNil(viewModel.approveError)
    }

    /// Another identity became active, or the network answers with the other
    /// login, while the sheet was up: nothing is approved on the old sheet,
    /// and the user decides again on what is true now.
    func testAnApprovalThatIsOutOfDateShowsTheRequestAgainAsItStands() async {
        let shown = Self.consent(identityId: "identity-a", terms: nil)
        let current = Self.consent(identityId: "identity-b", terms: .current)
        let spy = LoginApprovalSpy(shown: [shown, current])
        spy.approveFailures = [DashConnectPlatformError.approvalOutOfDate]
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        viewModel.onQRScanned("login")
        await waitUntil { viewModel.pendingRequest != nil }
        viewModel.approvePendingRequest()
        await waitUntil { !viewModel.isApproving }

        XCTAssertEqual(viewModel.pendingRequest, current)
        XCTAssertEqual(viewModel.approveError, DashConnectPlatformError.approvalOutOfDate.localizedDescription)

        viewModel.approvePendingRequest()
        await waitUntil { viewModel.pendingRequest == nil }

        XCTAssertEqual(spy.approvedConsents, [shown, current])
        XCTAssertNil(viewModel.approveError)
    }

    private static func consent(identityId: String, terms: AppConnect.SessionKeyTerms?) -> ConnectionRequest {
        ConnectionRequest(
            loginRequest: MockDashConnectDataSource.sampleLoginRequest,
            appLabel: "App",
            appUrl: "",
            walletUsername: nil,
            walletIdentityId: identityId,
            existingConnection: nil,
            login: terms.map(AppConnect.Login.oneQR) ?? .twoQR)
    }

    private static let connection = DAppConnection(
        id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", name: "App", url: "",
        status: .active, updatedAt: Date(timeIntervalSince1970: 1_000))

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

/// A `DashConnectDataSource` that counts approvals and can hold one suspended.
///
/// `MockDashConnectDataSource` cannot stand in: it always fails before
/// submission, counts nothing, and has no suspension point to tap through.
private final class PurchaseApprovalSpy: DashConnectDataSource {
    /// Guards every stored property: the protocol's methods are nonisolated,
    /// so they run off the main actor the test asserts from.
    private let lock = NSLock()
    private var storedFailure: Error?
    private var storedSuspendsUntilReleased = false
    private var storedApproveCallCount = 0
    private var storedIsSuspended = false
    private var gate: CheckedContinuation<Void, Never>?

    /// Thrown once the call proceeds. `nil` completes the purchase.
    var failure: Error? {
        get { lock.withLock { storedFailure } }
        set { lock.withLock { storedFailure = newValue } }
    }

    /// When true, `approveTokenPurchase` suspends until `release()`.
    var suspendsUntilReleased: Bool {
        get { lock.withLock { storedSuspendsUntilReleased } }
        set { lock.withLock { storedSuspendsUntilReleased = newValue } }
    }

    var approveCallCount: Int {
        lock.withLock { storedApproveCallCount }
    }

    var isSuspended: Bool {
        lock.withLock { storedIsSuspended }
    }

    var connections: AnyPublisher<[DAppConnection], Never> {
        Just([DAppConnection]()).eraseToAnyPublisher()
    }

    /// Lets a suspended `approveTokenPurchase` finish.
    func release() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let waiting = gate
            gate = nil
            storedIsSuspended = false
            return waiting
        }
        waiting?.resume()
    }

    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        let suspends = lock.withLock { () -> Bool in
            storedApproveCallCount += 1
            return storedSuspendsUntilReleased
        }

        if suspends {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    gate = continuation
                    storedIsSuspended = true
                }
            }
        }

        if let failure {
            throw failure
        }
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        throw PurchaseSpyError.unsupported
    }

    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        XCTFail("makeConnectionRequest is not part of the purchase approval flow")
        return ConnectionRequest(loginRequest: loginRequest)
    }

    func approveLogin(_ request: DashKeyRequest, consent: ConnectionRequest) async throws -> DAppConnection {
        throw PurchaseSpyError.unsupported
    }

    func handleStateTransition(_ request: DashStRequest) async throws -> DashConnectStAction {
        throw PurchaseSpyError.unsupported
    }

    private var storedDisconnectFailure: Error?
    private var storedDisconnectedIds: [String] = []

    var disconnectFailure: Error? {
        get { lock.withLock { storedDisconnectFailure } }
        set { lock.withLock { storedDisconnectFailure = newValue } }
    }

    var disconnectedIds: [String] {
        lock.withLock { storedDisconnectedIds }
    }

    func disconnect(id: String) async throws {
        let failure = lock.withLock { () -> Error? in
            storedDisconnectedIds.append(id)
            return storedDisconnectFailure
        }
        if let failure { throw failure }
    }

    func remove(id: String) async {
        XCTFail("remove is not part of the purchase approval flow")
    }
}

/// A `DashConnectDataSource` for the login approval: every QR is the sample
/// login, each resolution of it hands out the next request in `shown` (the
/// last one from then on), and approvals are recorded with what they carried.
private final class LoginApprovalSpy: DashConnectDataSource {
    /// Guards every stored property: the protocol's methods are nonisolated,
    /// so they run off the main actor the test asserts from.
    private let lock = NSLock()
    private var shown: [ConnectionRequest]
    private var storedApproveFailures: [Error] = []
    private var storedApprovedConsents: [ConnectionRequest] = []

    init(shown: [ConnectionRequest]) {
        self.shown = shown
    }

    /// Thrown by the approvals in order, one each; later approvals succeed.
    var approveFailures: [Error] {
        get { lock.withLock { storedApproveFailures } }
        set { lock.withLock { storedApproveFailures = newValue } }
    }

    var approvedConsents: [ConnectionRequest] {
        lock.withLock { storedApprovedConsents }
    }

    var connections: AnyPublisher<[DAppConnection], Never> {
        Just([DAppConnection]()).eraseToAnyPublisher()
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        .login(MockDashConnectDataSource.sampleLoginRequest)
    }

    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        lock.withLock { shown.count > 1 ? shown.removeFirst() : shown[0] }
    }

    func approveLogin(_ request: DashKeyRequest, consent: ConnectionRequest) async throws -> DAppConnection {
        let failure = lock.withLock { () -> Error? in
            storedApprovedConsents.append(consent)
            return storedApproveFailures.isEmpty ? nil : storedApproveFailures.removeFirst()
        }
        if let failure { throw failure }
        return MockDashConnectDataSource.sample(.active)
    }

    func handleStateTransition(_ request: DashStRequest) async throws -> DashConnectStAction {
        throw PurchaseSpyError.unsupported
    }

    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        throw PurchaseSpyError.unsupported
    }

    func disconnect(id: String) async throws {
        throw PurchaseSpyError.unsupported
    }

    func remove(id: String) async {}
}

private enum PurchaseSpyError: LocalizedError {
    case refused
    case unsupported

    var errorDescription: String? {
        switch self {
        case .refused:
            return "spy refused"
        case .unsupported:
            return "not part of the purchase approval flow"
        }
    }
}

final class AppConnectLoginTests: XCTestCase {
    func testResponseLookupQueriesTheIndexInOrderWithBase64Hash() throws {
        let hash = Data(repeating: 0xAB, count: 20)
        let owner = Data(repeating: 0x01, count: 32)

        let clause = AppConnect.responseLookupWhereClause(appEphemeralPubKeyHash: hash, ownerIdentityId: owner)

        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(clause.utf8)) as? [[String]])
        XCTAssertEqual(parsed, [
            ["appEphemeralPubKeyHash", "==", hash.base64EncodedString()],
            ["$ownerId", "==", owner.toBase58String()],
        ])
    }

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppConnectLoginTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testOneQrLoginStartsAtProtocolVersion14() {
        XCTAssertFalse(AppConnect.isAvailable(protocolVersion: 13))
        XCTAssertTrue(AppConnect.isAvailable(protocolVersion: 14))
        XCTAssertTrue(AppConnect.isAvailable(protocolVersion: 15))
    }

    func testRequestIdIsHash256OfTheAppEphemeralKey() {
        // hash256 of the empty string, a published vector.
        XCTAssertEqual(
            AppConnect.requestId(appEphemeralPubKey: Data()).toHexString(),
            "5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456")
        XCTAssertEqual(AppConnect.requestId(appEphemeralPubKey: Data(repeating: 0x02, count: 33)).count, 32)
    }

    func testSessionKeyIsAbsentUntilItsHashIsOnTheIdentity() {
        let other = Self.key(keyId: 4, data: Data(repeating: 0x22, count: 20))
        XCTAssertEqual(Self.sessionKeyState(keys: [other]), .absent)
        // The same bytes under another key type are a different key.
        let sameBytesOtherType = Self.key(keyId: 5, keyType: .ecdsaSecp256k1, data: Self.sessionKeyHash)
        XCTAssertEqual(Self.sessionKeyState(keys: [sameBytesOtherType]), .absent)
    }

    func testRegisteredSessionKeyOfTheAppIsUsableWithItsKeyId() {
        XCTAssertEqual(Self.sessionKeyState(keys: [Self.sessionKey()]), .usable(keyId: 9))
        // Registered a moment ago by a clock that has since been set back.
        let afterClockCorrection = Self.sessionKey(expiresAt: Self.nowMilliseconds + 3_600_000 + 60_000)
        XCTAssertEqual(Self.sessionKeyState(keys: [afterClockCorrection]), .usable(keyId: 9))
        // Limits narrower than the approved terms are within them.
        let narrower = Self.sessionKey(
            totalBudget: Self.terms.budgetCredits - 1, expiresAt: Self.nowMilliseconds + 1)
        XCTAssertEqual(Self.sessionKeyState(keys: [narrower]), .usable(keyId: 9))
    }

    func testDisabledExpiredOrMisregisteredSessionKeyIsUnusable() {
        let latestExpiry = Int64(Self.terms.expiresAt(from: Self.now.addingTimeInterval(AppConnect.clockTolerance)))
        let unusable: [(String, ManagedIdentity.IdentityPublicKeyInfo)] = [
            ("disabled", Self.sessionKey(disabledAt: 1)),
            ("expired", Self.sessionKey(expiresAt: Self.nowMilliseconds)),
            ("wrong level", Self.sessionKey(securityLevel: .critical)),
            ("wrong purpose", Self.sessionKey(purpose: .transfer)),
            ("no budget", Self.sessionKey(totalBudget: nil)),
            ("no expiry", Self.sessionKey(expiresAt: nil)),
            ("budget above the approved one", Self.sessionKey(totalBudget: Self.terms.budgetCredits + 1)),
            ("expiry after the approved one", Self.sessionKey(expiresAt: latestExpiry + 1)),
        ]
        for (name, key) in unusable {
            XCTAssertEqual(Self.sessionKeyState(keys: [key]), .unusable, name)
        }
    }

    /// The key is derived from the identity and the request's ephemeral key
    /// alone, so a request that repeats another app's ephemeral key finds
    /// that app's key on the identity.
    func testARegisteredSessionKeyBoundToAnotherAppIsUnusable() {
        let otherApp = Data(repeating: 0xB2, count: 32)
        let boundElsewhere = [AppConnect.KeyBinding(keyId: 9, data: Self.sessionKeyHash, singleContractId: otherApp)]
        XCTAssertEqual(Self.sessionKeyState(keys: [Self.sessionKey()], bindings: boundElsewhere), .unusable)
        // A grant record does not outweigh a bound the store can read.
        XCTAssertEqual(
            Self.sessionKeyState(keys: [Self.sessionKey()], bindings: boundElsewhere, grantedKeyIds: [9]),
            .unusable)
        let unbound = [AppConnect.KeyBinding(keyId: 9, data: Self.sessionKeyHash, singleContractId: nil)]
        XCTAssertEqual(Self.sessionKeyState(keys: [Self.sessionKey()], bindings: unbound), .unusable)
    }

    func testARegisteredSessionKeyTheStoreCannotPlaceNeedsAGrantRecord() {
        let unplaced: [[AppConnect.KeyBinding]] = [
            [],
            // The stored row under this id is for a different key.
            [AppConnect.KeyBinding(keyId: 9, data: Data([0xFF]), singleContractId: Self.app)],
            [AppConnect.KeyBinding(
                keyId: 9, data: Self.sessionKeyHash, singleContractId: nil, hasUnreadableBound: true)],
        ]
        for bindings in unplaced {
            XCTAssertEqual(Self.sessionKeyState(keys: [Self.sessionKey()], bindings: bindings), .unusable)
            XCTAssertEqual(
                Self.sessionKeyState(keys: [Self.sessionKey()], bindings: bindings, grantedKeyIds: [8]),
                .unusable)
            XCTAssertEqual(
                Self.sessionKeyState(keys: [Self.sessionKey()], bindings: bindings, grantedKeyIds: [9]),
                .usable(keyId: 9))
        }
    }

    func testTheOneQrLoginHasTermsAndTheTwoQrLoginHasNone() {
        XCTAssertEqual(AppConnect.login(protocolVersion: 13), .twoQR)
        XCTAssertEqual(AppConnect.login(protocolVersion: 14), .oneQR(.current))
        XCTAssertNil(AppConnect.Login.twoQR.sessionKeyTerms)
        XCTAssertNil(AppConnect.Login.unresolved.sessionKeyTerms)
        XCTAssertEqual(AppConnect.Login.oneQR(.current).sessionKeyTerms, .current)
        // A request built without asking the network is not a two-QR one.
        XCTAssertEqual(ConnectionRequest(loginRequest: MockDashConnectDataSource.sampleLoginRequest).login, .unresolved)
        XCTAssertEqual(AppConnect.SessionKeyTerms.current.budgetCredits, AppConnect.sessionKeyBudgetCredits)
        XCTAssertEqual(AppConnect.SessionKeyTerms.current.lifetime, AppConnect.sessionKeyLifetime)
    }

    func testTheApprovalSheetNamesTheBudgetInDashAndTheLifetimeInDays() {
        let terms = AppConnect.SessionKeyTerms(budgetCredits: 5_000_000_000, lifetime: 90 * 24 * 60 * 60)
        XCTAssertEqual(terms.budgetText.filter { $0.isNumber || $0.isLetter }, "005DASH")
        XCTAssertEqual(terms.lifetimeDays, 90)
    }

    /// A response an earlier login deleted is published again when its
    /// request comes back. If that publish never confirms, the record must
    /// not say the response is gone: a disconnect would drop it and leave
    /// the response on Platform with nothing pointing at it.
    func testARepublishThatNeverConfirmsKeepsItsRecordThroughADisconnect() {
        var republished = Self.grant(sessionKeyId: 9)
        republished.responseDeleted = true
        republished.markPublishStarted()
        XCTAssertNil(republished.documentId)
        XCTAssertTrue(republished.hasUnconfirmedResponse)

        var knownGone = Self.grant(sessionKeyId: 10)
        knownGone.responseDeleted = true
        var otherApp = Self.grant(sessionKeyId: 11)
        otherApp.responseDeleted = true
        var grants = [republished, knownGone, otherApp]
        AppConnect.markKeysDisabled(in: &grants) { $0.sessionKeyId != 11 }

        XCTAssertEqual(grants.map(\.sessionKeyId), [9, 11])
        XCTAssertEqual(grants.map(\.keyDisabled), [true, nil])
        XCTAssertTrue(grants[0].hasUnconfirmedResponse, "the disconnect still has a response to look for")
    }

    func testNextKeyIdFollowsTheHighestKeyOnTheIdentity() {
        XCTAssertEqual(AppConnect.nextKeyId(currentIdentityPublicKeys: []), 1)
        XCTAssertEqual(
            AppConnect.nextKeyId(currentIdentityPublicKeys: [
                Self.key(keyId: 0, data: Data([1])),
                Self.key(keyId: 7, data: Data([2]), disabledAt: 1),
                Self.key(keyId: 3, data: Data([3])),
            ]),
            8)
    }

    func testThereIsNoNextKeyIdAfterTheLastOne() {
        // A key id is a UInt32 the SDK carries as an Int32 bit pattern.
        let last = Self.key(keyId: -1, data: Data([1]))
        XCTAssertNil(AppConnect.nextKeyId(currentIdentityPublicKeys: [last]))
        let disabledLast = Self.key(keyId: -1, data: Data([1]), disabledAt: 1)
        XCTAssertNil(AppConnect.nextKeyId(currentIdentityPublicKeys: [Self.key(keyId: 3, data: Data([3])), disabledLast]))
        XCTAssertEqual(
            AppConnect.nextKeyId(currentIdentityPublicKeys: [Self.key(keyId: -2, data: Data([2]))]),
            .max)
    }

    func testDisconnectDisablesOnlyTheLiveSessionKeysItGranted() {
        let grants = [9, 11, 12, 13].map { Self.grant(sessionKeyId: $0) }
        let keys = [
            Self.key(keyId: 0, securityLevel: .master, keyType: .ecdsaSecp256k1, data: Data([0])),
            Self.key(keyId: 9, data: Data([9])),
            // Not granted by these responses.
            Self.key(keyId: 10, data: Data([10])),
            // Already disabled.
            Self.key(keyId: 11, data: Data([11]), disabledAt: 1),
            // The id now belongs to a key this login would never register.
            Self.key(keyId: 12, securityLevel: .critical, data: Data([12])),
            // 13 is not on the identity at all.
            Self.key(keyId: 14, data: Data([14])),
        ]
        let app = Data(repeating: 0xA1, count: 32)
        XCTAssertEqual(
            AppConnect.sessionKeyIdsToDisable(
                for: grants, appContractId: app, bindings: [], currentIdentityPublicKeys: keys),
            [9])
        XCTAssertEqual(
            AppConnect.sessionKeyIdsToDisable(
                for: [], appContractId: app, bindings: [], currentIdentityPublicKeys: keys),
            [])
    }

    func testDisconnectAlsoDisablesLiveKeysBoundToTheAppThatHaveNoGrantRecord() {
        let app = Data(repeating: 0xA1, count: 32)
        let otherApp = Data(repeating: 0xB2, count: 32)
        let keys = [
            Self.key(keyId: 6, data: Data([6]), totalBudget: 5, expiresAt: 9_999),
            Self.key(keyId: 7, data: Data([7]), totalBudget: 5, expiresAt: 9_999),
            Self.key(keyId: 8, data: Data([8]), disabledAt: 1),
            Self.key(keyId: 9, data: Data([9]), totalBudget: 5, expiresAt: 9_999),
            Self.key(keyId: 10, data: Data([10]), totalBudget: 5, expiresAt: 9_999),
            Self.key(keyId: 11, data: Data([11]), totalBudget: 5, expiresAt: 9_999),
            // Bound to the app and of the same kind, but without limits and
            // without a grant record: not a key this login registered.
            Self.key(keyId: 13, data: Data([13])),
            // Bound to the app, but not a key this login registers.
            Self.key(
                keyId: 12, purpose: .encryption, securityLevel: .medium, keyType: .ecdsaSecp256k1,
                data: Data([12]), totalBudget: 5, expiresAt: 9_999),
            // Bound to the app with one limit only.
            Self.key(keyId: 14, data: Data([14]), expiresAt: 9_999),
        ]
        let bindings = [
            AppConnect.KeyBinding(keyId: 6, data: Data([6]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 7, data: Data([7]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 8, data: Data([8]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 9, data: Data([9]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 10, data: Data([10]), singleContractId: otherApp),
            // The stored row under this id is for a different key.
            AppConnect.KeyBinding(keyId: 11, data: Data([0xFF]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 12, data: Data([12]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 13, data: Data([13]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 14, data: Data([14]), singleContractId: app),
        ]
        XCTAssertEqual(
            AppConnect.sessionKeyIdsToDisable(
                for: [Self.grant(sessionKeyId: 9)],
                appContractId: app,
                bindings: bindings,
                currentIdentityPublicKeys: keys),
            [6, 7, 9])
        XCTAssertEqual(
            AppConnect.sessionKeyIdsToDisable(
                for: [], appContractId: otherApp, bindings: bindings, currentIdentityPublicKeys: keys),
            [10])
        // Key 7 is the two-QR login's authentication key, given limits by
        // its `dash-st:` registration: it stays unless a grant names it.
        XCTAssertEqual(
            AppConnect.sessionKeyIdsToDisable(
                for: [Self.grant(sessionKeyId: 9)],
                appContractId: app,
                bindings: bindings,
                currentIdentityPublicKeys: keys,
                twoQRAuthenticationKeyHash160: Data([7])),
            [6, 9])
    }

    /// Keys of the app on an identity that is not the active one are
    /// recognised from the wallet's store: no grant record names them.
    func testTheStoreShowsAnAppKeyHeldOnAnotherIdentityWhileItIsLive() {
        let app = Data(repeating: 0xA1, count: 32)
        let authentication = Data(repeating: 0x51, count: 20)
        let encryption = Data(repeating: 0x52, count: 33)
        func holdsTwoQR(_ bindings: [AppConnect.KeyBinding]) -> Bool {
            AppConnect.holdsLiveTwoQRLoginKey(
                authenticationPublicKeyHash160: authentication, encryptionPublicKey: encryption, bindings: bindings)
        }
        func authenticationKey(data: Data = authentication, isDisabled: Bool = false) -> AppConnect.KeyBinding {
            AppConnect.KeyBinding(
                keyId: 3, data: data, singleContractId: app, isDisabled: isDisabled,
                isTwoQRAuthenticationKeyShaped: true)
        }
        let encryptionKey = AppConnect.KeyBinding(
            keyId: 4, data: encryption, singleContractId: nil, isTwoQREncryptionKeyShaped: true)

        XCTAssertTrue(holdsTwoQR([authenticationKey()]))
        XCTAssertTrue(holdsTwoQR([authenticationKey(isDisabled: true), encryptionKey]))
        XCTAssertFalse(holdsTwoQR([authenticationKey(isDisabled: true)]))
        // Another app's key: same kind, another payload.
        XCTAssertFalse(holdsTwoQR([authenticationKey(data: Data(repeating: 0x53, count: 20))]))
        // The same bytes under another kind are not that key.
        XCTAssertFalse(holdsTwoQR([AppConnect.KeyBinding(keyId: 5, data: authentication, singleContractId: app)]))
        XCTAssertFalse(holdsTwoQR([]))

        let sessionKey = AppConnect.KeyBinding(
            keyId: 6, data: Data([6]), singleContractId: app, isSessionKeyShaped: true)
        var disabledSessionKey = sessionKey
        disabledSessionKey.isDisabled = true
        XCTAssertTrue(AppConnect.holdsLiveSessionKey(appContractId: app, bindings: [sessionKey]))
        XCTAssertFalse(AppConnect.holdsLiveSessionKey(appContractId: app, bindings: [disabledSessionKey]))
        XCTAssertFalse(
            AppConnect.holdsLiveSessionKey(appContractId: Data(repeating: 0xB2, count: 32), bindings: [sessionKey]))
        // The two-QR authentication key is bound to the app but carries no limits.
        XCTAssertFalse(AppConnect.holdsLiveSessionKey(appContractId: app, bindings: [authenticationKey()]))
    }

    func testOnlyAWholeSingleContractBoundNamesTheApp() {
        let app = Data(repeating: 0xA1, count: 32)
        XCTAssertEqual(AppConnect.singleContractId(boundsKind: 1, boundIds: [app]), app)
        XCTAssertNil(AppConnect.singleContractId(boundsKind: 0, boundIds: nil))
        XCTAssertNil(AppConnect.singleContractId(boundsKind: 2, boundIds: [app]))
        XCTAssertNil(AppConnect.singleContractId(boundsKind: 3, boundIds: [app]))
        XCTAssertNil(AppConnect.singleContractId(boundsKind: 1, boundIds: []))
        XCTAssertNil(AppConnect.singleContractId(boundsKind: 1, boundIds: [Data([1, 2])]))

        for kind in [0, 2, 3] {
            XCTAssertTrue(AppConnect.isReadableBound(boundsKind: kind, boundIds: kind == 0 ? nil : [app]))
        }
        XCTAssertTrue(AppConnect.isReadableBound(boundsKind: 1, boundIds: [app]))
        XCTAssertFalse(AppConnect.isReadableBound(boundsKind: 1, boundIds: [Data([1, 2])]))
        XCTAssertFalse(AppConnect.isReadableBound(boundsKind: 1, boundIds: nil))
        XCTAssertFalse(AppConnect.isReadableBound(boundsKind: 4, boundIds: [app]))
    }

    func testAKeyBoundElsewhereOrNotAtAllIsNeitherDisabledNorUnknown() {
        let app = Data(repeating: 0xA1, count: 32)
        let keys = [4, 5, 6].map {
            Self.key(keyId: Int32($0), data: Data([UInt8($0)]), totalBudget: 5, expiresAt: 9_999)
        }
        let bindings = [
            // A document-type bound and an unbounded key both store no single contract.
            AppConnect.KeyBinding(keyId: 4, data: Data([4]), singleContractId: nil),
            AppConnect.KeyBinding(keyId: 5, data: Data([5]), singleContractId: nil),
            AppConnect.KeyBinding(keyId: 6, data: Data([6]), singleContractId: Data(repeating: 0xB2, count: 32)),
        ]
        XCTAssertEqual(
            AppConnect.sessionKeyIdsToDisable(
                for: [], appContractId: app, bindings: bindings, currentIdentityPublicKeys: keys),
            [])
        XCTAssertEqual(
            AppConnect.sessionKeyIdsWithUnknownBinding(for: [], bindings: bindings, currentIdentityPublicKeys: keys),
            [])
    }

    func testAStoredLiveKeyOfTheAppMissingFromTheIdentityViewIsReported() {
        let app = Data(repeating: 0xA1, count: 32)
        let otherApp = Data(repeating: 0xB2, count: 32)
        let keys = [Self.key(keyId: 6, data: Data([6]))]
        let bindings = [
            AppConnect.KeyBinding(keyId: 6, data: Data([6]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 7, data: Data([7]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 8, data: Data([8]), singleContractId: app, isDisabled: true),
            AppConnect.KeyBinding(keyId: 9, data: Data([9]), singleContractId: otherApp),
        ]
        XCTAssertEqual(AppConnect.boundKeyIdsMissing(from: keys, appContractId: app, bindings: bindings), [7])
    }

    func testALiveSessionKeyTheStoreCannotPlaceStopsADisconnect() {
        let app = Data(repeating: 0xA1, count: 32)
        let keys = [
            Self.key(keyId: 0, securityLevel: .master, keyType: .ecdsaSecp256k1, data: Data([0])),
            Self.key(keyId: 6, data: Data([6])),
            Self.key(keyId: 7, data: Data([7])),
            Self.key(keyId: 8, data: Data([8]), disabledAt: 1),
            Self.key(keyId: 9, data: Data([9])),
            Self.key(keyId: 11, data: Data([11])),
        ]
        let bindings = [
            AppConnect.KeyBinding(keyId: 6, data: Data([6]), singleContractId: nil),
            AppConnect.KeyBinding(keyId: 11, data: Data([0xFF]), singleContractId: app),
            AppConnect.KeyBinding(keyId: 14, data: Data([14]), singleContractId: nil, hasUnreadableBound: true),
        ]
        // 0 and 8 cannot be session keys that sign; 6 is in the store; 9 has
        // a grant record. 7 is unknown, so is 11 (its row is another key) and
        // 14 (its stored bound cannot be read).
        XCTAssertEqual(
            AppConnect.sessionKeyIdsWithUnknownBinding(
                for: [Self.grant(sessionKeyId: 9)],
                bindings: bindings,
                currentIdentityPublicKeys: keys + [Self.key(keyId: 14, data: Data([14]))]),
            [7, 11, 14])
    }

    private static func grant(sessionKeyId: UInt32) -> AppConnectGrant {
        AppConnectGrant(
            identityId: "identity", appContractId: "app", documentId: "document-\(sessionKeyId)",
            values: .init(appEphemeralPubKeyHash: "aa", walletEphemeralPubKey: "bb", encryptedPayload: "cc"),
            sessionKeyId: sessionKeyId, totalBudget: nil, expiresAt: nil,
            publishedAt: Date(timeIntervalSince1970: 1_000))
    }

    func testSessionKeyIsBoundToTheRequestedContractWithBothLimits() {
        let hash = Data(repeating: 0x11, count: 20)
        let contractId = Data(repeating: 0x33, count: 32)
        let key = AppConnect.sessionIdentityPubkey(
            keyId: 8, publicKeyHash160: hash, appContractId: contractId, totalBudget: 5, expiresAt: 6)
        XCTAssertEqual(key.keyId, 8)
        XCTAssertEqual(key.keyType, .ecdsaHash160)
        XCTAssertEqual(key.purpose, .authentication)
        XCTAssertEqual(key.securityLevel, .high)
        XCTAssertEqual(key.pubkeyBytes, hash)
        XCTAssertEqual(key.contractBounds, .singleContract(id: contractId))
        XCTAssertEqual(key.totalBudget, 5)
        XCTAssertEqual(key.expiresAt, 6)
    }

    func testExpiryIsTheLifetimeAfterNowInMilliseconds() {
        XCTAssertEqual(
            AppConnect.SessionKeyTerms(budgetCredits: 1, lifetime: 60).expiresAt(from: Date(timeIntervalSince1970: 1_000)),
            1_060_000)
    }

    func testResponseCarriesTheSessionKeyOnlyTheAppCanDecrypt() throws {
        let sessionPrivateKey = Data(repeating: 0x5a, count: 32)
        let appEphemeralPrivateKey = Data(repeating: 0x07, count: 32)
        let appEphemeralPubKey = try Secp256k1.compressedPublicKey(privateKey: appEphemeralPrivateKey)
        let walletEphemeralPrivateKeyBytes = Data(repeating: 0x09, count: 32)
        var walletEphemeralPrivateKey = walletEphemeralPrivateKeyBytes

        let values = AppConnect.ResponseValues(try AppConnect.seal(
            sessionPrivateKey,
            appEphemeralPubKey: appEphemeralPubKey,
            walletEphemeralPrivateKey: &walletEphemeralPrivateKey))

        XCTAssertEqual(walletEphemeralPrivateKey, Data(repeating: 0, count: 32), "the ephemeral key is wiped")
        XCTAssertEqual(
            values.appEphemeralPubKeyHash,
            try KeyExchangeCrypto.hash160(appEphemeralPubKey).toHexString())
        let walletEphemeralPubKey = try Secp256k1.compressedPublicKey(privateKey: walletEphemeralPrivateKeyBytes)
        XCTAssertEqual(values.walletEphemeralPubKey, walletEphemeralPubKey.toHexString())
        // 28-byte envelope plus one 32-byte key: the contract's minimum.
        XCTAssertEqual(values.encryptedPayload.count, 60 * 2)

        let payload = try XCTUnwrap(Self.data(hex: values.encryptedPayload))
        // The app's side of the exchange: its private key with the wallet's
        // public key. ECDH is symmetric, so the helper's parameters take the
        // opposite pair to the one that encrypted.
        XCTAssertEqual(
            try KeyExchangeCrypto.decryptLoginKey(
                payload,
                walletEphemeralPriv: appEphemeralPrivateKey,
                appEphemeralPub: walletEphemeralPubKey),
            sessionPrivateKey)
    }

    func testPropertiesJsonHoldsExactlyTheThreeContractFields() throws {
        let values = AppConnect.ResponseValues(
            appEphemeralPubKeyHash: "aa", walletEphemeralPubKey: "bb", encryptedPayload: "cc")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(try values.propertiesJSON().utf8)) as? [String: String])
        XCTAssertEqual(object, [
            "appEphemeralPubKeyHash": "aa",
            "walletEphemeralPubKey": "bb",
            "encryptedPayload": "cc",
        ])
    }

    func testAGrantWrittenBeforeTheDeleteFlagsExistedStillLoads() throws {
        // The shape the first device run stored: no `responseDeleted`, no
        // `keyDisabled`. Losing it would leave that key impossible to find.
        let stored = """
        [{"identityId":"identity","appContractId":"app","documentId":"document",
          "values":{"appEphemeralPubKeyHash":"aa","walletEphemeralPubKey":"bb","encryptedPayload":"cc"},
          "sessionKeyId":6,"totalBudget":5000000000,"expiresAt":1799315762000,"publishedAt":1791539765792}]
        """
        defaults.set(Data(stored.utf8), forKey: "scope.app-connect-responses.v1")
        let store = UserDefaultsAppConnectResponseStore(defaults: defaults, network: .testnet) { "scope" }

        let grant = try XCTUnwrap(store.load().first)
        XCTAssertEqual(grant.sessionKeyId, 6)
        XCTAssertEqual(grant.documentId, "document")
        XCTAssertNil(grant.responseDeleted)
        XCTAssertNil(grant.keyDisabled)
        XCTAssertTrue(grant.hasDeletableResponse)
    }

    func testASavedGrantIsLoadedWithTheSameKey() {
        let store = UserDefaultsAppConnectResponseStore(defaults: defaults, network: .testnet) { "scope" }
        let grant = AppConnectGrant(
            identityId: "identity", appContractId: "app", documentId: nil,
            values: .init(appEphemeralPubKeyHash: "aa", walletEphemeralPubKey: "bb", encryptedPayload: "cc"),
            sessionKeyId: 6, totalBudget: nil, expiresAt: nil,
            publishedAt: Date(timeIntervalSince1970: 1_791_539_765.792_813))
        store.save([grant])

        XCTAssertEqual(store.load().first?.key, grant.key)
    }

    func testAStoreWithoutAScopeCannotPersist() {
        XCTAssertTrue(
            UserDefaultsAppConnectResponseStore(defaults: defaults, network: .testnet) { "scope" }.canPersist)
        XCTAssertFalse(
            UserDefaultsAppConnectResponseStore(defaults: defaults, network: .devnet) { nil }.canPersist)
    }

    func testResponseValuesAreReadBackFromNumbersBase64AndHex() {
        let hash = Data(repeating: 0xAB, count: 20)
        let walletKey = Data([0x02] + [UInt8](repeating: 0x11, count: 32))
        let payload = Data(repeating: 0x22, count: 60)
        let expected = AppConnect.ResponseValues(
            appEphemeralPubKeyHash: hash.toHexString(),
            walletEphemeralPubKey: walletKey.toHexString(),
            encryptedPayload: payload.toHexString())
        let encodings: [(Data) -> Any] = [
            { $0.map(Int.init) }, { $0.base64EncodedString() }, { $0.toHexString() },
        ]
        for encode in encodings {
            let document: [String: Any] = [
                "$id": "id",
                "appEphemeralPubKeyHash": encode(hash),
                "walletEphemeralPubKey": encode(walletKey),
                "encryptedPayload": encode(payload),
            ]
            XCTAssertEqual(
                AppConnect.responseValues(fromDocument: document, appEphemeralPubKeyHash: hash), expected)
            XCTAssertNil(
                AppConnect.responseValues(
                    fromDocument: document, appEphemeralPubKeyHash: Data(repeating: 0xCD, count: 20)))
        }
        XCTAssertNil(AppConnect.responseValues(fromDocument: ["$id": "id"], appEphemeralPubKeyHash: hash))
    }

    func testAnUnconfirmedResponseIsNeitherDeletableNorKnownGone() {
        var grant = Self.grant(sessionKeyId: 6)
        grant.documentId = nil
        XCTAssertTrue(grant.hasUnconfirmedResponse)
        XCTAssertFalse(grant.hasDeletableResponse)

        grant.responseDeleted = true
        XCTAssertFalse(grant.hasUnconfirmedResponse)
    }

    func testARowThisBuildCannotReadIsKeptWhenTheStoreIsSaved() throws {
        let stored = """
        [{"somethingNewer":true,"sessionKeyId":4},
         {"identityId":"identity","appContractId":"app","documentId":"document",
          "values":{"appEphemeralPubKeyHash":"aa","walletEphemeralPubKey":"bb","encryptedPayload":"cc"},
          "sessionKeyId":6,"publishedAt":1791539765792}]
        """
        defaults.set(Data(stored.utf8), forKey: "scope.app-connect-responses.v1")
        let store = UserDefaultsAppConnectResponseStore(defaults: defaults, network: .testnet) { "scope" }

        XCTAssertEqual(store.load().map(\.sessionKeyId), [6])
        store.save(store.load() + [Self.grant(sessionKeyId: 7)])
        XCTAssertEqual(store.load().map(\.sessionKeyId), [6, 7])

        let rows = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(defaults.data(forKey: "scope.app-connect-responses.v1"))) as? [[String: Any]])
        XCTAssertEqual(rows.filter { $0["somethingNewer"] as? Bool == true }.count, 1)

        // Clearing the readable grants must not clear the unreadable row.
        store.save([])
        XCTAssertNotNil(defaults.data(forKey: "scope.app-connect-responses.v1"))
    }

    func testAStoredValueThatIsNotARowListIsNeverReplaced() {
        let suiteName = "AppConnectResponseStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "scope.app-connect-responses.v1"
        let store = UserDefaultsAppConnectResponseStore(defaults: defaults, network: .testnet) { "scope" }

        XCTAssertTrue(store.canPersist)
        for stored in [Data(#"{"rows":[]}"#.utf8), Data([0xFF, 0x00])] {
            defaults.set(stored, forKey: key)
            // Nothing new would be kept, so a login must not start.
            XCTAssertFalse(store.canPersist)
            XCTAssertEqual(store.load().count, 0)
            store.save([Self.grant(sessionKeyId: 7)])
            XCTAssertEqual(defaults.data(forKey: key), stored)
            store.save([])
            XCTAssertEqual(defaults.data(forKey: key), stored)
        }
    }

    func testAGrantedKeyMissingFromTheIdentityViewIsReportedNotAssumedGone() {
        let grants = [9, 13].map { Self.grant(sessionKeyId: $0) }
        let keys = [Self.key(keyId: 9, data: Data([9]), disabledAt: 1)]
        XCTAssertEqual(AppConnect.sessionKeyIdsMissing(from: keys, for: grants), [13])
        XCTAssertEqual(AppConnect.sessionKeyIdsMissing(from: keys, for: [grants[0]]), [])
    }

    func testAGrantHasNothingToDeleteBeforeItIsPublishedOrAfterItsResponseIsGone() {
        var grant = Self.grant(sessionKeyId: 6)
        XCTAssertTrue(grant.hasDeletableResponse)
        grant.responseDeleted = true
        XCTAssertFalse(grant.hasDeletableResponse)
        grant.responseDeleted = nil
        grant.documentId = nil
        XCTAssertFalse(grant.hasDeletableResponse)
    }

    func testPublishedResponsesSurviveAReloadAndAreScoped() {
        let response = AppConnectGrant(
            identityId: "identity", appContractId: "app", documentId: "document",
            values: .init(appEphemeralPubKeyHash: "aa", walletEphemeralPubKey: "bb", encryptedPayload: "cc"),
            sessionKeyId: 8, totalBudget: 5, expiresAt: 6,
            publishedAt: Date(timeIntervalSince1970: 1_000))
        var scope: String? = "scope-a"
        let store = UserDefaultsAppConnectResponseStore(defaults: defaults, network: .testnet) { scope }

        store.save([response])
        XCTAssertEqual(store.load(), [response])

        scope = "scope-b"
        XCTAssertEqual(store.load(), [], "another wallet does not see the records")
        scope = nil
        store.save([response])
        XCTAssertEqual(store.load(), [], "nothing is stored without a wallet scope")

        scope = "scope-a"
        store.save([])
        XCTAssertEqual(store.load(), [])
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let nowMilliseconds: Int64 = 1_800_000_000_000
    private static let app = Data(repeating: 0xA1, count: 32)
    private static let sessionKeyHash = Data(repeating: 0x11, count: 20)
    private static let terms = AppConnect.SessionKeyTerms(budgetCredits: 500, lifetime: 3_600)

    /// Key 9 as the one-QR login registers it, within `terms`.
    private static func sessionKey(
        purpose: KeyPurpose = .authentication,
        securityLevel: SecurityLevel = .high,
        disabledAt: Int64? = nil,
        totalBudget: UInt64? = terms.budgetCredits,
        expiresAt: Int64? = nowMilliseconds + 3_600_000
    ) -> ManagedIdentity.IdentityPublicKeyInfo {
        key(
            keyId: 9, purpose: purpose, securityLevel: securityLevel, data: sessionKeyHash,
            disabledAt: disabledAt, totalBudget: totalBudget, expiresAt: expiresAt)
    }

    /// The state of the session key for `app`; by default the store shows
    /// key 9 bound to it.
    private static func sessionKeyState(
        keys: [ManagedIdentity.IdentityPublicKeyInfo],
        bindings: [AppConnect.KeyBinding] = [
            AppConnect.KeyBinding(keyId: 9, data: sessionKeyHash, singleContractId: app),
        ],
        grantedKeyIds: Set<UInt32> = []
    ) -> AppConnect.SessionKeyState {
        AppConnect.sessionKeyState(
            publicKeyHash160: sessionKeyHash,
            currentIdentityPublicKeys: keys,
            appContractId: app,
            bindings: bindings,
            grantedKeyIds: grantedKeyIds,
            terms: terms,
            now: now)
    }

    private static func key(
        keyId: Int32,
        purpose: KeyPurpose = .authentication,
        securityLevel: SecurityLevel = .high,
        keyType: KeyType = .ecdsaHash160,
        data: Data,
        disabledAt: Int64? = nil,
        totalBudget: UInt64? = nil,
        expiresAt: Int64? = nil
    ) -> ManagedIdentity.IdentityPublicKeyInfo {
        ManagedIdentity.IdentityPublicKeyInfo(
            keyId: keyId, purpose: purpose, securityLevel: securityLevel, keyType: keyType,
            readOnly: false, disabledAt: disabledAt, data: data, totalBudget: totalBudget, expiresAt: expiresAt)
    }

    private static func data(hex: String) -> Data? {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            guard let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex),
                  let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
