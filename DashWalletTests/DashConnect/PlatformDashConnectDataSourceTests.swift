import Combine
import Foundation
import XCTest
@testable import dashpay
@testable import SwiftDashSDK

final class PlatformDashConnectDataSourceTests: XCTestCase {
    // MARK: Consensus refusal of an identity update (AC-20b, ADR 0012)

    private static let refusedAt = Date(timeIntervalSince1970: 1_773_132_300)
    private static let consensusKinds: [PlatformConsensusError.Kind] = [.basic, .signature, .fee, .state]

    func testASDKConsensusRejectionOfEveryFamilyIsARefusalWithItsCode() {
        for (index, kind) in Self.consensusKinds.enumerated() {
            let code = UInt32(10_000 + index * 10_000 + 212)
            let error = SDKError.consensusRejection(PlatformConsensusError(code: code, kind: kind), "rendered text")
            XCTAssertEqual(
                PlatformDashConnectDataSource.consensusRefusal(from: error, at: Self.refusedAt),
                AppConnect.ConsensusRefusal(code: code, at: Self.refusedAt), "SDKError \(kind)")
        }
    }

    func testAPlatformWalletConsensusRejectionOfEveryFamilyIsARefusalWithItsCode() {
        for (index, kind) in Self.consensusKinds.enumerated() {
            let code = UInt32(10_000 + index * 10_000 + 407)
            let error = PlatformWalletError.consensusRejection(PlatformConsensusError(code: code, kind: kind), "rendered text")
            XCTAssertEqual(
                PlatformDashConnectDataSource.consensusRefusal(from: error, at: Self.refusedAt),
                AppConnect.ConsensusRefusal(code: code, at: Self.refusedAt), "PlatformWalletError \(kind)")
        }
    }

    func testARefusalCarriesTheCodeAndTheDateAndNeverThePlatformMessage() throws {
        let message = "identity 4Xh9 has insufficient balance"
        let error = SDKError.consensusRejection(PlatformConsensusError(code: 10_212, kind: .basic), message)
        let refusal = try XCTUnwrap(PlatformDashConnectDataSource.consensusRefusal(from: error, at: Self.refusedAt))
        XCTAssertFalse(String(describing: refusal).contains(message))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(refusal), as: UTF8.self).contains(message))
    }

    func testATimeoutOrATransportErrorIsNotARefusal() {
        let errors: [(String, Error)] = [
            ("SDK timeout", SDKError.timeout("deadline")),
            ("SDK network error", SDKError.networkError("connection lost")),
            ("URLError timed out", URLError(.timedOut)),
            ("URLError offline", URLError(.notConnectedToInternet)),
            ("cancelled", CancellationError()),
            ("wallet shutdown barrier", PlatformWalletError.shutdownIncomplete("busy")),
        ]
        for (name, error) in errors {
            XCTAssertNil(PlatformDashConnectDataSource.consensusRefusal(from: error, at: Self.refusedAt), name)
        }
    }

    func testAnUnknownOrUnconfirmedErrorIsNotARefusal() {
        let errors: [(String, Error)] = [
            ("SDK unknown", SDKError.unknown("???")),
            ("SDK internal", SDKError.internalError("oops")),
            ("SDK protocol", SDKError.protocolError("bad reply")),
            ("SDK invalid state", SDKError.invalidState("no sdk")),
            ("SDK not found", SDKError.notFound("identity")),
            ("SDK serialization", SDKError.serializationError("bad")),
            ("wallet unknown", PlatformWalletError.unknown("???")),
            ("wallet operation", PlatformWalletError.walletOperation("failed")),
            ("wallet broadcast unconfirmed", PlatformWalletError.transactionBroadcastUnconfirmed("maybe on the network")),
            ("wallet address nonce race (typed, no code)", PlatformWalletError.addressNonceMismatch("raced")),
            ("an error of the app", DashConnectPlatformError.approvalOutOfDate),
        ]
        for (name, error) in errors {
            XCTAssertNil(PlatformDashConnectDataSource.consensusRefusal(from: error, at: Self.refusedAt), name)
        }
    }

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
            store: TestDashConnectStore(initialConnections: [existing]),
            activeWalletIdHex: { "wallet" }
        )

        let request = await dataSource.makeConnectionRequest(from: MockDashConnectDataSource.sampleLoginRequest)

        var found = request.existingConnection
        XCTAssertNotNil(found?.scope, "a row from the published list names its scope")
        found?.scope = nil
        XCTAssertEqual(found, existing)
        XCTAssertEqual(request.appContractId, existing.id)
    }

    func testMakeConnectionRequestCarriesAConfirmingConnection() async {
        let existing = DAppConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            name: "Yappr",
            url: "yap.pr",
            status: .confirming,
            updatedAt: Date(timeIntervalSince1970: 1_773_132_300)
        )
        let dataSource = PlatformDashConnectDataSource(
            // Explicit: the default follows the app's current network, and on
            // a fresh install that is mainnet, which the initializer rejects.
            supportedNetwork: .testnet,
            store: TestDashConnectStore(initialConnections: [existing]),
            activeWalletIdHex: { "wallet" }
        )

        let request = await dataSource.makeConnectionRequest(from: MockDashConnectDataSource.sampleLoginRequest)

        var found = request.existingConnection
        XCTAssertNotNil(found?.scope, "a row from the published list names its scope")
        found?.scope = nil
        XCTAssertEqual(found, existing)
    }

    /// A Refused attempt connected nothing: the sheet of a new request does
    /// not offer it as the connection to sign in to again.
    func testMakeConnectionRequestDoesNotCarryARefusedAttempt() async {
        let refused = DAppConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
            name: "Yappr",
            url: "yap.pr",
            status: .refused,
            updatedAt: Date(timeIntervalSince1970: 1_773_132_300)
        )
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: TestDashConnectStore(initialConnections: [refused]),
            activeWalletIdHex: { "wallet" }
        )

        let request = await dataSource.makeConnectionRequest(from: MockDashConnectDataSource.sampleLoginRequest)

        XCTAssertEqual(request.appContractId, refused.id)
        XCTAssertNil(request.existingConnection)
    }

    /// A sheet whose details could not be read says so: a failed read is
    /// not details with only the app's id, which would replace the ones
    /// shown.
    func testConnectionDetailsThatCouldNotBeReadAreUnknown() async {
        let existing = DAppConnection(
            id: "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F", name: "Yappr", url: "yap.pr", status: .active,
            updatedAt: Date(timeIntervalSince1970: 1_773_132_300))
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: TestDashConnectStore(initialConnections: [existing]),
            activeWalletIdHex: { "wallet" }
        )
        let request = await dataSource.makeConnectionRequest(from: MockDashConnectDataSource.sampleLoginRequest)
        let scope = request.existingConnection?.scope
        XCTAssertNotNil(scope)
        // No SDK runs in tests: the identity cannot be read.
        let details = await dataSource.connectionDetails(id: existing.id, scope: scope)
        XCTAssertNil(details)
    }

    func testAVersion1LoginQRIsRefusedWhenScanned() async {
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: TestDashConnectStore(initialConnections: []),
            activeWalletIdHex: { "wallet" }
        )
        do {
            _ = try await dataSource.parseQR(MockDashConnectDataSource.sampleLoginQRCode)
            XCTFail("a v1 login QR was taken")
        } catch {
            XCTAssertEqual(error as? AppConnect.Refusal, AppConnect.v1Refusal)
        }
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
            store: TestDashConnectStore(initialConnections: [existing]),
            activeWalletIdHex: { "wallet" }
        )
        let request = try makeLoginRequest(
            contractId: Data(repeating: 0x44, count: 32),
            label: "Something else"
        )

        let connectionRequest = await dataSource.makeConnectionRequest(from: request)

        XCTAssertNil(connectionRequest.existingConnection)
    }

    func testParseQRTurnsAConnectRequestForItsNetworkIntoALoginThatKeepsTheRequest() async throws {
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .devnet,
            store: TestDashConnectStore(initialConnections: []),
            activeWalletIdHex: { "wallet" }
        )
        let uri = DashConnectUriTests.connectVectorUri

        let qr = try await dataSource.parseQR(uri)

        guard case let .login(request) = qr else { return XCTFail("expected a login, got \(qr)") }
        XCTAssertEqual(request.network, .devnet)
        XCTAssertEqual(request.appConnect, try DashConnectUri.parseConnectRequest(uri))
    }

    func testParseQRRefusesAConnectRequestForAnotherNetwork() async {
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: TestDashConnectStore(initialConnections: []),
            activeWalletIdHex: { "wallet" }
        )

        do {
            _ = try await dataSource.parseQR(DashConnectUriTests.connectVectorUri)
            XCTFail("a devnet request was accepted by a testnet wallet")
        } catch {
            XCTAssertEqual(
                error as? DashConnectPlatformError,
                .unsupportedRequestNetwork(expected: .testnet, actual: .devnet)
            )
        }
    }

    func testParseQRAsksForANewerWalletForAnUnknownDashpayVerb() async {
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: TestDashConnectStore(initialConnections: []),
            activeWalletIdHex: { "wallet" }
        )

        do {
            _ = try await dataSource.parseQR("dashpay://sign?v=3")
            XCTFail("an unknown dashpay verb was accepted")
        } catch {
            XCTAssertEqual(error as? DashConnectMockError, .needsNewerWallet)
        }
    }

    func testParserRefusesAnIdentityUpdate() throws {
        let wallet = ManagedPlatformWallet(handle: 0, walletId: Data(repeating: 0x00, count: 32))
        let bytes = try XCTUnwrap(Data(base64Encoded: Self.taggedIdentityUpdateFixtureBase64))
        let appParser = PlatformWalletDashConnectStateTransitionParser { bytes in
            Self.parsed(.identityUpdate(try wallet.parseIdentityUpdateTransition(bytes)))
        }
        XCTAssertThrowsError(try appParser.parse(bytes)) { error in
            guard case DashConnectPlatformError.unsupportedStateTransition = error else {
                return XCTFail("Expected an unsupported state transition, got \(error)")
            }
        }
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

    private static let taggedIdentityUpdateFixtureBase64 =
        "BgAREREREREREREREREREREREREREREREREREREREREREQcJAgARAAACAAAhAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICQaqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqABIAAQIBAUREREREREREREREREREREREREREREREREREREREREREB3Byb2ZpbGUBIQMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA0G7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7uwIECAIDQZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZ"


}

private extension AppConnect.GrantPlan {
    static let sample = AppConnect.GrantPlan(
        appId: Data(repeating: 0xA1, count: 32), appEphemeralPubKeyHash: Data(repeating: 0xEE, count: 20),
        auth: [], encryption: [], connectionId: nil, identityHint: nil, createdAt: 0)
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

    var scopeKey: String? { nil }

    func pinned(toWalletIdHex walletIdHex: String) -> any DashConnectStore { self }
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

        var shown = Self.connection
        shown.scope = "wallet-a t"
        viewModel.disconnect(shown)
        await waitUntil { !viewModel.isDisconnecting }

        XCTAssertEqual(spy.disconnectedIds, [Self.connection.id])
        XCTAssertEqual(spy.disconnectedScopes, ["wallet-a t"], "the row goes back with the scope it was shown for")
        XCTAssertNil(viewModel.message)
    }

    /// One disconnect turns off everything it can; it asks no second
    /// question, so the data source is called once and nothing is left on
    /// screen to answer.
    func testADisconnectAsksNoSecondQuestion() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 5)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }

        XCTAssertNil(viewModel.message, "nothing to answer after a disconnect that turned everything off")
        XCTAssertEqual(spy.disconnectedIds, [Self.connection.id], "one call, no follow-up")
    }

    /// A clean disconnect that also turned off keys no approval names says
    /// how many, under a neutral title.
    func testADisconnectThatTurnedOffUnrecordedKeysSaysHowMany() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 5, unrecordedKeysTurnedOff: 2)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }

        XCTAssertEqual(viewModel.message?.kind, .notice)
        let text = viewModel.message?.text ?? ""
        XCTAssertTrue(text.contains("no record of giving (2)"), text)
    }

    /// A disconnect that stopped part-way says what is still live, and
    /// Disconnect can run again.
    func testADisconnectThatStoppedPartWayNamesWhatIsStillLiveAndCanRunAgain() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 10, keysStillLive: 13)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }
        XCTAssertEqual(viewModel.message?.text.contains("13"), true, "the message names how many keys are still live")

        viewModel.message = nil
        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 13)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 2 }
        XCTAssertEqual(spy.disconnectedIds.count, 2, "Disconnect runs again")
        XCTAssertNil(viewModel.message)
    }

    /// A confirmed disconnect that cannot run now says why.
    func testADisconnectThatCannotRunNowSaysWhy() {
        let viewModel = ConnectionsViewModel(dataSource: PurchaseApprovalSpy(), featureUnavailable: false)
        viewModel.isProcessingStateTransition = true
        viewModel.disconnect(Self.connection)
        XCTAssertFalse(viewModel.isDisconnecting)
        XCTAssertEqual(viewModel.message?.kind, .error)
        XCTAssertEqual(viewModel.message?.text.contains("in progress"), true)
    }

    func testADisconnectThatCouldNotCheckSomeKeysSaysSo() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 3, keysNotChecked: 4)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }

        XCTAssertEqual(viewModel.message?.text.contains("4"), true)
    }

    /// AC-18: keys whose bounds are unknown stay on the identity; the text
    /// must not claim the disconnect is complete.
    func testADisconnectThatCouldNotCheckSomeKeysDoesNotSayDisconnected() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 3, keysNotChecked: 4)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }

        XCTAssertEqual(viewModel.message?.text.hasPrefix("Disconnected.") == false, true, "text: \(viewModel.message?.text ?? "nil")")
    }

    /// Keys a disconnect could not tell to be the app's are said to be left
    /// on; the text claims nothing about the connection's row, which may go.
    func testKeysThatCouldNotBeCheckedAreSaidToBeLeftOn() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 1, keysNotChecked: 2)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }

        let text = viewModel.message?.text ?? ""
        XCTAssertTrue(text.contains("(2), so it left them on"), text)
        XCTAssertFalse(text.contains("stays listed"), text)
    }

    /// Keys another app of the same developer may hold: their own text,
    /// pointing to the key's row, without a retry hint, and not an error.
    func testAKeyNotAttributableIsReportedWithoutARetryHint() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 1, keysNotAttributable: 1)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }

        let text = viewModel.message?.text ?? ""
        XCTAssertEqual(viewModel.message?.kind, .notice)
        XCTAssertEqual(viewModel.message?.title, "Disconnected", "not titled Success over keys left on")
        XCTAssertTrue(text.contains("may belong to another app of the same developer"), text)
        XCTAssertTrue(text.contains("its own row"), text)
        XCTAssertFalse(text.contains("again later"), text)
    }

    /// R13: a fence left on can still let the sign-in land: an error.
    func testADisconnectThatLeftAFenceOnIsReportedAsAFailure() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        spy.disconnectResult = DashConnectDisconnectResult(fencesNotPlaced: 1)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }

        XCTAssertEqual(viewModel.message?.kind, .error)
        let text = viewModel.message?.text.lowercased() ?? ""
        XCTAssertTrue(text.contains("sign-in") && text.contains("may still"), "says the sign-in may still land: \(text)")
        XCTAssertTrue(text.contains("disconnect") && text.contains("again"), "asks to disconnect again: \(text)")
    }

    /// T32 (F3): a fence placed and left on cannot let the sign-in land; the
    /// connection ends Disconnected and this is not an error.
    func testADisconnectThatLeftOnlyPlacedFencesOnShowsNoError() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 3, fencesLeftOn: 2)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }

        XCTAssertNotEqual(viewModel.message?.kind, .error, "text: \(viewModel.message?.text ?? "nil")")
        XCTAssertEqual(viewModel.message?.text.contains("stays listed") ?? false, false)
    }

    /// With the login unresolved the sheet's action asks again and approves
    /// nothing.
    func testAnUnresolvedLoginIsAskedForAgainInsteadOfApproved() async {
        let unresolved = ConnectionRequest(loginRequest: MockDashConnectDataSource.sampleLoginRequest)
        let resolved = Self.consent(identityId: "identity-a")
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
        let shown = Self.consent(identityId: "identity-a")
        let spy = LoginApprovalSpy(shown: [shown])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        viewModel.onQRScanned("login")
        await waitUntil { viewModel.pendingRequest != nil }
        viewModel.approvePendingRequest()
        await waitUntil { viewModel.pendingRequest == nil }

        XCTAssertEqual(spy.approvedConsents, [shown])
        XCTAssertNil(viewModel.approveError)
    }

    /// An App Connect request with a callback, approved from a scanned QR
    /// code or from a link opened on this phone.
    private func approveAppConnectRequest(byLink: Bool) async throws -> (opened: [URL], asked: URL?) {
        var request = MockDashConnectDataSource.sampleLoginRequest
        request.appConnect = try DashConnectUri.parseAppConnectRequest(
            "dash-key:2fAANHHASdojyjV9Sqa2wf2nwZE8kLLqmeHpZWa8sBfaGsddVqyMG2ZVte7xJkTKsXvmFYbXzXbNnMo7bJQBxNcf79N8YWi7pLKyb39Rqv6b1KUmxw9UeJGYz2CV9hFGNUQtcyMYVq2Fg6vAxtxpYays61H8gLMcWqaG8TfgGA3H7setGAYiBsM5YmdZgeuCdGAHSwfNfav5cfFjXNDkPWv37UNSgFxj6o58jfXc3kCLKqLJtc5ZPjm1thEGYxK8HVYBi8fRQeEVy76n27DXGrVTyHz94CfJRuMnH76xGYbMgeuvurxjJMLrQgWUu53cjocYyzzNWdJrgs2D5?n=d&v=2&cb=https%3A%2F%2Fyap.pr%2Fconnect%3Fr%3Dd77dc0da9df83a47755a15c42c5d9db9d7a7fd62")
        let spy = LoginApprovalSpy(shown: [Self.consent(identityId: "identity-a")], loginRequest: request)
        let opened = OpenedURLs()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false, openURL: { opened.urls.append($0) })

        if byLink {
            viewModel.onURIReceived("login")
        } else {
            viewModel.onQRScanned("login")
        }
        await waitUntil { viewModel.pendingRequest != nil }
        viewModel.approvePendingRequest()
        await waitUntil { viewModel.pendingRequest == nil }
        XCTAssertEqual(spy.approvedConsents.count, 1)
        return (opened.urls, viewModel.pendingReturn)
    }

    /// A QR code scanned off another screen is answered there: opening the
    /// callback on this phone would start an unrelated session of the app.
    func testApprovingAScannedAppConnectRequestDoesNotOpenItsCallback() async throws {
        let answered = try await approveAppConnectRequest(byLink: false)
        XCTAssertEqual(answered.opened, [])
        XCTAssertNil(answered.asked, "nothing to ask about either")
    }

    /// A link opened by the app on this phone returns to it when answered,
    /// once the user says yes on the sheet.
    func testApprovingALinkedAppConnectRequestAsksAboutItsCallback() async throws {
        let answered = try await approveAppConnectRequest(byLink: true)
        XCTAssertEqual(answered.opened, [])
        XCTAssertEqual(answered.asked?.host, "yap.pr")
        XCTAssertEqual(answered.asked?.absoluteString.contains("ac=ok"), true)
    }

    /// An attempt failed, the next one was cancelled at the PIN prompt, and
    /// the user then closed the sheet: the app hears the user's last answer,
    /// a decline, not the earlier failure.
    func testClosingTheSheetAfterACancelledRetryReportsADecline() async throws {
        var request = MockDashConnectDataSource.sampleLoginRequest
        request.appConnect = try DashConnectUri.parseAppConnectRequest(
            "dash-key:2fAANHHASdojyjV9Sqa2wf2nwZE8kLLqmeHpZWa8sBfaGsddVqyMG2ZVte7xJkTKsXvmFYbXzXbNnMo7bJQBxNcf79N8YWi7pLKyb39Rqv6b1KUmxw9UeJGYz2CV9hFGNUQtcyMYVq2Fg6vAxtxpYays61H8gLMcWqaG8TfgGA3H7setGAYiBsM5YmdZgeuCdGAHSwfNfav5cfFjXNDkPWv37UNSgFxj6o58jfXc3kCLKqLJtc5ZPjm1thEGYxK8HVYBi8fRQeEVy76n27DXGrVTyHz94CfJRuMnH76xGYbMgeuvurxjJMLrQgWUu53cjocYyzzNWdJrgs2D5?n=d&v=2&cb=https%3A%2F%2Fyap.pr%2Fconnect%3Fr%3Dd77dc0da9df83a47755a15c42c5d9db9d7a7fd62")
        let spy = LoginApprovalSpy(shown: [Self.consent(identityId: "identity-a")], loginRequest: request)
        spy.approveFailures = [DashConnectPlatformError.noIdentity, DashConnectPlatformError.authorizationCancelled]
        let opened = OpenedURLs()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false, openURL: { opened.urls.append($0) })

        viewModel.onURIReceived("login")
        await waitUntil { viewModel.pendingRequest != nil }
        viewModel.approvePendingRequest()
        await waitUntil { spy.approvedConsents.count == 1 && !viewModel.isApproving }
        viewModel.approvePendingRequest()
        await waitUntil { spy.approvedConsents.count == 2 && !viewModel.isApproving }
        viewModel.denyPendingRequest(asksToReturn: true)

        XCTAssertEqual(opened.urls, [])
        XCTAssertEqual(viewModel.pendingReturn?.absoluteString.contains("ac=declined"), true)
    }

    /// The request was refused when the user tapped Approve, after the sheet
    /// had shown where it returns: closing the sheet tells the app why.
    func testClosingTheSheetAfterARefusalAtApprovalReportsTheRefusal() async throws {
        var request = MockDashConnectDataSource.sampleLoginRequest
        request.appConnect = try DashConnectUri.parseAppConnectRequest(
            "dash-key:2fAANHHASdojyjV9Sqa2wf2nwZE8kLLqmeHpZWa8sBfaGsddVqyMG2ZVte7xJkTKsXvmFYbXzXbNnMo7bJQBxNcf79N8YWi7pLKyb39Rqv6b1KUmxw9UeJGYz2CV9hFGNUQtcyMYVq2Fg6vAxtxpYays61H8gLMcWqaG8TfgGA3H7setGAYiBsM5YmdZgeuCdGAHSwfNfav5cfFjXNDkPWv37UNSgFxj6o58jfXc3kCLKqLJtc5ZPjm1thEGYxK8HVYBi8fRQeEVy76n27DXGrVTyHz94CfJRuMnH76xGYbMgeuvurxjJMLrQgWUu53cjocYyzzNWdJrgs2D5?n=d&v=2&cb=https%3A%2F%2Fyap.pr%2Fconnect%3Fr%3Dd77dc0da9df83a47755a15c42c5d9db9d7a7fd62")
        let spy = LoginApprovalSpy(shown: [Self.consent(identityId: "identity-a")], loginRequest: request)
        spy.approveFailures = [AppConnect.Refusal(.stale, "The request is too old.")]
        let opened = OpenedURLs()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false, openURL: { opened.urls.append($0) })

        viewModel.onURIReceived("login")
        await waitUntil { viewModel.pendingRequest != nil }
        viewModel.approvePendingRequest()
        await waitUntil { spy.approvedConsents.count == 1 && !viewModel.isApproving }
        XCTAssertEqual(viewModel.pendingRequest?.login.isApprovable, false)
        viewModel.denyPendingRequest(asksToReturn: true)

        // The return is asked about first, as every return is.
        XCTAssertEqual(opened.urls, [])
        XCTAssertEqual(viewModel.pendingReturn?.absoluteString.contains("ac=stale"), true)
    }

    /// Another identity became active, or the network answers with the other
    /// login, while the sheet was up: nothing is approved on the old sheet,
    /// and the user decides again on what is true now.
    func testAnApprovalThatIsOutOfDateShowsTheRequestAgainAsItStands() async {
        let shown = Self.consent(identityId: "identity-a")
        let current = Self.consent(identityId: "identity-b")
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

    /// The wallet could not check which login the network gets at approve
    /// time: the sheet is rebuilt. When it still cannot tell, the sheet says
    /// so itself and no error is added; when it can again, a note says why
    /// nothing was approved.
    func testAnApprovalThatCouldNotCheckTheLoginRebuildsTheSheet() async {
        let shown = Self.consent(identityId: "identity-a")
        var unresolved = shown
        unresolved.login = .unresolved
        unresolved.unresolvedLoginReason = "no nodes"
        let spy = LoginApprovalSpy(shown: [shown, unresolved, shown])
        spy.approveFailures = [DashConnectPlatformError.loginUnresolved, DashConnectPlatformError.loginUnresolved]
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        viewModel.onQRScanned("login")
        await waitUntil { viewModel.pendingRequest != nil }
        viewModel.approvePendingRequest()
        await waitUntil { !viewModel.isApproving }

        XCTAssertEqual(viewModel.pendingRequest, unresolved)
        XCTAssertNil(viewModel.approveError, "the sheet states the unresolved login itself")

        viewModel.retryPendingRequest()
        await waitUntil { viewModel.pendingRequest == shown }
        viewModel.approvePendingRequest()
        await waitUntil { !viewModel.isApproving }

        XCTAssertEqual(viewModel.pendingRequest, shown)
        XCTAssertEqual(viewModel.approveError, DashConnectPlatformError.loginUnresolved.localizedDescription)
    }

    private static func consent(identityId: String) -> ConnectionRequest {
        ConnectionRequest(
            loginRequest: MockDashConnectDataSource.sampleLoginRequest,
            appLabel: "App",
            appUrl: "",
            walletUsername: nil,
            walletIdentityId: identityId,
            existingConnection: nil,
            login: .appConnect(.sample))
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

    var listing: AnyPublisher<DashConnectListing, Never> {
        Just(DashConnectListing(scope: nil, rows: [], disconnected: [])).eraseToAnyPublisher()
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

    func handleStateTransition(_ request: DashStRequest, refusesTokenPurchase: Bool) async throws -> DashConnectStAction {
        throw PurchaseSpyError.unsupported
    }

    private var storedDisconnectFailure: Error?
    private var storedDisconnectedIds: [String] = []
    private var storedDisconnectedScopes: [String?] = []

    var disconnectFailure: Error? {
        get { lock.withLock { storedDisconnectFailure } }
        set { lock.withLock { storedDisconnectFailure = newValue } }
    }

    var disconnectedIds: [String] {
        lock.withLock { storedDisconnectedIds }
    }

    var disconnectedScopes: [String?] {
        lock.withLock { storedDisconnectedScopes }
    }

    private var storedDisconnectResult = DashConnectDisconnectResult()

    /// What a successful disconnect reports.
    var disconnectResult: DashConnectDisconnectResult {
        get { lock.withLock { storedDisconnectResult } }
        set { lock.withLock { storedDisconnectResult = newValue } }
    }

    func disconnect(id: String, scope: String?) async throws -> DashConnectDisconnectResult {
        let (failure, result) = lock.withLock { () -> (Error?, DashConnectDisconnectResult) in
            storedDisconnectedIds.append(id)
            storedDisconnectedScopes.append(scope)
            return (storedDisconnectFailure, storedDisconnectResult)
        }
        if let failure { throw failure }
        return result
    }

    func remove(id: String, scope: String?) async {
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

    private let loginRequest: DashKeyRequest

    init(shown: [ConnectionRequest], loginRequest: DashKeyRequest = MockDashConnectDataSource.sampleLoginRequest) {
        self.shown = shown
        self.loginRequest = loginRequest
    }

    /// Thrown by the approvals in order, one each; later approvals succeed.
    var approveFailures: [Error] {
        get { lock.withLock { storedApproveFailures } }
        set { lock.withLock { storedApproveFailures = newValue } }
    }

    var approvedConsents: [ConnectionRequest] {
        lock.withLock { storedApprovedConsents }
    }


    /// The disconnected apps the page lists; `nil` reads as unreadable.
    var history: [DisconnectedConnection] = []
    /// The connections the page lists.
    var rows: [DAppConnection] = []
    private var storedSuspendsApproval = false
    private var storedIsApprovalSuspended = false
    private var approvalGate: CheckedContinuation<Void, Never>?

    /// When true, `approveLogin` suspends after recording its consent, until
    /// `releaseApproval()`.
    var suspendsApproval: Bool {
        get { lock.withLock { storedSuspendsApproval } }
        set { lock.withLock { storedSuspendsApproval = newValue } }
    }

    var isApprovalSuspended: Bool {
        lock.withLock { storedIsApprovalSuspended }
    }

    /// Lets a suspended `approveLogin` finish.
    func releaseApproval() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let waiting = approvalGate
            approvalGate = nil
            storedIsApprovalSuspended = false
            return waiting
        }
        waiting?.resume()
    }

    var listing: AnyPublisher<DashConnectListing, Never> {
        Just(DashConnectListing(scope: nil, rows: rows, disconnected: history)).eraseToAnyPublisher()
    }

    private var storedParsed: DashConnectQr?
    private var storedHandledStateTransitions = 0

    /// What every scanned code reads as; the sample login when `nil`.
    var parsed: DashConnectQr? {
        get { lock.withLock { storedParsed } }
        set { lock.withLock { storedParsed = newValue } }
    }

    private var storedStateTransitionAction: DashConnectStAction?

    /// What every state transition comes to; refused when `nil`.
    var stateTransitionAction: DashConnectStAction? {
        get { lock.withLock { storedStateTransitionAction } }
        set { lock.withLock { storedStateTransitionAction = newValue } }
    }

    private var storedStateTransitionFailure: Error?

    /// Thrown by every state transition when set.
    var stateTransitionFailure: Error? {
        get { lock.withLock { storedStateTransitionFailure } }
        set { lock.withLock { storedStateTransitionFailure = newValue } }
    }

    /// How many state transitions ran.
    var handledStateTransitions: Int {
        lock.withLock { storedHandledStateTransitions }
    }

    private var storedParseCount = 0
    private var storedHoldsVersionRead = false
    private var versionGate: CheckedContinuation<UInt32, Error>?

    /// How many times a scanned or opened request was handed to the parser.
    var parseCount: Int { lock.withLock { storedParseCount } }

    /// When true, `protocolVersion()` suspends until `releaseVersionRead`.
    var holdsVersionRead: Bool {
        get { lock.withLock { storedHoldsVersionRead } }
        set { lock.withLock { storedHoldsVersionRead = newValue } }
    }

    /// Whether a version read is suspended right now.
    var isVersionReadPending: Bool { lock.withLock { versionGate != nil } }

    /// Lets the suspended version read return `result`.
    func releaseVersionRead(_ result: Result<UInt32, Error>) {
        let waiting = lock.withLock { () -> CheckedContinuation<UInt32, Error>? in
            let waiting = versionGate
            versionGate = nil
            return waiting
        }
        waiting?.resume(with: result)
    }

    func protocolVersion() async throws -> UInt32 {
        guard holdsVersionRead else { throw PurchaseSpyError.unsupported }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { versionGate = continuation }
        }
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        lock.withLock { storedParseCount += 1 }
        return parsed ?? .login(loginRequest)
    }

    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        lock.withLock { shown.count > 1 ? shown.removeFirst() : shown[0] }
    }

    func approveLogin(_ request: DashKeyRequest, consent: ConnectionRequest) async throws -> DAppConnection {
        let (failure, suspends) = lock.withLock { () -> (Error?, Bool) in
            storedApprovedConsents.append(consent)
            return (storedApproveFailures.isEmpty ? nil : storedApproveFailures.removeFirst(), storedSuspendsApproval)
        }
        if suspends {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    approvalGate = continuation
                    storedIsApprovalSuspended = true
                }
            }
        }
        if let failure { throw failure }
        return MockDashConnectDataSource.sample(.active)
    }

    private var storedLastRefusesTokenPurchase: Bool?

    /// Whether the last state transition was asked to refuse a token
    /// purchase.
    var lastRefusesTokenPurchase: Bool? {
        lock.withLock { storedLastRefusesTokenPurchase }
    }

    func handleStateTransition(_ request: DashStRequest, refusesTokenPurchase: Bool) async throws -> DashConnectStAction {
        let (stored, failure) = lock.withLock { () -> (DashConnectStAction?, Error?) in
            storedHandledStateTransitions += 1
            storedLastRefusesTokenPurchase = refusesTokenPurchase
            return (storedStateTransitionAction, storedStateTransitionFailure)
        }
        if let failure { throw failure }
        guard let action = stored else { throw PurchaseSpyError.unsupported }
        if refusesTokenPurchase, case .tokenPurchaseApprovalRequired = action {
            throw DashConnectPlatformError.tokenPurchaseNeedsUsername
        }
        return action
    }

    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        throw PurchaseSpyError.unsupported
    }

    private var storedDisconnectCalls = 0
    private var storedRemovedIds: [String] = []

    /// How many times `disconnect` (the call that asks for the PIN and writes) was made.
    var disconnectCallCount: Int { lock.withLock { storedDisconnectCalls } }
    var removedIds: [String] { lock.withLock { storedRemovedIds } }

    func disconnect(id: String, scope: String?) async throws -> DashConnectDisconnectResult {
        lock.withLock { storedDisconnectCalls += 1 }
        throw PurchaseSpyError.unsupported
    }

    func remove(id: String, scope: String?) async {
        lock.withLock { storedRemovedIds.append(id) }
    }
}

