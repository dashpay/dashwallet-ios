import XCTest
@testable import dashpay

final class KeyExchangeCryptoTests: XCTestCase {
    private let sharedX = Data(hex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")!
    private let loginKey = Data(hex: "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f")!
    private let identityId = Data(hex: "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f")!
    private let walletEphemeralPriv = Data(repeating: 0x01, count: 32)
    private let appEphemeralPub = Data(hex: "031b84c5567b126440995d3ed5aaba0565d71e1834604819ff9c17f5e9d5dd078f")!
    private let fixedNonce = Data(hex: "101112131415161718191a1b")!
    private let kotlinAppPrivateKey = Data(repeating: 0x01, count: 32)
    private let kotlinWalletPrivateKey = Data(repeating: 0x02, count: 32)
    private let kotlinIdentityId = Data(repeating: 0xab, count: 32)
    private let kotlinContractId = Data(repeating: 0xcd, count: 32)
    private let kotlinFixedNonce = Data((0 ..< 12).map(UInt8.init))
    private let kotlinLoginKey = Data((0 ..< 32).map { UInt8(($0 * 7 + 3) & 0xff) })

    func testDeriveAesKeyMatchesVector() throws {
        let derived = try KeyExchangeCrypto.deriveAesKey(sharedX: sharedX)
        XCTAssertEqual(derived.hexEncodedString(), "0d14bc5a19d237e70d82bd357114307629c262c77fcde496d51dfeaa35d124c2")
    }

    func testEncryptLoginKeyWithFixedNonceMatchesVector() throws {
        let payload = try KeyExchangeCrypto.encryptLoginKey(
            loginKey,
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub,
            nonce: fixedNonce
        )

        XCTAssertEqual(payload.hexEncodedString(), "101112131415161718191a1b914189444d0fee69f81c2da90b6e1f451e003d9ef6196f231601d0dbd93c523969bcb8d144051b2b9badadb6e3a80fc8")
    }

    func testEncryptDecryptLoginKeyRoundTrips() throws {
        let payload = try KeyExchangeCrypto.encryptLoginKey(
            loginKey,
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub
        )
        let decrypted = try KeyExchangeCrypto.decryptLoginKey(
            payload,
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub
        )

        XCTAssertEqual(decrypted, loginKey)
    }

    func testPayloadHasExpectedLengthAndNoncePrefix() throws {
        let payload = try KeyExchangeCrypto.encryptLoginKey(
            loginKey,
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub,
            nonce: fixedNonce
        )

        XCTAssertEqual(payload.count, 60)
        XCTAssertEqual(payload.prefix(fixedNonce.count), fixedNonce)
    }

    func testDerivedIdentityKeysMatchVectorsAndDifferByInfo() throws {
        let auth = try KeyExchangeCrypto.deriveAuthPrivateKey(loginKey: loginKey, identityId: identityId)
        let encryption = try KeyExchangeCrypto.deriveEncryptionPrivateKey(loginKey: loginKey, identityId: identityId)

        XCTAssertEqual(auth.hexEncodedString(), "8b37cb699757243ca057a2d691ab43f88479f7422729eee270327a327d0c2bdc")
        XCTAssertEqual(encryption.hexEncodedString(), "3b658157640c41f675c6858794d4f184f55112c938715085470e056f2970cfa3")
        XCTAssertNotEqual(auth, encryption)
    }

    func testHash160MatchesKnownVector() {
        let input = Data(repeating: 0x00, count: 33)
        let hash = KeyExchangeCrypto.hash160(input)

        XCTAssertEqual(hash.hexEncodedString(), "29cfc6376255a78451eeb4b129ed8eacffa2feef")
    }

    func testKotlinHash160VectorMatchesExpectedHex() {
        let hash = KeyExchangeCrypto.hash160(Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(hash.hexEncodedString(), "9bc4860bb936abf262d7a51f74b4304833fee3b2")
    }

    func testKotlinAuthPrivateKeyVectorMatchesExpectedHex() throws {
        let auth = try KeyExchangeCrypto.deriveAuthPrivateKey(
            loginKey: kotlinLoginKey,
            identityId: kotlinIdentityId
        )

        XCTAssertEqual(auth.hexEncodedString(), "e06ee7ae45f257741dab7379793c854829b67171af111238c664d9fd90603706")
    }

    func testKotlinEncryptionPrivateKeyVectorMatchesExpectedHex() throws {
        let encryption = try KeyExchangeCrypto.deriveEncryptionPrivateKey(
            loginKey: kotlinLoginKey,
            identityId: kotlinIdentityId
        )

        XCTAssertEqual(encryption.hexEncodedString(), "6879c11819d1a60026adae34c296e83d13d06559ad63da41d03c44b203a90f80")
    }

    func testKotlinFixedNoncePayloadHasExpectedShapeAndRoundTrips() throws {
        let appEphemeralPub = try Secp256k1.compressedPublicKey(privateKey: kotlinAppPrivateKey)
        let payload = try KeyExchangeCrypto.encryptLoginKey(
            kotlinLoginKey,
            walletEphemeralPriv: kotlinWalletPrivateKey,
            appEphemeralPub: appEphemeralPub,
            nonce: kotlinFixedNonce
        )
        let decrypted = try KeyExchangeCrypto.decryptLoginKey(
            payload,
            walletEphemeralPriv: kotlinWalletPrivateKey,
            appEphemeralPub: appEphemeralPub
        )

        XCTAssertEqual(payload.count, 60)
        XCTAssertEqual(payload.prefix(kotlinFixedNonce.count), kotlinFixedNonce)
        XCTAssertEqual(decrypted, kotlinLoginKey)
        XCTAssertEqual(kotlinContractId.count, 32)
    }

    func testRejectsInvalidLoginKeyLength() {
        XCTAssertThrowsError(try KeyExchangeCrypto.encryptLoginKey(
            Data(repeating: 0x01, count: 31),
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub,
            nonce: fixedNonce
        ))
    }

    func testRejectsInvalidNonceLength() {
        XCTAssertThrowsError(try KeyExchangeCrypto.encryptLoginKey(
            loginKey,
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub,
            nonce: Data(repeating: 0x00, count: 11)
        ))
    }

    func testRejectsInvalidIdentityIdLength() {
        XCTAssertThrowsError(try KeyExchangeCrypto.deriveAuthPrivateKey(
            loginKey: loginKey,
            identityId: Data(repeating: 0x00, count: 31)
        ))
        XCTAssertThrowsError(try KeyExchangeCrypto.deriveEncryptionPrivateKey(
            loginKey: loginKey,
            identityId: Data(repeating: 0x00, count: 31)
        ))
    }

    func testRejectsInvalidPayloadLength() {
        XCTAssertThrowsError(try KeyExchangeCrypto.decryptLoginKey(
            Data(repeating: 0x00, count: 59),
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub
        ))
    }

    func testTamperedTagFailsToDecrypt() throws {
        var tampered = try KeyExchangeCrypto.encryptLoginKey(
            loginKey,
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub,
            nonce: fixedNonce
        )
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01

        XCTAssertThrowsError(try KeyExchangeCrypto.decryptLoginKey(
            tampered,
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub
        ))
    }
}
