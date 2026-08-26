import XCTest
@testable import dashpay

final class DashConnectDataSourceTests: XCTestCase {
    private let appPrivateKey = Data(repeating: 0x01, count: 32)
    private let contractId = Data(repeating: 0xcd, count: 32)
    private let label = "Login to Yappr"

    func testParseQRRoutesValidDashKeyUriToLoginRequest() async throws {
        let dataSource = MockDashConnectDataSource()

        let result = try await dataSource.parseQR(try validKeyUri())

        guard case let .login(request) = result else {
            return XCTFail("Expected a login request")
        }

        XCTAssertEqual(request.contractId, contractId)
        XCTAssertEqual(request.label, label)
        XCTAssertEqual(request.network, .testnet)
    }

    func testParseQRRoutesValidDashStUriToKeyRegistration() async throws {
        let dataSource = MockDashConnectDataSource()

        let result = try await dataSource.parseQR(validStUri())

        guard case let .keyRegistration(request) = result else {
            return XCTFail("Expected a key registration request")
        }

        XCTAssertEqual(request.transitionBytes, Data([0x01, 0x02, 0x03, 0x04]))
        XCTAssertEqual(request.network, .testnet)
    }

    func testParseQRRejectsJunkPayloads() async {
        let dataSource = MockDashConnectDataSource()
        let invalidPayloads = [
            "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kg3g4ty",
            "hello world",
            "",
        ]

        for payload in invalidPayloads {
            await XCTAssertThrowsErrorAsync({
                try await dataSource.parseQR(payload)
            }) { error in
                XCTAssertEqual(error as? DashConnectMockError, .notDashConnectQrCode)
            }
        }
    }

    func testParseQRRejectsWrongNetwork() async throws {
        let dataSource = MockDashConnectDataSource(supportedNetwork: .testnet)
        // Built outside the asserted closure: a fixture failure must not be
        // mistaken for the rejection this test is asserting.
        let uri = try validKeyUri(network: .mainnet)

        await XCTAssertThrowsErrorAsync({
            try await dataSource.parseQR(uri)
        }) { error in
            XCTAssertEqual(
                error as? DashConnectMockError,
                .unsupportedNetwork(expected: .testnet, actual: .mainnet)
            )
        }
    }

    func testParseQRToleratesLeadingAndTrailingWhitespace() async throws {
        let dataSource = MockDashConnectDataSource()

        let result = try await dataSource.parseQR("  \n\(try validKeyUri())\n\t ")

        guard case let .login(request) = result else {
            return XCTFail("Expected a login request")
        }

        XCTAssertEqual(request.contractId, contractId)
    }

    func testCompleteKeyRegistrationThrowsOnMock() async throws {
        let dataSource = MockDashConnectDataSource()

        await XCTAssertThrowsErrorAsync({
            try await dataSource.completeKeyRegistration(.init(
                transitionBytes: Data([0x01, 0x02, 0x03, 0x04]),
                network: .testnet
            ))
        }) { error in
            XCTAssertEqual(error as? DashConnectMockError, .keyRegistrationNotSupported)
        }
    }

    func testMakeConnectionRequestCarriesExistingConnectionForMatchingContract() async {
        let existing = MockDashConnectDataSource.sample(.active)
        let dataSource = MockDashConnectDataSource(initial: [existing])

        let request = await dataSource.makeConnectionRequest(from: MockDashConnectDataSource.sampleLoginRequest)

        XCTAssertEqual(request.existingConnection, existing)
    }

    func testMakeConnectionRequestCarriesApprovedConnection() async {
        let existing = MockDashConnectDataSource.sample(.approved)
        let dataSource = MockDashConnectDataSource(initial: [existing])

        let request = await dataSource.makeConnectionRequest(from: MockDashConnectDataSource.sampleLoginRequest)

        XCTAssertEqual(request.existingConnection, existing)
    }