/// The Connections page's tabs and connection sheet.
@MainActor
final class ConnectionsViewModelStatusTests: XCTestCase {
    private static func row(_ id: String, _ status: ConnectionStatus) -> DAppConnection {
        DAppConnection(
            id: id, name: id, url: "\(id).app", status: status, updatedAt: Date(timeIntervalSince1970: 10))
    }

    func testThePageListsEveryRow() async {
        let spy = ConnectionStatusSpy(rows: [
            Self.row("active", .active), Self.row("confirming", .confirming), Self.row("undelivered", .undelivered),
        ])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        XCTAssertFalse(viewModel.hasReadRows, "not known yet: no empty page")
        await waitUntil { viewModel.connections.count == 3 }
        XCTAssertTrue(viewModel.hasReadRows)

        XCTAssertEqual(viewModel.rows(for: .active).map(\.id), ["active", "confirming", "undelivered"])
        XCTAssertEqual(viewModel.rows(for: .active).map(\.status), [.active, .confirming, .undelivered])
    }

    func testARequestThatDoesNotReadLeavesTheConnectionSheetUp() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)], history: [])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        viewModel.onURIReceived("dash-key:anything")
        await waitUntil { viewModel.connectionSheetMessage != nil }
        XCTAssertEqual(viewModel.shownConnection?.id, "app", "a request that does not read closes nothing")
        XCTAssertEqual(viewModel.connectionSheetMessage?.kind, .error, "and says so on the sheet")
        XCTAssertNil(viewModel.message)
    }

    func testARowsDisconnectOpensItsSheetAskingAtOnce() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        let item = viewModel.rows(for: .active)[0]

        viewModel.showConnection(item, asksToDisconnect: true)
        XCTAssertEqual(viewModel.shownConnection?.id, "app")
        XCTAssertTrue(viewModel.shownAsksToDisconnect)
        XCTAssertTrue(viewModel.takeDisconnectQuestion())

        viewModel.hideConnection()
        viewModel.showConnection(item)
        XCTAssertFalse(viewModel.shownAsksToDisconnect, "opening the row itself asks nothing")
    }

    func testARowsDisconnectThatCannotAskSaysWhyOnTheSheet() async throws {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        spy.disconnectSucceeds = true
        spy.disconnectDelay = 300_000_000
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        let item = viewModel.rows(for: .active)[0]
        viewModel.showConnection(item, asksToDisconnect: true)
        viewModel.disconnect(try XCTUnwrap(item.connection))
        XCTAssertFalse(viewModel.takeDisconnectQuestion(), "a disconnect is already running")
        XCTAssertEqual(viewModel.connectionSheetMessage?.kind, .error)
        await waitUntil { !viewModel.isDisconnecting }
    }

    func testTheQuestionASheetWasOpenedForIsAskedOnce() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0], asksToDisconnect: true)
        XCTAssertTrue(viewModel.takeDisconnectQuestion())
        XCTAssertFalse(viewModel.takeDisconnectQuestion())
        XCTAssertNil(viewModel.connectionSheetMessage)
    }

    func testAScanWaitsForWhatSignsButSupersedesARequestStillResolving() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)], history: [])
        spy.disconnectSucceeds = true
        spy.disconnectDelay = 300_000_000
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        XCTAssertTrue(viewModel.mayScan())

        viewModel.onQRScanned("dash-key:unparseable")
        XCTAssertTrue(viewModel.mayScan(), "a newer scan supersedes a request still resolving")
        // The unparseable request ends in its error.
        await waitUntil { viewModel.message != nil }
        viewModel.message = nil

        viewModel.disconnect(viewModel.connections[0])
        XCTAssertFalse(viewModel.mayScan())
        XCTAssertEqual(viewModel.message?.kind, .error, "the page says why the scanner did not open")
    }

    func testADisconnectClosesTheOpenSheetOnceItHasEnded() async throws {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        spy.disconnectSucceeds = true
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        let item = viewModel.rows(for: .active)[0]
        viewModel.showConnection(item)
        viewModel.disconnect(try XCTUnwrap(item.connection))
        await waitUntil { viewModel.isDisconnecting }
        XCTAssertEqual(viewModel.shownConnection?.id, "app", "the sheet stays while the disconnect runs")
        await waitUntil { viewModel.shownConnection?.status == .disconnected || viewModel.shownConnection == nil }
        XCTAssertEqual(viewModel.shownConnection?.status, .disconnected)
        XCTAssertFalse(viewModel.isDisconnecting)
    }

    func testARequestRefusedDuringADisconnectIsSaidOnTheSheet() async throws {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)], history: [])
        spy.disconnectSucceeds = true
        spy.disconnectDelay = 300_000_000
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        let item = viewModel.rows(for: .active)[0]
        viewModel.showConnection(item)
        viewModel.disconnect(try XCTUnwrap(item.connection))
        await waitUntil { viewModel.isDisconnecting }
        viewModel.onURIReceived("dash-key:anything")
        XCTAssertEqual(viewModel.connectionSheetMessage?.kind, .error, "the page's alert cannot show over the sheet")
        XCTAssertNil(viewModel.message)
        await waitUntil { !viewModel.isDisconnecting }
    }

    /// A disconnect from the sheet turns the sheet into the disconnected
    /// app's, which says what the disconnect reports; the page shows nothing.
    func testAReportAfterADisconnectOnTheSheetIsShownOnTheDisconnectedAppsSheet() async throws {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        spy.disconnectSucceeds = true
        spy.disconnectResult = DashConnectDisconnectResult(keysTurnedOff: 1, keysNotChecked: 2)
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])

        viewModel.disconnectShown()
        await waitUntil { !viewModel.isDisconnecting && viewModel.shownConnection?.status == .disconnected }
        XCTAssertEqual(viewModel.shownConnection?.id, "app")
        XCTAssertEqual(viewModel.connectionSheetMessage?.kind, .notice)
        XCTAssertEqual(viewModel.connectionSheetMessage?.text.contains("2"), true)
        XCTAssertNil(viewModel.message, "not over the sheet")
    }

    func testAnExpiredRowIsListedUnderExpiredOnly() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("live", .active), Self.row("old", .expired)])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { viewModel.connections.count == 2 }
        XCTAssertEqual(viewModel.rows(for: .active).map(\.id), ["live"])
        XCTAssertEqual(viewModel.rows(for: .expired).map(\.id), ["old"])
        XCTAssertEqual(viewModel.rows(for: .expired).first?.status, .expired)
        XCTAssertEqual(
            viewModel.rows(for: .expired).first.map { ConnectionRow.actions(for: $0.status).contains(.disconnect) }, true,
            "its keys are still on")
    }

    /// A row that turns Refused or Disconnected while its sheet asks about
    /// a disconnect no longer offers one: neither the question nor its
    /// confirmation runs it, and the sheet says why.
    /// The sheet shows a connection's details while what is left of its
    /// budgets is still read, then adds the funding lines when they come.
    func testTheSheetShowsItsDetailsBeforeTheFundingReadEnds() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        spy.funding = .read([KeyFunding(isProfileKey: false, totalBudget: 1000, remaining: 400)])
        spy.fundingDelay = 400_000_000
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        await waitUntil { viewModel.shownDetails != nil }
        XCTAssertNil(viewModel.shownFundingLines, "the details do not wait for the budgets")
        await waitUntil { viewModel.shownFundingLines != nil }
        XCTAssertEqual(viewModel.shownFundingLines?.count, 1)

        spy.funding = .failed
        spy.fundingDelay = 0
        viewModel.hideConnection()
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        await waitUntil { viewModel.shownFundingFailed }
        XCTAssertNil(viewModel.shownFundingLines)
    }

    /// A refresh whose funding read ends with nothing to read (no key gives
    /// the app access any more, or no identity read) clears the lines and
    /// any failure the earlier read showed.
    func testAFundingRefreshWithNothingToReadClearsTheLines() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        spy.funding = .read([KeyFunding(isProfileKey: false, totalBudget: 1000, remaining: 400)])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        await waitUntil { viewModel.shownFundingLines != nil }

        spy.funding = .notRead
        // The same app and status, published again: the sheet reads anew.
        spy.sendRows([DAppConnection(
            id: "app", name: "app", url: "app.app", status: .active, updatedAt: Date(timeIntervalSince1970: 20))])
        await waitUntil { viewModel.shownFundingLines == nil }
        XCTAssertFalse(viewModel.shownFundingFailed)
    }

    /// A refresh of a sheet's details that fails keeps the details shown
    /// and says they could not be read again.
    func testARefreshThatFailsKeepsTheDetailsAndSaysSo() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        await waitUntil { viewModel.shownDetails != nil }
        XCTAssertFalse(viewModel.shownDetailsFailed)

        spy.failsDetails = true
        // The same app and status, published again: the sheet reads anew.
        spy.sendRows([DAppConnection(
            id: "app", name: "app", url: "app.app", status: .active, updatedAt: Date(timeIntervalSince1970: 20))])
        await waitUntil { viewModel.shownDetailsFailed }
        XCTAssertEqual(viewModel.shownDetails?.username, "bob", "the details already read stay")
    }

    func testAConfirmedDisconnectDoesNotRunOnceTheRowNoLongerOffersOne() async throws {
        for status in [ConnectionStatus.refused, .disconnected] {
            let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
            spy.disconnectSucceeds = true
            let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
            await waitUntil { !viewModel.connections.isEmpty }
            viewModel.showConnection(viewModel.rows(for: .active)[0])
            XCTAssertTrue(viewModel.disconnectQuestion(), "\(status)")

            spy.sendRows([Self.row("app", status)])
            await waitUntil { viewModel.shownConnection?.status == status }
            XCTAssertFalse(viewModel.disconnectQuestion(), "\(status)")
            XCTAssertNotNil(viewModel.connectionSheetMessage, "\(status)")
            viewModel.connectionSheetMessage = nil

            viewModel.disconnectShown()
            XCTAssertFalse(viewModel.isDisconnecting, "\(status)")
            XCTAssertNotNil(viewModel.connectionSheetMessage, "\(status)")
            try? await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(viewModel.connections.map(\.id), ["app"], "nothing was disconnected: \(status)")
        }
    }

    func testTheSheetListsWhatIsLeftOfEachKey() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)], history: [])
        spy.details = ConnectionDetails(
            appId: "app", identityId: "identity", username: nil, basis: Self.sheetBasis(revision: 1),
            connectedAt: Date(timeIntervalSince1970: 1_000))
        spy.funding = .read([
            KeyFunding(isProfileKey: false, totalBudget: 50_000_000_000, remaining: 20_000_000_000),
            KeyFunding(isProfileKey: true, totalBudget: 200_000_000, remaining: nil),
            KeyFunding(isProfileKey: false, totalBudget: nil, remaining: nil),
        ])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        await waitUntil { viewModel.shownFundingLines != nil }
        let lines = viewModel.shownFundingLines
        XCTAssertEqual(lines?.map(\.title), ["App key", "DashPay profile key", "App key"])
        let dash: (UInt64) -> String = PlatformCreditsFormatter.dashString
        XCTAssertEqual(lines?[0].value, "\(dash(20_000_000_000)) left of \(dash(50_000_000_000))")
        XCTAssertEqual(lines?[1].value, "Maximum of \(dash(200_000_000))", "Platform did not say what is left")
        XCTAssertEqual(lines?[2].value, "No limit")
        XCTAssertEqual(viewModel.shownConnectedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(spy.fundingBases, [Self.sheetBasis(revision: 1)], "read for the read the details were told from")
    }

    /// A refresh told from another read of the identity drops the funding
    /// lines of the earlier one, and shows those read for its own.
    func testARefreshFromAnotherReadDoesNotKeepTheEarlierFundingLines() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        spy.details = ConnectionDetails(
            appId: "app", identityId: "identity", username: nil, basis: Self.sheetBasis(revision: 1))
        spy.funding = .read([KeyFunding(isProfileKey: false, totalBudget: 1000, remaining: 400)])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        await waitUntil { viewModel.shownFundingLines != nil }

        spy.details = ConnectionDetails(
            appId: "app", identityId: "identity", username: nil, basis: Self.sheetBasis(revision: 2))
        spy.funding = .read([KeyFunding(isProfileKey: false, totalBudget: 5000, remaining: 4000)])
        spy.fundingDelay = 300_000_000
        spy.sendRows([Self.row("app", .active)])
        await waitUntil { viewModel.shownDetails?.basis == Self.sheetBasis(revision: 2) }
        XCTAssertNil(viewModel.shownDetails?.keyFunding, "the lines told of the earlier read")
        await waitUntil { viewModel.shownDetails?.keyFunding != nil }
        XCTAssertEqual(viewModel.shownDetails?.keyFunding?.first?.totalBudget, 5000)
    }

    /// An Expired row's sheet reads the funding of the connection it
    /// follows, and shows it beside the details of the whole read.
    func testAnExpiredSheetReadsTheFundingOfTheConnectionItFollows() async {
        let held = Self.sheetBasis(revision: 1)
        let intent = AppConnect.ConnectionIntent(
            id: UUID(), identityId: held.snapshot.identityId, appId: Data(repeating: 1, count: 32), appLabel: "App",
            appUrl: "", requestHash: Data(repeating: 0xEE, count: 20), connectionId: nil, keys: [],
            sentEncryptionKeyIds: [], disables: [],
            response: AppConnect.ResponseValues(
                appEphemeralPubKeyHash: "ee", walletEphemeralPubKey: "02", encryptedPayload: "00"),
            responseDocumentId: nil, responseRemoved: true, createdAt: Date(timeIntervalSince1970: 0), closedAt: nil)
        let basis = ConnectionBasis(
            snapshot: held.snapshot, intents: [intent], followedIntentIds: [], unrecorded: held.unrecorded,
            administeredGroups: [])
        XCTAssertNotEqual(basis.shown(as: .expired), basis)
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .expired)])
        spy.details = ConnectionDetails(appId: "app", identityId: "identity", username: nil, basis: basis)
        spy.funding = .read([KeyFunding(isProfileKey: false, totalBudget: 1000, remaining: 400)])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .expired)[0])
        await waitUntil { viewModel.shownFundingLines != nil }
        XCTAssertEqual(spy.fundingBases, [basis.shown(as: .expired)], "the followed connection's keys only")
    }

    /// A read of the identity with one app key, at `revision`.
    nonisolated static func sheetBasis(revision: UInt64) -> ConnectionBasis {
        let key = AppConnect.PlatformKey(
            id: 10, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: 3, count: 20), readOnly: false, bound: .singleContract(Data(repeating: 1, count: 32)),
            boundKnown: true, totalBudget: revision == 1 ? 1000 : 5000, expiresAt: 1_900_000_000_000, disabledAt: nil)
        return ConnectionBasis(
            snapshot: AppConnect.IdentitySnapshot(
                identityId: Data(repeating: 2, count: 32), revision: revision, keys: [key],
                platformTime: 1_800_000_000_000),
            intents: [], followedIntentIds: [], unrecorded: [key], administeredGroups: [])
    }

    func testADetailsReadFromBeforeTheSheetOpenedAgainIsNotShown() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        spy.details = ConnectionDetails(appId: "app", identityId: "identity", username: "before")
        spy.detailsDelay = 200_000_000
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        // The first read has its answer ("before", slow) before the sheet
        // closes; it ends after the second one.
        await waitUntil { spy.detailReads == 1 }
        viewModel.hideConnection()

        spy.details = ConnectionDetails(appId: "app", identityId: "identity", username: "after")
        spy.detailsDelay = 0
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        await waitUntil { viewModel.shownDetails != nil }
        XCTAssertEqual(viewModel.shownDetails?.username, "after")
        // The first read ends meanwhile.
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(viewModel.shownDetails?.username, "after", "the earlier read, ending later, does not replace it")
    }

    func testTheSheetReadsItsDetailsAgainWhenTheRowsArePublishedUnchanged() async {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        spy.details = ConnectionDetails(appId: "app", identityId: "identity", username: "before")
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        await waitUntil { viewModel.shownDetails?.username == "before" }

        spy.details = ConnectionDetails(appId: "app", identityId: "identity", username: "renewed")
        spy.sendRows([Self.row("app", .active)])
        await waitUntil { viewModel.shownDetails?.username == "renewed" }
        XCTAssertEqual(viewModel.shownDetails?.username, "renewed", "another grant of the same app, same status")
    }

    func testAnOldDismissalTimeoutDoesNotCloseALaterSheet() async throws {
        let spy = ConnectionStatusSpy(rows: [Self.row("app", .active)])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0])
        let closing = Task { await viewModel.closeConnectionSheet() }
        await waitUntil { viewModel.shownConnection == nil }
        viewModel.connectionSheetDismissed()
        await closing.value

        viewModel.showConnection(viewModel.rows(for: .active)[0])
        // The first close's fallback would have fired by now.
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(viewModel.isConnectionSheetOnScreen, "the later sheet is still up")
    }

    func testAnotherWalletsRowOfTheShownAppClosesItsSheet() async {
        var walletA = Self.row("app", .active)
        walletA.scope = "a"
        var walletB = walletA
        walletB.scope = "b"
        let spy = ConnectionStatusSpy(rows: [walletA])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        await waitUntil { !viewModel.connections.isEmpty }
        viewModel.showConnection(viewModel.rows(for: .active)[0], asksToDisconnect: true)

        spy.sendRows([walletB])
        await waitUntil { viewModel.shownConnection == nil }
        XCTAssertNil(viewModel.shownConnection, "the sheet, and its question, were about the other wallet's row")
        XCTAssertFalse(viewModel.takeDisconnectQuestion())
    }

    func testAnotherWalletsDisconnectedAppOfTheShownAppClosesItsSheet() async {
        let entry = DisconnectedConnection(
            id: "app", name: "App", url: "app.example", identityId: nil, username: nil,
            disconnectedAt: Date(timeIntervalSince1970: 50), access: nil)
        let spy = ConnectionStatusSpy(rows: [])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        spy.sendWallet("a", rows: [], history: [entry])
        await waitUntil { !viewModel.rows(for: .disconnected).isEmpty }
        viewModel.showConnection(viewModel.rows(for: .disconnected)[0])
        XCTAssertNotNil(viewModel.shownConnection)

        spy.sendWallet("b", rows: [], history: [entry])
        await waitUntil { viewModel.shownConnection == nil }
        XCTAssertNil(viewModel.shownConnection, "the sheet was about the other wallet's disconnected app")
        XCTAssertEqual(viewModel.rows(for: .disconnected).first?.scope, "b")
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

/// A data source with fixed rows and history.
private final class ConnectionStatusSpy: DashConnectDataSource {
    private let lock = NSLock()
    private let published: CurrentValueSubject<DashConnectListing, Never>
    private var history: [DisconnectedConnection]
    /// The scope of the rows sent last; kept while none is sent.
    private var scope: String?
    private var storedDetailReads = 0
    /// A disconnect succeeds: the row goes and the app is in the history.
    var disconnectSucceeds = false
    /// What a disconnect that succeeds answers.
    var disconnectResult = DashConnectDisconnectResult()
    /// How long a disconnect takes, in nanoseconds.
    var disconnectDelay: UInt64 = 0
    /// How long a details read takes, in nanoseconds.
    var detailsDelay: UInt64 = 0
    /// What the details read answers; a fixed connection on `identity` when
    /// unset.
    var details: ConnectionDetails?
    /// Reads of the details fail, as when the identity cannot be read.
    var failsDetails = false
    /// What the funding read answers, and how long it takes.
    var funding: ConnectionFundingRead = .notRead
    var fundingDelay: UInt64 = 0
    private var storedFundingBases: [ConnectionBasis] = []
    /// The bases funding was read for, in order.
    var fundingBases: [ConnectionBasis] { lock.withLock { storedFundingBases } }
    private var storedDisconnectFailure: Error?
    /// Thrown by every disconnect while set, before anything runs.
    var disconnectFailure: Error? {
        get { lock.withLock { storedDisconnectFailure } }
        set { lock.withLock { storedDisconnectFailure = newValue } }
    }

    init(rows: [DAppConnection], history: [DisconnectedConnection] = []) {
        scope = rows.first?.scope
        published = CurrentValueSubject(DashConnectListing(scope: scope, rows: rows, disconnected: history))
        self.history = history
    }

    private var rows: [DAppConnection] { published.value.rows }

    var detailReads: Int { lock.withLock { storedDetailReads } }

    var listing: AnyPublisher<DashConnectListing, Never> { published.eraseToAnyPublisher() }

    func connectionDetails(id: String, scope: String?) async -> ConnectionDetails? {
        // What the read answers, and how long it takes, as they were when it
        // started.
        let (answer, delay, fails) = lock.withLock {
            storedDetailReads += 1
            return (details, detailsDelay, failsDetails)
        }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        if fails { return nil }
        return answer ?? ConnectionDetails(
            appId: id, identityId: "identity", username: "bob",
            basis: ConnectionsViewModelStatusTests.sheetBasis(revision: 1))
    }

    func connectionFunding(for basis: ConnectionBasis, scope: String?) async -> ConnectionFundingRead {
        let (answer, delay) = lock.withLock {
            storedFundingBases.append(basis)
            return (funding, fundingDelay)
        }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return answer
    }

    func sendRows(_ value: [DAppConnection]) {
        let history = lock.withLock { () -> [DisconnectedConnection] in
            if let rowScope = value.first?.scope { scope = rowScope }
            return self.history
        }
        published.send(DashConnectListing(scope: scope, rows: value, disconnected: history))
    }

    /// Another wallet's list: `rows` and `history` under `scope`.
    func sendWallet(_ scope: String, rows: [DAppConnection], history: [DisconnectedConnection]) {
        lock.withLock {
            self.scope = scope
            self.history = history
        }
        published.send(DashConnectListing(scope: scope, rows: rows, disconnected: history))
    }

    func parseQR(_ content: String) async throws -> DashConnectQr { throw PurchaseSpyError.unsupported }
    func makeConnectionRequest(from loginRequest: DashKeyRequest) async -> ConnectionRequest {
        ConnectionRequest(loginRequest: loginRequest)
    }
    func approveLogin(_ request: DashKeyRequest, consent: ConnectionRequest) async throws -> DAppConnection {
        throw PurchaseSpyError.unsupported
    }
    func handleStateTransition(_ request: DashStRequest, refusesTokenPurchase: Bool) async throws -> DashConnectStAction {
        throw PurchaseSpyError.unsupported
    }
    func approveTokenPurchase(_ request: DashConnectTokenPurchaseRequest) async throws {
        throw PurchaseSpyError.unsupported
    }
    func disconnect(id: String, scope: String?) async throws -> DashConnectDisconnectResult {
        let failure = lock.withLock { storedDisconnectFailure }
        if disconnectDelay > 0 { try? await Task.sleep(nanoseconds: disconnectDelay) }
        if let failure { throw failure }
        guard disconnectSucceeds, let row = rows.first(where: { $0.id == id }) else {
            throw PurchaseSpyError.unsupported
        }
        lock.withLock {
            history += [DisconnectedConnection(
                id: id, name: row.name, url: row.url, identityId: "identity", username: nil,
                disconnectedAt: Date(timeIntervalSince1970: 50), access: nil)]
        }
        sendRows(rows.filter { $0.id != id })
        return disconnectResult
    }
    func remove(id: String, scope: String?) async {}
}

/// The URLs a view model asked to open, in order.
/// A v2 request's sheet.
private func appConnectConsent(_ loginRequest: DashKeyRequest) -> ConnectionRequest {
    let plan = AppConnect.GrantPlan(
        appId: loginRequest.contractId, appEphemeralPubKeyHash: Data(repeating: 0x01, count: 20), auth: [],
        encryption: [], connectionId: nil, identityHint: nil, createdAt: 0)
    var request = ConnectionRequest(loginRequest: loginRequest)
    request.login = .appConnect(plan)
    return request
}

@MainActor
private final class OpenedURLs {
    var urls: [URL] = []
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

    func testDisconnectOfARowFromAnotherWalletIsRefusedAndTheListMovesToTheActiveWallet() async {
        let active = ActiveWallet("wallet-a")
        let row = Self.row(status: .active)
        let (dataSource, connections) = makeScopedDataSource(active: active, rows: [row])
        let shown = Self.shownRows(dataSource)
        let other = Self.row(id: "7UaqHGBJBbRLJ4fUWS45cnud8PPUugJWoGTt1SKwHJ2P", status: .confirming)
        active.idHex = "wallet-b"
        connections.save([other])

        await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope) }

        XCTAssertEqual(Self.shownRows(dataSource).map(\.id), [other.id], "the list shows the wallet that is active")
        XCTAssertEqual(connections.load(), [other])
        active.idHex = "wallet-a"
        XCTAssertEqual(connections.load(), [row], "the other wallet's row is untouched")
    }

    func testDisconnectIsRefusedWhenTheNewlyActiveWalletHasARowForTheSameApp() async {
        let active = ActiveWallet("wallet-a")
        let row = Self.row(status: .active)
        let (dataSource, connections) = makeScopedDataSource(active: active, rows: [row])
        let shown = Self.shownRows(dataSource)
        active.idHex = "wallet-b"
        connections.save([row])

        await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope) }

        XCTAssertEqual(connections.load().map(\.status), [.active])
    }

    func testDisconnectFromAnOldListIsRefusedAfterTheListAlreadyMovedToTheNewWallet() async throws {
        let active = ActiveWallet("wallet-a")
        let row = Self.row(status: .active)
        let center = NotificationCenter()
        let (dataSource, connections) = makeScopedDataSource(
            active: active, rows: [row], notificationCenter: center)
        // What the screen still holds when the tap lands.
        let shown = Self.shownRows(dataSource)
        active.idHex = "wallet-b"
        connections.save([row])
        let moved = expectation(description: "the active wallet's rows are published")
        moved.assertForOverFulfill = false
        let subscription = dataSource.connections.sink { rows in
            if rows.first?.scope != nil, rows.first?.scope != shown[0].scope { moved.fulfill() }
        }
        defer { subscription.cancel() }
        center.post(name: SwiftDashSDKWalletState.activeWalletDidChangeNotification, object: nil)
        await fulfillment(of: [moved], timeout: 2)

        await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope) }
        await dataSource.remove(id: shown[0].id, scope: shown[0].scope)

        XCTAssertEqual(connections.load(), [row], "the new wallet's row for the same app is untouched")
        // The row the new list shows is this wallet's own.
        let current = Self.shownRows(dataSource)
        await Self.expectNotWalletChanged {
            try await dataSource.disconnect(id: current[0].id, scope: current[0].scope)
        }
    }

    func testRemoveDoesNothingForARowPublishedForAnotherWallet() async {
        let active = ActiveWallet("wallet-a")
        let row = Self.row(status: .active)
        let (dataSource, connections) = makeScopedDataSource(active: active, rows: [row])
        let shown = Self.shownRows(dataSource)
        active.idHex = "wallet-b"
        connections.save([row])

        await dataSource.remove(id: shown[0].id, scope: shown[0].scope)
        XCTAssertEqual(connections.load(), [row])

        let current = Self.shownRows(dataSource)
        await dataSource.remove(id: current[0].id, scope: current[0].scope)
        XCTAssertEqual(connections.load(), [], "the list is this wallet's now")
    }

    func testARowShownForADevnetAtOtherNodesIsNotActedOnUnderTheSameName() async throws {
        let active = ActiveWallet("wallet-a")
        let endpoint = Endpoint("https://quorums.one.example")
        let center = NotificationCenter()
        let row = Self.row(status: .active)
        let (dataSource, connections) = makeScopedDataSource(
            active: active, rows: [row], notificationCenter: center, endpoint: endpoint)
        let shown = Self.shownRows(dataSource)

        // The same wallet and devnet name, pointed at other nodes.
        endpoint.url = "https://quorums.two.example"

        await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope) }
        XCTAssertEqual(connections.load().map(\.status), [.active])
        let current = Self.shownRows(dataSource)
        XCTAssertNotEqual(current[0].scope, shown[0].scope)
        await Self.expectNotWalletChanged {
            try await dataSource.disconnect(id: current[0].id, scope: current[0].scope)
        }
    }

    func testARowWithNoScopeIsNotActedOn() async {
        let active = ActiveWallet("wallet-a")
        let row = Self.row(status: .active)
        let (dataSource, connections) = makeScopedDataSource(active: active, rows: [row])

        await Self.expectWalletChanged { try await dataSource.disconnect(id: row.id, scope: nil) }
        await dataSource.remove(id: row.id, scope: nil)

        XCTAssertEqual(connections.load(), [row])
    }

    func testTheListMovesToTheActiveWalletWhenTheWalletChangeIsAnnounced() async {
        let active = ActiveWallet("wallet-a")
        let row = Self.row(status: .active)
        let center = NotificationCenter()
        let (dataSource, connections) = makeScopedDataSource(
            active: active, rows: [row], notificationCenter: center)
        let other = Self.row(id: "7UaqHGBJBbRLJ4fUWS45cnud8PPUugJWoGTt1SKwHJ2P", status: .confirming)
        active.idHex = "wallet-b"
        connections.save([other])
        let moved = expectation(description: "the active wallet's rows are published")
        let subscription = dataSource.connections.sink { rows in
            if rows.map(\.id) == [other.id] { moved.fulfill() }
        }
        defer { subscription.cancel() }

        center.post(
            name: SwiftDashSDKWalletState.activeWalletDidChangeNotification, object: nil)

        await fulfillment(of: [moved], timeout: 2)
    }

    /// The listing names the active wallet's scope and puts its Disconnected
    /// rows on the Disconnected tab, read off the intents the disconnect marked.
    func testTheListingSplitsTheActiveWalletsRowsFromItsDisconnectedApps() {
        let active = ActiveWallet("wallet-a")
        let connected = Self.row(id: "7UaqHGBJBbRLJ4fUWS45cnud8PPUugJWoGTt1SKwHJ2P", status: .active)
        let (_, connections) = makeScopedDataSource(active: active)
        saveDisconnected(in: connections, at: Date(timeIntervalSince1970: 40), keeping: [connected])

        let listing = Self.listing(of: makeScopedDataSource(active: active, rows: connections.load()).0)

        XCTAssertNotNil(listing.scope)
        XCTAssertEqual(listing.rows.first?.scope, listing.scope)
        XCTAssertEqual(listing.rows.map(\.id), [connected.id])
        XCTAssertEqual(listing.disconnected.map(\.id), [Self.app.toBase58String()])
        XCTAssertEqual(listing.disconnected.first?.disconnectedAt, Date(timeIntervalSince1970: 40))
    }

    /// A disconnect saved by another data source over the same wallet moves
    /// the app off the rows and onto the Disconnected tab in one listing.
    func testADisconnectSavedElsewherePublishesTheRowsGoneAndTheDisconnectedAppTogether() async {
        let active = ActiveWallet("wallet-a")
        let center = NotificationCenter()
        let appId = Self.app.toBase58String()
        let (dataSource, connections) = makeScopedDataSource(
            active: active, rows: [Self.row(id: appId, status: .active)], notificationCenter: center)
        var published: [DashConnectListing] = []
        let moved = expectation(description: "the disconnected app is published")
        moved.assertForOverFulfill = false
        let subscription = dataSource.listing.sink { listing in
            published.append(listing)
            if !listing.disconnected.isEmpty { moved.fulfill() }
        }
        defer { subscription.cancel() }

        saveDisconnected(in: connections, at: Date(timeIntervalSince1970: 40))

        await fulfillment(of: [moved], timeout: 2)
        let after = published.first { !$0.disconnected.isEmpty }
        XCTAssertEqual(after?.rows, [], "the row left in the same listing")
        XCTAssertEqual(after?.disconnected.map(\.id), [appId])
        XCTAssertFalse(
            published.contains { listing in !listing.rows.contains { $0.id == appId } && listing.disconnected.isEmpty },
            "no listing showed the app in neither tab")
    }

    /// A switch to a wallet whose only connection is a disconnected app moves
    /// the listing to that wallet: no rows, its disconnected app, its scope.
    func testAWalletSwitchToAWalletWithOnlyADisconnectedAppMovesTheListing() async {
        let active = ActiveWallet("wallet-a")
        let center = NotificationCenter()
        let (dataSource, connections) = makeScopedDataSource(
            active: active, rows: [Self.row(id: "7UaqHGBJBbRLJ4fUWS45cnud8PPUugJWoGTt1SKwHJ2P", status: .active)],
            notificationCenter: center)
        let before = Self.listing(of: dataSource)
        active.idHex = "wallet-b"
        saveDisconnected(in: connections, at: Date(timeIntervalSince1970: 40))
        let moved = expectation(description: "wallet b's listing is published")
        moved.assertForOverFulfill = false
        var after: DashConnectListing?
        let subscription = dataSource.listing.sink { listing in
            if listing.scope != before.scope, !listing.disconnected.isEmpty {
                after = listing
                moved.fulfill()
            }
        }
        defer { subscription.cancel() }

        center.post(name: SwiftDashSDKWalletState.activeWalletDidChangeNotification, object: nil)

        await fulfillment(of: [moved], timeout: 2)
        XCTAssertEqual(after?.rows, [])
        XCTAssertEqual(after?.disconnected.map(\.id), [Self.app.toBase58String()])
        XCTAssertNotNil(after?.scope)
    }

    /// Saves, for the wallet `connections` is on now, `Self.app` disconnected
    /// at `date` as a disconnect does: its marked intent first, then its
    /// Disconnected row, with `keeping` rows next to it.
    private func saveDisconnected(
        in connections: UserDefaultsDashConnectStore, at date: Date, keeping: [DAppConnection] = []
    ) {
        var intent = AppConnect.ConnectionIntent(
            id: UUID(), identityId: Data(repeating: 0x01, count: 32), appId: Self.app, appLabel: "Yappr",
            appUrl: "yap.pr", requestHash: Data(repeating: 0xEE, count: 20),
            connectionId: nil, keys: [], sentEncryptionKeyIds: [], disables: [],
            response: AppConnect.ResponseValues(appEphemeralPubKeyHash: "ee", walletEphemeralPubKey: "02", encryptedPayload: "00"),
            responseDocumentId: nil, responseRemoved: true, createdAt: Date(timeIntervalSince1970: 10), closedAt: date)
        intent.disconnectedAt = date
        UserDefaultsAppConnectIntentStore(defaults: defaults, scope: .connections(connections)).save([intent])
        connections.save(keeping + [Self.row(id: Self.app.toBase58String(), status: .disconnected)])
    }

    /// The listing the data source publishes right now.
    private static func listing(of dataSource: PlatformDashConnectDataSource) -> DashConnectListing {
        var listing = DashConnectListing(scope: nil, rows: [], disconnected: [])
        let subscription = dataSource.listing.sink { listing = $0 }
        subscription.cancel()
        return listing
    }

    func testOperationsForOneWalletRunOneAtATimeInArrivalOrder() async {
        let gate = DashConnectOperationGate()
        let log = OperationLog()
        let firstStarted = expectation(description: "the first operation is running")
        let secondWaits = expectation(description: "the second operation waits")
        let thirdWaits = expectation(description: "the third operation waits")
        let release = AsyncStream<Void>.makeStream()

        let first = Task {
            await gate.run(for: "wallet-a") {
                await log.add("first starts")
                firstStarted.fulfill()
                for await _ in release.stream { break }
                await log.add("first ends")
            }
        }
        await fulfillment(of: [firstStarted], timeout: 2)
        let second = Task {
            await gate.run(for: "wallet-a", onWait: { secondWaits.fulfill() }) { await log.add("second runs") }
        }
        await fulfillment(of: [secondWaits], timeout: 2)
        let third = Task {
            await gate.run(for: "wallet-a", onWait: { thirdWaits.fulfill() }) { await log.add("third runs") }
        }
        await fulfillment(of: [thirdWaits], timeout: 2)
        // Another wallet does not wait for this one.
        await gate.run(for: "wallet-b") { await log.add("other wallet runs") }
        release.continuation.yield()
        await first.value
        await second.value
        await third.value

        let entries = await log.entries
        XCTAssertEqual(
            entries, ["first starts", "other wallet runs", "first ends", "second runs", "third runs"])
    }

    func testADisconnectWaitsForAnOperationAnotherDataSourceIsRunning() async throws {
        let gate = DashConnectOperationGate()
        let active = ActiveWallet("wallet-a")
        let row = Self.row(status: .active)
        let (dataSource, connections) = makeScopedDataSource(active: active, rows: [row], operationGate: gate)
        let shown = Self.shownRows(dataSource)
        let otherStarted = expectation(description: "the other operation is running")
        let release = AsyncStream<Void>.makeStream()
        // What another data source of the same wallet would be doing.
        let other = Task {
            await gate.run(for: "wallet-a") {
                otherStarted.fulfill()
                for await _ in release.stream { break }
                // It wrote a row of its own meanwhile.
                connections.save([row, Self.row(id: "7UaqHGBJBbRLJ4fUWS45cnud8PPUugJWoGTt1SKwHJ2P", status: .active)])
            }
        }
        await fulfillment(of: [otherStarted], timeout: 2)

        // With no wallet to sign, the disconnect fails once its turn comes;
        // when it ends is what is checked.
        let log = OperationLog()
        let disconnect = Task {
            _ = try? await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope)
            await log.add("disconnect ended")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let ended = await log.entries
        XCTAssertEqual(ended, [], "the disconnect waits for the other operation")

        release.continuation.yield()
        await other.value
        await disconnect.value

        let entries = await log.entries
        XCTAssertEqual(entries, ["disconnect ended"])
        XCTAssertEqual(connections.load().count, 2, "the row the other operation wrote is kept")
    }

    func testAnOperationDoesNotStartForAWalletThatIsNoLongerActiveWhenItsTurnComes() async {
        let gate = DashConnectOperationGate()
        let active = ActiveWallet("wallet-a")
        let row = Self.row(status: .active)
        let (dataSource, connections) = makeScopedDataSource(active: active, rows: [row], operationGate: gate)
        let shown = Self.shownRows(dataSource)
        let otherStarted = expectation(description: "the other operation is running")
        let release = AsyncStream<Void>.makeStream()
        let other = Task {
            await gate.run(for: "wallet-a") {
                otherStarted.fulfill()
                for await _ in release.stream { break }
            }
        }
        await fulfillment(of: [otherStarted], timeout: 2)

        let disconnect = Task {
            await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope) }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        active.idHex = "wallet-b"
        release.continuation.yield()
        await other.value
        await disconnect.value

        active.idHex = "wallet-a"
        XCTAssertEqual(connections.load(), [row])
    }

    func testAFailedOperationHandsTheTurnOn() async {
        let gate = DashConnectOperationGate()

        do {
            try await gate.run(for: "wallet-a") { throw DashConnectPlatformError.noWallet }
            XCTFail("the failure was swallowed")
        } catch {}
        let ran = await gate.run(for: "wallet-a") { true }

        XCTAssertTrue(ran)
    }

    private actor OperationLog {
        private(set) var entries: [String] = []
        func add(_ entry: String) { entries.append(entry) }
    }

    func testAnApprovalIsForTheIdentityWalletAndNetworkItsRequestWasResolvedFor() {
        let request = ConnectionRequest(
            loginRequest: MockDashConnectDataSource.sampleLoginRequest,
            appLabel: "App",
            appUrl: "",
            walletUsername: nil,
            walletIdentityId: "identity-a",
            existingConnection: nil,
            login: .appConnect(.sample),
            scope: "wallet-a devnet-one")

        XCTAssertTrue(request.wasResolved(forIdentityId: "identity-a", scope: "wallet-a devnet-one"))
        XCTAssertFalse(request.wasResolved(forIdentityId: "identity-b", scope: "wallet-a devnet-one"))
        XCTAssertFalse(
            request.wasResolved(forIdentityId: "identity-a", scope: "wallet-a devnet-two"),
            "the same wallet and identity on another devnet")
        // A request that was not resolved against a wallet approves nothing.
        var unscoped = request
        unscoped.scope = nil
        XCTAssertFalse(unscoped.wasResolved(forIdentityId: "identity-a", scope: "wallet-a devnet-one"))
    }

    func testDisconnectWithNoActiveWalletIsRefused() async {
        let active = ActiveWallet(nil)
        let (dataSource, _) = makeScopedDataSource(active: active)

        do {
            try await dataSource.disconnect(id: Self.row(status: .active).id, scope: nil)
            XCTFail("disconnected with no wallet")
        } catch {
            guard case DashConnectPlatformError.noWallet = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    /// The rows the data source publishes right now.
    private static func shownRows(_ dataSource: PlatformDashConnectDataSource) -> [DAppConnection] {
        var rows: [DAppConnection] = []
        let subscription = dataSource.connections.sink { rows = $0 }
        subscription.cancel()
        return rows
    }

    /// The operation is not refused for being another wallet's; it may
    /// still fail further on, with no wallet to sign in tests.
    private static func expectNotWalletChanged(
        _ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await operation()
        } catch DashConnectPlatformError.walletChanged {
            XCTFail("refused as another wallet's", file: file, line: line)
        } catch {}
    }

    private static func expectWalletChanged(
        _ action: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await action()
            XCTFail("a row of a wallet that is no longer active was acted on", file: file, line: line)
        } catch {
            guard case DashConnectPlatformError.walletChanged = error else {
                return XCTFail("unexpected error: \(error)", file: file, line: line)
            }
        }
    }

    private final class ActiveWallet {
        var idHex: String?
        init(_ idHex: String?) { self.idHex = idHex }
    }

    private final class Endpoint {
        var url: String?
        init(_ url: String?) { self.url = url }
    }

    /// `rows` are the active wallet's, stored before the data source loads
    /// its list.
    private func makeScopedDataSource(
        active: ActiveWallet,
        rows: [DAppConnection] = [],
        notificationCenter: NotificationCenter = NotificationCenter(),
        operationGate: DashConnectOperationGate = DashConnectOperationGate(),
        endpoint: Endpoint = Endpoint(nil)
    ) -> (PlatformDashConnectDataSource, UserDefaultsDashConnectStore) {
        let connections = UserDefaultsDashConnectStore(
            defaults: defaults,
            network: .testnet,
            walletIdHexProvider: { active.idHex },
            devnetNameProvider: { nil },
            notificationCenter: notificationCenter
        )
        connections.save(rows)
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: connections,
            intentStore: UserDefaultsAppConnectIntentStore(defaults: defaults, scope: .connections(connections)),
            activeWalletIdHex: { active.idHex },
            networkEndpoint: { endpoint.url },
            notificationCenter: notificationCenter,
            operationGate: operationGate,
            defaults: defaults
        )
        return (dataSource, connections)
    }

    /// What an earlier build noted about kept shared profile keys is removed
    /// once, when the data source starts; nothing else in the defaults is
    /// touched, and a later start scans nothing.
    func testKeptSharedProfileKeysAreRemovedWhenTheDataSourceStarts() {
        defaults.set([4, 7], forKey: "DashConnect.keptSharedProfileKeys wallet-a t identity-a")
        defaults.set([9], forKey: "DashConnect.keptSharedProfileKeys wallet-b t identity-b")
        defaults.set("x", forKey: "DashConnect.other")

        _ = makeScopedDataSource(active: ActiveWallet("wallet-a"))

        XCTAssertNil(defaults.object(forKey: "DashConnect.keptSharedProfileKeys wallet-a t identity-a"))
        XCTAssertNil(defaults.object(forKey: "DashConnect.keptSharedProfileKeys wallet-b t identity-b"))
        XCTAssertEqual(defaults.string(forKey: "DashConnect.other"), "x")
        XCTAssertTrue(defaults.bool(forKey: PlatformDashConnectDataSource.keptSharedProfileKeysRemovedKey))

        defaults.set([5], forKey: "DashConnect.keptSharedProfileKeys wallet-c t identity-c")
        _ = makeScopedDataSource(active: ActiveWallet("wallet-a"))
        XCTAssertNotNil(
            defaults.object(forKey: "DashConnect.keptSharedProfileKeys wallet-c t identity-c"), "it runs once")
    }

    private static func row(
        id: String = "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F",
        status: ConnectionStatus
    ) -> DAppConnection {
        DAppConnection(
            id: id, name: "Yappr", url: "yap.pr", status: status,
            updatedAt: Date(timeIntervalSince1970: 1_773_132_300))
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let nowMilliseconds: Int64 = 1_800_000_000_000
    private static let app = Data(repeating: 0xA1, count: 32)
    private static let sessionKeyHash = Data(repeating: 0x11, count: 20)
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

// MARK: - Identity snapshot from the proved keys read

extension PlatformDashConnectDataSourceTests {
    private static let snapshotIdentity = Data(repeating: 0x11, count: 32)

    private static func keyInfo(
        _ id: Int32, disabledAt: Int64? = nil, totalBudget: UInt64? = nil, expiresAt: Int64? = nil
    ) -> ManagedIdentity.IdentityPublicKeyInfo {
        ManagedIdentity.IdentityPublicKeyInfo(
            keyId: id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160, readOnly: false,
            disabledAt: disabledAt, data: Data(repeating: UInt8(id), count: 20),
            totalBudget: totalBudget, expiresAt: expiresAt)
    }

    func testTheSnapshotCarriesTheProvedBlockTime() throws {
        let fetched = FetchedIdentityPublicKeys(
            keys: [FetchedIdentityPublicKey(key: Self.keyInfo(0), expiredAtProofTime: false)],
            blockTimeMs: 1_790_000_000_123)

        let (snapshot, _) = try PlatformDashConnectDataSource.identitySnapshot(
            identityId: Self.snapshotIdentity, revision: 3, fetched: fetched, bindings: [])

        XCTAssertEqual(snapshot.platformTime, 1_790_000_000_123)
        XCTAssertEqual(snapshot.revision, 3)
    }

    func testTheSnapshotKeepsADisabledKeyWithItsTime() throws {
        let fetched = FetchedIdentityPublicKeys(
            keys: [
                FetchedIdentityPublicKey(key: Self.keyInfo(0), expiredAtProofTime: false),
                FetchedIdentityPublicKey(key: Self.keyInfo(5, disabledAt: 1_780_000_000_000), expiredAtProofTime: false),
            ],
            blockTimeMs: 1_790_000_000_000)

        let (snapshot, keys) = try PlatformDashConnectDataSource.identitySnapshot(
            identityId: Self.snapshotIdentity, revision: 1, fetched: fetched, bindings: [])

        XCTAssertEqual(snapshot.keys.map(\.id), [0, 5])
        XCTAssertEqual(snapshot.keys.first { $0.id == 5 }?.disabledAt, 1_780_000_000_000)
        XCTAssertEqual(keys.map(\.keyId), [0, 5])
    }

    func testAReadThatFindsNoIdentityIsNoSnapshot() {
        let fetched = FetchedIdentityPublicKeys(keys: nil, blockTimeMs: 1_790_000_000_000)

        XCTAssertThrowsError(try PlatformDashConnectDataSource.identitySnapshot(
            identityId: Self.snapshotIdentity, revision: 1, fetched: fetched, bindings: [])
        ) { error in
            guard case DashConnectPlatformError.noIdentity = error else {
                return XCTFail("expected noIdentity, got \(error)")
            }
        }
    }
}

/// AC-11: a request answered before is refused before any PIN, whether this
/// wallet's record, a response on Platform or the request's own auth keys on
/// the identity tell it; a lookup that fails is never "not answered".
final class AppConnectAnsweredTests: XCTestCase {
    private static let identity = Data(repeating: 0x01, count: 32)
    private static let app = Data(repeating: 0xA1, count: 32)
    private static let otherApp = Data(repeating: 0xA2, count: 32)
    private static let requestHash = Data(repeating: 0xEE, count: 20)
    /// The hash160 of the auth key the request derives (`authKeyLeaf`).
    private static let requestKeyHash = Data(repeating: 0x77, count: 20)

    private struct LookupFailed: Error {}

    private static func key(
        id: UInt32 = 10, data: Data = requestKeyHash, purpose: KeyPurpose = .authentication,
        keyType: KeyType = .ecdsaHash160, expiresAt: UInt64? = nil, disabledAt: UInt64? = nil
    ) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: id, purpose: purpose, securityLevel: .high, keyType: keyType, data: data, readOnly: false,
            bound: .singleContract(app), boundKnown: true, totalBudget: 1000, expiresAt: expiresAt, disabledAt: disabledAt)
    }

    private static func snapshot(_ keys: [AppConnect.PlatformKey]) -> AppConnect.IdentitySnapshot {
        AppConnect.IdentitySnapshot(identityId: identity, revision: 5, keys: keys, platformTime: 1_800_000_000_000)
    }

    private static func intent(app: Data = app, requestHash: Data = requestHash) -> AppConnect.ConnectionIntent {
        AppConnect.ConnectionIntent(
            id: UUID(), identityId: identity, appId: app, appLabel: "App", appUrl: "", requestHash: requestHash,
            connectionId: nil, keys: [], sentEncryptionKeyIds: [], disables: [],
            response: AppConnect.ResponseValues(appEphemeralPubKeyHash: "ee", walletEphemeralPubKey: "02", encryptedPayload: "00"),
            responseDocumentId: nil, responseRemoved: true, createdAt: Date(timeIntervalSince1970: 0), closedAt: nil)
    }

    private func state(
        lookup: Result<Bool, Error>, keys: [AppConnect.PlatformKey] = [], tie: [Data] = [requestKeyHash],
        intents: [AppConnect.ConnectionIntent] = []
    ) -> AppConnect.AnsweredState {
        AppConnect.answeredState(
            responseLookup: lookup, requestAuthKeyHashes: tie, snapshot: Self.snapshot(keys), intents: intents,
            appId: Self.app, requestHash: Self.requestHash)
    }

    // MARK: Response on Platform

    func testAResponseOnPlatformMeansAnswered() {
        XCTAssertEqual(state(lookup: .success(true)), .answered)
    }

    // MARK: Keys on Platform

    func testTheRequestsAuthKeyOnTheIdentityMeansAnsweredEvenWithoutAResponse() {
        XCTAssertEqual(state(lookup: .success(false), keys: [Self.key()]), .answered)
    }

    func testTheRequestsAuthKeyMeansAnsweredWhetherItIsOffOrExpired() {
        XCTAssertEqual(state(lookup: .success(false), keys: [Self.key(disabledAt: 1)]), .answered, "disabled")
        XCTAssertEqual(state(lookup: .success(false), keys: [Self.key(expiresAt: 1)]), .answered, "expired")
    }

    func testTheRequestsAuthKeyMeansAnsweredWhenTheResponseLookupFailed() {
        XCTAssertEqual(state(lookup: .failure(LookupFailed()), keys: [Self.key()]), .answered)
    }

    func testAKeyThatIsNotTheRequestsAuthKeyDoesNotMeanAnswered() {
        let other = Data(repeating: 0x55, count: 20)
        XCTAssertEqual(state(lookup: .success(false), keys: [Self.key(data: other)]), .notAnswered, "other payload")
        XCTAssertEqual(
            state(lookup: .success(false), keys: [Self.key(purpose: .encryption, keyType: .ecdsaSecp256k1)]),
            .notAnswered, "an encryption key")
    }

    func testARequestWithoutAuthKeysHasNoKeyTie() {
        XCTAssertEqual(state(lookup: .success(false), keys: [Self.key()], tie: []), .notAnswered)
    }

    // MARK: This wallet's record (built; regression guard)

    func testAnIntentOfThisWalletForTheRequestMeansAnswered() {
        XCTAssertEqual(state(lookup: .success(false), intents: [Self.intent()]), .answered)
    }

    func testAnIntentOfThisWalletMeansAnsweredWhenTheLookupFailed() {
        XCTAssertEqual(state(lookup: .failure(LookupFailed()), intents: [Self.intent()]), .answered)
    }

    func testAnIntentOfAnotherAppOrAnotherRequestDoesNotMeanAnswered() {
        let intents = [Self.intent(app: Self.otherApp), Self.intent(requestHash: Data(repeating: 0x11, count: 20))]
        XCTAssertEqual(state(lookup: .success(false), intents: intents), .notAnswered)
    }

    // MARK: Neither, and a lookup that fails

    func testNeitherAResponseNorKeysNorAnIntentMeansNotAnswered() {
        XCTAssertEqual(state(lookup: .success(false)), .notAnswered)
    }

    func testAFailedLookupWithNothingElseToGoOnIsUncheckableNeverNotAnswered() {
        let result = state(lookup: .failure(LookupFailed()))
        XCTAssertEqual(result, .uncheckable)
        XCTAssertNotEqual(result, .notAnswered)
    }

    // MARK: Reading the document list

    func testADocumentInTheListMeansAResponseExists() throws {
        let list: [String: Any] = ["documents": [["$id": "someId"]]]
        XCTAssertTrue(try AppConnect.responseExists(inDocumentList: list))
    }

    func testAnEmptyListMeansNoResponse() throws {
        let none: [[String: Any]] = []
        XCTAssertFalse(try AppConnect.responseExists(inDocumentList: ["documents": none]))
    }

    func testAListWithoutADocumentsArrayIsAFailureNotNoResponse() {
        XCTAssertThrowsError(try AppConnect.responseExists(inDocumentList: [:]))
        XCTAssertThrowsError(try AppConnect.responseExists(inDocumentList: ["documents": "nope"]))
    }
}

