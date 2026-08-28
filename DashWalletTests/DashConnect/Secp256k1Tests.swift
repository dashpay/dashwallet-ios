import XCTest
@testable import dashpay

final class Secp256k1Tests: XCTestCase {
    private enum CandidateError: Error {
        case notFound
    }

    private let expectedPublicKeyA = Data(hex: "031b84c5567b126440995d3ed5aaba0565d71e1834604819ff9c17f5e9d5dd078f")!

    func testCompressedPublicKeyMatchesExpectedHex() throws {
        let publicKey = try Secp256k1.compressedPublicKey(privateKey: privateKeyA)
        XCTAssertEqual(publicKey, expectedPublicKeyA)
    }

    func testIsValidCompressedPointAcceptsKnownGoodPointAndRejectsMalformedInputs() {
        XCTAssertTrue(Secp256k1.isValidCompressedPoint(expectedPublicKeyA))
        XCTAssertFalse(Secp256k1.isValidCompressedPoint(Data(expectedPublicKeyA.dropLast())))
        XCTAssertFalse(Secp256k1.isValidCompressedPoint(appending(expectedPublicKeyA, Data([0x00]))))
        XCTAssertFalse(Secp256k1.isValidCompressedPoint(appending(Data([0x04]), Data(expectedPublicKeyA.dropFirst()))))
        XCTAssertFalse(Secp256k1.isValidCompressedPoint(appending(Data([0x02]), Data(repeating: 0x00, count: 32))))
    }

    func testECDHIsSymmetric() throws {
        let publicKeyA = try Secp256k1.compressedPublicKey(privateKey: privateKeyA)
        let publicKeyB = try Secp256k1.compressedPublicKey(privateKey: privateKeyB)

        let sharedAB = try Secp256k1.ecdhSharedX(privateKey: privateKeyA, publicKey: publicKeyB)
        let sharedBA = try Secp256k1.ecdhSharedX(privateKey: privateKeyB, publicKey: publicKeyA)

        XCTAssertEqual(sharedAB, sharedBA)
        XCTAssertEqual(sharedAB.count, 32)
    }

    func testECDHSharedXStaysLeftPaddedTo32Bytes() throws {
        let candidate = try findLeadingZeroSharedXCandidate()
        let shared = try Secp256k1.ecdhSharedX(
            privateKey: candidate.privateKey,
            publicKey: candidate.publicKey
        )

        XCTAssertEqual(shared.count, 32)
        XCTAssertEqual(shared.first, 0x00)
    }

    private func findLeadingZeroSharedXCandidate() throws -> (privateKey: Data, publicKey: Data) {
        for a in UInt16(1)...UInt16(128) {
            let privateKeyA = makePrivateKey(a)
            let publicKeyA = try Secp256k1.compressedPublicKey(privateKey: privateKeyA)

            for b in UInt16(129)...UInt16(256) {
                let privateKeyB = makePrivateKey(b)
                let publicKeyB = try Secp256k1.compressedPublicKey(privateKey: privateKeyB)
                let sharedAB = try Secp256k1.ecdhSharedX(privateKey: privateKeyA, publicKey: publicKeyB)
                let sharedBA = try Secp256k1.ecdhSharedX(privateKey: privateKeyB, publicKey: publicKeyA)

                if sharedAB.first == 0x00 {
                    XCTAssertEqual(sharedAB, sharedBA)
                    return (privateKeyA, publicKeyB)
                }
            }
        }

        XCTFail("Expected to find a deterministic ECDH pair whose shared X starts with 0x00.")
        throw CandidateError.notFound
    }

    private var privateKeyA: Data {
        Data(repeating: 0x01, count: 32)
    }

    private var privateKeyB: Data {
        Data(repeating: 0x02, count: 32)
    }

    private func makePrivateKey(_ value: UInt16) -> Data {
        var bytes = Data(repeating: 0x00, count: 32)
        bytes[30] = UInt8(value >> 8)
        bytes[31] = UInt8(value & 0xff)
        return bytes
    }

    private func appending(_ lhs: Data, _ rhs: Data) -> Data {
        var result = lhs
        result.append(rhs)
        return result
    }
}
