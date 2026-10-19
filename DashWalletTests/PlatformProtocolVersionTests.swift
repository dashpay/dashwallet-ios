//
//  PlatformProtocolVersionTests.swift
//  DashWalletTests
//
//  The Platform protocol version `SwiftDashSDKHost` builds the SDK with, per
//  network.
//
//  These pin the per-network choice only. Whether the linked SDK's protocol 14
//  is the one testnet runs depends on the platform commit it was built from
//  (`.platform-ref` in CI, the sibling `../platform` checkout locally), which
//  no app-side test can observe.
//

import XCTest
import SwiftDashSDK
@testable import dashpay

@MainActor
final class PlatformProtocolVersionTests: XCTestCase {
    /// A change here is deliberate: bump testnet together with the pin when
    /// testnet activates a new protocol. `0` is auto-detect. Regtest is left
    /// out: `makeRuntime` rejects it, so its value is never used.
    func testPlatformVersionPerNetwork() {
        let expected: [Network: UInt32] = [
            .mainnet: 0,
            .testnet: 14,
            .devnet: 0,
        ]
        for (network, version) in expected {
            XCTAssertEqual(SwiftDashSDKHost.platformVersion(for: network), version, "\(network)")
        }
    }
}