// MARK: - Mainnet entry rules (AC-12, AC-24, AC-25, AC-26)

/// `AppConnect.intakeRefusal(forCode:network:)` is the pure decision request
/// intake takes before it parses a code: which codes the wallet refuses on
/// which network. Codes are classified by scheme and `v=` only; whether the
/// rest parses is `parseQR`'s business.
extension PlatformDashConnectDataSourceTests {
    private static let allNetworks: [DashConnectNetwork] = [.mainnet, .testnet, .devnet]

    private static func dashKeyV2(on network: DashConnectNetwork) -> String { "dash-key:abc?n=\(network.rawValue)&v=2" }
    private static func dashKeyV1(on network: DashConnectNetwork) -> String { "dash-key:abc?n=\(network.rawValue)&v=1" }
    private static func connectLink(on network: DashConnectNetwork) -> String { "dashpay://connect?v=2&n=\(network.rawValue)&r=abc" }
    private static func tokenPurchase(on network: DashConnectNetwork) -> String { "dash-st:abc?n=\(network.rawValue)&v=1" }

    /// AC-25: a dash-key request on mainnet is refused, and the reason says
    /// this kind of code is not accepted on mainnet.
    func testADashKeyCodeIsRefusedOnMainnetWithATypedReason() throws {
        let refusal = try XCTUnwrap(
            AppConnect.intakeRefusal(forCode: Self.dashKeyV2(on: .mainnet), network: .mainnet),
            "a dash-key code was taken on mainnet")
        XCTAssertTrue(refusal.reason.localizedCaseInsensitiveContains("mainnet"), "reason: \(refusal.reason)")
        XCTAssertNotEqual(refusal, AppConnect.v1Refusal, "a v2 dash-key code is not told to be a v1 code")
    }

