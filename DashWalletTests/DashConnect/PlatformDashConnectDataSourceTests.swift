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
        auth: [], encryption: [], connectionId: nil, identityHint: nil, createdAt: 0, callbackHost: nil)
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

    /// A disconnect that left keys no approval names offers to turn them
    /// off as well; one that left none says nothing.
    func testADisconnectThatLeftUnrecordedKeysOffersToTurnThemOff() async {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)

        let offeredKeys = DashConnectOfferedKeys(identityId: Data(repeating: 0x01, count: 32), keyIds: [20, 21])
        spy.disconnectResult = DashConnectDisconnectResult(offeredUnrecordedKeys: offeredKeys)
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }
        XCTAssertEqual(viewModel.message?.text.contains("2"), true)
        XCTAssertEqual(viewModel.message?.unrecordedKeysOf, Self.connection)
        XCTAssertEqual(viewModel.message?.unrecordedKeys, offeredKeys, "the message keeps the offered keys and their identity")
        XCTAssertEqual(spy.disconnectedUnrecordedKeys, [nil])

        let offered = viewModel.message?.unrecordedKeys
        viewModel.message = nil
        spy.disconnectResult = DashConnectDisconnectResult()
        viewModel.disconnect(Self.connection, unrecordedKeys: offered)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 2 }
        XCTAssertEqual(spy.disconnectedUnrecordedKeys, [nil, offeredKeys], "the answer passes back exactly the offered keys, with their identity")
        XCTAssertNil(viewModel.message)
    }

    /// The message a disconnect result words, its paragraphs in order.
    private func message(after result: DashConnectDisconnectResult) async -> ConnectionsScreenMessage? {
        let spy = PurchaseApprovalSpy()
        let viewModel = ConnectionsViewModel(dataSource: spy, featureUnavailable: false)
        spy.disconnectResult = result
        viewModel.disconnect(Self.connection)
        await waitUntil { !viewModel.isDisconnecting && spy.disconnectedIds.count == 1 }
        return viewModel.message
    }

    private static let notChecked = "could not tell yet which app holds some keys"
    private static let notAttributable = "may belong to another app of the same developer"
    private static let leftAfterQuestion = "Disconnect it again to turn them off"

    private static func paragraphs(_ message: ConnectionsScreenMessage?) -> [String] {
        message?.text.components(separatedBy: "\n\n") ?? []
    }

    /// SCR-03 with-warnings: the question carries the warnings, so leaving
    /// the keys still shows them.
    func testTheQuestionCarriesTheWarnings() async {
        let message = await message(after: DashConnectDisconnectResult(
            keysTurnedOff: 1, offeredUnrecordedKeys: DashConnectOfferedKeys(identityId: Data(repeating: 0x01, count: 32), keyIds: [20]),
            keysNotChecked: 2, keysNotAttributable: 3))
        let paragraphs = Self.paragraphs(message)
        XCTAssertEqual(message?.kind, .question)
        guard paragraphs.count == 3 else { return XCTFail("paragraphs: \(paragraphs)") }
        XCTAssertTrue(paragraphs[0].contains("Turn them off too?"))
        XCTAssertTrue(paragraphs[1].contains(Self.notChecked) && paragraphs[1].contains("(2)"))
        XCTAssertTrue(paragraphs[2].contains(Self.notAttributable) && paragraphs[2].contains("(3)"))
    }

    /// SCR-04 not-attributable: its own text, pointing to the key's row,
    /// without a retry hint.
    func testAKeyNotAttributableIsReportedWithoutARetryHint() async {
        let message = await message(after: DashConnectDisconnectResult(keysTurnedOff: 1, keysNotAttributable: 1))
        XCTAssertEqual(message?.kind, .warning)
        XCTAssertEqual(Self.paragraphs(message).count, 1)
        XCTAssertTrue(message?.text.contains(Self.notAttributable) == true)
        XCTAssertTrue(message?.text.contains("its own row") == true)
        XCTAssertFalse(message?.text.contains("again later") == true)
    }

    /// SCR-04 left-after-question: a key attributed only after the question
    /// stays on, and the result says so.
    func testAKeyLeftAfterTheQuestionIsReported() async {
        let message = await message(after: DashConnectDisconnectResult(keysTurnedOff: 2, keysLeftAfterQuestion: 1))
        XCTAssertEqual(message?.kind, .warning)
        XCTAssertTrue(message?.text.contains(Self.leftAfterQuestion) == true)
        XCTAssertTrue(message?.text.contains("(1)") == true)
    }

    /// Keys left on whose app's row is gone are sent to the row that shows
    /// them, by its name, never to a second disconnect of the app.
    func testKeysLeftUnderAnotherRowNameThatRow() async {
        let message = await message(after: DashConnectDisconnectResult(
            keysTurnedOff: 1, keysLeftAfterQuestion: 2, keysLeftUnder: "Other App"))
        XCTAssertEqual(message?.kind, .warning)
        XCTAssertEqual(Self.paragraphs(message).count, 1)
        XCTAssertTrue(message?.text.contains("(2)") == true)
        XCTAssertTrue(message?.text.contains("show under Other App in Connections") == true)
        XCTAssertFalse(message?.text.contains(Self.leftAfterQuestion) == true)
    }

    /// SCR-04 combined: not checked, not attributable, left after the
    /// question, another identity, in that order; a finding besides the
    /// other identity keeps the success heading.
    func testSeveralFindingsAreWordedInOrder() async {
        let message = await message(after: DashConnectDisconnectResult(
            keysNotChecked: 1, keysNotAttributable: 1, keysLeftAfterQuestion: 1, keysOnAnotherIdentity: true))
        let paragraphs = Self.paragraphs(message)
        guard paragraphs.count == 4 else { return XCTFail("paragraphs: \(paragraphs)") }
        XCTAssertTrue(paragraphs[0].contains(Self.notChecked))
        XCTAssertTrue(paragraphs[1].contains(Self.notAttributable))
        XCTAssertTrue(paragraphs[2].contains(Self.leftAfterQuestion))
        XCTAssertEqual(paragraphs[3], DashConnectPlatformError.grantOnAnotherIdentity.localizedDescription)
        XCTAssertEqual(message?.kind, .warning)
        XCTAssertEqual(message?.title, "Success")
    }

    /// The error heading stays for keys on another identity alone with
    /// nothing turned off.
    func testKeysOnlyOnAnotherIdentityWithNothingTurnedOffAreAnError() async {
        let message = await message(after: DashConnectDisconnectResult(keysOnAnotherIdentity: true))
        XCTAssertEqual(message?.kind, .error)
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
    private func approveAppConnectRequest(byLink: Bool) async throws -> [URL] {
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
        return opened.urls
    }

    /// A QR code scanned off another screen is answered there: opening the
    /// callback on this phone would start an unrelated session of the app.
    func testApprovingAScannedAppConnectRequestDoesNotOpenItsCallback() async throws {
        let opened = try await approveAppConnectRequest(byLink: false)
        XCTAssertEqual(opened, [])
    }

    /// A link opened by the app on this phone returns to it when answered.
    func testApprovingALinkedAppConnectRequestOpensItsCallback() async throws {
        let opened = try await approveAppConnectRequest(byLink: true)
        XCTAssertEqual(opened.map(\.host), ["yap.pr"])
        XCTAssertEqual(opened.first?.absoluteString.contains("ac=ok"), true)
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
        viewModel.denyPendingRequest()

        XCTAssertEqual(opened.urls.count, 1)
        XCTAssertEqual(opened.urls.first?.absoluteString.contains("ac=declined"), true)
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
        viewModel.denyPendingRequest()

        XCTAssertEqual(opened.urls.count, 1)
        XCTAssertEqual(opened.urls.first?.absoluteString.contains("ac=stale"), true)
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
    private var storedDisconnectedScopes: [String?] = []
    private var storedDisconnectedUnrecordedKeys: [DashConnectOfferedKeys?] = []

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

    var disconnectedUnrecordedKeys: [DashConnectOfferedKeys?] {
        lock.withLock { storedDisconnectedUnrecordedKeys }
    }

    private var storedDisconnectResult = DashConnectDisconnectResult()

    /// What a successful disconnect reports.
    var disconnectResult: DashConnectDisconnectResult {
        get { lock.withLock { storedDisconnectResult } }
        set { lock.withLock { storedDisconnectResult = newValue } }
    }

    func disconnect(id: String, scope: String?, unrecordedKeys: DashConnectOfferedKeys?) async throws -> DashConnectDisconnectResult {
        let (failure, result) = lock.withLock { () -> (Error?, DashConnectDisconnectResult) in
            storedDisconnectedIds.append(id)
            storedDisconnectedScopes.append(scope)
            storedDisconnectedUnrecordedKeys.append(unrecordedKeys)
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

    var connections: AnyPublisher<[DAppConnection], Never> {
        Just([DAppConnection]()).eraseToAnyPublisher()
    }

    func parseQR(_ content: String) async throws -> DashConnectQr {
        .login(loginRequest)
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

    func disconnect(id: String, scope: String?, unrecordedKeys: DashConnectOfferedKeys?) async throws -> DashConnectDisconnectResult {
        throw PurchaseSpyError.unsupported
    }

    func remove(id: String, scope: String?) async {}
}

/// The URLs a view model asked to open, in order.
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

        await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope, unrecordedKeys: nil) }

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

        await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope, unrecordedKeys: nil) }

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

        await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope, unrecordedKeys: nil) }
        await dataSource.remove(id: shown[0].id, scope: shown[0].scope)

        XCTAssertEqual(connections.load(), [row], "the new wallet's row for the same app is untouched")
        // The row the new list shows is this wallet's own.
        let current = Self.shownRows(dataSource)
        await Self.expectNotWalletChanged {
            try await dataSource.disconnect(id: current[0].id, scope: current[0].scope, unrecordedKeys: nil)
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

        await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope, unrecordedKeys: nil) }
        XCTAssertEqual(connections.load().map(\.status), [.active])
        let current = Self.shownRows(dataSource)
        XCTAssertNotEqual(current[0].scope, shown[0].scope)
        await Self.expectNotWalletChanged {
            try await dataSource.disconnect(id: current[0].id, scope: current[0].scope, unrecordedKeys: nil)
        }
    }

    func testARowWithNoScopeIsNotActedOn() async {
        let active = ActiveWallet("wallet-a")
        let row = Self.row(status: .active)
        let (dataSource, connections) = makeScopedDataSource(active: active, rows: [row])

        await Self.expectWalletChanged { try await dataSource.disconnect(id: row.id, scope: nil, unrecordedKeys: nil) }
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
            _ = try? await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope, unrecordedKeys: nil)
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
            await Self.expectWalletChanged { try await dataSource.disconnect(id: shown[0].id, scope: shown[0].scope, unrecordedKeys: nil) }
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
            try await dataSource.disconnect(id: Self.row(status: .active).id, scope: nil, unrecordedKeys: nil)
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
            devnetNameProvider: { nil }
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

