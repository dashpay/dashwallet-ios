//
//  PlatformProtocolVersionTests.swift
//  DashWalletTests
//
//  The Platform protocol version `SwiftDashSDKHost` builds the SDK with, per
//  network.
//

import XCTest
import SwiftDashSDK
@testable import dashpay

@MainActor
final class PlatformProtocolVersionTests: XCTestCase {
    /// A change here is deliberate: the pin must equal the protocol testnet
    /// has activated.
    func testTestnetIsPinnedToTheActivatedProtocol() {
        XCTAssertEqual(SwiftDashSDKHost.platformVersion(for: .testnet), 14)
    }

    func testMainnetAndDevnetAutoDetect() {
        XCTAssertEqual(SwiftDashSDKHost.platformVersion(for: .mainnet), 0)
        XCTAssertEqual(SwiftDashSDKHost.platformVersion(for: .devnet), 0)
    }
}