    /// AC-25: on testnet (and devnet) a dash-key code is still answered.
    func testADashKeyCodeIsNotRefusedOnTestnetOrDevnet() {
        for network in [DashConnectNetwork.testnet, .devnet] {
            XCTAssertNil(
                AppConnect.intakeRefusal(forCode: Self.dashKeyV2(on: network), network: network),
                "a dash-key code was refused on \(network)")
        }
    }

    /// AC-26: a DashPay connect link works on every network, mainnet included.
    func testADashpayConnectLinkIsNotRefusedOnAnyNetwork() {
        for network in Self.allNetworks {
            XCTAssertNil(
                AppConnect.intakeRefusal(forCode: Self.connectLink(on: network), network: network),
                "a dashpay://connect link was refused on \(network)")
        }
    }

    /// AC-12: a v1 code is refused on every network, with the ask for a new code.
    func testAVersion1CodeIsRefusedOnEveryNetwork() {
        for network in Self.allNetworks {
            XCTAssertEqual(
                AppConnect.intakeRefusal(forCode: Self.dashKeyV1(on: network), network: network),
                AppConnect.v1Refusal, "a v1 code on \(network)")
        }
    }

    /// AC-12: a token purchase code is still a purchase, so intake refuses
    /// nothing on any network. (Whether the wallet has a username is judged
    /// later, when the purchase is built: AC-05.)
    func testATokenPurchaseCodeIsNotRefusedOnAnyNetwork() {
        for network in Self.allNetworks {
            XCTAssertNil(
                AppConnect.intakeRefusal(forCode: Self.tokenPurchase(on: network), network: network),
                "a token purchase code was refused on \(network)")
        }
    }

    /// A code that is none of the above is no concern of this decision: the
    /// parser answers it.
    func testAnUnrelatedCodeIsNotRefusedByTheIntakeDecision() {
        for network in Self.allNetworks {
            XCTAssertNil(AppConnect.intakeRefusal(forCode: "https://example.com", network: network))
        }
    }
}

// MARK: - Connections page availability (AC-24, AC-26)

/// `ConnectionsViewModel.availability(protocolVersion:)` is the pure rule the
/// Connections page is gated by: the protocol version read at runtime, and
/// nothing else. The view model has no injected version read, so the rule is
/// tested as a function of the read's result.
extension ConnectionsViewModelPurchaseTests {
    private struct VersionReadFailed: Error {}

}

// MARK: - Removing a Refused row (AC-20b, T27 R8)

extension ConnectionsViewModelPurchaseTests {
    func testRemovingARefusedRowAsksNoPinAndWritesNothing() async {
        let spy = LoginApprovalSpy(shown: [])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        let refused = DAppConnection(
            id: "refused-1", name: "Yap", url: "yap.pr", status: .refused, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))

        viewModel.removeConnection(refused)
        await waitUntil { !spy.removedIds.isEmpty }

        // `disconnect` is the call that asks for the PIN and writes to Platform.
        XCTAssertEqual(spy.removedIds, ["refused-1"])
        XCTAssertEqual(spy.disconnectCallCount, 0)
        XCTAssertNil(viewModel.message)
    }
}

// MARK: - Declining the approve sheet (AC-04)

/// Deny and a cancelled PIN write nothing and do not spend the request: the
/// data source's only writing entry point, `approveLogin`, is either never
/// called or throws, nothing is added to the connections, and the same request
/// opened again can be approved.
extension ConnectionsViewModelPurchaseTests {
    private static let callbackUri = [
        "dash-key:",
        "2fAANHHASdojyjV9Sqa2wf2nwZE8kLLqmeHpZWa8sBfaGsddVqyMG2ZVte7xJkTKsXvmFYbXzXbNnMo7bJQBxNcf79N8YWi7pLKyb39Rqv6b1KUmxw9UeJGYz2CV9hFGNUQtcyMYVq2Fg",
        "6vAxtxpYays61H8gLMcWqaG8TfgGA3H7setGAYiBsM5YmdZgeuCdGAHSwfNfav5cfFjXNDkPWv37UNSgFxj6o58jfXc3kCLKqLJtc5ZPjm1thEGYxK8HVYBi8fRQeEVy76n27DXGrVTyHz94CfJRuM",
        "nH76xGYbMgeuvurxjJMLrQgWUu53cjocYyzzNWdJrgs2D5?n=d&v=2&cb=https%3A%2F%2Fyap.pr%2Fconnect%3Fr%3Dd77dc0da9df83a47755a15c42c5d9db9d7a7fd62",
    ].joined()

    func testDenyingTheApproveSheetWritesNothingAndTheRequestCanBeApprovedWhenOpenedAgain() async {
        let shown = Self.consent(identityId: "identity-a")
        let spy = LoginApprovalSpy(shown: [shown])
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        viewModel.onQRScanned("login")
        await waitUntil { viewModel.pendingRequest != nil }
        viewModel.denyPendingRequest(asksToReturn: true)

        XCTAssertNil(viewModel.pendingRequest)
        XCTAssertNil(viewModel.approveError)
        XCTAssertEqual(spy.approvedConsents, [], "Deny asks for no approval, so nothing is added to the identity or to history")
        XCTAssertEqual(viewModel.connections, [])

        // Not spent: while it is fresh, the user opens it again and approves.
        viewModel.onQRScanned("login")
        await waitUntil { viewModel.pendingRequest != nil }
        XCTAssertEqual(viewModel.pendingRequest, shown)
        viewModel.approvePendingRequest()
        await waitUntil { viewModel.pendingRequest == nil }

        XCTAssertEqual(spy.approvedConsents, [shown])
    }

    // MARK: - R2: a link received while the version read is out

    /// An app that asked through a link is told the user declined once the
    /// user agrees to return; one that asked through a scanned code is
    /// answered on the other screen.
    func testDenyingALinkRequestTellsTheAppTheUserDeclinedAndAScannedOneOpensNothing() async throws {
        var request = MockDashConnectDataSource.sampleLoginRequest
        request.appConnect = try DashConnectUri.parseAppConnectRequest(Self.callbackUri)
        let shown = Self.consent(identityId: "identity-a")

        let linkSpy = LoginApprovalSpy(shown: [shown], loginRequest: request)
        let linkOpened = OpenedURLs()
        let linked = ConnectionsViewModel(dataSource: linkSpy, featureUnavailable: false, openURL: { linkOpened.urls.append($0) })
        linked.onURIReceived("login")
        await waitUntil { linked.pendingRequest != nil }
        linked.denyPendingRequest(asksToReturn: true)
        XCTAssertEqual(linkOpened.urls, [], "the return is asked about first")
        linked.openPendingReturn()

        XCTAssertEqual(linkOpened.urls.count, 1)
        XCTAssertEqual(linkOpened.urls.first?.host, "yap.pr")
        XCTAssertEqual(linkOpened.urls.first?.absoluteString.contains("ac=declined"), true)
        XCTAssertEqual(linkSpy.approvedConsents, [])

        let scanSpy = LoginApprovalSpy(shown: [shown], loginRequest: request)
        let scanOpened = OpenedURLs()
        let scanned = ConnectionsViewModel(dataSource: scanSpy, featureUnavailable: false, openURL: { scanOpened.urls.append($0) })
        scanned.onQRScanned("login")
        await waitUntil { scanned.pendingRequest != nil }
        scanned.denyPendingRequest(asksToReturn: true)

        XCTAssertEqual(scanOpened.urls, [])
        XCTAssertEqual(scanSpy.approvedConsents, [])
    }

    /// While the approval runs (the sheet's connecting state) Deny does
    /// nothing: the sheet is not dismissed and the approval is not cut off.
    func testDenyIsIgnoredWhileTheApprovalIsConnecting() async {
        let shown = Self.consent(identityId: "identity-a")
        let spy = LoginApprovalSpy(shown: [shown])
        spy.suspendsApproval = true
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        viewModel.onQRScanned("login")
        await waitUntil { viewModel.pendingRequest != nil }
        viewModel.approvePendingRequest()
        await waitUntil { spy.isApprovalSuspended }
        XCTAssertTrue(viewModel.isApproving)

        viewModel.denyPendingRequest(asksToReturn: true)
        XCTAssertEqual(viewModel.pendingRequest, shown, "dismissal is locked while connecting")

        spy.releaseApproval()
        await waitUntil { viewModel.pendingRequest == nil }
        XCTAssertEqual(spy.approvedConsents, [shown])
    }
}

// MARK: - A timed-out write, per write (T12, ADR 0009, AC-08 / AC-17 / AC-21)

/// What the data source does after a Platform write the executor ended with
/// `timedOut` (or `failed`), one test per write. The executor is the real one
/// with a clock that fires at once and a submit that never returns; the
/// decision is `AppConnect.nextStep(after:outcome:at:)`, the one function the
/// four writes of `PlatformDashConnectDataSource` switch on after
/// `AppConnectWriteExecutor.run`. A timeout says nothing of what Platform did
/// (spec AC-20, ADR 0004): only the next read decides, so no timeout is ever a
/// refusal and none is ever reported as published or deleted.
final class AppConnectWriteTimeoutTests: XCTestCase {
    private static let at = Date(timeIntervalSince1970: 1_773_132_300)

    /// An executor whose submit runs `submit`. Its timer fires at once when
    /// the write is meant to time out, and never otherwise, so a submit that
    /// returns or throws is not raced by the timer.
    private static func executor(
        timesOut: Bool,
        submit: @escaping @Sendable (PlatformWrite) async throws -> Void
    ) -> AppConnectWriteExecutor {
        AppConnectWriteExecutor(
            sleep: { _ in if !timesOut { try await Task.sleep(for: .seconds(1_000_000)) } },
            log: { _ in }, submit: submit)
    }

    /// A submit that never returns on its own.
    private static let hang: @Sendable (PlatformWrite) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(1_000_000))
    }

    /// With no `submit` the write hangs and times out; with one, it ends as
    /// `submit` does.
    private func nextStep(
        after write: PlatformWrite, submit: (@Sendable (PlatformWrite) async throws -> Void)? = nil
    ) async -> AppConnect.WriteNextStep {
        let outcome = await Self.executor(timesOut: submit == nil, submit: submit ?? Self.hang).run(write)
        return AppConnect.nextStep(after: write, outcome: outcome, at: Self.at)
    }

    // MARK: updateKeys (the approval's identity update)

    func testAnIdentityUpdateThatTimedOutIsReadAgainAndNeverRecordedAsARefusal() async {
        let step = await nextStep(after: .updateKeys(add: [10, 11], disable: [4]))
        XCTAssertEqual(step, .readIdentity, "a timed-out update is not a verdict: the intent stays Confirming until a read decides")
    }

    func testAnIdentityUpdateThatFailedWithoutAVerdictIsReadAgain() async {
        let step = await nextStep(after: .updateKeys(add: [10], disable: [])) { _ in
            throw SDKError.networkError("connection lost")
        }
        XCTAssertEqual(step, .readIdentity)
    }

    func testAConsensusRejectionOfTheIdentityUpdateStillRecordsTheRefusal() async {
        let rejection = SDKError.consensusRejection(PlatformConsensusError(code: 10_212, kind: .basic), "rendered text")
        let step = await nextStep(after: .updateKeys(add: [10], disable: [])) { _ in throw rejection }
        XCTAssertEqual(step, .recordRefusal(AppConnect.ConsensusRefusal(code: 10_212, at: Self.at)))
    }

    func testAnIdentityUpdateThatWasSubmittedNeedsNoRead() async {
        let step = await nextStep(after: .updateKeys(add: [10], disable: [])) { _ in }
        XCTAssertEqual(step, .done)
    }

    // MARK: publish

    func testAPublishThatTimedOutIsNotReportedPublishedUntilTheResponseIsSeen() async {
        let step = await nextStep(after: .publish(requestHash: Data([1, 2, 3])))
        XCTAssertEqual(step, .lookUpResponse, "only a read of Platform's documents says the response is published")
    }

    func testAPublishThatFailedIsCheckedAgainstPlatformToo() async {
        let step = await nextStep(after: .publish(requestHash: Data([1, 2, 3]))) { _ in
            throw SDKError.networkError("connection lost")
        }
        XCTAssertEqual(step, .lookUpResponse)
    }

    // MARK: fence

    func testAFenceThatTimedOutStopsTheDisconnect() async {
        let step = await nextStep(after: .fence(keyIds: [7]))
        XCTAssertEqual(step, .stop)
    }

    /// Through the real `submitDisconnect`, which sends what production sends
    /// (`.updateKeys(add:disable:)`): the update that timed out ends the run,
    /// the updates after it are not sent, and every key of the plan that was
    /// not turned off is reported still live. The next run, with the write
    /// going through, carries the whole plan.
    func testADisconnectWhoseUpdateTimedOutStopsAndReportsKeysStillLiveThenRunsForward() async {
        let disable = (0 ..< UInt32(AppConnect.maxKeysDisabledPerUpdate + 1)).map { 100 + $0 }
        let plan = AppConnect.DisconnectPlan(disable: disable, fence: [7])
        XCTAssertEqual(plan.updates.count, 2, "the plan needs two updates for the stop to leave one unsent")

        let sent = WriteLog()
        let hanging = Self.executor(timesOut: true) { write in
            sent.record(write)
            try await Self.hang(write)
        }
        let stopped = await PlatformDashConnectDataSource.submitDisconnect(plan, executor: hanging, now: { Self.at })
        XCTAssertTrue(stopped.progress.stopped)
        XCTAssertEqual(sent.kinds, ["updateKeys"], "the update after the timed-out one is not sent, and none is a fence")
        XCTAssertEqual(stopped.progress.turnedOff, [])
        XCTAssertEqual(stopped.progress.stillLive.sorted(), disable, "every key of the plan is still live")
        XCTAssertNotNil(stopped.failure)

        let going = Self.executor(timesOut: false) { _ in }
        let next = await PlatformDashConnectDataSource.submitDisconnect(plan, executor: going, now: { Self.at })
        XCTAssertFalse(next.progress.stopped)
        XCTAssertEqual(next.progress.turnedOff.sorted(), disable)
        XCTAssertEqual(next.progress.stillLive, [])
        XCTAssertNil(next.failure)
    }

    // MARK: The disconnect's write path (T20: R9, R11, R13, R17)

    /// An executor whose timer is real and short: a submit that returns is
    /// never raced by it, one that hangs is ended after 100 ms.
    private static func quickExecutor(
        submit: @escaping @Sendable (PlatformWrite) async throws -> Void
    ) -> AppConnectWriteExecutor {
        AppConnectWriteExecutor(
            timeout: .milliseconds(100), sleep: { try await Task.sleep(for: $0) }, log: { _ in }, submit: submit)
    }

    private static func liveKey(_ id: UInt32, disabledAt: UInt64? = nil) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: UInt8(truncatingIfNeeded: id), count: 20), readOnly: false, bound: nil,
            boundKnown: false, totalBudget: nil, expiresAt: nil, disabledAt: disabledAt)
    }

    private static func read(_ keys: [AppConnect.PlatformKey]) -> AppConnect.IdentitySnapshot {
        AppConnect.IdentitySnapshot(
            identityId: Data(repeating: 0x01, count: 32), revision: 9, keys: keys, platformTime: 1_800_000_000_000)
    }

    /// R13: a Confirming connection's disconnect plans only fences. When its
    /// write times out the progress names the fence, so the result is not a
    /// clean all-zero one.
    func testAFenceOnlyDisconnectWhoseWriteTimedOutReportsTheFenceNotPlaced() async {
        let log = WriteLog()
        let plan = AppConnect.DisconnectPlan(disable: [], fence: [7])
        let executor = Self.quickExecutor { write in
            log.record(write)
            try await Task.sleep(for: .seconds(1_000_000))
        }

        let submission = await PlatformDashConnectDataSource.submitDisconnect(plan, executor: executor, now: { Self.at })

        XCTAssertTrue(submission.progress.stopped)
        XCTAssertEqual(submission.progress.unplacedFences, [7], "the fence of the update that timed out is carried")
        XCTAssertNotNil(submission.failure)
        XCTAssertEqual(log.kinds, ["updateKeys"], "nothing else is sent after the stop")

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 1, leftoverFenceIds: [], keysNotChecked: 0, fenceKeyIds: [], after: nil, submission: submission)
        XCTAssertEqual(result.fencesNotPlaced, 1, "the sign-in can still land: this is not a clean result")
        XCTAssertEqual(result.fencesLeftOn, 0, "no read shows the fence on the identity: it is not a placed fence")
        XCTAssertEqual(result.keysStillLive, 0, "a fence is not an app key")
        XCTAssertEqual(result.keysTurnedOff, 0)
    }

    /// R13 mixed case: 7 fences and 3 disables are two updates; the second is
    /// fence-only and fails. The fence keys of the first were added and, with
    /// phase 2 skipped, are left on as well.
    func testADisconnectWhoseFenceOnlySecondUpdateFailedReportsEveryFenceLeft() async {
        let log = WriteLog()
        let fences: [UInt32] = [20, 21, 22, 23, 24, 25, 26]
        let plan = AppConnect.DisconnectPlan(disable: [10, 11, 12], fence: fences)
        XCTAssertEqual(plan.updates.map(\.disable), [[10, 11, 12], []])
        let executor = Self.quickExecutor { write in
            if log.record(write) == 2 { throw SDKError.networkError("connection lost") }
        }

        let submission = await PlatformDashConnectDataSource.submitDisconnect(plan, executor: executor, now: { Self.at })

        XCTAssertTrue(submission.progress.stopped)
        XCTAssertEqual(submission.progress.turnedOff, [10, 11, 12])
        XCTAssertEqual(submission.progress.unplacedFences, [26])
        XCTAssertEqual(submission.fencesLeftOn.sorted(), [20, 21, 22, 23, 24, 25], "added, and not turned off")
        XCTAssertEqual(log.kinds, ["updateKeys", "updateKeys"])
        XCTAssertEqual(
            submission.markKeyIds, Set([10, 11, 12, 20, 21, 22, 23, 24, 25, 26]),
            "T51 (L2): the done update's keys and fences, and the failed one's fence")

        // The read shows the first update's six fences on the identity, live.
        let after = Self.read([10, 11, 12].map { Self.liveKey($0, disabledAt: 1) } + [20, 21, 22, 23, 24, 25].map { Self.liveKey($0) })
        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 10, leftoverFenceIds: [], keysNotChecked: 0, fenceKeyIds: [20, 21, 22, 23, 24, 25], after: after, submission: submission)
        XCTAssertEqual(result.fencesLeftOn, 6, "placed and still on")
        XCTAssertEqual(result.fencesNotPlaced, 1, "the failed update's fence is not on the read")
        XCTAssertEqual(result.keysStillLive, 0)
        XCTAssertEqual(result.keysTurnedOff, 3)
    }

    /// T51 (L2, AC-16, AC-19): the same split, the fence-only second update
    /// refused: the fences of the done update still mark, the refused one's
    /// does not.
    func testADisconnectWhoseFenceOnlySecondUpdateIsRefusedCountsTheDoneUpdatesFencesForTheMark() async {
        let log = WriteLog()
        let plan = AppConnect.DisconnectPlan(disable: [10, 11, 12], fence: [20, 21, 22, 23, 24, 25, 26])
        let executor = Self.quickExecutor { write in
            if log.record(write) == 2 {
                throw SDKError.consensusRejection(PlatformConsensusError(code: 10_212, kind: .basic), "rendered text")
            }
        }

        let submission = await PlatformDashConnectDataSource.submitDisconnect(
            plan, executor: executor, now: { Self.at })

        XCTAssertTrue(submission.progress.stopped)
        XCTAssertEqual(submission.markKeyIds, Set([10, 11, 12, 20, 21, 22, 23, 24, 25]))
    }

    /// R17: phase 2 sends nothing when phase 1 stopped.
    func testTurningFencesOffIsSkippedWhenTheFirstPhaseStopped() async {
        let log = WriteLog()
        let plan = AppConnect.DisconnectPlan(disable: [], fence: [20, 21, 22, 23, 24, 25, 26])
        let executor = Self.quickExecutor { write in
            if log.record(write) == 2 { throw SDKError.networkError("connection lost") }
        }

        _ = await PlatformDashConnectDataSource.submitDisconnect(plan, executor: executor, now: { Self.at })

        XCTAssertFalse(log.kinds.contains("fence"), "sent: \(log.kinds)")
    }

    /// R17: phase 2 stops at its first step that is not `.done`.
    func testTurningFencesOffStopsAtTheFirstBatchThatFailed() async {
        let log = WriteLog()
        let fences = (0 ..< UInt32(11)).map { 20 + $0 }
        let plan = AppConnect.DisconnectPlan(disable: [], fence: fences)
        XCTAssertEqual(plan.updates.count, 2)
        let executor = Self.quickExecutor { write in
            if case .fence = write { log.record(write); throw SDKError.networkError("connection lost") }
            log.record(write)
        }

        let submission = await PlatformDashConnectDataSource.submitDisconnect(plan, executor: executor, now: { Self.at })

        XCTAssertEqual(log.kinds, ["updateKeys", "updateKeys", "fence"], "the second fence batch is not sent")
        XCTAssertFalse(submission.progress.stopped)
        XCTAssertEqual(submission.fencesLeftOn.sorted(), fences, "the failed batch and the unsent one stay on")
        XCTAssertNotNil(submission.failure)
    }

    /// T46 (K1, AC-16, AC-19): a run stopped by an update of unknown outcome
    /// may have landed the keys of every update it sent: those of the updates
    /// reported done, and those of the one that failed.
    func testAStoppedRunWhoseLastUpdateHasAnUnknownOutcomeCountsTheKeysOfEveryUpdateItSent() async {
        let disable = Array(1 ... UInt32(AppConnect.maxKeysDisabledPerUpdate + 1))
        let plan = AppConnect.DisconnectPlan(disable: disable, fence: [])
        XCTAssertEqual(plan.updates.count, 2)
        let log = WriteLog()
        let executor = Self.quickExecutor { write in
            if log.record(write) == 2 { throw SDKError.networkError("connection lost") }
        }

        let submission = await PlatformDashConnectDataSource.submitDisconnect(
            plan, executor: executor, now: { Self.at })

        XCTAssertTrue(submission.progress.stopped)
        XCTAssertEqual(submission.markKeyIds, Set(disable), "the done update's keys and the failed one's")
    }

    /// T46 (K1, AC-16, AC-19): a refused update did not land, but the updates
    /// reported done before it did.
    func testAStoppedRunWhoseLastUpdateIsRefusedCountsOnlyTheKeysOfTheUpdatesReportedDone() async {
        let disable = Array(1 ... UInt32(AppConnect.maxKeysDisabledPerUpdate + 1))
        let plan = AppConnect.DisconnectPlan(disable: disable, fence: [])
        let log = WriteLog()
        let executor = Self.quickExecutor { write in
            if log.record(write) == 2 {
                throw SDKError.consensusRejection(PlatformConsensusError(code: 10_212, kind: .basic), "rendered text")
            }
        }

        let submission = await PlatformDashConnectDataSource.submitDisconnect(
            plan, executor: executor, now: { Self.at })

        XCTAssertTrue(submission.progress.stopped)
        XCTAssertEqual(submission.markKeyIds, Set(plan.updates[0].disable), "only the done update's keys")
    }

    /// T46 (K1): a run that was not stopped and left no fence on leaves the
    /// mark to the read after.
    func testARunThatWasNotStoppedAndLeftNoFenceOnCountsNoKeyForTheMark() async {
        let plan = AppConnect.DisconnectPlan(disable: [1, 2], fence: [])
        let executor = Self.quickExecutor { _ in }

        let submission = await PlatformDashConnectDataSource.submitDisconnect(
            plan, executor: executor, now: { Self.at })

        XCTAssertFalse(submission.progress.stopped)
        XCTAssertEqual(submission.markKeyIds, [])
    }

    /// T50 (L1, AC-18, AC-19): phase 1 finished and the update that turns
    /// the fences off failed: the fences left on hold the ids of the intents
    /// the disconnect ran on, so they count for the mark.
    func testARunWhoseFenceTurnOffFailedCountsTheFencesLeftOnForTheMark() async {
        let plan = AppConnect.DisconnectPlan(disable: [1], fence: [20, 21])
        let executor = Self.quickExecutor { write in
            if case .fence = write { throw SDKError.networkError("connection lost") }
        }

        let submission = await PlatformDashConnectDataSource.submitDisconnect(
            plan, executor: executor, now: { Self.at })

        XCTAssertFalse(submission.progress.stopped)
        XCTAssertEqual(submission.fencesLeftOn.sorted(), [20, 21])
        XCTAssertEqual(submission.markKeyIds, [20, 21])
    }

    /// R11/R16: still-live app keys come from the fresh read, not from the
    /// plan.
    func testStillLiveKeysAreCountedFromTheFreshReadOfAStoppedDisconnect() {
        let plan = AppConnect.DisconnectPlan(disable: [10, 11], fence: [])
        var progress = AppConnect.DisconnectProgress()
        progress.stopped = true
        progress.stillLive = [10, 11]
        let submission = PlatformDashConnectDataSource.DisconnectSubmission(
            progress: progress, fencesLeftOn: [], failure: AppConnectWriteTimedOut())
        // The update landed after all: key 10 shows disabled.
        let after = Self.read([Self.liveKey(10, disabledAt: 1), Self.liveKey(11)])

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 2, leftoverFenceIds: [], keysNotChecked: 0, fenceKeyIds: [], after: after, submission: submission)

        XCTAssertEqual(result.keysStillLive, 1)
        XCTAssertEqual(result.keysTurnedOff, 1)
    }

    /// Of the keys turned off, those no intent names are counted on their
    /// own; one the read still shows live is not.
    func testUnrecordedKeysTurnedOffAreCountedFromTheFreshRead() {
        var plan = AppConnect.DisconnectPlan(disable: [30, 10, 20], fence: [])
        plan.unrecorded = [20, 30]
        var progress = AppConnect.DisconnectProgress()
        progress.stopped = true
        progress.stillLive = [10, 20, 30]
        let submission = PlatformDashConnectDataSource.DisconnectSubmission(
            progress: progress, fencesLeftOn: [], failure: AppConnectWriteTimedOut())
        let after = Self.read([Self.liveKey(10, disabledAt: 1), Self.liveKey(20), Self.liveKey(30, disabledAt: 1)])

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 3, leftoverFenceIds: [], keysNotChecked: 0, fenceKeyIds: [], after: after, submission: submission)

        XCTAssertEqual(result.keysTurnedOff, 2)
        XCTAssertEqual(result.unrecordedKeysTurnedOff, 1, "key 30 is off; key 20 still shows live")
    }

    /// R11/R16: only when the fresh read failed does `progress.stillLive` stand.
    func testStillLiveKeysComeFromTheProgressOnlyWhenTheFreshReadFailed() {
        let plan = AppConnect.DisconnectPlan(disable: [10, 11], fence: [])
        var progress = AppConnect.DisconnectProgress()
        progress.stopped = true
        progress.stillLive = [10, 11]
        let submission = PlatformDashConnectDataSource.DisconnectSubmission(
            progress: progress, fencesLeftOn: [], failure: AppConnectWriteTimedOut())

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 2, leftoverFenceIds: [], keysNotChecked: 0, fenceKeyIds: [], after: nil, submission: submission)

        XCTAssertEqual(result.keysStillLive, 2)
    }

    /// R11/R16: a leftover fence key of the wallet is in `plan.disable` but is
    /// not an app key; it is reported as a fence left on.
    func testALeftoverFenceKeyIsNotCountedAsAnAppKey() {
        let plan = AppConnect.DisconnectPlan(disable: [10, 50], fence: [])
        var progress = AppConnect.DisconnectProgress()
        progress.turnedOff = [10]
        progress.stopped = true
        progress.stillLive = [50]
        let submission = PlatformDashConnectDataSource.DisconnectSubmission(
            progress: progress, fencesLeftOn: [], failure: AppConnectWriteTimedOut())
        let after = Self.read([Self.liveKey(10, disabledAt: 1), Self.liveKey(50)])

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 1, leftoverFenceIds: [50], keysNotChecked: 0, fenceKeyIds: [50], after: after, submission: submission)

        XCTAssertEqual(result.keysStillLive, 0)
        XCTAssertEqual(result.fencesLeftOn, 1)
        XCTAssertEqual(result.keysTurnedOff, 1)
    }

    /// T32 (F3): a fence the after-read shows live was placed and not turned
    /// off: `fencesLeftOn` (no error). One the read does not show, or no read
    /// at all, was never placed: `fencesNotPlaced` (an error).
    func testAFenceTheAfterReadShowsOnIsPlacedAndOneItDoesNotShowIsNotPlaced() {
        let plan = AppConnect.DisconnectPlan(disable: [10], fence: [20, 21])
        var progress = AppConnect.DisconnectProgress()
        progress.stopped = true
        progress.turnedOff = [10]
        progress.unplacedFences = [21]
        let submission = PlatformDashConnectDataSource.DisconnectSubmission(
            progress: progress, fencesLeftOn: [20], failure: AppConnectWriteTimedOut())
        let after = Self.read([Self.liveKey(10, disabledAt: 1), Self.liveKey(20)])

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 3, leftoverFenceIds: [], keysNotChecked: 0, fenceKeyIds: [20], after: after, submission: submission)

        XCTAssertEqual(result.fencesLeftOn, 1, "fence 20 is live on the read: placed, not turned off")
        XCTAssertEqual(result.fencesNotPlaced, 1, "fence 21 is not on the read: never placed")
    }

    /// T32 (F3): a fence whose update timed out but that the read shows live
    /// was placed after all.
    func testAnUnplacedFenceThatTheAfterReadShowsLiveIsReportedAsPlaced() {
        let plan = AppConnect.DisconnectPlan(disable: [], fence: [7])
        var progress = AppConnect.DisconnectProgress()
        progress.stopped = true
        progress.unplacedFences = [7]
        let submission = PlatformDashConnectDataSource.DisconnectSubmission(
            progress: progress, fencesLeftOn: [], failure: AppConnectWriteTimedOut())

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 1, leftoverFenceIds: [], keysNotChecked: 0, fenceKeyIds: [7],
            after: Self.read([Self.liveKey(7)]), submission: submission)

        XCTAssertEqual(result.fencesLeftOn, 1)
        XCTAssertEqual(result.fencesNotPlaced, 0)
    }

    /// T37 (G3): the intent's own key under a fence id is no fence: its
    /// sign-in landed before the fence could be placed, so it is an app key
    /// still live, and the user is told.
    func testTheIntentsOwnKeyUnderAFenceIdIsAnAppKeyStillLiveNotAPlacedFence() {
        let plan = AppConnect.DisconnectPlan(disable: [], fence: [7])
        var progress = AppConnect.DisconnectProgress()
        progress.stopped = true
        progress.unplacedFences = [7]
        let submission = PlatformDashConnectDataSource.DisconnectSubmission(
            progress: progress, fencesLeftOn: [], failure: AppConnectWriteTimedOut())

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 1, leftoverFenceIds: [], keysNotChecked: 0, fenceKeyIds: [],
            after: Self.read([Self.liveKey(7)]), submission: submission)

        XCTAssertEqual(result.keysStillLive, 1, "the sign-in landed: its key is live")
        XCTAssertEqual(result.fencesLeftOn, 0)
        XCTAssertEqual(result.fencesNotPlaced, 0)
    }

    /// T37 (G4), T42 (H5): with no read after a run that was not stopped and
    /// whose update turning the fences off failed, a leftover fence the run
    /// turned off counts as nothing and a fence added and not turned off as
    /// placed and left on; no fence counts as not placed.
    func testWithNoReadAfterARunFencesAreSortedFromTheSubmission() {
        let plan = AppConnect.DisconnectPlan(disable: [10, 50], fence: [20])
        var progress = AppConnect.DisconnectProgress()
        progress.turnedOff = [10, 50]
        let submission = PlatformDashConnectDataSource.DisconnectSubmission(
            progress: progress, fencesLeftOn: [20], failure: AppConnectWriteTimedOut())

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 2, leftoverFenceIds: [50], keysNotChecked: 0, fenceKeyIds: [],
            after: nil, submission: submission)

        XCTAssertEqual(result.fencesLeftOn, 1, "fence 20 was added and not turned off")
        XCTAssertEqual(result.fencesNotPlaced, 0, "every fence was placed")
        XCTAssertEqual(result.keysStillLive, 0)
    }

    /// T37 (G4): with no read after a stopped run, a leftover fence the
    /// progress still has live is a placed fence left on, not an unplaced one.
    func testWithNoReadAfterAStoppedRunALeftoverFenceStillLiveIsPlaced() {
        let plan = AppConnect.DisconnectPlan(disable: [10, 50], fence: [])
        var progress = AppConnect.DisconnectProgress()
        progress.stopped = true
        progress.stillLive = [10, 50]
        let submission = PlatformDashConnectDataSource.DisconnectSubmission(
            progress: progress, fencesLeftOn: [], failure: AppConnectWriteTimedOut())

        let result = PlatformDashConnectDataSource.disconnectResult(
            plan: plan, appKeysOff: 1, leftoverFenceIds: [50], keysNotChecked: 0, fenceKeyIds: [],
            after: nil, submission: submission)

        XCTAssertEqual(result.fencesLeftOn, 1)
        XCTAssertEqual(result.fencesNotPlaced, 0)
        XCTAssertEqual(result.keysStillLive, 1, "key 10 went out in the update that failed")
    }

    // MARK: deleteResponse

    func testAResponseDeleteThatTimedOutIsNotMarkedRemovedUntilTheResponseIsGone() async {
        let step = await nextStep(after: .deleteResponse(documentId: Data([0x0A, 0x0B])))
        XCTAssertEqual(step, .lookUpResponse, "the response stays marked, and the next disconnect deletes it again unless a lookup finds it gone")
    }

    func testAResponseDeleteThatWasSubmittedIsDone() async {
        let step = await nextStep(after: .deleteResponse(documentId: Data([0x0A, 0x0B]))) { _ in }
        XCTAssertEqual(step, .done)
    }
}

