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

    func testHash160MatchesKnownVector() throws {
        let input = Data(repeating: 0x00, count: 33)
        let hash = try KeyExchangeCrypto.hash160(input)

        XCTAssertEqual(hash.hexEncodedString(), "29cfc6376255a78451eeb4b129ed8eacffa2feef")
    }

    func testKotlinHash160VectorMatchesExpectedHex() throws {
        let hash = try KeyExchangeCrypto.hash160(Data([0x01, 0x02, 0x03]))
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

    // MARK: - App Connect v2 response

    /// Yappr's published vectors (`vendor/platform-auth/src/app-connect/vectors.json`).
    private enum AppConnectVector {
        static let appEphemeralPriv = Data(hex: "83adc3b5a48a1f3938969be4e3d674210d09aec8a2c2cb2b43b22972afca8682")!
        static let appEphemeralPub = Data(hex: "03e83cb927e85f96ae50a95ca3be21cc7a3755139a941b15d99b01af4fecf0d270")!
        static let appEphemeralPubKeyHash = Data(hex: "d77dc0da9df83a47755a15c42c5d9db9d7a7fd62")!
        static let ownerId = Data(hex: "9296d642338cb3bfceeb554285462719e15f004d0579ce53ea77fb6d86cd9ab9")!
        static let walletEphemeralPriv = Data(hex: "d1772740bcf476137df337bbe42122e82da08e11b632d6c3ff0d7281576e4127")!
        static let walletEphemeralPub = Data(hex: "02ee49ae562aa74ea28f95094da6800db9244b1addc1499439ffc7382cd7862d5a")!
        static let nonce = Data(hex: "22bb26ec9e0d316c4fb36be2")!
        static let slots = [
            Data(hex: "7df2f40f15e6079e514d7e5cb9cb1861b89986906ed820e158c3144272df9586")!,
            Data(hex: "3a992d9275d082af7540d1333a134ff0572c2bb79567437daa88dee55af1571f")!,
            Data(hex: "b37bb0ae8d6bbf01b38e843470570d5158d1939762a88673dd6cdf71bc144753")!,
        ]
        static let hkdfOutput = "b9837f16975f02d7c06df91441bbf3dad51ca7d65016178f34084247dd1b703f"
        static let aad = "646173683a6170702d636f6e6e6563743a7632d77dc0da9df83a47755a15c42c5d9db9d7a7fd629296d642338cb3bfceeb554285462719e15f004d0579ce53ea77fb6d86cd9ab9"
        static let encryptedPayload = "22bb26ec9e0d316c4fb36be20e3f2a358cce3609d09094351ce5e78f08e5253b0f9258616374753411c97faecb1fbde336c01d7f08380095a0a7ffe3fe207f80e92a7adb7bd8731dffe3b96a6b2c363aa1302c4e82d60f75419aa1f6f3ac5522453f2b761495fb3b7816ea8bfe66a210e14fdad8b7f7c15ffb3ef39b"
    }

    func testAppConnectKeyAndAssociatedDataMatchThePublishedVector() throws {
        XCTAssertEqual(try KeyExchangeCrypto.hash160(AppConnectVector.appEphemeralPub), AppConnectVector.appEphemeralPubKeyHash)
        XCTAssertEqual(
            try Secp256k1.compressedPublicKey(privateKey: AppConnectVector.walletEphemeralPriv),
            AppConnectVector.walletEphemeralPub)

        let sharedX = try Secp256k1.ecdhSharedX(
            privateKey: AppConnectVector.walletEphemeralPriv,
            publicKey: AppConnectVector.appEphemeralPub)
        XCTAssertEqual(try KeyExchangeCrypto.deriveAppConnectAesKey(sharedX: sharedX).hexEncodedString(), AppConnectVector.hkdfOutput)
        // The legacy exchange derives another key from the same secret.
        XCTAssertNotEqual(try KeyExchangeCrypto.deriveAesKey(sharedX: sharedX).hexEncodedString(), AppConnectVector.hkdfOutput)

        XCTAssertEqual(
            try KeyExchangeCrypto.appConnectAssociatedData(
                appEphemeralPubKeyHash: AppConnectVector.appEphemeralPubKeyHash,
                ownerId: AppConnectVector.ownerId).hexEncodedString(),
            AppConnectVector.aad)
    }

    func testAppConnectPayloadMatchesThePublishedVector() throws {
        let payload = try KeyExchangeCrypto.encryptAppConnectSlots(
            AppConnectVector.slots,
            walletEphemeralPriv: AppConnectVector.walletEphemeralPriv,
            appEphemeralPub: AppConnectVector.appEphemeralPub,
            ownerId: AppConnectVector.ownerId,
            nonce: AppConnectVector.nonce)

        XCTAssertEqual(payload.hexEncodedString(), AppConnectVector.encryptedPayload)
        XCTAssertEqual(payload.count, 28 + 32 * 3)
    }

    func testAppConnectPayloadOpensForTheAppAndOnlyUnderTheSameIdentity() throws {
        let payload = try KeyExchangeCrypto.encryptAppConnectSlots(
            AppConnectVector.slots,
            walletEphemeralPriv: AppConnectVector.walletEphemeralPriv,
            appEphemeralPub: AppConnectVector.appEphemeralPub,
            ownerId: AppConnectVector.ownerId)

        XCTAssertNotEqual(payload.prefix(12), AppConnectVector.nonce)
        XCTAssertEqual(
            try KeyExchangeCrypto.decryptAppConnectSlots(
                payload,
                appEphemeralPriv: AppConnectVector.appEphemeralPriv,
                walletEphemeralPub: AppConnectVector.walletEphemeralPub,
                ownerId: AppConnectVector.ownerId),
            AppConnectVector.slots)
        // Copied under another identity it does not open.
        XCTAssertThrowsError(try KeyExchangeCrypto.decryptAppConnectSlots(
            payload,
            appEphemeralPriv: AppConnectVector.appEphemeralPriv,
            walletEphemeralPub: AppConnectVector.walletEphemeralPub,
            ownerId: Data(repeating: 0x01, count: 32)))
    }

    func testAppConnectPayloadTakesOneToSeventeenKeysOf32Bytes() throws {
        let slot = AppConnectVector.slots[0]
        func encrypt(_ slots: [Data], ownerId: Data = AppConnectVector.ownerId) throws -> Data {
            try KeyExchangeCrypto.encryptAppConnectSlots(
                slots,
                walletEphemeralPriv: AppConnectVector.walletEphemeralPriv,
                appEphemeralPub: AppConnectVector.appEphemeralPub,
                ownerId: ownerId)
        }

        XCTAssertEqual(try encrypt([slot]).count, 60)
        XCTAssertEqual(try encrypt(Array(repeating: slot, count: 17)).count, 572)
        XCTAssertThrowsError(try encrypt([]))
        XCTAssertThrowsError(try encrypt(Array(repeating: slot, count: 18)))
        XCTAssertThrowsError(try encrypt([slot.dropLast()]))
        XCTAssertThrowsError(try encrypt([slot], ownerId: Data(repeating: 1, count: 31)))
    }
}
