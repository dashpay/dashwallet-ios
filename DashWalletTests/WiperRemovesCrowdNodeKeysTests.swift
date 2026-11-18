//
//  WiperRemovesCrowdNodeKeysTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//

import XCTest
@testable import dashpay

/// The wiper's own calls, against `UserDefaults.standard` where the old
/// code wrote the keys (AC-11).
@MainActor
final class WiperRemovesCrowdNodeKeysTests: XCTestCase {
    private let drainDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WiperRemovesCrowdNodeKeysTests.\(UUID().uuidString)")
    private var writtenKeys: [String] = []

    override func tearDown() {
        for key in writtenKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        writtenKeys = []
        try? FileManager.default.removeItem(at: drainDirectory)
        super.tearDown()
    }

    /// Hex digits a-f in the id prove the wiper writes the suffix in
    /// lowercase, as the old code did.
    private func makeWalletId() -> Data {
        Data([0xab, 0xcd, 0xef]) + Data((0..<29).map { _ in UInt8.random(in: 0...255) })
    }

    private func hex(_ walletId: Data) -> String {
        walletId.map { String(format: "%02x", $0) }.joined()
    }

    private func write(_ keys: [String]) {
        for key in keys {
            UserDefaults.standard.set(1, forKey: key)
        }
        writtenKeys += keys
    }

    func testDeletingAWalletRemovesItsPerWalletKeys() throws {
        let deleted = makeWalletId()
        let other = makeWalletId()
        let removed = RetiredCrowdNodeDefaults.perWalletKeys.map { "\($0)_\(hex(deleted))" }
        let kept = RetiredCrowdNodeDefaults.perWalletKeys.map { "\($0)_\(hex(other))" }
        write(removed + kept)

        try SwiftDashSDKWalletWiper.deleteWalletFromSDK(
            deleted,
            deleteWallet: { _ in },
            scope: "testnet",
            drainStore: CoreShieldedDrainFileStore(directory: drainDirectory))

        for key in removed {
            XCTAssertNil(UserDefaults.standard.object(forKey: key), key)
        }
        for key in kept {
            XCTAssertNotNil(UserDefaults.standard.object(forKey: key), key)
        }
    }

    func testFullWipeStepRemovesEveryCrowdNodeKey() {
        let walletKeys = RetiredCrowdNodeDefaults.perWalletKeys.map { "\($0)_\(hex(makeWalletId()))" }
        let keys = RetiredCrowdNodeDefaults.globalKeys + RetiredCrowdNodeDefaults.perWalletKeys + walletKeys
        write(keys)

        SwiftDashSDKWalletWiper.resetUserDefaultsStoresForWipe()

        for key in keys {
            XCTAssertNil(UserDefaults.standard.object(forKey: key), key)
        }
    }
}
