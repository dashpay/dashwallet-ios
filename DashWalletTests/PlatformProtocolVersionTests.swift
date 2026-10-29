//
//  PlatformProtocolVersionTests.swift
//  DashWalletTests
//
//  The Platform protocol version `SwiftDashSDKHost` builds the SDK with, per
//  network.
//
//  Zero enables SDK auto-detection; verified network responses determine the
//  effective version. Live proof verification is covered by integration tests.
//

import XCTest
import SwiftDashSDK
@testable import dashpay

@MainActor
final class PlatformProtocolVersionTests: XCTestCase {
    /// All supported networks follow verified protocol upgrades without an app pin.
    /// Regtest is omitted because `makeRuntime` rejects it.
    func testPlatformVersionPerNetwork() {
        let expected: [Network: UInt32] = [
            .mainnet: 0,
            .testnet: 0,
            .devnet: 0,
        ]
        for (network, version) in expected {
            XCTAssertEqual(SwiftDashSDKHost.platformVersion(for: network), version, "\(network)")
        }
    }
}