/// A Connections refresh and a disconnect read the owners they need and
/// place unrecorded keys with the ones they know (`projectWithOwners`,
/// `plannedDisconnect`).
final class AppConnectRefreshOwnersTests: XCTestCase {
    private static let identity = Data(repeating: 0x01, count: 32)
    private static let app = Data(repeating: 0xA1, count: 32)
    private static let sibling = Data(repeating: 0xC1, count: 32)
    private static let sibling2 = Data(repeating: 0xC3, count: 32)
    private static let owner = Data(repeating: 0x0A, count: 32)
    private static let otherApp = Data(repeating: 0xA2, count: 32)
    private static let group = Data(repeating: 0xC2, count: 32)

    private static func key(
        _ id: UInt32, on contract: Data, bound: AppConnect.StoredBound? = nil, boundKnown: Bool = true, disabledAt: UInt64? = nil
    ) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: id, purpose: .authentication, securityLevel: .high, keyType: .ecdsaHash160,
            data: Data(repeating: UInt8(id), count: 20), readOnly: false,
            bound: boundKnown ? bound ?? .singleContract(contract) : nil, boundKnown: boundKnown,
            totalBudget: 1000, expiresAt: 1_800_000_001_000, disabledAt: disabledAt)
    }

    private static func intent(_ key: AppConnect.PlatformKey, app: Data = app) -> AppConnect.ConnectionIntent {
        AppConnect.ConnectionIntent(
            id: UUID(), identityId: identity, appId: app, appLabel: "App", appUrl: "", requestHash: Data(repeating: 0xEE, count: 20),
            connectionId: nil,
            keys: [AppConnect.IntendedKey(
                id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType, data: key.data,
                readOnly: false, bound: key.bound, totalBudget: key.totalBudget, expiresAt: key.expiresAt)],
            sentEncryptionKeyIds: [], disables: [],
            response: AppConnect.ResponseValues(appEphemeralPubKeyHash: "ee", walletEphemeralPubKey: "02", encryptedPayload: "00"),
            responseDocumentId: nil, responseRemoved: true, createdAt: Date(timeIntervalSince1970: 0), closedAt: nil)
    }

    private final class Reader: @unchecked Sendable {
        private let lock = NSLock()
        private var reads: [Data: Int] = [:]
        var failing: Set<Data> = []
        /// Ids whose next read fails, and only that one.
        var failingOnce: Set<Data> = []
        /// The owner each id reads as; any other id reads as `owner`.
        var owners: [Data: Data] = [:]
        /// Groups that read with an admin; any other reads with none.
        var administered: Set<Data> = []

        func read(_ id: Data) throws -> [String: Any] {
            lock.lock()
            defer { lock.unlock() }
            reads[id, default: 0] += 1
            if failing.contains(id) { throw SDKError.timeout("slow") }
            if failingOnce.remove(id) != nil { throw SDKError.timeout("slow") }
            return [
                "ownerId": (owners[id] ?? AppConnectRefreshOwnersTests.owner).toBase58String(),
                "adminIds": administered.contains(id) ? [Data(repeating: 0x0B, count: 32).toBase58String()] as [Any] : [] as [Any],
            ]
        }

        var total: Int {
            lock.lock()
            defer { lock.unlock() }
            return reads.values.reduce(0, +)
        }
    }

    private static func ownerReader(
        _ memory: PlatformDashConnectDataSource.OwnerMemory, _ reader: Reader
    ) -> PlatformDashConnectDataSource.OwnerReader {
        .init(network: "testnet", memory: memory, readContract: { try reader.read($0) }, readGroup: { try reader.read($0) })
    }

    private static func rows(
        _ keys: [AppConnect.PlatformKey], _ intents: [AppConnect.ConnectionIntent],
        memory: PlatformDashConnectDataSource.OwnerMemory, reader: Reader
    ) async -> [Data: [UInt32]] {
        let snapshot = AppConnect.IdentitySnapshot(identityId: identity, revision: 1, keys: keys, platformTime: nil)
        let projection = await PlatformDashConnectDataSource.projectWithOwners(snapshot, intents: intents, owners: ownerReader(memory, reader))
        return Dictionary(uniqueKeysWithValues: projection.connections.map { ($0.appId, $0.unrecordedKeyIds[identity] ?? []) })
    }

    func testAKeyOfTheAppsOwnerJoinsItsRow() async {
        let own = Self.key(10, on: Self.app)
        let rows = await Self.rows([own, Self.key(20, on: Self.sibling)], [Self.intent(own)], memory: .init(), reader: Reader())
        XCTAssertEqual(rows, [Self.app: [20]], "AC-03: one row for the app, none for the sibling")
    }

    func testAKeyWhoseOwnerCouldNotBeReadMovesOnceALaterRefreshReadsIt() async {
        let own = Self.key(10, on: Self.app)
        let memory = PlatformDashConnectDataSource.OwnerMemory(), reader = Reader()
        reader.failing = [Self.sibling]
        let first = await Self.rows([own, Self.key(20, on: Self.sibling)], [Self.intent(own)], memory: memory, reader: reader)
        XCTAssertEqual(first, [Self.app: [], Self.sibling: [20]], "AC-05: a separate row while unknown")
        reader.failing = []
        let second = await Self.rows([own, Self.key(20, on: Self.sibling)], [Self.intent(own)], memory: memory, reader: reader)
        XCTAssertEqual(second, [Self.app: [20]], "AC-05: moves once read")
        XCTAssertEqual(reader.total, 3, "the app's owner is not read again")
    }

    func testWithoutAnIntentKeysOfOneOwnerKeepTheirOwnRows() async {
        let rows = await Self.rows([Self.key(20, on: Self.sibling), Self.key(21, on: Self.sibling2)], [], memory: .init(), reader: Reader())
        XCTAssertEqual(rows, [Self.sibling: [20], Self.sibling2: [21]], "AC-10")
    }

    func testNoUnrecordedKeyReadsNoOwner() async {
        let own = Self.key(10, on: Self.app), reader = Reader()
        _ = await Self.rows([own], [Self.intent(own)], memory: .init(), reader: reader)
        XCTAssertEqual(reader.total, 0)
    }

    private static func planned(
        _ keys: [AppConnect.PlatformKey], _ intents: [AppConnect.ConnectionIntent], listed: Set<UInt32>?,
        memory: PlatformDashConnectDataSource.OwnerMemory = .init(), reader: Reader = Reader(), appId: Data = app
    ) async -> PlatformDashConnectDataSource.PlannedDisconnect {
        let snapshot = AppConnect.IdentitySnapshot(identityId: identity, revision: 1, keys: keys, platformTime: nil)
        return await PlatformDashConnectDataSource.plannedDisconnect(
            appId: appId, snapshot: snapshot, intents: intents, unrecordedKeyIds: listed, fences: [], owners: ownerReader(memory, reader))
    }

    /// QG-2: the question listed one key; an owner read that fails before the
    /// PIN and succeeds after attributes a second key, which stays on.
    func testADisconnectTurnsOffOnlyTheKeysTheQuestionListed() async {
        let own = Self.key(10, on: Self.app)
        let keys = [own, Self.key(20, on: Self.sibling), Self.key(21, on: Self.sibling2)]
        let memory = PlatformDashConnectDataSource.OwnerMemory(), reader = Reader()
        reader.failing = [Self.sibling2]
        let beforePin = await Self.planned(keys, [Self.intent(own)], listed: [20], memory: memory, reader: reader)
        XCTAssertEqual(Set(beforePin.plan.disable), [10, 20])
        reader.failing = []
        let afterPin = await Self.planned(keys, [Self.intent(own)], listed: [20], memory: memory, reader: reader)
        XCTAssertEqual(Set(afterPin.plan.disable), [10, 20], "nothing beyond the listed keys")
        XCTAssertEqual(afterPin.appKeysOff, 2, "the keys counted are the keys turned off")
        XCTAssertEqual(afterPin.leftAfterQuestion, 1)
    }

    /// AC-01, AC-02: a key of the app's owner on a sibling contract, a
    /// document type of it or a contract group is offered, then turned off
    /// and counted.
    func testAKeyOfTheAppsOwnerIsOfferedThenTurnedOffAndCounted() async {
        let own = Self.key(10, on: Self.app)
        for (name, stray) in [
            ("contract", Self.key(20, on: Self.sibling)),
            ("document type", Self.key(20, on: Self.sibling, bound: .documentType(contractId: Self.sibling, name: "note"))),
            ("contract group", Self.key(20, on: Self.group, bound: .contractGroup(Self.group))),
        ] {
            let asked = await Self.planned([own, stray], [Self.intent(own)], listed: nil)
            XCTAssertEqual(asked.offered, [20], name)
            XCTAssertEqual(asked.plan.disable, [10], name)
            let confirmed = await Self.planned([own, stray], [Self.intent(own)], listed: asked.offered)
            XCTAssertEqual(Set(confirmed.plan.disable), [10, 20], name)
            XCTAssertEqual(confirmed.appKeysOff, 2, name)
            XCTAssertEqual([confirmed.notChecked, confirmed.notAttributable, confirmed.leftAfterQuestion], [0, 0, 0], name)
        }
    }

    /// A key on a contract group of the app's owner whose admins may add
    /// their own contracts to it may be another developer's app: it is not
    /// offered or turned off, and the result says it may be another app's.
    func testAKeyOnAGroupWithAdminsIsNotAttributedByOwner() async {
        let own = Self.key(10, on: Self.app), stray = Self.key(20, on: Self.group, bound: .contractGroup(Self.group))
        let reader = Reader()
        reader.administered = [Self.group]
        let asked = await Self.planned([own, stray], [Self.intent(own)], listed: nil, memory: .init(), reader: reader)
        XCTAssertEqual(asked.offered, [])
        XCTAssertEqual(asked.plan.disable, [10])
        XCTAssertEqual([asked.notChecked, asked.notAttributable], [0, 1])
    }

    /// AC-04, AC-11, AC-12: the disconnect still turns off the app's keys,
    /// and reports the key that could not be checked.
    func testAKeyThatCouldNotBeCheckedStaysOnAndIsReported() async {
        let own = Self.key(10, on: Self.app)
        let z = Self.intent(Self.key(11, on: Self.otherApp), app: Self.otherApp)
        struct Case {
            let name: String
            let keys: [AppConnect.PlatformKey]
            let intents: [AppConnect.ConnectionIntent]
            let failing: Set<Data>
        }
        let cases = [
            Case(name: "AC-04 owner unread", keys: [own, Self.key(20, on: Self.sibling)], intents: [Self.intent(own)], failing: [Self.sibling]),
            Case(name: "AC-11 unplaced", keys: [own, Self.key(20, on: Self.sibling, boundKnown: false)], intents: [Self.intent(own)], failing: []),
            Case(name: "AC-12 other app's owner unread", keys: [own, Self.key(20, on: Self.sibling)], intents: [Self.intent(own), z],
                 failing: [Self.otherApp]),
        ]
        for c in cases {
            let name = c.name
            let reader = Reader()
            reader.failing = c.failing
            let result = await Self.planned(c.keys, c.intents, listed: [20], reader: reader)
            XCTAssertEqual(result.plan.disable, [10], name)
            XCTAssertEqual(result.notChecked, 1, name)
            XCTAssertEqual(result.appKeysOff, 1, name)
        }
    }

    /// DashPay profile keys no intent names are offered with any app's
    /// disconnect, and turned off only when listed.
    func testAProfileKeyIsOfferedAndTurnedOffOnlyWhenListed() async {
        let own = Self.key(10, on: Self.app)
        let dashPay = Data.identifier(fromBase58: AppConnect.dashPayContractId)!
        let profile = Self.key(30, on: dashPay, bound: .documentType(contractId: dashPay, name: "profile"))
        let asked = await Self.planned([own, profile], [Self.intent(own)], listed: nil)
        XCTAssertEqual(asked.offered, [30])
        XCTAssertEqual(asked.plan.disable, [10])
        let confirmed = await Self.planned([own, profile], [Self.intent(own)], listed: [30])
        XCTAssertEqual(confirmed.plan.disable, [30, 10], "other keys before the app's")
        XCTAssertEqual(confirmed.appKeysOff, 2)
        let unlisted = await Self.planned([own, profile], [Self.intent(own)], listed: [])
        XCTAssertEqual(unlisted.plan.disable, [10])
        XCTAssertEqual(unlisted.leftAfterQuestion, 1)
    }
}

