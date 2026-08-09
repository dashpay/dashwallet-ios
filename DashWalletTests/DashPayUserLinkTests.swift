//
//  DashPayUserLinkTests.swift
//  DashWalletTests
//
//  Pure-parsing tests for the `dashpay://user` QR payload codec.
//

import Foundation
import XCTest
@testable import dashwallet

final class DashPayUserLinkTests: XCTestCase {

    /// Any 32 bytes round-trip through base58 in the QR URI.
    private let identityId = Data((0..<32).map { UInt8($0 &* 7 &+ 3) })

    func testEncodeParseRoundTrip() {
        let link = DashPayUserLink(identityId: identityId, username: "alice")
        let parsed = DashPayUserLink.parse(link.uriString)
        XCTAssertEqual(parsed, link)
    }

    func testParseStripsDashSuffixAndWhitespace() {
        let base58 = identityId.toBase58String()
        let parsed = DashPayUserLink.parse("  dashpay://user?id=\(base58)&username=alice.dash\n")
        XCTAssertEqual(parsed?.username, "alice")
        XCTAssertEqual(parsed?.identityId, identityId)
    }

    func testParseIsCaseInsensitiveOnSchemeHostAndParamNames() {
        let base58 = identityId.toBase58String()
        let parsed = DashPayUserLink.parse("DASHPAY://USER?ID=\(base58)&USERNAME=alice")
        XCTAssertEqual(parsed?.username, "alice")
    }

    func testParseRejectsForeignPayloads() {
        let base58 = identityId.toBase58String()
        XCTAssertNil(DashPayUserLink.parse("dash:XoyzY6j9wkYp1yPe9GHmBdqSwSCmDHb2y7?amount=1"))
        XCTAssertNil(DashPayUserLink.parse("dashpay://invite?du=alice&cftx=abc"))
        XCTAssertNil(DashPayUserLink.parse("alice"))
        XCTAssertNil(DashPayUserLink.parse(""))
        // Missing either parameter.
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?id=\(base58)"))
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?username=alice"))
        // `.dash`-only label collapses to empty.
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?id=\(base58)&username=.dash"))
    }

    func testParseRejectsNonCanonicalURIShapes() {
        let base58 = identityId.toBase58String()
        let canonicalQuery = "id=\(base58)&username=alice"
        // Userinfo, port, path, and fragment are not part of the wire
        // contract.
        XCTAssertNil(DashPayUserLink.parse("dashpay://someone@user?\(canonicalQuery)"))
        XCTAssertNil(DashPayUserLink.parse("dashpay://someone:secret@user?\(canonicalQuery)"))
        XCTAssertNil(DashPayUserLink.parse("dashpay://user:1234?\(canonicalQuery)"))
        XCTAssertNil(DashPayUserLink.parse("dashpay://user/profile?\(canonicalQuery)"))
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?\(canonicalQuery)#fragment"))
        // Each parameter exactly once, and nothing but id + username.
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?\(canonicalQuery)&id=\(base58)"))
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?\(canonicalQuery)&username=bob"))
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?id=invalid&ID=\(base58)&username=alice"))
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?\(canonicalQuery)&amount=1"))
    }

    func testParseRejectsInvalidIdentityIds() {
        // Base58 alphabet excludes 0, O, I, l.
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?id=0OIl&username=alice"))
        // Valid base58 but not 32 bytes.
        let short = Data([1, 2, 3]).toBase58String()
        XCTAssertNil(DashPayUserLink.parse("dashpay://user?id=\(short)&username=alice"))
    }
}