/// The writes an executor submitted, in order.
private final class WriteLog: @unchecked Sendable {
    private let lock = NSLock()
    private var written: [PlatformWrite] = []

    /// Records `write`; returns how many writes there are now.
    @discardableResult
    func record(_ write: PlatformWrite) -> Int {
        lock.withLock { written.append(write); return written.count }
    }

    var kinds: [String] { lock.withLock { written.map(\.kind) } }
}

// MARK: - The data source's write paths (T21: R9; AC-08, AC-11, AC-20, AC-20b, AC-21)

/// What the data source does around each Platform write, through the real
/// code path with the real `AppConnectWriteExecutor` (a short real timer and
/// a submit that hangs, throws or returns) and plain values in place of the
/// live SDK. Each `PlatformDashConnectDataSource` static used here is the part
/// of a private method that follows its SDK-bound step; the private method
/// calls it with its context's stores, reads and signer.
final class AppConnectDataSourceWriteTests: XCTestCase {
    private static let at = Date(timeIntervalSince1970: 1_773_132_300)
    private static let identity = Data(repeating: 0x01, count: 32)
    private static let app = Data(repeating: 0xA1, count: 32)
    private static let installA = Data(repeating: 0xC1, count: 32)
    private static let installB = Data(repeating: 0xC2, count: 32)
    private static let requestHash = Data(repeating: 0xEE, count: 20)
    private static let documentId = Data(repeating: 0xDD, count: 32)

    private struct ReadFailed: Error {}

    /// A timer of 100 ms: a submit that returns is never raced by it, one that
    /// hangs is ended by it.
    private static func executor(
        submit: @escaping @Sendable (PlatformWrite) async throws -> Void
    ) -> AppConnectWriteExecutor {
        AppConnectWriteExecutor(
            timeout: .milliseconds(100), sleep: { try await Task.sleep(for: $0) }, log: { _ in }, submit: submit)
    }

    private static let hang: @Sendable (PlatformWrite) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(1_000_000))
    }

    private static func authKey(_ id: UInt32) -> AppConnect.IntendedKey {
        AppConnect.IntendedKey(
            id: id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: UInt8(truncatingIfNeeded: id), count: 20), readOnly: false,
            bound: .singleContract(app), totalBudget: 1000, expiresAt: nil)
    }

    private static func onPlatform(_ key: AppConnect.IntendedKey, disabledAt: UInt64? = nil) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType, data: key.data,
            readOnly: key.readOnly, bound: key.bound, boundKnown: true, totalBudget: key.totalBudget,
            expiresAt: key.expiresAt, disabledAt: disabledAt)
    }

    private static func snapshot(_ keys: [AppConnect.PlatformKey] = []) -> AppConnect.IdentitySnapshot {
        AppConnect.IdentitySnapshot(identityId: identity, revision: 5, keys: keys, platformTime: 1_800_000_000_000)
    }

    private static func intent(
        keys: [UInt32], disables: [UInt32] = [], connectionId: Data? = installA, app: Data = app,
        responseDocumentId: Data? = nil, responseRemoved: Bool = false, refusal: AppConnect.ConsensusRefusal? = nil
    ) -> AppConnect.ConnectionIntent {
        var intent = AppConnect.ConnectionIntent(
            id: UUID(), identityId: identity, appId: app, appLabel: "App", appUrl: "", requestHash: requestHash,
            connectionId: connectionId, keys: keys.map(authKey), sentEncryptionKeyIds: [], disables: disables,
            response: AppConnect.ResponseValues(appEphemeralPubKeyHash: "ee", walletEphemeralPubKey: "02", encryptedPayload: "00"),
            responseDocumentId: responseDocumentId, responseRemoved: responseRemoved,
            createdAt: Date(timeIntervalSince1970: 0), closedAt: nil)
        intent.refusal = refusal
        return intent
    }

    /// Writes handed to the submit, whole.
    private final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var writes: [PlatformWrite] = []
        func record(_ write: PlatformWrite) { lock.withLock { writes.append(write) } }
        var all: [PlatformWrite] { lock.withLock { writes } }
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func hit() { lock.withLock { n += 1 } }
        var count: Int { lock.withLock { n } }
    }

    private final class MemoryIntentStore: AppConnectIntentStore, @unchecked Sendable {
        private var intents: [AppConnect.ConnectionIntent]
        let canPersist: Bool
        init(_ intents: [AppConnect.ConnectionIntent] = [], canPersist: Bool = true) {
            self.intents = intents
            self.canPersist = canPersist
        }
        func load() -> [AppConnect.ConnectionIntent] { intents }
        func save(_ intents: [AppConnect.ConnectionIntent]) { if canPersist { self.intents = intents } }
        func pinned(toWalletIdHex walletIdHex: String) -> any AppConnectIntentStore { self }
    }

    // MARK: 1. The identity update times out (AC-20)

    func testAnIdentityUpdateThatTimedOutLeavesTheIntentRecordedBeforeItConfirmingAndTheRequestSpent() async throws {
        let intent = Self.intent(keys: [13])
        let store = MemoryIntentStore()
        let recordedAtSubmit = Calls()
        let sent = Sent()
        let afterRecording = Calls()
        let executor = Self.executor { write in
            if store.load().contains(where: { $0.id == intent.id }) { recordedAtSubmit.hit() }
            sent.record(write)
            try await Self.hang(write)
        }

        var thrown: Error?
        do {
            _ = try await PlatformDashConnectDataSource.recordAndSubmitIdentityUpdate(
                intent, snapshot: Self.snapshot(), intents: store,
                makeExecutor: { executor }, now: { Self.at },
                afterRecording: { afterRecording.hit() },
                // No read shows the update: the cause stands.
                readAfterFailure: { throw $0 })
        } catch {
            thrown = error
        }

        XCTAssertTrue(thrown is AppConnectWriteTimedOut, "a timeout is not a verdict: \(String(describing: thrown))")
        XCTAssertEqual(recordedAtSubmit.count, 1, "the intent is in the store when the update is sent")
        XCTAssertEqual(afterRecording.count, 1)
        XCTAssertEqual(sent.all.count, 1)
        let stored = try XCTUnwrap(store.load().first { $0.id == intent.id })
        XCTAssertNil(stored.closedAt)
        XCTAssertNil(stored.refusal, "a timeout is never recorded as a refusal")
        XCTAssertEqual(AppConnect.status(of: stored, in: Self.snapshot()), .confirming)
        let failure = PlatformDashConnectDataSource.approvalFailure(after: try XCTUnwrap(thrown))
        XCTAssertEqual((failure as? AppConnect.Refusal)?.status, .failed, "the request is spent: the app is told it failed")
    }

    func testAnIdentityUpdateThatTimedOutButLandedReturnsTheReadThatShowsIt() async throws {
        let intent = Self.intent(keys: [13])
        let landed = Self.snapshot([Self.onPlatform(Self.authKey(13))])

        let result = try await PlatformDashConnectDataSource.recordAndSubmitIdentityUpdate(
            intent, snapshot: Self.snapshot(), intents: MemoryIntentStore(),
            makeExecutor: { Self.executor(submit: Self.hang) }, now: { Self.at },
            afterRecording: {}, readAfterFailure: { _ in landed })

        XCTAssertEqual(result, landed)
    }

    func testAnIdentityUpdateThatWasSubmittedNeedsNoRead() async throws {
        let reads = Calls()
        let result = try await PlatformDashConnectDataSource.recordAndSubmitIdentityUpdate(
            Self.intent(keys: [13]), snapshot: Self.snapshot(), intents: MemoryIntentStore(),
            makeExecutor: { Self.executor { _ in } }, now: { Self.at },
            afterRecording: {}, readAfterFailure: { reads.hit(); throw $0 })

        XCTAssertNil(result)
        XCTAssertEqual(reads.count, 0)
    }

    func testNothingIsSentWhenTheIntentCannotBeRecorded() async {
        let sent = Sent()
        do {
            _ = try await PlatformDashConnectDataSource.recordAndSubmitIdentityUpdate(
                Self.intent(keys: [13]), snapshot: Self.snapshot(), intents: MemoryIntentStore(canPersist: false),
                makeExecutor: { Self.executor { sent.record($0) } }, now: { Self.at },
                afterRecording: {}, readAfterFailure: { throw $0 })
            XCTFail("expected grantNotRecorded")
        } catch {
            XCTAssertEqual(error as? DashConnectPlatformError, .grantNotRecorded)
        }
        XCTAssertEqual(sent.all.count, 0, "keys no intent names are never submitted")
    }

    // MARK: 4. A consensus refusal of the identity update (AC-20b)

    func testAConsensusRefusalOfTheIdentityUpdateIsRecordedOnTheIntentAndShowsRefused() async throws {
        let intent = Self.intent(keys: [13])
        let store = MemoryIntentStore()
        let rejection = SDKError.consensusRejection(PlatformConsensusError(code: 10_212, kind: .basic), "rendered text")
        let reads = Calls()

        var thrown: Error?
        do {
            _ = try await PlatformDashConnectDataSource.recordAndSubmitIdentityUpdate(
                intent, snapshot: Self.snapshot(), intents: store,
                makeExecutor: { Self.executor { _ in throw rejection } }, now: { Self.at },
                afterRecording: {}, readAfterFailure: { reads.hit(); throw $0 })
        } catch {
            thrown = error
        }

        XCTAssertEqual(thrown as? DashConnectPlatformError, .networkRefused(code: 10_212))
        XCTAssertEqual(reads.count, 0, "a verdict needs no read")
        let stored = try XCTUnwrap(store.load().first { $0.id == intent.id })
        XCTAssertEqual(stored.refusal, AppConnect.ConsensusRefusal(code: 10_212, at: Self.at))
        XCTAssertEqual(AppConnect.status(of: stored, in: Self.snapshot()), .refused)
        let failure = PlatformDashConnectDataSource.approvalFailure(after: try XCTUnwrap(thrown))
        XCTAssertEqual(failure as? DashConnectPlatformError, .networkRefused(code: 10_212), "typed, so the app is told for good")
    }

    func testAFailureWithoutAVerdictIsNotRecordedAsARefusal() async throws {
        let intent = Self.intent(keys: [13])
        let store = MemoryIntentStore()

        _ = try? await PlatformDashConnectDataSource.recordAndSubmitIdentityUpdate(
            intent, snapshot: Self.snapshot(), intents: store,
            makeExecutor: { Self.executor { _ in throw SDKError.networkError("connection lost") } }, now: { Self.at },
            afterRecording: {}, readAfterFailure: { throw $0 })

        XCTAssertNil(try XCTUnwrap(store.load().first).refusal)
    }

    // MARK: 4b. An answered request is refused before any PIN (AC-11)

    func testARequestAnsweredBeforeIsRefusedWithoutAskingForAPIN() async {
        let pins = Calls()
        do {
            try await PlatformDashConnectDataSource.authorizeUnlessAnswered(
                answered: { .answered }, authorize: { pins.hit() })
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual((error as? AppConnect.Refusal)?.status, .failed, "spent: the app asks anew")
        }
        XCTAssertEqual(pins.count, 0)
    }

    func testARequestThatCannotBeCheckedIsRefusedWithoutAskingForAPIN() async {
        let pins = Calls()
        do {
            try await PlatformDashConnectDataSource.authorizeUnlessAnswered(
                answered: { .uncheckable }, authorize: { pins.hit() })
            XCTFail("expected answeredUncheckable")
        } catch {
            XCTAssertEqual(error as? DashConnectPlatformError, .answeredUncheckable)
        }
        XCTAssertEqual(pins.count, 0)
    }

    func testARequestNotAnsweredBeforeAsksForThePINOnce() async throws {
        let pins = Calls()
        try await PlatformDashConnectDataSource.authorizeUnlessAnswered(
            answered: { .notAnswered }, authorize: { pins.hit() })
        XCTAssertEqual(pins.count, 1)
    }

    // MARK: 2. The publish times out (AC-08, AC-20)

    func testAPublishThatTimedOutIsNotDeliveredUntilALookupFindsTheResponse() async throws {
        let intent = Self.intent(keys: [13])
        let store = MemoryIntentStore([intent])

        do {
            try await PlatformDashConnectDataSource.publishAndRecord(
                intent, intents: store, executor: Self.executor(submit: Self.hang), now: { Self.at },
                createdDocumentId: { nil }, lookUp: { nil })
            XCTFail("a publish nobody can find is not delivered")
        } catch {
            XCTAssertTrue(error is AppConnectWriteTimedOut, "\(error)")
        }
        XCTAssertNil(try XCTUnwrap(store.load().first).responseDocumentId, "never reported as published")
    }

    func testAPublishThatTimedOutIsDeliveredOnceALookupFindsTheResponse() async throws {
        let intent = Self.intent(keys: [13])
        let store = MemoryIntentStore([intent])

        try await PlatformDashConnectDataSource.publishAndRecord(
            intent, intents: store, executor: Self.executor(submit: Self.hang), now: { Self.at },
            createdDocumentId: { nil }, lookUp: { Self.documentId })

        let stored = try XCTUnwrap(store.load().first)
        XCTAssertEqual(stored.responseDocumentId, Self.documentId)
        XCTAssertFalse(stored.responseRemoved)
    }

    func testAPublishThatTimedOutWithAFailedLookupIsNotDelivered() async throws {
        let intent = Self.intent(keys: [13])
        let store = MemoryIntentStore([intent])

        do {
            try await PlatformDashConnectDataSource.publishAndRecord(
                intent, intents: store, executor: Self.executor(submit: Self.hang), now: { Self.at },
                createdDocumentId: { nil }, lookUp: { throw ReadFailed() })
            XCTFail("a lookup that fails says nothing")
        } catch {}
        XCTAssertNil(try XCTUnwrap(store.load().first).responseDocumentId)
    }

    func testAPublishThatWasSubmittedRecordsTheCreatedDocumentWithoutALookup() async throws {
        let intent = Self.intent(keys: [13])
        let store = MemoryIntentStore([intent])
        let lookups = Calls()

        try await PlatformDashConnectDataSource.publishAndRecord(
            intent, intents: store, executor: Self.executor { _ in }, now: { Self.at },
            createdDocumentId: { Self.documentId }, lookUp: { lookups.hit(); return nil })

        XCTAssertEqual(try XCTUnwrap(store.load().first).responseDocumentId, Self.documentId)
        XCTAssertEqual(lookups.count, 0)
    }

    // MARK: 3. The response delete times out

    func testAResponseDeleteThatTimedOutLeavesTheResponseMarkedWhileItIsStillThere() async throws {
        let intent = Self.intent(keys: [13], responseDocumentId: Self.documentId)
        let store = MemoryIntentStore([intent])

        await PlatformDashConnectDataSource.deleteResponse(
            documentId: Self.documentId, of: intent.id, intents: store,
            executor: Self.executor(submit: Self.hang), now: { Self.at }, lookUp: { Self.documentId })

        XCTAssertFalse(try XCTUnwrap(store.load().first).responseRemoved, "not reported deleted")
    }

    func testAResponseDeleteThatTimedOutAndWhoseLookupFailedLeavesTheResponseMarked() async throws {
        let intent = Self.intent(keys: [13], responseDocumentId: Self.documentId)
        let store = MemoryIntentStore([intent])

        await PlatformDashConnectDataSource.deleteResponse(
            documentId: Self.documentId, of: intent.id, intents: store,
            executor: Self.executor(submit: Self.hang), now: { Self.at }, lookUp: { throw ReadFailed() })

        XCTAssertFalse(try XCTUnwrap(store.load().first).responseRemoved)
    }

    func testAResponseDeleteThatTimedOutIsRemovedWhenALookupShowsItGone() async throws {
        let intent = Self.intent(keys: [13], responseDocumentId: Self.documentId)
        let store = MemoryIntentStore([intent])

        await PlatformDashConnectDataSource.deleteResponse(
            documentId: Self.documentId, of: intent.id, intents: store,
            executor: Self.executor(submit: Self.hang), now: { Self.at }, lookUp: { nil })

        XCTAssertTrue(try XCTUnwrap(store.load().first).responseRemoved, "it landed without confirming")
    }

    func testAResponseDeleteThatWasSubmittedIsRemovedWithoutALookup() async throws {
        let intent = Self.intent(keys: [13], responseDocumentId: Self.documentId)
        let store = MemoryIntentStore([intent])
        let lookups = Calls()

        await PlatformDashConnectDataSource.deleteResponse(
            documentId: Self.documentId, of: intent.id, intents: store,
            executor: Self.executor { _ in }, now: { Self.at }, lookUp: { lookups.hit(); return Self.documentId })

        XCTAssertTrue(try XCTUnwrap(store.load().first).responseRemoved)
        XCTAssertEqual(lookups.count, 0)
    }

    // MARK: 5. Remove of a Refused row (AC-20b)

    func testRemoveHidesARefusedConnectionAndTouchesNothingElse() throws {
        let refused = Self.intent(keys: [13], refusal: AppConnect.ConsensusRefusal(code: 10_212, at: Self.at))
        let otherApp = Self.intent(keys: [20], app: Data(repeating: 0xA2, count: 32))
        let store = MemoryIntentStore([refused, otherApp])

        let removed = PlatformDashConnectDataSource.hideRefused(
            appId: Self.app, intents: store, snapshot: Self.snapshot(), at: Self.at)

        XCTAssertTrue(removed)
        let loaded = store.load()
        XCTAssertEqual(try XCTUnwrap(loaded.first { $0.id == refused.id }).removedAt, Self.at)
        XCTAssertNil(try XCTUnwrap(loaded.first { $0.id == otherApp.id }).removedAt)
    }

    func testRemoveIgnoresAConnectionThatDoesNotShowRefused() throws {
        // Confirming (no refusal, its key not on the identity yet), and a refusal whose key landed after all.
        let confirming = Self.intent(keys: [13])
        let landed = Self.intent(keys: [14], refusal: AppConnect.ConsensusRefusal(code: 10_212, at: Self.at))
        for (name, intents, snapshot) in [
            ("confirming", [confirming], Self.snapshot()),
            ("landed", [landed], Self.snapshot([Self.onPlatform(Self.authKey(14))])),
        ] {
            let store = MemoryIntentStore(intents)
            XCTAssertFalse(
                PlatformDashConnectDataSource.hideRefused(appId: Self.app, intents: store, snapshot: snapshot, at: Self.at), name)
            XCTAssertEqual(store.load(), intents, "\(name): nothing is written")
        }
    }

    // MARK: 6. Supersede (AC-21)

    func testTheEarlierConnectionOfTheSameInstallIsTurnedOffInTheUpdateThatAddsTheNewKeys() async throws {
        let earlier = Self.intent(keys: [10, 11], connectionId: Self.installA)
        let sameAppOtherInstall = Self.intent(keys: [12], connectionId: Self.installB)
        let onIdentity = Self.snapshot([10, 11, 12].map { Self.onPlatform(Self.authKey($0)) })

        let superseded = PlatformDashConnectDataSource.supersededKeys(
            connectionId: Self.installA, appId: Self.app, snapshot: onIdentity,
            intents: [earlier, sameAppOtherInstall])
        XCTAssertEqual(superseded.disable, [10, 11], "the other install's key 12 stays")

        let new = Self.intent(keys: [13, 14], disables: superseded.disable, connectionId: Self.installA)
        let write = PlatformDashConnectDataSource.identityUpdateWrite(for: new, in: onIdentity)
        guard case .updateKeys(let add, let disable) = write else { return XCTFail("expected updateKeys, got \(write.kind)") }
        XCTAssertEqual(add, [13, 14])
        XCTAssertEqual(disable, [10, 11], "one update adds the new keys and turns the earlier ones off")

        // And it is that one update that is sent.
        let sent = Sent()
        _ = try await PlatformDashConnectDataSource.recordAndSubmitIdentityUpdate(
            new, snapshot: onIdentity, intents: MemoryIntentStore(),
            makeExecutor: { Self.executor { sent.record($0) } }, now: { Self.at },
            afterRecording: {}, readAfterFailure: { throw $0 })
        XCTAssertEqual(sent.all.map(\.kind), ["updateKeys"], "no separate update turns the earlier keys off")
        guard case .updateKeys(let sentAdd, let sentDisable)? = sent.all.first else { return XCTFail("nothing sent") }
        XCTAssertEqual(sentAdd, [13, 14])
        XCTAssertEqual(sentDisable, [10, 11])
    }

    func testADifferentInstallOfTheSameAppIsNotSuperseded() {
        let installA = Self.intent(keys: [10], connectionId: Self.installA)
        let onIdentity = Self.snapshot([Self.onPlatform(Self.authKey(10))])

        let superseded = PlatformDashConnectDataSource.supersededKeys(
            connectionId: Self.installB, appId: Self.app, snapshot: onIdentity, intents: [installA])

        XCTAssertEqual(superseded, AppConnect.DisconnectPlan(), "nothing to turn off, nothing to fence")
        let new = Self.intent(keys: [13], disables: superseded.disable, connectionId: Self.installB)
        guard case .updateKeys(_, let disable) = PlatformDashConnectDataSource.identityUpdateWrite(for: new, in: onIdentity) else {
            return XCTFail("expected updateKeys")
        }
        XCTAssertEqual(disable, [])
    }

    func testARequestWithoutAnInstallSupersedesNothing() {
        let installA = Self.intent(keys: [10], connectionId: Self.installA)
        let onIdentity = Self.snapshot([Self.onPlatform(Self.authKey(10))])

        let superseded = PlatformDashConnectDataSource.supersededKeys(
            connectionId: nil, appId: Self.app, snapshot: onIdentity, intents: [installA])

        XCTAssertEqual(superseded, AppConnect.DisconnectPlan())
    }

    func testAPendingEarlierConnectionOfTheSameInstallIsFencedFirst() {
        let pending = Self.intent(keys: [10], connectionId: Self.installA)

        let superseded = PlatformDashConnectDataSource.supersededKeys(
            connectionId: Self.installA, appId: Self.app, snapshot: Self.snapshot(), intents: [pending])

        XCTAssertEqual(superseded.fence, [10], "a pending update is made unable to land (AC-17)")
        XCTAssertEqual(superseded.disable, [])
    }

    func testARefusedEarlierConnectionOfTheSameInstallIsNotFenced() {
        // T22 (R8): its update can never land, so a fence would only cost two identity updates.
        let refused = Self.intent(keys: [10], connectionId: Self.installA, refusal: AppConnect.ConsensusRefusal(code: 10_212, at: Self.at))

        let superseded = PlatformDashConnectDataSource.supersededKeys(
            connectionId: Self.installA, appId: Self.app, snapshot: Self.snapshot(), intents: [refused])

        XCTAssertEqual(superseded.fence, [])
        XCTAssertEqual(superseded.disable, [])
    }
}