/// The refresh and the disconnect of the data source on a real
/// `UserDefaults` store, with owners scripted per id: what is stored, what
/// is planned to be turned off, and what the result reports.
extension AppConnectRefreshOwnersTests {
    private static func disabled(_ key: AppConnect.PlatformKey) -> AppConnect.PlatformKey {
        AppConnect.PlatformKey(
            id: key.id, purpose: key.purpose, securityLevel: key.securityLevel, keyType: key.keyType, data: key.data,
            readOnly: key.readOnly, bound: key.bound, boundKnown: key.boundKnown, totalBudget: key.totalBudget,
            expiresAt: key.expiresAt, disabledAt: 1)
    }

    /// A store on a throwaway suite, removed when the test ends.
    private func makeStore() -> UserDefaultsDashConnectStore {
        let suiteName = "AppConnectRefreshOwnersTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return UserDefaultsDashConnectStore(
            defaults: defaults, network: .testnet, walletIdHexProvider: { "wallet" }, devnetNameProvider: { nil })
    }

    /// Refreshes `store` from a read of `keys`, as the data source does, and
    /// returns the stored rows by id.
    @discardableResult
    private static func refresh(
        _ store: UserDefaultsDashConnectStore, _ keys: [AppConnect.PlatformKey], _ intents: [AppConnect.ConnectionIntent],
        memory: PlatformDashConnectDataSource.OwnerMemory, reader: Reader
    ) async -> [Data: DAppConnection] {
        let snapshot = AppConnect.IdentitySnapshot(identityId: identity, revision: 1, keys: keys, platformTime: nil)
        let change = await PlatformDashConnectDataSource.refreshedRows(
            snapshot: snapshot, intents: intents, owners: ownerReader(memory, reader), at: Date(timeIntervalSince1970: 0))
        store.save(change(store.load()))
        return Dictionary(uniqueKeysWithValues: store.load().map { (Data.identifier(fromBase58: $0.id)!, $0) })
    }

    /// AC-03, AC-05: a failing owner read stores a row for Y; the next
    /// refresh with the owner read stores the key under X and no row for Y.
    func testARefreshStoresASiblingKeyUnderTheAppOnceItsOwnerIsRead() async {
        let store = makeStore(), memory = PlatformDashConnectDataSource.OwnerMemory(), reader = Reader()
        let own = Self.key(10, on: Self.app)
        let keys = [own, Self.key(20, on: Self.sibling)]
        reader.failing = [Self.sibling]
        let before = await Self.refresh(store, keys, [Self.intent(own)], memory: memory, reader: reader)
        XCTAssertEqual(Set(before.keys), [Self.app, Self.sibling], "AC-05: an unread owner keeps its own row")
        reader.failing = []
        let after = await Self.refresh(store, keys, [Self.intent(own)], memory: memory, reader: reader)
        XCTAssertEqual(Set(after.keys), [Self.app], "AC-03: no row named by Y")
        XCTAssertEqual(after[Self.app]?.seenOn, [Self.identity.toBase58String()], "the key shows under X")
    }

    /// AC-06: a key of another owner stays on its own stored row, and X's
    /// disconnect never plans it.
    func testADisconnectNeverPlansAKeyOfAnotherOwnerAndItsRowStays() async {
        let store = makeStore(), memory = PlatformDashConnectDataSource.OwnerMemory(), reader = Reader()
        reader.owners = [Self.sibling: Data(repeating: 0x0B, count: 32)]
        let own = Self.key(10, on: Self.app), onW = Self.key(20, on: Self.sibling)
        await Self.refresh(store, [own, onW], [Self.intent(own)], memory: memory, reader: reader)
        let asked = await Self.planned([own, onW], [Self.intent(own)], listed: nil, memory: memory, reader: reader)
        XCTAssertEqual(asked.offered, [])
        let confirmed = await Self.planned([own, onW], [Self.intent(own)], listed: [20], memory: memory, reader: reader)
        XCTAssertEqual(confirmed.plan.disable, [10], "the key on W is never submitted")
        let after = await Self.refresh(store, [Self.disabled(own), onW], [Self.intent(own)], memory: memory, reader: reader)
        XCTAssertEqual(Set(after.keys), [Self.sibling], "W's row stays stored")
    }

    /// AC-10: after a fresh-restore refresh both rows are stored; a
    /// disconnect of one plans only its key, and the other row stays.
    func testWithoutAnIntentADisconnectOfOneRowTurnsOffOnlyItsKey() async {
        let store = makeStore(), memory = PlatformDashConnectDataSource.OwnerMemory(), reader = Reader()
        let onY = Self.key(20, on: Self.sibling), onY2 = Self.key(21, on: Self.sibling2)
        let rows = await Self.refresh(store, [onY, onY2], [], memory: memory, reader: reader)
        XCTAssertEqual(Set(rows.keys), [Self.sibling, Self.sibling2])
        let asked = await Self.planned([onY, onY2], [], listed: nil, memory: memory, reader: reader, appId: Self.sibling)
        XCTAssertEqual(asked.offered, [20])
        let confirmed = await Self.planned([onY, onY2], [], listed: asked.offered, memory: memory, reader: reader, appId: Self.sibling)
        XCTAssertEqual(confirmed.plan.disable, [20])
        let after = await Self.refresh(store, [Self.disabled(onY), onY2], [], memory: memory, reader: reader)
        XCTAssertEqual(Set(after.keys), [Self.sibling2])
        XCTAssertEqual(reader.total, 0, "no owner decides anything without an intent")
    }

    /// The row the user saw for Y because its owner could not be read: its
    /// disconnect still offers and turns off Y's key once the owner reads as
    /// X's.
    func testARowShownForAnUnreadOwnerStillTurnsOffItsKeyOnceTheOwnerIsRead() async {
        let store = makeStore(), memory = PlatformDashConnectDataSource.OwnerMemory(), reader = Reader()
        let own = Self.key(10, on: Self.app), onY = Self.key(20, on: Self.sibling)
        reader.failing = [Self.sibling]
        let shown = await Self.refresh(store, [own, onY], [Self.intent(own)], memory: memory, reader: reader)
        XCTAssertNotNil(shown[Self.sibling])
        reader.failing = []
        let readsAtRefresh = reader.total
        let asked = await Self.planned([own, onY], [Self.intent(own)], listed: nil, memory: memory, reader: reader, appId: Self.sibling)
        XCTAssertEqual(asked.offered, [20])
        let confirmed = await Self.planned(
            [own, onY], [Self.intent(own)], listed: asked.offered, memory: memory, reader: reader, appId: Self.sibling)
        XCTAssertEqual(confirmed.plan.disable, [20])
        XCTAssertEqual(confirmed.appKeysOff, 1)
        XCTAssertEqual(reader.total, readsAtRefresh, "no owner decides anything for a row with no intent")
    }

    /// What a disconnect reports from its plan: the offered keys only before
    /// the question, and every count as planned.
    func testTheDisconnectResultReportsThePlan() async {
        let own = Self.key(10, on: Self.app)
        let z = Self.intent(Self.key(11, on: Self.otherApp), app: Self.otherApp)
        let keys = [own, Self.key(20, on: Self.sibling), Self.key(21, on: Self.sibling2, boundKnown: false)]
        let reader = Reader()
        reader.owners = [Self.otherApp: Data(repeating: 0x0B, count: 32)]
        let asked = await Self.planned(keys, [Self.intent(own), z], listed: nil, reader: reader)
        XCTAssertEqual(
            PlatformDashConnectDataSource.disconnectResult(of: asked, remaining: asked, listed: nil, identityId: Self.identity, keysOnAnotherIdentity: true),
            DashConnectDisconnectResult(
                keysTurnedOff: 1, offeredUnrecordedKeys: DashConnectOfferedKeys(identityId: Self.identity, keyIds: [20]),
                keysNotChecked: 1, keysNotAttributable: 0,
                keysLeftAfterQuestion: 0, keysOnAnotherIdentity: true))
        let confirmed = await Self.planned(keys, [Self.intent(own), z], listed: [], reader: reader)
        XCTAssertEqual(
            PlatformDashConnectDataSource.disconnectResult(of: confirmed, remaining: confirmed, listed: [], identityId: Self.identity, keysOnAnotherIdentity: false),
            DashConnectDisconnectResult(
                keysTurnedOff: 1, offeredUnrecordedKeys: nil, keysNotChecked: 1, keysNotAttributable: 0,
                keysLeftAfterQuestion: 1, keysOnAnotherIdentity: false))
    }

    /// What stays on is told from the read after the update: a key of the
    /// app that first shows there is reported, before the question as
    /// offered and after it as left on, while the keys turned off are those
    /// the plan before the update turned off.
    func testAKeyFirstSeenOnTheReadAfterTheUpdateIsReportedAsStillOn() async {
        let own = Self.key(10, on: Self.app)
        let ownOff = Self.key(10, on: Self.app, disabledAt: 1)
        let listedOff = Self.key(20, on: Self.app, disabledAt: 1)
        let landed = Self.key(21, on: Self.app)
        let intents = [Self.intent(own)]

        let asked = await Self.planned([own], intents, listed: nil)
        let askedAfter = await Self.planned([ownOff, landed], intents, listed: nil)
        let first = PlatformDashConnectDataSource.disconnectResult(
            of: asked, remaining: askedAfter, listed: nil, identityId: Self.identity, keysOnAnotherIdentity: false)
        XCTAssertEqual(first.keysTurnedOff, 1)
        XCTAssertEqual(first.offeredUnrecordedKeys, DashConnectOfferedKeys(identityId: Self.identity, keyIds: [21]))

        let confirmed = await Self.planned([own, Self.key(20, on: Self.app)], intents, listed: [20])
        let confirmedAfter = await Self.planned([ownOff, listedOff, landed], intents, listed: [20])
        let second = PlatformDashConnectDataSource.disconnectResult(
            of: confirmed, remaining: confirmedAfter, listed: [20], identityId: Self.identity, keysOnAnotherIdentity: false)
        XCTAssertEqual(second.keysTurnedOff, 2, "the keys the update turned off")
        XCTAssertEqual(second.keysLeftAfterQuestion, 1, "AC-08: the key that landed during the update stays on and is said")
        XCTAssertNil(second.offeredUnrecordedKeys)
    }

    /// The rows and what stays on after a disconnect come from one read of
    /// the owners: whether the owner of a key on a sibling contract reads,
    /// does not, or fails once and then reads, a result that says a key of
    /// the app stays on keeps the app's row, and a key the rows give a row of
    /// its own is reported as not checked. The read here is also the one a
    /// disconnect with nothing to submit settles on.
    func testTheRowsAndWhatStaysOnAfterADisconnectComeFromTheSameOwners() async {
        let own = Self.key(10, on: Self.app), onY = Self.key(20, on: Self.sibling)
        let intents = [Self.intent(own)]
        let after = AppConnect.IdentitySnapshot(
            identityId: Self.identity, revision: 2, keys: [Self.disabled(own), onY], platformTime: nil)
        for (ownerReads, failsOnce) in [(false, false), (true, false), (false, true)] {
            let store = makeStore(), reader = Reader()
            reader.failing = [Self.sibling]
            await Self.refresh(store, [own, onY], intents, memory: .init(), reader: reader)
            reader.failing = ownerReads || failsOnce ? [] : [Self.sibling]
            reader.failingOnce = failsOnce ? [Self.sibling] : []
            let (change, remaining, _) = await PlatformDashConnectDataSource.settledDisconnect(
                appId: Self.app, after: after, intents: intents, unrecordedKeyIds: [],
                owners: Self.ownerReader(.init(), reader), at: Date(timeIntervalSince1970: 0))
            let rows = Set(change(store.load()).compactMap { Data.identifier(fromBase58: $0.id) })
            if ownerReads {
                XCTAssertEqual(remaining.leftAfterQuestion, 1, "the sibling key is the app's and stays on")
                XCTAssertTrue(rows.contains(Self.app), "the row a second disconnect needs is there")
            } else {
                XCTAssertEqual(remaining.leftAfterQuestion, 0, "nothing of the app is said to stay on")
                XCTAssertEqual(remaining.notChecked, 1, "the key with an unread owner is reported as not checked")
                XCTAssertEqual(rows, [Self.sibling], "the key keeps its own row")
            }
        }
    }

    /// A key the question listed that a failed owner read kept out of the
    /// update is still on: once the owner reads on the read after it, the
    /// result says so, as it does for a key found since the question.
    func testAListedKeyKeptOutOfTheUpdateIsReportedAsStillOn() async {
        let own = Self.key(10, on: Self.app), onY = Self.key(20, on: Self.sibling)
        let intents = [Self.intent(own)]
        let memory = PlatformDashConnectDataSource.OwnerMemory(), reader = Reader()
        reader.failing = [Self.sibling]
        let confirmed = await Self.planned([own, onY], intents, listed: [20], memory: memory, reader: reader)
        XCTAssertEqual(confirmed.plan.disable, [10], "the listed key is not submitted while its owner is unread")
        reader.failing = []
        let after = AppConnect.IdentitySnapshot(
            identityId: Self.identity, revision: 2, keys: [Self.disabled(own), onY], platformTime: nil)
        let (_, remaining, _) = await PlatformDashConnectDataSource.settledDisconnect(
            appId: Self.app, after: after, intents: intents, unrecordedKeyIds: [20],
            owners: Self.ownerReader(memory, reader), at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(remaining.leftAfterQuestion, 1, "the listed key that stayed on is reported")
    }

    /// A row with no intent whose owner reads on the read after its
    /// disconnect is gone, its keys now under the app of the same owner: a
    /// key that arrived after the question is reported under that app's row,
    /// the one the user can still disconnect.
    func testKeysLeftOnARowThatIsGoneAreReportedUnderTheRowThatShowsThem() async {
        let store = makeStore(), reader = Reader()
        let own = Self.key(10, on: Self.app), listed = Self.key(20, on: Self.sibling), arrived = Self.key(21, on: Self.sibling)
        let intents = [Self.intent(own)]
        reader.failing = [Self.sibling]
        let shown = await Self.refresh(store, [own, listed], intents, memory: .init(), reader: reader)
        XCTAssertNotNil(shown[Self.sibling], "an unread owner gives Y its own row")
        reader.failing = []
        let after = AppConnect.IdentitySnapshot(
            identityId: Self.identity, revision: 2, keys: [own, Self.disabled(listed), arrived], platformTime: nil)
        let (change, remaining, holder) = await PlatformDashConnectDataSource.settledDisconnect(
            appId: Self.sibling, after: after, intents: intents, unrecordedKeyIds: [20],
            owners: Self.ownerReader(.init(), reader), at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(remaining.leftAfterQuestion, 1, "the key that arrived after the question stays on")
        XCTAssertEqual(holder, Self.app)
        let rows = change(store.load())
        XCTAssertFalse(rows.contains { $0.id == Self.sibling.toBase58String() }, "Y's row is gone")
        let appRow = rows.first { $0.id == Self.app.toBase58String() }
        XCTAssertNotNil(appRow)
        XCTAssertEqual(
            PlatformDashConnectDataSource.keysLeftUnder(app: Self.sibling.toBase58String(), holder: holder, rows: rows), appRow?.name)
        XCTAssertNil(
            PlatformDashConnectDataSource.keysLeftUnder(app: Self.app.toBase58String(), holder: holder, rows: rows),
            "nil while the app's own row is there")
    }

    /// Keys left on can show under several rows: a DashPay profile key
    /// under DashPay's, the app's own under the app of the same owner. The
    /// user is sent to the row whose disconnect offers them all, the app's,
    /// since every disconnect also offers the profile keys; not to DashPay's,
    /// even when it sorts first.
    func testKeysLeftUnderSeveralRowsAreReportedUnderTheRowThatOffersThemAll() async {
        let store = makeStore(), reader = Reader()
        let holderApp = Data(repeating: 0xB1, count: 32)
        let dashPay = Data.identifier(fromBase58: AppConnect.dashPayContractId)!
        XCTAssertTrue(dashPay.lexicographicallyPrecedes(holderApp), "DashPay's row sorts first")
        let own = Self.key(10, on: holderApp), listed = Self.key(20, on: Self.sibling)
        let arrived = Self.key(21, on: Self.sibling)
        let profile = Self.key(30, on: dashPay, bound: .documentType(contractId: dashPay, name: "profile"))
        let intents = [Self.intent(own, app: holderApp)]
        reader.failing = [Self.sibling]
        let shown = await Self.refresh(store, [own, listed], intents, memory: .init(), reader: reader)
        XCTAssertNotNil(shown[Self.sibling], "an unread owner gives Y its own row")
        reader.failing = []
        let after = AppConnect.IdentitySnapshot(
            identityId: Self.identity, revision: 2, keys: [own, Self.disabled(listed), arrived, profile], platformTime: nil)
        let (change, remaining, holder) = await PlatformDashConnectDataSource.settledDisconnect(
            appId: Self.sibling, after: after, intents: intents, unrecordedKeyIds: [20],
            owners: Self.ownerReader(.init(), reader), at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(remaining.leftAfterQuestion, 2, "the key and the profile key that arrived after the question stay on")
        XCTAssertEqual(holder, holderApp)
        let rows = change(store.load())
        XCTAssertFalse(rows.contains { $0.id == Self.sibling.toBase58String() }, "Y's row is gone")
    }

    /// A key id is unique only within an identity: keys offered on one
    /// identity are never turned off while another is active, even when it
    /// has keys with the same ids. Checked before the PIN and after it.
    func testOfferedKeysOfAnotherIdentityAreRefusedEvenWithTheSameKeyIds() {
        let other = Data(repeating: 0x0E, count: 32)
        let offered = DashConnectOfferedKeys(identityId: Self.identity, keyIds: [20])
        XCTAssertNoThrow(try PlatformDashConnectDataSource.requireOffered(offered, on: Self.identity))
        XCTAssertNoThrow(try PlatformDashConnectDataSource.requireOffered(nil, on: other), "nothing offered, nothing to check")
        XCTAssertThrowsError(try PlatformDashConnectDataSource.requireOffered(offered, on: other)) { error in
            guard case DashConnectPlatformError.walletChanged = error else { return XCTFail("\(error)") }
        }
    }
}

/// The disconnect question and result on Connections, as DashUIKit's
/// `ModalDialog` (SCR-03, SCR-04).
@MainActor
final class ConnectionsMessageDialogTests: XCTestCase {
    private static let connection = MockDashConnectDataSource.sample(.active)

    /// SCR-03: «Leave them» above a destructive «Turn them off», which passes
    /// back exactly the offered keys.
    func testAQuestionOffersToTurnOffExactlyTheOfferedKeys() {
        var turnedOff: (DAppConnection, DashConnectOfferedKeys)?
        var dismissed = false
        let offered = DashConnectOfferedKeys(identityId: Data(repeating: 0x01, count: 32), keyIds: [20, 21])
        let message = ConnectionsScreenMessage(
            kind: .question, text: "Question.\n\nWarning.", unrecordedKeysOf: Self.connection, unrecordedKeys: offered)

        let dialog = ConnectionsMessageDialog.dialog(
            for: message, turnOff: { turnedOff = ($0, $1) }, dismiss: { dismissed = true })

        XCTAssertEqual(dialog.icon, .warning)
        XCTAssertEqual(dialog.heading, message.title)
        XCTAssertEqual(dialog.paragraphs, ["Question.", "Warning."])
        XCTAssertEqual(dialog.primaryAction.title, "Turn them off")
        XCTAssertEqual(dialog.primaryAction.role, .destructive)
        XCTAssertEqual(dialog.secondaryAction?.title, "Leave them")
        dialog.primaryAction.handler()
        XCTAssertEqual(turnedOff?.0, Self.connection)
        XCTAssertEqual(turnedOff?.1, offered)
        XCTAssertFalse(dismissed)
        dialog.secondaryAction?.handler()
        XCTAssertTrue(dismissed)
    }

    /// SCR-04: one «OK», which only dismisses.
    func testAResultHasOneOKButtonThatDismisses() {
        var dismissed = false
        let message = ConnectionsScreenMessage(kind: .warning, text: "Not checked.\n\nNot attributable.")

        let dialog = ConnectionsMessageDialog.dialog(
            for: message, turnOff: { _, _ in XCTFail("a result turns nothing off") }, dismiss: { dismissed = true })

        XCTAssertEqual(dialog.icon, .warning)
        XCTAssertEqual(dialog.heading, message.title)
        XCTAssertEqual(dialog.paragraphs, ["Not checked.", "Not attributable."])
        XCTAssertEqual(dialog.primaryAction.title, "OK")
        XCTAssertEqual(dialog.primaryAction.role, .regular)
        XCTAssertNil(dialog.secondaryAction)
        dialog.primaryAction.handler()
        XCTAssertTrue(dismissed)
    }
    /// Only a plain success comes without the warning icon: a token purchase
    /// that completed is no warning.
    func testTheIconFollowsTheKindOfTheMessage() {
        let icons = [ConnectionsScreenMessage.Kind.success, .warning, .error, .question].map { kind in
            ConnectionsMessageDialog.dialog(
                for: ConnectionsScreenMessage(kind: kind, text: "Text."), turnOff: { _, _ in }, dismiss: {}).icon
        }
        XCTAssertEqual(icons, [nil, .warning, .warning, .warning])
    }
}
