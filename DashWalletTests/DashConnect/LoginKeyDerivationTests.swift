import XCTest
@testable import dashpay

final class LoginKeyDerivationTests: XCTestCase {
    private let chainKey = Data(hex: "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f")!
    private let identityId = Data(hex: "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f")!
    private let appContractId = Data(hex: "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")!

    func testDefaultKeyIndexIsZero() {
        XCTAssertEqual(LoginKeyDerivation.defaultKeyIndex, 0)
    }

    func testDeriveLoginKeyMatchesVector() throws {
        let loginKey = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        XCTAssertEqual(loginKey.hexEncodedString(), "0c6ee8098b3618e2cebe7a5fb4a5b3307eb84f410262489fedc386eca0cd882d")
    }

    func testDeriveLoginKeyIsDeterministic() throws {
        let first = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )
        let second = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )

        XCTAssertEqual(first, second)
    }

    func testDeriveLoginKeyChangesWhenAnyInputChanges() throws {
        let baseline = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: appContractId
        )
        let differentChainKey = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: Data(hex: "616162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f")!,
            identityId: identityId,
            appContractId: appContractId
        )
        let differentIdentity = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: Data(hex: "414142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f")!,
            appContractId: appContractId
        )
        let differentContract = try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: Data(hex: "818182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")!
        )

        XCTAssertNotEqual(baseline, differentChainKey)
        XCTAssertNotEqual(baseline, differentIdentity)
        XCTAssertNotEqual(baseline, differentContract)
    }

    func testRejectsInvalidLengths() {
        XCTAssertThrowsError(try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: Data(repeating: 0x00, count: 31),
            identityId: identityId,
            appContractId: appContractId
        ))
        XCTAssertThrowsError(try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: Data(repeating: 0x00, count: 31),
            appContractId: appContractId
        ))
        XCTAssertThrowsError(try LoginKeyDerivation.deriveLoginKey(
            chainKeyPrivateBytes: chainKey,
            identityId: identityId,
            appContractId: Data(repeating: 0x00, count: 31)
        ))
    }
}