// MARK: - T23 (review R5, R12a)

extension PlatformDashConnectDataSourceTests {
    /// R5 / AC-05: a token purchase code opened by a wallet with no username
    /// is refused before any sheet is built.
    func testATokenPurchaseWithoutAResolvedUsernameIsRefused() {
        for resolved in [nil, "", "   "] as [String?] {
            XCTAssertThrowsError(
                try PlatformDashConnectDataSource.requireTokenPurchaseUsername(resolved, lookupFailed: false),
                "\(String(describing: resolved))") {
                XCTAssertEqual($0 as? DashConnectPlatformError, .tokenPurchaseNeedsUsername)
            }
        }
    }

    /// A failed DPNS read with no stored name does not tell the user to
    /// create a name they may already have.
    func testATokenPurchaseWhoseUsernameLookupFailedIsNotToldToCreateOne() {
        XCTAssertThrowsError(try PlatformDashConnectDataSource.requireTokenPurchaseUsername(nil, lookupFailed: true)) {
            XCTAssertEqual($0 as? DashConnectPlatformError, .tokenPurchaseUsernameUncheckable)
        }
    }

    func testATokenPurchaseWithAResolvedUsernameCarriesItToTheSheet() throws {
        XCTAssertEqual(try PlatformDashConnectDataSource.requireTokenPurchaseUsername("dashuser", lookupFailed: false), "dashuser")
        XCTAssertEqual(try PlatformDashConnectDataSource.requireTokenPurchaseUsername("dashuser", lookupFailed: true), "dashuser",
                       "a stored name stands in when the DPNS read fails")
    }

    /// R12a / AC-09: after the PIN, a request dated in the future is not
    /// reported as expired, and the stale case keeps its own text.
    func testAFutureDatedRequestAfterThePinIsNotReportedAsExpired() {
        XCTAssertNoThrow(try PlatformDashConnectDataSource.requireFreshRequest(age: .fresh))
        XCTAssertThrowsError(try PlatformDashConnectDataSource.requireFreshRequest(age: .uncheckable)) {
            XCTAssertEqual($0 as? DashConnectPlatformError, .requestAgeUncheckable)
        }

        var stale: AppConnect.Refusal?
        XCTAssertThrowsError(try PlatformDashConnectDataSource.requireFreshRequest(age: .stale)) { stale = $0 as? AppConnect.Refusal }
        XCTAssertEqual(stale?.status, .stale)
        XCTAssertTrue(stale?.reason.lowercased().contains("expired") == true, "the stale case still says expired")

        var future: AppConnect.Refusal?
        XCTAssertThrowsError(try PlatformDashConnectDataSource.requireFreshRequest(age: .future)) { future = $0 as? AppConnect.Refusal }
        XCTAssertNotNil(future, "a future-dated request is a typed refusal")
        let text = future?.reason.lowercased() ?? ""
        XCTAssertFalse(text.contains("expired"), text)
        XCTAssertFalse(text.contains("clock"), text)
        XCTAssertTrue(text.contains("new"), "it asks the app for a new code: \(text)")
        XCTAssertNotEqual(future?.reason, stale?.reason)
        XCTAssertTrue(text.contains("ahead"), "it gives the reason, the request is dated ahead: \(text)")
        XCTAssertTrue(text.contains("network"), "it names the network's time: \(text)")
    }
}

// MARK: - A keys read behind the wallet copy (T25, AC-15)

extension PlatformDashConnectDataSourceTests {
    private func assertReadBehind(
        copy: [ManagedIdentity.IdentityPublicKeyInfo], proved: [ManagedIdentity.IdentityPublicKeyInfo],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try PlatformDashConnectDataSource.requireKeysNotBehind(copy: copy, proved: proved), file: file, line: line
        ) { error in
            XCTAssertEqual(error as? DashConnectPlatformError, .identityReadBehind, file: file, line: line)
        }
    }

    func testAProvedReadMissingAKeyOfTheCopyIsBehind() {
        assertReadBehind(copy: [Self.keyInfo(0), Self.keyInfo(1)], proved: [Self.keyInfo(0)])
    }

    func testAKeyDisabledInTheCopyButEnabledInTheProvedReadIsBehind() {
        assertReadBehind(
            copy: [Self.keyInfo(0), Self.keyInfo(1, disabledAt: 1_780_000_000_000)],
            proved: [Self.keyInfo(0), Self.keyInfo(1)])
    }

    func testAProvedReadWithANewerKeyIsNotBehind() {
        XCTAssertNoThrow(try PlatformDashConnectDataSource.requireKeysNotBehind(
            copy: [Self.keyInfo(0)], proved: [Self.keyInfo(0), Self.keyInfo(2)]))
    }

    func testIdenticalKeysAreNotBehind() {
        XCTAssertNoThrow(try PlatformDashConnectDataSource.requireKeysNotBehind(
            copy: [Self.keyInfo(0), Self.keyInfo(1)], proved: [Self.keyInfo(0), Self.keyInfo(1)]))
    }

    func testAKeyDisabledInBothIsNotBehind() {
        let disabled = Self.keyInfo(1, disabledAt: 1_780_000_000_000)
        XCTAssertNoThrow(try PlatformDashConnectDataSource.requireKeysNotBehind(
            copy: [Self.keyInfo(0), disabled], proved: [Self.keyInfo(0), disabled]))
    }

    /// Platform raises a key's limits without a new revision: a proved read
    /// with the limits from before the raise is behind the copy.
    func testALowerBudgetOrAnEarlierExpiryThanTheCopyIsBehind() {
        assertReadBehind(
            copy: [Self.keyInfo(1, totalBudget: 2_000, expiresAt: 1_800_000_000_000)],
            proved: [Self.keyInfo(1, totalBudget: 1_000, expiresAt: 1_800_000_000_000)])
        assertReadBehind(
            copy: [Self.keyInfo(1, totalBudget: 1_000, expiresAt: 1_800_000_000_000)],
            proved: [Self.keyInfo(1, totalBudget: 1_000, expiresAt: 1_790_000_000_000)])
    }

    /// The SDK gives an expiry as the bit pattern of an unsigned block time:
    /// one past `Int64.max` is later than any ordinary one, not earlier.
    func testAnExpiryPastInt64MaxIsComparedUnsigned() {
        let farOff = Int64(bitPattern: UInt64(Int64.max) + 10)
        assertReadBehind(
            copy: [Self.keyInfo(1, expiresAt: farOff)], proved: [Self.keyInfo(1, expiresAt: 1_800_000_000_000)])
        XCTAssertNoThrow(try PlatformDashConnectDataSource.requireKeysNotBehind(
            copy: [Self.keyInfo(1, expiresAt: 1_800_000_000_000)], proved: [Self.keyInfo(1, expiresAt: farOff)]))
    }

    func testRaisedLimitsInTheProvedReadAreNotBehind() {
        XCTAssertNoThrow(try PlatformDashConnectDataSource.requireKeysNotBehind(
            copy: [Self.keyInfo(1, totalBudget: 1_000, expiresAt: 1_790_000_000_000)],
            proved: [Self.keyInfo(1, totalBudget: 2_000, expiresAt: 1_800_000_000_000)]))
    }

    func testAKeyEnabledInTheCopyButDisabledInTheProvedReadIsNotBehind() {
        XCTAssertNoThrow(try PlatformDashConnectDataSource.requireKeysNotBehind(
            copy: [Self.keyInfo(1)], proved: [Self.keyInfo(1, disabledAt: 1_780_000_000_000)]))
    }
}

// MARK: T29 (F11): a whole disconnect through the injected seams

/// A whole `disconnect(id:scope:)` of the data source, with no live SDK: the
/// platform is `DashConnectPlatformPort` (the seam T29 adds, which the data
/// source takes as `platform:` and which stands for the wallet, the SDK and the
/// PIN prompt), and every write goes through the injected `makeWriteExecutor`.
/// The executor here never calls the `submit` it is given, so a write that
/// still builds its own executor would reach the live SDK and fail.
final class DashConnectDisconnectThroughSeamsTests: XCTestCase {
    private static let at = Date(timeIntervalSince1970: 1_773_132_300)
    private static let identity = Data(repeating: 0x01, count: 32)
    private static let app = Data(repeating: 0xA1, count: 32)
    private static let documentId = Data(repeating: 0xDD, count: 32)
    private static let walletIdHex = "wallet"
    /// `"\(walletIdHex) \(scopeKey ?? "") \(endpoint ?? "")"` of the pinned stores.
    private static let scope = "wallet  "

    private static let key = AppConnect.IntendedKey(
        id: 13, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
        data: Data(repeating: 13, count: 20), readOnly: false,
        bound: .singleContract(app), totalBudget: 1000, expiresAt: nil)