    func testApprovingSameAppTwiceReplacesExistingRow() async throws {
        // Captured relative to now rather than hard-coded: a fixed 2026 date
        // makes the assertion fail on any machine whose clock is set earlier.
        let initialDate = Date().addingTimeInterval(-60)
        let existing = DAppConnection(
            id: MockDashConnectDataSource.sample(.approved).id,
            name: "Yappr",
            url: "yap.pr",
            status: .approved,
            updatedAt: initialDate
        )
        let dataSource = MockDashConnectDataSource(initial: [existing])

        _ = try await dataSource.approveLogin(MockDashConnectDataSource.sampleLoginRequest)

        XCTAssertEqual(dataSource.connectionsSnapshot.count, 1)
        XCTAssertEqual(dataSource.connectionsSnapshot.first?.id, existing.id)
        XCTAssertTrue((dataSource.connectionsSnapshot.first?.updatedAt ?? .distantPast) > initialDate)
    }

    private func validKeyUri(network: DashConnectNetwork = .testnet) throws -> String {
        let labelData = Data(label.utf8)
        let payload = data([
            Data([0x01]),
            try validEphemeralPublicKey(),
            contractId,
            Data([UInt8(labelData.count)]),
            labelData,
        ])
        return "dash-key:\(base58Encode(payload))?n=\(network.rawValue)&v=1"
    }

    private func validStUri(network: DashConnectNetwork = .testnet) -> String {
        "dash-st:\(base58Encode(Data([0x01, 0x02, 0x03, 0x04])))?n=\(network.rawValue)&v=1"
    }

    private func validEphemeralPublicKey() throws -> Data {
        try Secp256k1.compressedPublicKey(privateKey: appPrivateKey)
    }

    private func base58Encode(_ data: Data) -> String {
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

    private func data(_ chunks: [Data]) -> Data {
        var result = Data()
        for chunk in chunks {
            result.append(chunk)
        }
        return result
    }

    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: () async throws -> T,
        _ handler: (Error) -> Void
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error to be thrown")
        } catch {
            handler(error)
        }
    }
}

// MARK: - Branding is keyed on the contract id, not the spoofable label

extension DashConnectDataSourceTests {
    /// Yappr's data contract on testnet, taken from a real login QR.
    private static let yapprContractId = Data([
        0xc8, 0xb1, 0x02, 0xb5, 0x6e, 0xa7, 0xbb, 0xac,
        0xf7, 0x72, 0xd8, 0x36, 0x23, 0xf8, 0xd1, 0x8c,
        0x53, 0xae, 0xf2, 0x07, 0x66, 0x59, 0x9a, 0xc6,
        0x82, 0xb6, 0xa0, 0x19, 0xf2, 0x9d, 0x35, 0x3e
    ])

    private func makeLoginRequest(contractId: Data, label: String) throws -> DashKeyRequest {
        DashKeyRequest(
            appEphemeralPubKey: try Secp256k1.compressedPublicKey(privateKey: Data(repeating: 0x01, count: 32)),
            contractId: contractId,
            label: label,
            network: .testnet
        )
    }

    /// A QR may claim any label it likes. Branding must follow the contract id, otherwise
    /// an attacker's contract renders with Yappr's name and website.
    func testBrandingIgnoresSpoofedLabelOnUnknownContract() throws {
        let request = try makeLoginRequest(
            contractId: Data(repeating: 0x11, count: 32),
            label: "Login to Yappr"
        )

        let connectionRequest = ConnectionRequest(loginRequest: request)

        XCTAssertEqual(connectionRequest.appLabel, "Login to Yappr")
        XCTAssertEqual(
            connectionRequest.appUrl,
            "",
            "An unknown contract must not borrow a known app's website."
        )
    }

    /// The real Yappr contract resolves to its branding whatever the label says.
    func testBrandingResolvesKnownContractRegardlessOfLabel() throws {
        let request = try makeLoginRequest(
            contractId: Self.yapprContractId,
            label: "anything at all"
        )

        let connectionRequest = ConnectionRequest(loginRequest: request)

        XCTAssertEqual(connectionRequest.appContractId, "EWR695MsqPUuW8EnTbYzD4KybNQD5n7CUDWydJYNg63F")
        XCTAssertEqual(connectionRequest.appLabel, "Yappr")
        XCTAssertEqual(connectionRequest.appUrl, "yap.pr")
    }
}
