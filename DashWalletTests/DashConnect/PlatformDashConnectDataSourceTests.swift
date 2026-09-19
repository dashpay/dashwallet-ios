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
            .identityUpdate(try wallet.parseIdentityUpdateTransition(bytes))
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
            .tokenPurchase(ManagedPlatformWallet.ParsedTokenPurchaseTransition(
                ownerId: ownerId,
                dataContractId: contractId,
                tokenId: tokenId,
                tokenContractPosition: 3,
                tokenCount: 100,
                totalAgreedPrice: 100_000_000
            ))
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
            data: data
        )
    }

    private static let taggedIdentityUpdateFixtureBase64 =
        "BgAREREREREREREREREREREREREREREREREREREREREREQcJAgARAAACAAAhAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICQaqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqABIAAQIBAUREREREREREREREREREREREREREREREREREREREREREB3Byb2ZpbGUBIQMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA0G7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7uwIECAIDQZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZ"

    private static let taglessIdentityUpdateFixtureBase64 =
        "ABERERERERERERERERERERERERERERERERERERERERERBwkCABEAAAIAACECAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgJBqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqoAEgABAgEBREREREREREREREREREREREREREREREREREREREREREQHcHJvZmlsZQEhAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDQbu7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7AgQIAgNBmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZk="

    private static let realKeyRegistrationFixtureHex =
        "0089fd6ddba75136a4fea02dc7d89ef0ca5bcc32ccf12fb8da6a1a03740567ae7201010200060200020000145e24e38a86e720f61757647996957e322686abb7000007000103000021035e8cfb0785b54e8902a3dc17bdaad8a5738c6019a18ebc527f79d1c64a27826a4120dc911df1d1e6cccf8c95ec0d423c928433397933de6dd9ad006bc40dc0334d6d270d50c6d5e2dcdc5560e40487ddfe28bd1066d0729fad4b26f92ae33f12a04b00000000"

    // MARK: - Per-network configuration

    func testTestnetResolvesThePinnedKeyExchangeContract() throws {
        let id = try DashConnectNetworkConfiguration.loginKeyExchangeContractId(for: .testnet, devnetContractId: nil)

        XCTAssertEqual(id.toBase58String(), "7UaqHGBJBbRLJ4fUWS45cnud8PPUugJWoGTt1SKwHJ2P")
    }

    func testDevnetResolvesTheConfiguredContract() throws {
        let configured = "7UaqHGBJBbRLJ4fUWS45cnud8PPUugJWoGTt1SKwHJ2P"

        let id = try DashConnectNetworkConfiguration.loginKeyExchangeContractId(for: .devnet, devnetContractId: configured)

        XCTAssertEqual(id.toBase58String(), configured)
    }

    func testDevnetWithoutAUsableContractIdIsNotConfigured() {
        for configured in [nil, "not-an-identifier"] as [String?] {
            XCTAssertThrowsError(
                try DashConnectNetworkConfiguration.loginKeyExchangeContractId(for: .devnet, devnetContractId: configured)
            ) { error in
                XCTAssertEqual(error as? DashConnectPlatformError, .devnetLoginContractNotConfigured)
            }
        }
    }

    func testMainnetHasNoKeyExchangeContractYet() {
        XCTAssertFalse(DashConnectNetworkConfiguration.isAvailable(on: .mainnet))
        XCTAssertThrowsError(
            try DashConnectNetworkConfiguration.loginKeyExchangeContractId(for: .mainnet, devnetContractId: nil)
        ) { error in
            XCTAssertEqual(error as? DashConnectPlatformError, .loginContractUnavailable)
        }
    }

    func testAvailabilityFollowsTheKeyExchangeContract() {
        XCTAssertTrue(DashConnectNetworkConfiguration.isAvailable(on: .testnet))
        XCTAssertTrue(DashConnectNetworkConfiguration.isAvailable(on: .devnet))
        XCTAssertEqual(
            DashConnectNetworkConfiguration.isAvailable(on: .mainnet),
            DashConnectNetworkConfiguration.mainnetLoginKeyExchangeContractId != nil
        )
    }

    func testRuntimeNetworkMatchesTheDashConnectNetwork() {
        XCTAssertEqual(DashConnectNetworkConfiguration.runtimeNetwork(for: .mainnet), .mainnet)
        XCTAssertEqual(DashConnectNetworkConfiguration.runtimeNetwork(for: .testnet), .testnet)
        XCTAssertEqual(DashConnectNetworkConfiguration.runtimeNetwork(for: .devnet), .devnet)
    }

    /// An app's contract id is only meaningful on the chain it was registered
    /// on, so known branding does not leak to another network.
    func testKnownAppBrandingIsPerNetwork() {
        let yapprTestnet = "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F"

        let onTestnet = DashConnectNetworkConfiguration.appMetadata(
            contractId: yapprTestnet, unauthenticatedLabel: " QR label ", on: .testnet)
        let onMainnet = DashConnectNetworkConfiguration.appMetadata(
            contractId: yapprTestnet, unauthenticatedLabel: " QR label ", on: .mainnet)

        XCTAssertEqual(onTestnet, DashConnectAppMetadata(name: "Yappr", url: "yap.pr"))
        XCTAssertEqual(onMainnet, DashConnectAppMetadata(name: "QR label", url: ""))
    }

    func testParseQRRejectsALoginForAnotherNetwork() async throws {
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: TestDashConnectStore(initialConnections: [])
        )
        let label = Data("Yappr".utf8)
        let payload = Data([0x01])
            + (try Secp256k1.compressedPublicKey(privateKey: Data(repeating: 0x01, count: 32)))
            + Data(repeating: 0x44, count: 32)
            + Data([UInt8(label.count)])
            + label
        let mainnetUri = "dash-key:\(payload.toBase58String())?n=\(DashConnectNetwork.mainnet.rawValue)&v=1"

        do {
            _ = try await dataSource.parseQR(mainnetUri)
            XCTFail("A mainnet login must not parse on a testnet data source")
        } catch {
            XCTAssertEqual(
                error as? DashConnectPlatformError,
                .unsupportedRequestNetwork(expected: .testnet, actual: .mainnet)
            )
        }
    }
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

    func approveLogin(_ request: DashKeyRequest) async throws -> DAppConnection {
        throw PurchaseSpyError.unsupported
    }

    func handleStateTransition(_ request: DashStRequest) async throws -> DashConnectStAction {
        throw PurchaseSpyError.unsupported
    }

    func disconnect(id: String) async {
        XCTFail("disconnect is not part of the purchase approval flow")
    }

    func remove(id: String) async {
        XCTFail("remove is not part of the purchase approval flow")
    }
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