    private static func onPlatform(disabledAt: UInt64? = nil) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType, data: key.data,
            readOnly: key.readOnly, bound: key.bound, boundKnown: true, totalBudget: key.totalBudget,
            expiresAt: key.expiresAt, disabledAt: disabledAt)
    }

    /// A live key of the wallet's auth shape that no intent names and whose
    /// bound the key store does not hold yet: it is `unplaced` in the plan.
    private static func unknownBoundKey() -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: 14, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: 14, count: 20), readOnly: false, bound: nil, boundKnown: false,
            totalBudget: nil, expiresAt: 1_900_000_000_000, disabledAt: nil)
    }

    /// T44 (J3): a live key of another app or device under `id`, bound to no app.
    private static func foreignKey(_ id: UInt32) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: 0x77, count: 20), readOnly: false, bound: nil, boundKnown: true,
            totalBudget: nil, expiresAt: nil, disabledAt: nil)
    }

    /// The fence key the fake platform derives for `keyId`: not the payload
    /// of the intent's key under that id.
    private static func fenceHash(_ keyId: UInt32) -> Data { Data(repeating: 0xF0 ^ UInt8(truncatingIfNeeded: keyId), count: 20) }

    /// T56 (N1), T59 (P1): another app, whose intent's key id holds the
    /// wallet's turned-off fence.
    private static let otherApp = Data(repeating: 0xB2, count: 32)
    private static let otherAppKey = AppConnect.IntendedKey(
        id: 20, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
        data: Data(repeating: 20, count: 20), readOnly: false,
        bound: .singleContract(otherApp), totalBudget: 1000, expiresAt: nil)

    /// T59 (P1): the key of this app's earlier intent, closed when a later
    /// approval fenced it.
    private static let closedIntentKey = AppConnect.IntendedKey(
        id: 21, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
        data: Data(repeating: 21, count: 20), readOnly: false,
        bound: .singleContract(app), totalBudget: 1000, expiresAt: nil)

    /// The wallet's turned-off fence under `key`'s id.
    private static func turnedOffFence(under key: AppConnect.IntendedKey) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: key.id, purpose: key.purpose, securityLevel: key.securityLevel,
            keyType: key.keyType, data: fenceHash(key.id), readOnly: false, bound: nil,
            boundKnown: true, totalBudget: nil, expiresAt: nil, disabledAt: 1_700_000_000_000)
    }

    /// The wallet's fence under the intent's key id: turned off, or live.
    private static func fence(live: Bool = false) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType, data: fenceHash(key.id),
            readOnly: false, bound: nil, boundKnown: true, totalBudget: nil, expiresAt: nil,
            disabledAt: live ? nil : 1_800_000_000_000)
    }

    /// The identity as read. `disabled`: the disconnect's update landed.
    /// `confirming`: the intent's key never landed, so a landed update shows
    /// the fence that holds its id. `offElsewhere`: the key was turned off
    /// without this wallet's disconnect. `liveFence`: with `confirming`, the
    /// fence under its id is on. `otherAppFenceOff`: the identity holds the
    /// wallet's turned-off fence under the other app's key id.
    /// `closedIntentFenceOff`: the identity holds the wallet's turned-off
    /// fence under the key id of this app's closed intent.
    private static func snapshot(
        disabled: Bool, withUnknownBoundKey: Bool = false, confirming: Bool = false, offElsewhere: Bool = false,
        liveFence: Bool = false, foreignKeyId: UInt32? = nil, otherAppFenceOff: Bool = false,
        closedIntentFenceOff: Bool = false
    ) -> AppConnect.IdentitySnapshot {
        let appKeys: [AppConnect.PlatformKey]
        if confirming {
            appKeys = disabled || liveFence ? [fence(live: liveFence)] : []
        } else {
            appKeys = [onPlatform(disabledAt: disabled || offElsewhere ? 1_800_000_000_000 : nil)]
        }
        return AppConnect.IdentitySnapshot(
            identityId: identity, revision: disabled ? 6 : 5,
            keys: appKeys + (withUnknownBoundKey ? [unknownBoundKey()] : [])
                + (foreignKeyId.map { [foreignKey($0)] } ?? [])
                + (otherAppFenceOff ? [turnedOffFence(under: otherAppKey)] : [])
                + (closedIntentFenceOff ? [turnedOffFence(under: closedIntentKey)] : []),
            platformTime: 1_800_000_000_000)
    }

    private static func intent(
        app: Data = app, key: AppConnect.IntendedKey = key, closedAt: Date? = nil
    ) -> AppConnect.ConnectionIntent {
        AppConnect.ConnectionIntent(
            id: UUID(), identityId: identity, appId: app, appLabel: "App", appUrl: "",
            requestHash: Data(repeating: 0xEE, count: 20), connectionId: Data(repeating: 0xC1, count: 32),
            keys: [key], sentEncryptionKeyIds: [], disables: [],
            response: AppConnect.ResponseValues(appEphemeralPubKeyHash: "ee", walletEphemeralPubKey: "02", encryptedPayload: "00"),
            responseDocumentId: documentId, responseRemoved: false,
            createdAt: Date(timeIntervalSince1970: 0), closedAt: closedAt)
    }

    private final class MemoryIntents: AppConnectIntentStore, @unchecked Sendable {
        private var intents: [AppConnect.ConnectionIntent]
        let canPersist = true
        init(_ intents: [AppConnect.ConnectionIntent]) { self.intents = intents }
        func load() -> [AppConnect.ConnectionIntent] { intents }
        func save(_ intents: [AppConnect.ConnectionIntent]) { self.intents = intents }
        func pinned(toWalletIdHex walletIdHex: String) -> any AppConnectIntentStore { self }
    }

    private final class MemoryRows: DashConnectStore {
        private var rows: [DAppConnection]
        init(_ rows: [DAppConnection]) { self.rows = rows }
        func load() -> [DAppConnection] { rows }
        func save(_ connections: [DAppConnection]) { rows = connections }
        var scopeKey: String? { nil }
        func pinned(toWalletIdHex walletIdHex: String) -> any DashConnectStore { self }
    }

    /// What the executor saw, and whether the identity update, the update
    /// that turns the fences off and the response delete landed: the reads
    /// after them show them. A write whose kind is in `failing` is seen, does
    /// not land and throws a network error (an unknown outcome: `landLate()`
    /// lands the update afterwards); one in `refusing` is seen, does not land
    /// and throws a consensus rejection (a permanent refusal).
    private final class Chain: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String] = []
        private var landed = false
        private var fencesOff = false
        private var responseDeleted = false
        private let failing: Set<String>
        private let refusing: Set<String>
        init(failing: Set<String> = [], refusing: Set<String> = []) {
            self.failing = failing
            self.refusing = refusing
        }
        func record(_ write: PlatformWrite) throws {
            let refused = lock.withLock { () -> Bool in
                seen.append(write.kind)
                return refusing.contains(write.kind)
            }
            if refused {
                throw SDKError.consensusRejection(PlatformConsensusError(code: 10_212, kind: .basic), "rendered text")
            }
            let fails = lock.withLock { () -> Bool in
                guard !failing.contains(write.kind) else { return true }
                if case .updateKeys = write { landed = true }
                if case .fence = write { fencesOff = true }
                if case .deleteResponse = write { responseDeleted = true }
                return false
            }
            if fails { throw SDKError.networkError("connection lost") }
        }
        /// The identity update that failed with an unknown outcome lands now.
        func landLate() { lock.withLock { landed = true } }
        var kinds: [String] { lock.withLock { seen } }
        var updateLanded: Bool { lock.withLock { landed } }
        var fenceUpdateLanded: Bool { lock.withLock { fencesOff } }
        var responseDeleteLanded: Bool { lock.withLock { responseDeleted } }
    }

    private final class FakePlatform: DashConnectPlatformPort, @unchecked Sendable {
        let chain: Chain
        let response: (documentId: Data, values: AppConnect.ResponseValues)
        /// How many reads after the update landed throw `identityReadBehind`
        /// (`nil`: every one), as a proved read that lags the wallet's copy does.
        let behindReads: Int?
        private let lock = NSLock()
        private var unknownBound: Bool
        private var keyOffElsewhere = false
        private var behindNow = false
        private var reads = 0
        private var authorizations = 0
        private var behindSoFar = 0
        /// The intent's key never landed (see `snapshot(confirming:)`).
        var confirming = false
        /// With `confirming`: an earlier try left the fence on, so the plan's
        /// read shows it live and the identity update turns it off.
        var leftoverFence = false
        /// T44 (J3): the identity holds a key of another device under this id.
        var foreignKeyId: UInt32?
        /// T50 (L1): with `confirming`, an earlier try placed the fence and it
        /// was turned off later, so the plan's read shows it turned off.
        var earlierFenceOff = false
        /// T53 (M1): the wallet cannot derive a fence key.
        var fenceHashFails = false
        /// T56 (N1): the identity holds the wallet's turned-off fence under
        /// the other app's key id.
        var otherAppFenceOff = false
        /// T59 (P1): the identity holds the wallet's turned-off fence under
        /// the key id of this app's closed intent.
        var closedIntentFenceOff = false
        /// Whether the next reads show a key of unknown bound.
        var withUnknownBoundKey: Bool {
            get { lock.withLock { unknownBound } }
            set { lock.withLock { unknownBound = newValue } }
        }
        /// Whether the next reads after the update landed throw
        /// `identityReadBehind`, whatever `behindReads` says.
        var readsBehind: Bool {
            get { lock.withLock { behindNow } }
            set { lock.withLock { behindNow = newValue } }
        }
        /// Whether the next reads show the app's key turned off by another device.
        var offElsewhere: Bool {
            get { lock.withLock { keyOffElsewhere } }
            set { lock.withLock { keyOffElsewhere = newValue } }
        }
        var readCount: Int { lock.withLock { reads } }
        /// How many times the PIN was asked for.
        var authorizeCount: Int { lock.withLock { authorizations } }
        init(chain: Chain, response: (documentId: Data, values: AppConnect.ResponseValues), behindReads: Int? = 0, withUnknownBoundKey: Bool = false) {
            self.unknownBound = withUnknownBoundKey
            self.chain = chain
            self.response = response
            self.behindReads = behindReads
        }
        var identityId: Data { DashConnectDisconnectThroughSeamsTests.identity }
        var owners: PlatformDashConnectDataSource.OwnerReader { unreadOwners }

        func authorize() async throws { lock.withLock { authorizations += 1 } }
        func readIdentity() async throws -> AppConnect.IdentitySnapshot {
            lock.withLock { reads += 1 }
            if chain.updateLanded {
                let behind = lock.withLock { () -> Bool in
                    if behindNow { return true }
                    if let behindReads, behindSoFar >= behindReads { return false }
                    behindSoFar += 1
                    return true
                }
                if behind { throw DashConnectPlatformError.identityReadBehind }
            }
            // A fence the identity update added stays on until the update
            // that turns the fences off lands.
            let liveFence = chain.updateLanded ? !(leftoverFence || chain.fenceUpdateLanded) : leftoverFence
            return DashConnectDisconnectThroughSeamsTests.snapshot(
                disabled: chain.updateLanded || earlierFenceOff, withUnknownBoundKey: withUnknownBoundKey,
                confirming: confirming,
                offElsewhere: offElsewhere, liveFence: liveFence, foreignKeyId: foreignKeyId,
                otherAppFenceOff: otherAppFenceOff, closedIntentFenceOff: closedIntentFenceOff)
        }
        func fenceKeyHash(keyId: UInt32) async throws -> Data {
            if fenceHashFails { throw FenceDerivationFailed() }
            return DashConnectDisconnectThroughSeamsTests.fenceHash(keyId)
        }
        func findResponse(requestHash: Data) async throws -> (documentId: Data, values: AppConnect.ResponseValues)? {
            chain.responseDeleteLanded ? nil : response
        }
    }

    /// The wallet could not derive a fence key.
    private struct FenceDerivationFailed: Error {}

    private func makeDataSource(
        chain: Chain, intents: MemoryIntents, rows: MemoryRows, behindReads: Int? = 0, withUnknownBoundKey: Bool = false,
        platform: FakePlatform? = nil
    ) -> PlatformDashConnectDataSource {
        let intent = intents.load()[0]
        return PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: rows,
            intentStore: intents,
            activeWalletIdHex: { Self.walletIdHex },
            now: { Self.at },
            makeWriteExecutor: { _ in
                AppConnectWriteExecutor(
                    timeout: .milliseconds(100), sleep: { try await Task.sleep(for: $0) }, log: { _ in },
                    submit: { write in try chain.record(write) })
            },
            platform: platform ?? FakePlatform(chain: chain, response: (Self.documentId, intent.response), behindReads: behindReads,
                withUnknownBoundKey: withUnknownBoundKey),
            pauseForLaggingNode: { _ in })
    }

    private func connectedApp(status: ConnectionStatus = .active) -> (MemoryIntents, MemoryRows, AppConnect.ConnectionIntent) {
        let intent = Self.intent()
        let row = DAppConnection(
            id: Self.app.toBase58String(), name: "App", url: "", status: status,
            updatedAt: Date(timeIntervalSince1970: 0))
        return (MemoryIntents([intent]), MemoryRows([row]), intent)
    }

    /// AC-17, AC-18: the app's keys are turned off, its intents closed, its
    /// response deleted and its row shown as Disconnected.
    func testAWholeDisconnectClosesTheIntentsDeletesTheResponseAndShowsTheRowDisconnected() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows)

        let result = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(result.keysTurnedOff, 1)
        XCTAssertEqual(result.keysStillLive, 0)
        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the intent is closed")
        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.responseRemoved, true, "the response is marked removed")
        XCTAssertEqual(rows.load().first?.status, .disconnected, "the row is refreshed to Disconnected")
    }

    /// T45 (J4, AC-16): a response delete that fails did not land, so the
    /// lookup after it still finds the response and it is not marked removed.
    func testAResponseDeleteThatFailsLeavesTheResponseNotMarkedRemoved() async throws {
        let chain = Chain(failing: ["deleteResponse"])
        let (intents, rows, intent) = connectedApp()
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows)

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(chain.kinds, ["updateKeys", "deleteResponse"])
        XCTAssertEqual(
            intents.load().first { $0.id == intent.id }?.responseRemoved, false, "the response is still on Platform")
    }

    /// A response an earlier disconnect could not delete has no row left to
    /// reach it: the next disconnect on the identity deletes it too.
    func testADisconnectAlsoDeletesTheResponseAnEarlierDisconnectLeft() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        let left = Self.intent(app: Self.otherApp, key: Self.otherAppKey, closedAt: Self.at)
        intents.save(intents.load() + [left])
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows)

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.responseRemoved, true)
        XCTAssertEqual(intents.load().first { $0.id == left.id }?.responseRemoved, true, "the response left before is gone too")
    }

    /// F11: the identity update and the response delete are written by the
    /// executor the factory built, never by one the data source builds itself.
    func testADisconnectSendsItsIdentityUpdateAndItsResponseDeleteThroughTheInjectedExecutor() async throws {
        let chain = Chain()
        let (intents, rows, _) = connectedApp()
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows)

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(chain.kinds, ["updateKeys", "deleteResponse"])
    }

    /// T31 (F4, AC-16, AC-19): the read after writes that landed is behind
    /// once; it is read again, and the disconnect finishes.
    func testADisconnectWhoseReadAfterItsWritesIsBehindOnceReadsAgainAndFinishes() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, behindReads: 1)

        let result = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(result.keysTurnedOff, 1)
        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the intent is closed")
        XCTAssertEqual(chain.kinds, ["updateKeys", "deleteResponse"], "the response is deleted")
        XCTAssertEqual(rows.load().first?.status, .disconnected)
    }

    /// T31 (F4): the read after the writes is behind every time; the update
    /// landed (the executor said so), so the disconnect does not throw, the
    /// intents are closed, the response deleted and the row kept Disconnected.
    func testADisconnectWhoseReadAfterItsWritesIsAlwaysBehindStillClosesTheIntentsAndDeletesTheResponse() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, behindReads: nil)

        do {
            _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)
        } catch {
            XCTFail("the disconnect threw after its writes landed: \(error)")
        }

        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the intent is closed")
        XCTAssertEqual(chain.kinds, ["updateKeys", "deleteResponse"], "the response is deleted")
        XCTAssertEqual(rows.load().first?.status, .disconnected, "the row is not lost")
    }

    /// T32 (F2, AC-18): a key on the identity whose bound is unknown stays
    /// live, so the app's newest intent is not closed and its row keeps its
    /// status and Disconnect; no row is re-added as Active.
    func testADisconnectWithAKeyOfUnknownBoundDoesNotCloseTheIntentAndKeepsTheRowActive() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, withUnknownBoundKey: true)

        let result = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(result.keysNotChecked, 1)
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt, "the intent stays open while a key's bound is unknown")
        XCTAssertEqual(rows.load().first?.status, .active, "the row keeps its earlier status")
        XCTAssertEqual(rows.load().count, 1)
    }

    /// T32 (AC-18): while the read shows a key of unknown bound, a refresh
    /// keeps the row (status and Disconnect) of an open Disconnected intent;
    /// once none is left, a refresh closes that intent and the row turns
    /// Disconnected.
    func testARefreshKeepsTheRowWhileAKeyOfUnknownBoundRemainsAndClosesTheIntentOnceNoneIsLeft() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response), withUnknownBoundKey: true)
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt)
        XCTAssertEqual(rows.load().first?.status, .active)

        let readsBefore = platform.readCount
        await dataSource.refreshConnections()

        XCTAssertGreaterThan(platform.readCount, readsBefore, "the refresh reads through the injected platform port")
        XCTAssertEqual(rows.load().count, 1, "the row stays while a key's bound is unknown")
        XCTAssertEqual(rows.load().first?.status, .active, "the row keeps its status")
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt, "the intent stays open")

        platform.withUnknownBoundKey = false
        await dataSource.refreshConnections()

        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the refresh closes the intent")
        XCTAssertEqual(rows.load().first?.status, .disconnected, "the row turns Disconnected")
    }

    /// T35 (G1, AC-18): a Confirming connection disconnected while a key of
    /// unknown bound is on the identity keeps its row, with its status and
    /// Disconnect, although the fence now holds its key id.
    func testADisconnectOfAConfirmingConnectionWithAKeyOfUnknownBoundKeepsTheRow() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp(status: .confirming)
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response), withUnknownBoundKey: true)
        platform.confirming = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        let result = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(result.keysNotChecked, 1)
        XCTAssertTrue(chain.kinds.contains("updateKeys"), "the fence was placed")
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt, "the intent stays open while a key's bound is unknown")
        XCTAssertNotNil(intents.load().first { $0.id == intent.id }?.disconnectedAt, "the disconnect marks the intent it ran on")
        XCTAssertEqual(rows.load().count, 1, "the row is not lost")
        XCTAssertEqual(rows.load().first?.status, .confirming, "the row keeps its earlier status")
    }

    /// T35 (G1, AC-18): after such a disconnect a refresh keeps the
    /// Confirming row while the key of unknown bound remains, then closes the
    /// intent and the row turns Disconnected.
    func testARefreshKeepsAFencedConfirmingRowWhileAKeyOfUnknownBoundRemainsThenShowsItDisconnected() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp(status: .confirming)
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response), withUnknownBoundKey: true)
        platform.confirming = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)
        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        await dataSource.refreshConnections()

        XCTAssertEqual(rows.load().count, 1, "the row stays while a key's bound is unknown")
        XCTAssertEqual(rows.load().first?.status, .confirming)
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt)

        platform.withUnknownBoundKey = false
        await dataSource.refreshConnections()

        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the refresh closes the intent")
        XCTAssertEqual(rows.load().first?.status, .disconnected, "the row turns Disconnected")
    }

    /// T35 (G5, AC-19): keys turned off from another device are no disconnect
    /// of this wallet: a refresh leaves the intent open and the app no row.
    func testKeysTurnedOffElsewhereLeaveNoRowAndTheIntentOpen() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        platform.offElsewhere = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        await dataSource.refreshConnections()

        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt, "no disconnect of this wallet closed it")
        XCTAssertTrue(rows.load().isEmpty, "no Disconnected entry for a disconnect made elsewhere")
    }

    /// T35 (G5, AC-14): a key of unknown bound does not keep the row of an
    /// app whose keys were turned off elsewhere Active: no key of it is live.
    /// It keeps the row Confirming, with Disconnect, as the key may be the app's.
    func testAKeyOfUnknownBoundDoesNotKeepTheRowOfAnAppTurnedOffElsewhere() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response), withUnknownBoundKey: true)
        platform.offElsewhere = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        await dataSource.refreshConnections()

        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt)
        XCTAssertNil(rows.load().first { $0.status == .active }, "no Active row with no live key")
        XCTAssertEqual(rows.load().map(\.status), [.confirming], "the row stays while a key's bound is unknown")
    }

    /// T43 (J1, H1, AC-19): a disconnect whose identity update was refused
    /// for good did not land: it leaves the app's live intent unmarked, so
    /// keys later turned off from another device leave no Disconnected entry.
    func testADisconnectWhoseUpdateIsRefusedLeavesItsLiveIntentUnmarkedSoKeysTurnedOffElsewhereLeaveNoRow() async throws {
        let chain = Chain(refusing: ["updateKeys"])
        let (intents, rows, intent) = connectedApp()
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        let result = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(result.keysStillLive, 1, "the update did not land")
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt)
        XCTAssertNil(
            intents.load().first { $0.id == intent.id }?.disconnectedAt, "a refused update leaves the live intent unmarked")

        platform.offElsewhere = true
        await dataSource.refreshConnections()

        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt, "no disconnect of this wallet closed it")
        XCTAssertTrue(rows.load().isEmpty, "no Disconnected entry for keys turned off elsewhere")
    }

    /// T43 (J1, AC-16, AC-19): a disconnect whose identity update has an
    /// unknown outcome (a network error) while the read after still shows the
    /// key live leaves the intent open and marked; once the update lands, a
    /// refresh closes it and the app shows a Disconnected entry.
    func testADisconnectWhoseUpdateHasAnUnknownOutcomeMarksTheIntentSoALateLandingShowsDisconnected() async throws {
        let chain = Chain(failing: ["updateKeys"])
        let (intents, rows, intent) = connectedApp()
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        let result = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(result.keysStillLive, 1, "the read after still shows the key live")
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt, "the intent stays open")
        XCTAssertNotNil(
            intents.load().first { $0.id == intent.id }?.disconnectedAt, "an update of unknown outcome marks the intent it carried")

        chain.landLate()
        await dataSource.refreshConnections()

        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the refresh closes the intent")
        XCTAssertEqual(rows.load().first?.status, .disconnected, "the app shows a Disconnected entry")
    }

    /// T48 (K4, AC-16, AC-19): a Confirming connection's disconnect whose
    /// update (it adds the fence) has an unknown outcome: the fence id marks
    /// the intent, so once the update lands a refresh shows Disconnected.
    func testAConfirmingDisconnectWhoseFenceUpdateHasAnUnknownOutcomeMarksTheIntentSoALateLandingShowsDisconnected()
        async throws {
        let chain = Chain(failing: ["updateKeys"])
        let (intents, rows, intent) = connectedApp(status: .confirming)
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        platform.confirming = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt, "the read after shows no fence yet")
        XCTAssertNotNil(
            intents.load().first { $0.id == intent.id }?.disconnectedAt,
            "the update of unknown outcome carried its fence")

        chain.landLate()
        await dataSource.refreshConnections()

        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the refresh closes the intent")
        XCTAssertEqual(rows.load().first?.status, .disconnected, "the app shows a Disconnected entry")
    }

    /// T43 (J2, AC-14, AC-18): a refused update with a key of unknown bound
    /// on the identity leaves the app's newest intent live and unmarked.
    func testARefusedUpdateWithAKeyOfUnknownBoundLeavesTheNewestLiveIntentUnmarked() async throws {
        let chain = Chain(refusing: ["updateKeys"])
        let (intents, rows, intent) = connectedApp()
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response), withUnknownBoundKey: true)
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt)
        XCTAssertNil(
            intents.load().first { $0.id == intent.id }?.disconnectedAt, "a refused update leaves the newest live intent unmarked")
    }

    /// T44 (J3, AC-13, AC-19): A «Yappr iOS» is Active, the newer C «Yappr
    /// web» never landed (another key took its id). A disconnect closes C
    /// without the mark, and the Disconnected entry is A's, not C's.
    func testADisconnectClosesAnIntentThatNeverLandedWithoutTheMarkSoTheEntryNamesTheOneThatLanded() async throws {
        let run = try await disconnectAppWithAnIntentThatNeverLanded()
        let (landed, neverLanded, intents, rows) = (run.landed, run.neverLanded, run.intents, run.rows)

        let storedLanded = intents.load().first { $0.id == landed }
        let storedNever = intents.load().first { $0.id == neverLanded }
        XCTAssertEqual(storedLanded?.closedAt, Self.at)
        XCTAssertNotNil(storedLanded?.disconnectedAt, "the intent that landed is marked")
        XCTAssertEqual(storedNever?.closedAt, Self.at, "the intent that never landed is closed")
        XCTAssertNil(storedNever?.disconnectedAt, "and not marked: it never landed")
        XCTAssertEqual(rows.load().first?.status, .disconnected)
        XCTAssertEqual(rows.load().first?.name, "Yappr iOS")
        XCTAssertEqual(rows.load().first?.url, "https://ios.yappr.example")
    }

    /// T48 (K3, AC-18): the same disconnect with a key of unknown bound on the
    /// identity. The intent left open as the app's newest is A, which landed,
    /// never the newer C, which never did: A stays open and marked, so the
    /// row keeps its status, and C is closed unmarked.
    func testWithAKeyOfUnknownBoundTheNewestIntentLeftOpenIsTheOneThatLanded() async throws {
        let run = try await disconnectAppWithAnIntentThatNeverLanded(withUnknownBoundKey: true)
        let (landed, neverLanded, intents, rows) = (run.landed, run.neverLanded, run.intents, run.rows)

        let storedLanded = intents.load().first { $0.id == landed }
        let storedNever = intents.load().first { $0.id == neverLanded }
        XCTAssertNil(storedLanded?.closedAt, "A stays open while a key's bound is unknown")
        XCTAssertNotNil(storedLanded?.disconnectedAt, "and is marked")
        XCTAssertEqual(storedNever?.closedAt, Self.at, "C is closed")
        XCTAssertNil(storedNever?.disconnectedAt, "and not marked")
        XCTAssertEqual(rows.load().first?.name, "Yappr iOS")
    }

    private struct NeverLandedRun {
        let landed: UUID
        let neverLanded: UUID
        let intents: MemoryIntents
        let rows: MemoryRows
    }

    /// A «Yappr iOS» is Active, the newer C «Yappr web» never landed (another
    /// key took its id); the app is disconnected.
    private func disconnectAppWithAnIntentThatNeverLanded(withUnknownBoundKey: Bool = false) async throws
        -> NeverLandedRun {
        let chain = Chain()
        let template = Self.intent()
        let landed = AppConnect.ConnectionIntent(
            id: UUID(), identityId: Self.identity, appId: Self.app, appLabel: "Yappr iOS", appUrl: "https://ios.yappr.example",
            requestHash: template.requestHash, connectionId: template.connectionId, keys: [Self.key],
            sentEncryptionKeyIds: [], disables: [], response: template.response, responseDocumentId: Self.documentId,
            responseRemoved: false, createdAt: Date(timeIntervalSince1970: 0), closedAt: nil)
        let neverLanded = AppConnect.ConnectionIntent(
            id: UUID(), identityId: Self.identity, appId: Self.app, appLabel: "Yappr web", appUrl: "https://web.yappr.example",
            requestHash: Data(repeating: 0xEF, count: 20), connectionId: nil,
            keys: [AppConnect.IntendedKey(
                id: 15, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
                data: Data(repeating: 15, count: 20), readOnly: false,
                bound: .singleContract(Self.app), totalBudget: 1000, expiresAt: nil)],
            sentEncryptionKeyIds: [], disables: [], response: template.response, responseDocumentId: nil,
            responseRemoved: true, createdAt: Date(timeIntervalSince1970: 100), closedAt: nil)
        let intents = MemoryIntents([landed, neverLanded])
        let rows = MemoryRows([DAppConnection(
            id: Self.app.toBase58String(), name: "Yappr iOS", url: "https://ios.yappr.example", status: .active,
            updatedAt: Date(timeIntervalSince1970: 0))])
        let platform = FakePlatform(
            chain: chain, response: (Self.documentId, landed.response), withUnknownBoundKey: withUnknownBoundKey)
        platform.foreignKeyId = 15
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)
        return NeverLandedRun(landed: landed.id, neverLanded: neverLanded.id, intents: intents, rows: rows)
    }

    /// T42 (H4, G3, AC-17): the update that turns the fence off fails, and
    /// the read after the writes shows the wallet's fence live under the
    /// intent's id: it is a fence left on, not an app key still live.
    func testAFenceTheReadAfterTheWritesShowsLiveIsAFenceLeftOnNotAnAppKey() async throws {
        let chain = Chain(failing: ["fence"])
        let (intents, rows, intent) = connectedApp(status: .confirming)
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        platform.confirming = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        let result = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(chain.kinds, ["updateKeys", "fence", "deleteResponse"])
        XCTAssertEqual(result.fencesLeftOn, 1, "the wallet's own fence is still on")
        XCTAssertEqual(result.keysStillLive, 0, "no key of the app is live")
        XCTAssertEqual(result.fencesNotPlaced, 0)
    }

    /// T42 (H4, G4, AC-18): with no read after the writes, a run that turned
    /// a leftover fence off is finished, so the app's open intent on another
    /// identity of the wallet is reported.
    func testWithNoReadAfterTheWritesAFinishedRunReportsTheAppsGrantOnAnotherIdentity() async throws {
        let chain = Chain()
        let intent = Self.intent()
        let elsewhere = AppConnect.ConnectionIntent(
            id: UUID(), identityId: Data(repeating: 0x02, count: 32), appId: Self.app, appLabel: "App", appUrl: "",
            requestHash: Data(repeating: 0xEF, count: 20), connectionId: nil, keys: [Self.key],
            sentEncryptionKeyIds: [], disables: [], response: intent.response, responseDocumentId: nil,
            responseRemoved: true, createdAt: Date(timeIntervalSince1970: 0), closedAt: nil)
        let intents = MemoryIntents([intent, elsewhere])
        let rows = MemoryRows([DAppConnection(
            id: Self.app.toBase58String(), name: "App", url: "", status: .confirming,
            updatedAt: Date(timeIntervalSince1970: 0))])
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response), behindReads: nil)
        platform.confirming = true
        platform.leftoverFence = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        do {
            _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)
            XCTFail("the grant on another identity is reported")
        } catch DashConnectPlatformError.grantOnAnotherIdentity {
        }
        XCTAssertEqual(chain.kinds.first, "updateKeys", "the leftover fence was turned off")
        XCTAssertFalse(chain.kinds.contains("fence"), "no fence was added, so none is turned off")
        XCTAssertNotNil(
            intents.load().first { $0.id == intent.id }?.disconnectedAt,
            "T47 (K2): the wallet's own fence is no conflict, so the disconnect marks the intent")
    }

    /// T47 (K2, AC-18, AC-19): an earlier disconnect left its fence on under
    /// a Confirming intent's id without marking it. Disconnect again: the
    /// wallet's own fence does not make the intent Never landed, so it is
    /// closed and marked and the row reads Disconnected.
    func testARetriedDisconnectOfAConfirmingIntentWhoseFenceAnEarlierRunLeftOnEndsDisconnected() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp(status: .confirming)
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        platform.confirming = true
        platform.leftoverFence = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at)
        XCTAssertNotNil(intents.load().first { $0.id == intent.id }?.disconnectedAt, "closed and marked")
        XCTAssertEqual(rows.load().first?.status, .disconnected)
    }

    /// T50 (L1, AC-18, AC-19): the fence went out and the update that turns
    /// it off failed, and no read after the writes worked. The intent stays
    /// open and marked; once a read shows the wallet's fence under its id a
    /// refresh closes it and the row reads Disconnected.
    func testAFenceLeftOnWithNoReadAfterMarksTheConfirmingIntentSoARefreshShowsDisconnected() async throws {
        let chain = Chain(failing: ["fence"])
        let (intents, rows, intent) = connectedApp(status: .confirming)
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        platform.confirming = true
        // Every read after the writes is behind; the refresh's is not.
        platform.readsBehind = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        do {
            _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)
            XCTFail("no read shows the run's outcome yet")
        } catch DashConnectPlatformError.identityKeysOutOfDate {
            // «Try again later» (AC-18).
        } catch {
            XCTFail("\(error)")
        }

        XCTAssertEqual(chain.kinds.prefix(2), ["updateKeys", "fence"])
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt, "no read shows the fence yet")
        XCTAssertNotNil(
            intents.load().first { $0.id == intent.id }?.disconnectedAt, "the fence left on was placed under its id")
        XCTAssertEqual(rows.load().first?.status, .confirming, "the row keeps its status and Disconnect until a read")

        platform.readsBehind = false
        await dataSource.refreshConnections()

        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the refresh closes the intent")
        XCTAssertEqual(rows.load().first?.status, .disconnected, "the app shows a Disconnected entry")
    }

    /// T50 (L1, AC-18, AC-19): an earlier run placed the fence and left the
    /// intent unmarked, and the fence was turned off later. Disconnect again:
    /// the wallet's turned-off fence is its own, not another key, so the
    /// intent is closed and marked and the row reads Disconnected.
    func testARetriedDisconnectOfAConfirmingIntentWhoseFenceWasTurnedOffLaterEndsDisconnected() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp(status: .confirming)
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        platform.confirming = true
        platform.earlierFenceOff = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at)
        XCTAssertNotNil(intents.load().first { $0.id == intent.id }?.disconnectedAt, "closed and marked")
        XCTAssertEqual(rows.load().first?.status, .disconnected)
    }

    /// T53 (M1, AC-18, AC-19): an earlier try placed the fence under a
    /// Confirming intent's id and it was turned off later, and the wallet
    /// cannot derive the fence key now. The disconnect cannot tell its own
    /// fence from another key, so it stops before the PIN and any write: the
    /// intent and its row stay as they were, and Disconnect can run again.
    func testADisconnectThatCannotDeriveTheOwnFenceStopsBeforeAnyWriteAndKeepsTheConfirmingRow() async {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp(status: .confirming)
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        platform.confirming = true
        platform.earlierFenceOff = true
        platform.fenceHashFails = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        do {
            _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)
            XCTFail("the disconnect cannot tell the wallet's fence from another key")
        } catch {
            XCTAssertTrue(error is FenceDerivationFailed, "\(error)")
        }

        XCTAssertEqual(platform.authorizeCount, 0, "no PIN is asked for")
        XCTAssertEqual(chain.kinds, [], "nothing is written")
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.closedAt, "the intent stays open")
        XCTAssertNil(intents.load().first { $0.id == intent.id }?.disconnectedAt, "and unmarked")
        XCTAssertEqual(rows.load().first?.status, .confirming, "the row keeps its status and Disconnect")
    }

    /// T56 (N1, AC-16): the wallet cannot derive a fence key, and the
    /// identity holds its turned-off fence under another app's closed
    /// intent. Disconnecting an Active app has no fence to tell apart, so it
    /// goes through.
    func testADisconnectOfAnActiveAppGoesThroughWhenOnlyAnotherAppsTurnedOffFenceCannotBeDerived() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        intents.save(intents.load() + [Self.intent(app: Self.otherApp, key: Self.otherAppKey, closedAt: Self.at)])
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        platform.otherAppFenceOff = true
        platform.fenceHashFails = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        let result = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(result.keysTurnedOff, 1)
        XCTAssertEqual(platform.authorizeCount, 1, "the PIN is asked for once")
        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the intent is closed")
        XCTAssertEqual(rows.load().first?.status, .disconnected)
    }

    /// T59 (P1, AC-16): the wallet cannot derive a fence key, and the
    /// identity holds its turned-off fences under this app's closed intent
    /// and under another app's open intent that reads Never landed. Neither
    /// is an open intent of this app that a fence tells apart, so
    /// disconnecting the Active app goes through.
    func testADisconnectGoesThroughWithUnderivableFencesUnderThisAppsClosedAndAnotherAppsOpenIntent() async throws {
        let chain = Chain()
        let (intents, rows, intent) = connectedApp()
        intents.save(intents.load() + [
            Self.intent(key: Self.closedIntentKey, closedAt: Date(timeIntervalSince1970: 1)),
            Self.intent(app: Self.otherApp, key: Self.otherAppKey),
        ])
        let platform = FakePlatform(chain: chain, response: (Self.documentId, intent.response))
        platform.otherAppFenceOff = true
        platform.closedIntentFenceOff = true
        platform.fenceHashFails = true
        let dataSource = makeDataSource(chain: chain, intents: intents, rows: rows, platform: platform)

        let result = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertEqual(result.keysTurnedOff, 1)
        XCTAssertEqual(intents.load().first { $0.id == intent.id }?.closedAt, Self.at, "the intent is closed")
        XCTAssertNil(intents.load().first { $0.appId == Self.otherApp }?.closedAt, "the other app's intent stays open")
        XCTAssertEqual(rows.load().first?.status, .disconnected)
    }

    // MARK: T46 (K1): a disconnect split over two identity updates

    /// An identity whose app keys a disconnect turns off over two updates.
    /// Writes land at once, but the reads show only what had landed when
    /// `frozen` was set until `catchUp()`. The second identity update fails
    /// with a network error (`refuseSecond`: a consensus rejection) and does
    /// not land; `landLate()` lands it afterwards.
    private final class SplitPlatform: DashConnectPlatformPort, @unchecked Sendable {
        private let lock = NSLock()
        private let keys: [AppConnect.IntendedKey]
        private var off: Set<UInt32> = []
        private var shown: Set<UInt32>?
        private var updates = 0
        private var failedDisable: [UInt32] = []
        let refuseSecond: Bool

        init(keys: [AppConnect.IntendedKey], refuseSecond: Bool) {
            self.keys = keys
            self.refuseSecond = refuseSecond
        }

        var identityId: Data { DashConnectDisconnectThroughSeamsTests.identity }
        var owners: PlatformDashConnectDataSource.OwnerReader { unreadOwners }

        func authorize() async throws {}
        /// The reads stop showing new writes.
        func freeze() { lock.withLock { shown = off } }
        func catchUp() { lock.withLock { shown = nil } }
        func landLate() { lock.withLock { off.formUnion(failedDisable) } }
        func submit(_ write: PlatformWrite) throws {
            guard case .updateKeys(_, let disable) = write else { return }
            let second = lock.withLock { () -> Bool in
                updates += 1
                guard updates == 2 else { off.formUnion(disable); return false }
                failedDisable = disable
                return true
            }
            guard second else { return }
            if refuseSecond {
                throw SDKError.consensusRejection(PlatformConsensusError(code: 10_212, kind: .basic), "rendered text")
            }
            throw SDKError.networkError("connection lost")
        }
        func readIdentity() async throws -> AppConnect.IdentitySnapshot {
            let disabled = lock.withLock { shown ?? off }
            return AppConnect.IdentitySnapshot(
                identityId: identityId, revision: 5 + UInt64(disabled.count), keys: keys.map { key in
                    AppConnect.PlatformKey(
                        id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType,
                        data: key.data, readOnly: key.readOnly, bound: key.bound, boundKnown: true,
                        totalBudget: key.totalBudget, expiresAt: key.expiresAt,
                        disabledAt: disabled.contains(key.id) ? 1_800_000_000_000 : nil)
                }, platformTime: 1_800_000_000_000)
        }
        func fenceKeyHash(keyId: UInt32) async throws -> Data {
            DashConnectDisconnectThroughSeamsTests.fenceHash(keyId)
        }
        func findResponse(requestHash: Data) async throws -> (documentId: Data, values: AppConnect.ResponseValues)? {
            nil
        }
    }

    private static func appKey(_ id: UInt32) -> AppConnect.IntendedKey {
        AppConnect.IntendedKey(
            id: id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: UInt8(id), count: 20), readOnly: false,
            bound: .singleContract(app), totalBudget: 1000, expiresAt: nil)
    }

    private struct Split {
        let dataSource: PlatformDashConnectDataSource
        let platform: SplitPlatform
        let intents: MemoryIntents
        let rows: MemoryRows
        let older: UUID
        let newer: UUID
    }

    /// A, the older intent, holds the keys of the first update; B, the newer,
    /// the one key of the second.
    private func splitDisconnect(refuseSecond: Bool) -> Split {
        let template = Self.intent()
        let olderKeys = (1 ... UInt32(AppConnect.maxKeysDisabledPerUpdate)).map(Self.appKey)
        let newerKey = Self.appKey(UInt32(AppConnect.maxKeysDisabledPerUpdate + 1))
        func intent(_ keys: [AppConnect.IntendedKey], createdAt: TimeInterval, hash: UInt8)
            -> AppConnect.ConnectionIntent {
            AppConnect.ConnectionIntent(
                id: UUID(), identityId: Self.identity, appId: Self.app, appLabel: "App", appUrl: "",
                requestHash: Data(repeating: hash, count: 20), connectionId: template.connectionId, keys: keys,
                sentEncryptionKeyIds: [], disables: [], response: template.response, responseDocumentId: nil,
                responseRemoved: true, createdAt: Date(timeIntervalSince1970: createdAt), closedAt: nil)
        }
        let older = intent(olderKeys, createdAt: 0, hash: 0xE1)
        let newer = intent([newerKey], createdAt: 100, hash: 0xE2)
        let intents = MemoryIntents([older, newer])
        let rows = MemoryRows([DAppConnection(
            id: Self.app.toBase58String(), name: "App", url: "", status: .active,
            updatedAt: Date(timeIntervalSince1970: 0))])
        let platform = SplitPlatform(keys: olderKeys + [newerKey], refuseSecond: refuseSecond)
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: rows,
            intentStore: intents,
            activeWalletIdHex: { Self.walletIdHex },
            now: { Self.at },
            makeWriteExecutor: { _ in
                AppConnectWriteExecutor(
                    timeout: .milliseconds(100), sleep: { try await Task.sleep(for: $0) }, log: { _ in },
                    submit: { write in try platform.submit(write) })
            },
            platform: platform,
            pauseForLaggingNode: { _ in })
        return Split(
            dataSource: dataSource, platform: platform, intents: intents, rows: rows, older: older.id, newer: newer.id)
    }

    /// T46 (K1, AC-16, AC-19): the first update lands, the second has an
    /// unknown outcome, and the read after still shows every key live. Both
    /// intents may have been turned off, so both are marked and stay open;
    /// once the second update lands and the reads catch up, a refresh closes
    /// them and the app shows a Disconnected entry.
    func testAStoppedSplitDisconnectMarksTheIntentOfItsDoneUpdateSoTheEntryShowsOnceReadsCatchUp() async throws {
        let split = splitDisconnect(refuseSecond: false)
        let (dataSource, platform, intents, rows) = (split.dataSource, split.platform, split.intents, split.rows)
        let (older, newer) = (split.older, split.newer)
        platform.freeze()

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertNil(intents.load().first { $0.id == older }?.closedAt, "the read after still shows its keys live")
        XCTAssertNotNil(intents.load().first { $0.id == older }?.disconnectedAt, "the done update carried its keys")
        XCTAssertNotNil(
            intents.load().first { $0.id == newer }?.disconnectedAt, "the update of unknown outcome carried its key")

        platform.landLate()
        platform.catchUp()
        await dataSource.refreshConnections()

        XCTAssertEqual(intents.load().first { $0.id == older }?.closedAt, Self.at)
        XCTAssertEqual(intents.load().first { $0.id == newer }?.closedAt, Self.at)
        XCTAssertEqual(rows.load().first?.status, .disconnected, "the app shows a Disconnected entry")
    }

    /// T46 (K1, AC-16, AC-19): the first update lands, the second is refused.
    /// The intent of the done update is marked; the one whose only key the
    /// refused update carried stays live and unmarked.
    func testAStoppedSplitDisconnectWhoseSecondUpdateIsRefusedMarksOnlyTheIntentOfTheDoneUpdate() async throws {
        let split = splitDisconnect(refuseSecond: true)
        let (dataSource, platform, intents) = (split.dataSource, split.platform, split.intents)
        let (older, newer) = (split.older, split.newer)
        platform.freeze()

        _ = try await dataSource.disconnect(id: Self.app.toBase58String(), scope: Self.scope)

        XCTAssertNotNil(intents.load().first { $0.id == older }?.disconnectedAt, "the done update carried its keys")
        XCTAssertNil(intents.load().first { $0.id == newer }?.disconnectedAt, "the refused update did not land")

        platform.catchUp()
        await dataSource.refreshConnections()

        XCTAssertEqual(
            intents.load().first { $0.id == older }?.closedAt, Self.at, "its keys are off: the refresh closes it")
        XCTAssertNil(intents.load().first { $0.id == newer }?.closedAt, "its key is still live")
    }
}

/// The owners of contracts and contract groups, read from Platform and
/// remembered for the app's run: a known owner is never read again, and a
/// read that fails leaves the owner unknown, to be read again.
final class AppConnectOwnerMemoryTests: XCTestCase {
    private static let contract = Data(repeating: 0xC1, count: 32)
    private static let group = Data(repeating: 0xC2, count: 32)
    private static let owner = Data(repeating: 0x0A, count: 32)

    /// Counts reads per id and answers with what the test sets.
    private final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [Data: Int] = [:]
        var answer: (Data) throws -> [String: Any] = { _ in [:] }

        func read(_ id: Data) throws -> [String: Any] {
            lock.lock()
            counts[id, default: 0] += 1
            let answer = self.answer
            lock.unlock()
            return try answer(id)
        }

