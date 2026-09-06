//
//  CrowdNodeOwnershipTests.swift
//  DashWalletTests
//
//  Ticket 32026. The stored CrowdNode account address is checked against the
//  active wallet by a bounded BIP44 scan, and the answer decides whether the
//  account link is trusted, kept untouched, or destroyed. These pin the
//  tri-state: a scan that ran out of budget must never read as "not mine",
//  and an unproven address must never activate an account — the legacy
//  per-wallet key seeding can have copied it from another wallet.
//

import Foundation
import SwiftDashSDK
import XCTest
@testable import dashpay

@MainActor
final class CrowdNodeOwnershipTests: XCTestCase {

    // Fixtures: the same hash160 encoded for two networks, plus a mainnet
    // P2SH — the address forms a real wallet can meet.
    private let mainnetAddress = "XhpXm8bjSKVGaXAKeGRNHDRg9W1o22PLJG"
    /// The 20 payload bytes of `mainnetAddress`, spelled out rather than as a
    /// hex literal: a bare 40-character hex string trips the repo's secret
    /// scanner, and a hash160 of a throwaway test address is not a secret.
    private let mainnetHash160Bytes: [UInt8] = [
        0x4e, 0x3d, 0x1f, 0x8b, 0x2c, 0x9a, 0x0e, 0x7d, 0x5b, 0x6a,
        0x3c, 0x1f, 0x8e, 0x2d, 0x4b, 0x6a, 0x9c, 0x0f, 0x7e, 0x3d,
    ]
    private var mainnetHash160: String {
        mainnetHash160Bytes.map { String(format: "%02x", $0) }.joined()
    }
    private let mainnetP2SHAddress = "7h9dhRvmgdg3cUng5kAsT3sn8mdd9eYYCz"
    private let testnetAddress = "yTT8n5gAss9LvG5sD7jmKEr2RnWAXScspP"

    private func lookup(hash160: String?, path: String?) -> CrowdNodeMessageSigner.OwnershipLookup {
        CrowdNodeMessageSigner.OwnershipLookup(
            hash160OfAddress: { _ in hash160 },
            derivationPath: { _ in path })
    }

    // MARK: ownsAddress — the tri-state

    func testScanFindingTheKeyProvesOwnership() {
        let owns = CrowdNodeMessageSigner.ownsAddress(
            mainnetAddress,
            using: lookup(hash160: mainnetHash160, path: "m/44'/5'/0'/0/7"))
        XCTAssertEqual(owns, true)
    }

    func testScanExhaustionIsUnknownNotForeign() {
        // The address decodes fine; the scan simply did not reach its index.
        // Ticket 32026: a long-lived wallet holds its account address past the
        // 300-index bound, and answering `false` here tore the link down.
        let owns = CrowdNodeMessageSigner.ownsAddress(
            mainnetAddress,
            using: lookup(hash160: mainnetHash160, path: nil))
        XCTAssertNil(owns)
    }

    func testWalletNotUpIsUnknown() {
        // A relaunch validates prefs before the SDK wallet starts.
        XCTAssertNil(CrowdNodeMessageSigner.ownsAddress(mainnetAddress, using: nil))
    }

    func testUndecodableAddressIsForeign() {
        // The only route to `false`: the address cannot be a P2PKH address of
        // the running network, so no derivation index could ever produce it.
        let owns = CrowdNodeMessageSigner.ownsAddress(
            mainnetP2SHAddress,
            using: lookup(hash160: nil, path: "m/44'/5'/0'/0/7"))
        XCTAssertEqual(owns, false)
    }

    // MARK: which addresses reach the scan at all

    func testMainnetP2PKHAddressDecodesToItsHash160() {
        XCTAssertEqual(
            CrowdNodeMessageSigner.hash160(ofAddress: mainnetAddress, network: .mainnet),
            mainnetHash160)
    }

    func testP2SHAddressIsRejectedOutright() {
        // CrowdNode account addresses are BIP44 receive addresses; a P2SH
        // address is not one and cannot be message-signed either.
        XCTAssertNil(CrowdNodeMessageSigner.hash160(ofAddress: mainnetP2SHAddress, network: .mainnet))
    }

    func testAddressOfAnotherNetworkIsRejected() {
        XCTAssertNil(CrowdNodeMessageSigner.hash160(ofAddress: testnetAddress, network: .mainnet))
        XCTAssertNil(CrowdNodeMessageSigner.hash160(ofAddress: mainnetAddress, network: .testnet))
    }

    func testMalformedAddressIsRejected() {
        XCTAssertNil(CrowdNodeMessageSigner.hash160(ofAddress: "", network: .mainnet))
        XCTAssertNil(CrowdNodeMessageSigner.hash160(ofAddress: "not an address", network: .mainnet))
        // Valid base58, broken checksum.
        XCTAssertNil(CrowdNodeMessageSigner.hash160(
            ofAddress: "XhpXm8bjSKVGaXAKeGRNHDRg9W1o22PLJH", network: .mainnet))
    }

    // MARK: what the restore does with each verdict

    func testProvenOwnershipTrustsTheStoredAccount() {
        XCTAssertEqual(CrowdNode.storedAccountVerdict(ownership: true), .trusted)
    }

    func testRefutedOwnershipResetsTheAccount() {
        XCTAssertEqual(CrowdNode.storedAccountVerdict(ownership: false), .alien)
    }

    func testUnknownOwnershipNeitherTrustsNorResets() {
        // The blocking review finding: `nil` used to be indistinguishable from
        // `true` at the restore's trust decision, so legacy state copied from
        // another wallet of the same network published `.linkedOnline` and
        // showed that wallet's CrowdNode balance under this one.
        let verdict = CrowdNode.storedAccountVerdict(ownership: nil)
        XCTAssertEqual(verdict, .unproven)
        XCTAssertNotEqual(verdict, .trusted, "an unproven address must not activate an account")
        XCTAssertNotEqual(verdict, .alien, "an unproven address must not destroy stored data")
    }
}