        func count(_ id: Data) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return counts[id] ?? 0
        }
    }

    private func owners(
        _ memory: PlatformDashConnectDataSource.OwnerMemory, _ reads: Reads, network: String = "testnet",
        contracts: Set<Data> = [contract], groups: Set<Data> = []
    ) async -> [Data: Data] {
        await memory.owners(
            contracts: contracts, groups: groups, network: network,
            readContract: { try reads.read($0) }, readGroup: { try reads.read($0) })
    }

    func testAKnownOwnerIsNeverReadAgain() async {
        let memory = PlatformDashConnectDataSource.OwnerMemory(), reads = Reads()
        reads.answer = { _ in ["ownerId": Self.owner.toBase58String(), "adminIds": [Any]()] }
        let first = await owners(memory, reads, groups: [Self.group])
        let second = await owners(memory, reads, groups: [Self.group])
        XCTAssertEqual(first, [Self.contract: Self.owner, Self.group: Self.owner])
        XCTAssertEqual(second, first)
        XCTAssertEqual(reads.count(Self.contract), 1)
        XCTAssertEqual(reads.count(Self.group), 1)
    }

    func testAContractOwnerIsReadFromEitherOwnerField() async {
        let memory = PlatformDashConnectDataSource.OwnerMemory(), reads = Reads()
        reads.answer = { _ in ["$ownerId": Self.owner.toBase58String()] }
        let known = await owners(memory, reads)
        XCTAssertEqual(known, [Self.contract: Self.owner])
    }

    func testAnOwnerThatCouldNotBeReadStaysUnknownAndIsReadAgain() async {
        let failures: [(String, (Data) throws -> [String: Any])] = [
            ("network error", { _ in throw SDKError.timeout("slow") }),
            ("not found", { _ in throw SDKError.notFound("behind") }),
            ("no readable owner", { _ in ["ownerId": 7] }),
        ]
        for (name, failure) in failures {
            let memory = PlatformDashConnectDataSource.OwnerMemory(), reads = Reads()
            reads.answer = failure
            let unknown = await owners(memory, reads, groups: [Self.group])
            XCTAssertEqual(unknown, [:], name)
            reads.answer = { _ in ["ownerId": Self.owner.toBase58String(), "adminIds": [Any]()] }
            let known = await owners(memory, reads, groups: [Self.group])
            XCTAssertEqual(known, [Self.contract: Self.owner, Self.group: Self.owner], name)
            XCTAssertEqual(reads.count(Self.contract), 2, name)
            XCTAssertEqual(reads.count(Self.group), 2, name)
        }
    }

    func testAnOwnerKnownOnOneNetworkIsReadAgainOnAnother() async {
        let memory = PlatformDashConnectDataSource.OwnerMemory(), reads = Reads()
        reads.answer = { _ in ["ownerId": Self.owner.toBase58String(), "adminIds": [Any]()] }
        _ = await owners(memory, reads, network: "testnet")
        _ = await owners(memory, reads, network: "mainnet")
        XCTAssertEqual(reads.count(Self.contract), 2)
    }

    /// "devnet" is not one chain: an owner known on one devnet is read again
    /// on a devnet of another name, or of the same name at another endpoint.
    func testAnOwnerKnownOnOneDevnetIsReadAgainOnAnotherNameOrEndpoint() async {
        let memory = PlatformDashConnectDataSource.OwnerMemory(), reads = Reads()
        reads.answer = { _ in ["ownerId": Self.owner.toBase58String(), "adminIds": [Any]()] }
        let scope = PlatformDashConnectDataSource.ownerScope
        for network in [
            scope("dashconnect.connections.v1.devnet-alpha.ab12", "https://alpha.example:1443"),
            scope("dashconnect.connections.v1.devnet-beta.ab12", "https://alpha.example:1443"),
            scope("dashconnect.connections.v1.devnet-alpha.ab12", "https://other.example:1443"),
        ] {
            _ = await owners(memory, reads, network: network)
        }
        XCTAssertEqual(reads.count(Self.contract), 3)
        _ = await owners(memory, reads, network: scope("dashconnect.connections.v1.devnet-alpha.ab12", "https://alpha.example:1443"))
        XCTAssertEqual(reads.count(Self.contract), 3, "the same devnet at the same endpoint reads no owner again")
        XCTAssertEqual(scope("dashconnect.connections.v1.testnet.ab12", nil), scope("dashconnect.connections.v1.testnet.ab12", nil))
    }

    /// A contract group's admins may add their own contracts to it, so a
    /// group with admins, or whose admins the read does not show, has no
    /// single owner: it is remembered as administered, not as its owner's.
    func testAGroupWithAdminsHasNoSingleOwner() async {
        let admin = Data(repeating: 0x0B, count: 32).toBase58String()
        for (name, admins, expected) in [
            ("admins", [admin] as [Any]?, AppConnect.administeredGroupOwnerId),
            ("admins not shown", nil, AppConnect.administeredGroupOwnerId),
            ("no admins", [], Self.owner),
        ] {
            let memory = PlatformDashConnectDataSource.OwnerMemory(), reads = Reads()
            reads.answer = { id in
                var info: [String: Any] = ["ownerId": Self.owner.toBase58String()]
                if id == Self.group, let admins { info["adminIds"] = admins }
                return info
            }
            let known = await owners(memory, reads, groups: [Self.group])
            XCTAssertEqual(known, [Self.contract: Self.owner, Self.group: expected], name)
        }
    }
}


/// An owner reader whose every read fails: no owner is known.
private let unreadOwners = PlatformDashConnectDataSource.OwnerReader(
    network: "testnet", memory: .init(),
    readContract: { _ in throw SDKError.timeout("unread") },
    readGroup: { _ in throw SDKError.timeout("unread") })

/// A Connections refresh and a disconnect, through the platform port, read
/// the owners they need and place, turn off and report unrecorded keys by
/// the ones they know (spec AC-01…AC-12 of app-connect-owner-attribution).
final class AppConnectOwnersThroughSeamsTests: XCTestCase {
    private static let at = Date(timeIntervalSince1970: 1_773_132_300)
    private static let identity = Data(repeating: 0x01, count: 32)
    private static let app = Data(repeating: 0xA1, count: 32)
    private static let otherApp = Data(repeating: 0xA2, count: 32)
    private static let sibling = Data(repeating: 0xC1, count: 32)
    private static let sibling2 = Data(repeating: 0xC3, count: 32)
    private static let group = Data(repeating: 0xC2, count: 32)
    private static let owner = Data(repeating: 0x0A, count: 32)
    private static let otherOwner = Data(repeating: 0x0B, count: 32)

    private static func key(_ id: UInt32, bound: AppConnect.StoredBound?, boundKnown: Bool = true) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: UInt8(id), count: 20), readOnly: false,
            bound: boundKnown ? bound : nil, boundKnown: boundKnown,
            totalBudget: 1000, expiresAt: 1_900_000_000_000, disabledAt: nil)
    }

    private static func on(_ contract: Data, _ id: UInt32 = 20) -> AppConnect.PlatformKey {
        key(id, bound: .singleContract(contract))
    }

    private static func intent(_ key: AppConnect.PlatformKey, app: Data = app) -> AppConnect.ConnectionIntent {
        AppConnect.ConnectionIntent(
            id: UUID(), identityId: identity, appId: app, appLabel: "App", appUrl: "",
            requestHash: Data(repeating: 0xEE, count: 20), connectionId: nil,
            keys: [AppConnect.IntendedKey(
                id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType, data: key.data,
                readOnly: false, bound: key.bound, totalBudget: key.totalBudget, expiresAt: key.expiresAt)],
            sentEncryptionKeyIds: [], disables: [],
            response: AppConnect.ResponseValues(appEphemeralPubKeyHash: "ee", walletEphemeralPubKey: "02", encryptedPayload: "00"),
            responseDocumentId: nil, responseRemoved: true, createdAt: Date(timeIntervalSince1970: 0), closedAt: nil)
    }

    /// Counts owner reads per id; an id in `failing` fails, any other reads
    /// as its entry in `owners`, or as `owner`.
    private final class Reader: @unchecked Sendable {
        private let lock = NSLock()
        private var reads: [Data: Int] = [:]
        var failing: Set<Data> = []
        /// Ids whose reads fail this many more times, then read.
        var failingTimes: [Data: Int] = [:]
        var owners: [Data: Data] = [:]
        /// Groups that read with an admin; any other reads with none.
        var administered: Set<Data> = []

        func read(_ id: Data) throws -> [String: Any] {
            try lock.withLock {
                reads[id, default: 0] += 1
                if failing.contains(id) { throw SDKError.timeout("slow") }
                if let left = failingTimes[id], left > 0 {
                    failingTimes[id] = left - 1
                    throw SDKError.timeout("slow")
                }
                return [
                    "ownerId": (owners[id] ?? AppConnectOwnersThroughSeamsTests.owner).toBase58String(),
                    "adminIds": administered.contains(id) ? [Data(repeating: 0x0B, count: 32).toBase58String()] as [Any] : [] as [Any],
                ]
            }
        }

        func count(_ id: Data) -> Int { lock.withLock { reads[id] ?? 0 } }
        var total: Int { lock.withLock { reads.values.reduce(0, +) } }
    }

    /// The identity's keys; an identity update the executor lands turns the
    /// keys it disables off. `disabled` is every key id submitted to be
    /// turned off.
    private final class Platform: DashConnectPlatformPort, @unchecked Sendable {
        private let lock = NSLock()
        private var keys: [AppConnect.PlatformKey]
        private var revision: UInt64 = 5
        private var submitted: [UInt32] = []
        /// Keys that land with the next identity update, as a grant from
        /// another device would during the disconnect.
        var landing: [AppConnect.PlatformKey] = []
        let reader: Reader
        let memory = PlatformDashConnectDataSource.OwnerMemory()

        init(keys: [AppConnect.PlatformKey], reader: Reader) {
            self.keys = keys
            self.reader = reader
        }

        var identityId: Data { AppConnectOwnersThroughSeamsTests.identity }
        var owners: PlatformDashConnectDataSource.OwnerReader {
            let reader = reader
            return .init(network: "testnet", memory: memory, readContract: { try reader.read($0) }, readGroup: { try reader.read($0) })
        }
        var disabled: [UInt32] { lock.withLock { submitted } }

        func submit(_ write: PlatformWrite) {
            guard case .updateKeys(_, let disable) = write else { return }
            lock.withLock {
                submitted += disable
                revision += 1
                keys = keys.map { key in
                    guard disable.contains(key.id) else { return key }
                    return AppConnect.PlatformKey(
                        id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType,
                        data: key.data, readOnly: key.readOnly, bound: key.bound, boundKnown: key.boundKnown,
                        totalBudget: key.totalBudget, expiresAt: key.expiresAt, disabledAt: 1_800_000_000_000)
                } + landing
                landing = []
            }
        }

        func authorize() async throws {}
        func readIdentity() async throws -> AppConnect.IdentitySnapshot {
            lock.withLock {
                AppConnect.IdentitySnapshot(identityId: identityId, revision: revision, keys: keys, platformTime: 1_800_000_000_000)
            }
        }
        func fenceKeyHash(keyId: UInt32) async throws -> Data { Data(repeating: 0xF0, count: 20) }
        func findResponse(requestHash: Data) async throws -> (documentId: Data, values: AppConnect.ResponseValues)? { nil }
    }

    private final class MemoryIntents: AppConnectIntentStore, @unchecked Sendable {
        private var intents: [AppConnect.ConnectionIntent]
        let canPersist = true
        /// The store holds intents of every identity it could not read.
        var hasUnreadable = false
        init(_ intents: [AppConnect.ConnectionIntent]) { self.intents = intents }
        func load() -> [AppConnect.ConnectionIntent] { intents }
        func save(_ intents: [AppConnect.ConnectionIntent]) { self.intents = intents }
        func hasUnreadableRows(identityId: Data) -> Bool { hasUnreadable }
        func pinned(toWalletIdHex walletIdHex: String) -> any AppConnectIntentStore { self }
    }

    private final class MemoryRows: DashConnectStore {
        private var rows: [DAppConnection] = []
        func load() -> [DAppConnection] { rows }
        func save(_ connections: [DAppConnection]) { rows = connections }
        var scopeKey: String? { nil }
        func pinned(toWalletIdHex walletIdHex: String) -> any DashConnectStore { self }
    }

    private struct Harness {
        let dataSource: PlatformDashConnectDataSource
        let platform: Platform
        let rows: MemoryRows
        let intents: MemoryIntents

        /// The ids of the stored rows.
        var rowIds: Set<Data> { Set(rows.load().compactMap { Data.identifier(fromBase58: $0.id) }) }

        func refresh() async { await dataSource.refreshConnections() }

        func disconnect(_ appId: Data) async throws -> DashConnectDisconnectResult {
            await refresh()
            return try await dataSource.disconnect(id: appId.toBase58String(), scope: "wallet  ")
        }
    }

    private func harness(
        _ keys: [AppConnect.PlatformKey], _ intents: [AppConnect.ConnectionIntent], reader: Reader = Reader()
    ) -> Harness {
        let platform = Platform(keys: keys, reader: reader)
        let rows = MemoryRows()
        let stored = MemoryIntents(intents)
        let dataSource = PlatformDashConnectDataSource(
            supportedNetwork: .testnet,
            store: rows,
            intentStore: stored,
            activeWalletIdHex: { "wallet" },
            now: { Self.at },
            makeWriteExecutor: { _ in
                AppConnectWriteExecutor(
                    timeout: .milliseconds(100), sleep: { try await Task.sleep(for: $0) }, log: { _ in },
                    submit: { write in platform.submit(write) })
            },
            platform: platform,
            pauseForLaggingNode: { _ in })
        return Harness(dataSource: dataSource, platform: platform, rows: rows, intents: stored)
    }

    // MARK: Refresh

    /// AC-03, AC-05: an unread owner keeps the key on its own row; once a
    /// later refresh reads it as the app's owner, the key is the app's and no
    /// row is named by Y. The app's owner is not read again.
    func testARefreshShowsASiblingKeyUnderTheAppOnceItsOwnerIsRead() async {
        let own = Self.on(Self.app, 10)
        let reader = Reader()
        reader.failing = [Self.sibling]
        let h = harness([own, Self.on(Self.sibling)], [Self.intent(own)], reader: reader)
        await h.refresh()
        XCTAssertEqual(h.rowIds, [Self.app, Self.sibling], "AC-05: a separate row while the owner is unknown")
        reader.failing = []
        await h.refresh()
        XCTAssertEqual(h.rowIds, [Self.app], "AC-03: no row named by Y")
        XCTAssertEqual(h.rows.load().first?.seenOn, [Self.identity.toBase58String()], "the key shows under the app")
        XCTAssertEqual(reader.count(Self.app), 1, "a known owner is not read again")
        XCTAssertEqual(reader.count(Self.sibling), 2, "an unread owner is read again")
    }

    /// AC-10: with no intent here, keys of one owner keep their own rows,
    /// and no owner is read.
    func testWithoutAnIntentKeysOfOneOwnerKeepTheirOwnRowsAndNoOwnerIsRead() async {
        let reader = Reader()
        let h = harness([Self.on(Self.sibling, 20), Self.on(Self.sibling2, 21)], [], reader: reader)
        await h.refresh()
        XCTAssertEqual(h.rowIds, [Self.sibling, Self.sibling2])
        XCTAssertEqual(reader.total, 0)
    }

    /// A Disconnected row stays while the identity has intents the store
    /// could not read: one of them may be its disconnect. With every intent
    /// read and none of the app's, the row goes.
    func testADisconnectedRowStaysWhileTheIdentityHasAnUnreadableIntent() async {
        let row = DAppConnection(
            id: Self.app.toBase58String(), name: "App", url: "app.example", status: .disconnected,
            updatedAt: Date(timeIntervalSince1970: 1))
        let h = harness([], [])
        h.rows.save([row])
        h.intents.hasUnreadable = true
        await h.refresh()
        XCTAssertEqual(h.rows.load().map(\.status), [.disconnected])

        h.intents.hasUnreadable = false
        await h.refresh()
        XCTAssertEqual(h.rows.load(), [])
    }

    func testNoUnrecordedKeyReadsNoOwner() async {
        let own = Self.on(Self.app, 10)
        let reader = Reader()
        let h = harness([own], [Self.intent(own)], reader: reader)
        await h.refresh()
        XCTAssertEqual(reader.total, 0)
    }

    // MARK: Disconnect

    /// AC-01, AC-02: a key of the app's owner on a sibling contract, a
    /// document type of it or a contract group is turned off with the app's
    /// keys and counted; nothing is reported left.
    func testADisconnectTurnsOffAndCountsAKeyOfTheAppsOwner() async throws {
        let own = Self.on(Self.app, 10)
        for (name, stray) in [
            ("contract", Self.on(Self.sibling)),
            ("document type", Self.key(20, bound: .documentType(contractId: Self.sibling, name: "note"))),
            ("contract group", Self.key(20, bound: .contractGroup(Self.group))),
        ] {
            let h = harness([own, stray], [Self.intent(own)])
            let result = try await h.disconnect(Self.app)
            XCTAssertEqual(Set(h.platform.disabled), [10, 20], name)
            XCTAssertEqual(result.keysTurnedOff, 2, name)
            XCTAssertEqual([result.keysStillLive, result.keysNotChecked, result.keysNotAttributable], [0, 0, 0], name)
        }
    }

    /// A key of the app's owner that lands during the update is told from
    /// the read after it, as the rows are: it is reported as still on, and
    /// the app keeps the row a second disconnect needs.
    func testAKeyThatLandsDuringTheUpdateIsReportedAsStillOn() async throws {
        let own = Self.on(Self.app, 10)
        let h = harness([own], [Self.intent(own)])
        h.platform.landing = [Self.on(Self.sibling, 30)]
        let result = try await h.disconnect(Self.app)
        XCTAssertEqual(h.platform.disabled, [10])
        XCTAssertEqual([result.keysTurnedOff, result.keysStillLive, result.keysNotChecked], [1, 1, 0])
        XCTAssertEqual(h.rowIds, [Self.app])
    }

    /// AC-18: a key of unknown bound that lands during the update keeps the
    /// app's intent open, as one the plan's read showed would: the row keeps
    /// its status and its Disconnect, and the key is reported unchecked.
    func testAKeyOfUnknownBoundThatLandsDuringTheUpdateKeepsTheRow() async throws {
        let own = Self.on(Self.app, 10)
        let h = harness([own], [Self.intent(own)])
        h.platform.landing = [Self.key(20, bound: nil, boundKnown: false)]
        let result = try await h.disconnect(Self.app)
        XCTAssertEqual(h.platform.disabled, [10])
        XCTAssertEqual([result.keysTurnedOff, result.keysNotChecked], [1, 1])
        let row = h.rows.load().first { $0.id == Self.app.toBase58String() }
        XCTAssertNotNil(row, "the row is not lost")
        XCTAssertNotEqual(row?.status, .disconnected, "the row keeps its Disconnect while a key's bound is unknown")
    }

    /// An owner that could not be read before the update and reads after it
    /// places the key with the app for the rows and the result alike: the
    /// key is still on, not unchecked, and the app keeps its row.
    func testAnOwnerReadAfterTheUpdateDecidesTheRowsAndTheResultAlike() async throws {
        let own = Self.on(Self.app, 10)
        let reader = Reader()
        // The refresh, the plan and the plan after the PIN fail; the read
        // after the update reads.
        reader.failingTimes = [Self.sibling: 3]
        let h = harness([own, Self.on(Self.sibling)], [Self.intent(own)], reader: reader)
        let result = try await h.disconnect(Self.app)
        XCTAssertEqual(h.platform.disabled, [10])
        XCTAssertEqual([result.keysStillLive, result.keysNotChecked, result.keysNotAttributable], [1, 0, 0])
        XCTAssertEqual(h.rowIds, [Self.app], "the key shows under the app, not on its own row")
    }

    /// A key on a contract group of the app's owner whose admins may add
    /// their own contracts to it may be another developer's app: it is not
    /// turned off, and the result says it may be another app's.
    func testAKeyOnAGroupWithAdminsIsNotAttributedByOwner() async throws {
        let own = Self.on(Self.app, 10)
        let reader = Reader()
        reader.administered = [Self.group]
        let h = harness([own, Self.key(20, bound: .contractGroup(Self.group))], [Self.intent(own)], reader: reader)
        let result = try await h.disconnect(Self.app)
        XCTAssertEqual(h.platform.disabled, [10])
        XCTAssertEqual([result.keysTurnedOff, result.keysNotChecked, result.keysNotAttributable], [1, 0, 1])
    }

    /// AC-04, AC-11, AC-12: the disconnect still turns off the app's keys,
    /// leaves the key that could not be checked on, and reports it.
    func testAKeyThatCouldNotBeCheckedStaysOnAndIsReported() async throws {
        let own = Self.on(Self.app, 10)
        let z = Self.intent(Self.on(Self.otherApp, 11), app: Self.otherApp)
        let cases: [(String, [AppConnect.PlatformKey], [AppConnect.ConnectionIntent], Set<Data>)] = [
            ("AC-04 owner unread", [own, Self.on(Self.sibling)], [Self.intent(own)], [Self.sibling]),
            ("AC-11 unplaced", [own, Self.key(20, bound: nil, boundKnown: false)], [Self.intent(own)], []),
            ("AC-12 another app's owner unread", [own, Self.on(Self.otherApp, 11), Self.on(Self.sibling)], [Self.intent(own), z], [Self.otherApp]),
        ]
        for (name, keys, intents, failing) in cases {
            let reader = Reader()
            reader.failing = failing
            let h = harness(keys, intents, reader: reader)
            let result = try await h.disconnect(Self.app)
            XCTAssertEqual(h.platform.disabled, [10], name)
            XCTAssertEqual(result.keysTurnedOff, 1, name)
            XCTAssertEqual(result.keysNotChecked, 1, name)
        }
    }

    /// AC-06: a key of another owner is never submitted, and its row stays.
    func testAKeyOfAnotherOwnerIsNeverTurnedOffAndItsRowStays() async throws {
        let own = Self.on(Self.app, 10)
        let reader = Reader()
        reader.owners = [Self.sibling: Self.otherOwner]
        let h = harness([own, Self.on(Self.sibling)], [Self.intent(own)], reader: reader)
        let result = try await h.disconnect(Self.app)
        XCTAssertEqual(h.platform.disabled, [10])
        XCTAssertEqual([result.keysTurnedOff, result.keysNotChecked, result.keysNotAttributable], [1, 0, 0])
        XCTAssertTrue(h.rowIds.contains(Self.sibling), "W's row stays")
    }

    /// AC-07: with two apps of one owner here, a key on a third contract of
    /// that owner is left on and reported as not attributable.
    func testAKeyTwoAppsOfOneOwnerMayHoldIsLeftOnAndReported() async throws {
        let own = Self.on(Self.app, 10)
        let z = Self.intent(Self.on(Self.otherApp, 11), app: Self.otherApp)
        let h = harness([own, Self.on(Self.otherApp, 11), Self.on(Self.sibling)], [Self.intent(own), z])
        let result = try await h.disconnect(Self.app)
        XCTAssertEqual(h.platform.disabled, [10])
        XCTAssertEqual([result.keysNotChecked, result.keysNotAttributable], [0, 1])
        XCTAssertTrue(h.rowIds.contains(Self.sibling), "the key stays on its own row")
    }

    /// AC-10: with no intent here, a disconnect of one row turns off only
    /// its key, reads no owner, and the other row stays.
    func testWithoutAnIntentADisconnectOfOneRowTurnsOffOnlyItsKey() async throws {
        let reader = Reader()
        let h = harness([Self.on(Self.sibling, 20), Self.on(Self.sibling2, 21)], [], reader: reader)
        let result = try await h.disconnect(Self.sibling)
        XCTAssertEqual(h.platform.disabled, [20])
        XCTAssertEqual(result.keysTurnedOff, 1)
        XCTAssertEqual(h.rowIds, [Self.sibling2])
        XCTAssertEqual(reader.total, 0, "no owner decides anything without an intent")
    }

    /// The row the user saw for Y because its owner could not be read: its
    /// disconnect turns off Y's key once the owner reads as the app's, and
    /// reads no owner for it.
    func testARowShownForAnUnreadOwnerStillTurnsOffItsKey() async throws {
        let own = Self.on(Self.app, 10)
        let reader = Reader()
        reader.failing = [Self.sibling]
        let h = harness([own, Self.on(Self.sibling)], [Self.intent(own)], reader: reader)
        await h.refresh()
        XCTAssertTrue(h.rowIds.contains(Self.sibling))
        reader.failing = []
        let result = try await h.dataSource.disconnect(id: Self.sibling.toBase58String(), scope: "wallet  ")
        XCTAssertEqual(h.platform.disabled, [20])
        XCTAssertEqual(result.keysTurnedOff, 1)
    }
}

/// The approve sheet's terms and caution: expiries set and bounded at the
/// Platform time the request was resolved at, and a Refused attempt that
/// connected nothing.
@MainActor
final class ConnectionsViewModelTermsTests: XCTestCase {
    private static let phone = Date(timeIntervalSince1970: 1_791_676_800)
    private static let appId = "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F"

    private static func request(platformTimeMs: UInt64, expiresAt: UInt64) -> ConnectionRequest {
        let app = Data(repeating: 0xA1, count: 32)
        let binding = AppConnectRequest.AuthBinding(
            kind: .singleContract, securityLevel: .high, id: app,
            totalBudget: 1000, expiresAt: expiresAt, documentTypeName: nil)
        var plan = AppConnect.GrantPlan(
            appId: app, appEphemeralPubKeyHash: Data(repeating: 0x01, count: 20),
            auth: [AppConnect.AuthGrant(bindingIndex: 0, binding: binding, totalBudget: 1000, expiresAt: expiresAt)],
            encryption: [], connectionId: nil, identityHint: nil, createdAt: 0)
        plan.platformTimeMs = platformTimeMs
        var request = ConnectionRequest(loginRequest: MockDashConnectDataSource.sampleLoginRequest)
        request.login = .appConnect(plan)
        return request
    }

    func testTheYearPresetIsInBoundsAtAPlatformTimeBehindThePhone() {
        let platform = AppConnect.milliseconds(Self.phone) - 120_000
        let viewModel = ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(store: TestDashConnectStore()), featureUnavailable: false,
            now: { Self.phone })
        viewModel.pendingRequest = Self.request(platformTimeMs: platform, expiresAt: platform + 3_600_000)

        viewModel.setExpiry(days: 365)

        let applied = viewModel.termsAppliedPlan
        XCTAssertNotNil(applied)
        XCTAssertNil(applied.flatMap { AppConnect.termsFailure(of: $0, platformTimeMs: platform) })
        XCTAssertNil(applied.flatMap { AppConnect.termsFailure(of: $0, platformTimeMs: platform + 60_000) })
    }

    func testAnExpiryPastAtPlatformTimeTurnsApproveOffWhileThePhoneClockIsBehind() {
        var phone = Self.phone
        let platform = AppConnect.milliseconds(Self.phone) + 2 * 3_600_000
        let viewModel = ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(store: TestDashConnectStore()), featureUnavailable: false,
            now: { phone })
        viewModel.pendingRequest = Self.request(platformTimeMs: platform, expiresAt: platform + 3_600_000)
        XCTAssertNotNil(viewModel.termsAppliedPlan)

        // Two hours on: past the expiry at Platform's time, an hour before
        // it by this phone's clock.
        phone = phone.addingTimeInterval(2 * 3600)

        XCTAssertNil(viewModel.termsAppliedPlan)
        XCTAssertEqual(
            viewModel.approveDisabledReason,
            NSLocalizedString(
                "This expiry has passed. Pick another one, then approve.",
                comment: "DashConnect approve sheet: the chosen expiry is in the past"))
    }

    func testARefusedAttemptKeepsTheFirstConnectionCaution() async {
        let refused = DAppConnection(
            id: Self.appId, name: "Yappr", url: "yap.pr", status: .refused, updatedAt: Self.phone)
        let viewModel = ConnectionsViewModel(
            dataSource: MockDashConnectDataSource(initial: [refused], store: TestDashConnectStore()),
            featureUnavailable: false, now: { Self.phone })
        let deadline = Date().addingTimeInterval(2)
        while !viewModel.hasReadRows, Date() < deadline { try? await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertTrue(viewModel.hasReadRows)

        viewModel.pendingRequest = ConnectionRequest(loginRequest: MockDashConnectDataSource.sampleLoginRequest)

        XCTAssertEqual(viewModel.pendingRequest?.appContractId, Self.appId)
        XCTAssertTrue(viewModel.pendingIsFirstConnection)
    }
}
