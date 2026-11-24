//
//  WalletSetupErrorTextTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

@testable import dashpay
import SwiftDashSDK
import XCTest

/// The wallet setup errors that name a network fill their text with the
/// network's display name, for every network the SDK knows.
final class WalletSetupErrorTextTests: XCTestCase {
    func testNetworkErrorsNameEveryNetwork() {
        for network in Network.allCases {
            let name = WalletEnvironment.displayName(of: network)
            let texts = [
                SwiftDashSDKHost.HostError.unsupportedNetwork(network).errorDescription,
                SwiftDashSDKHost.HostError.walletNotFound(network).errorDescription,
            ]
            for text in texts {
                let text = text ?? ""
                XCTAssert(text.hasSuffix(" " + name), "\(network): \(text)")
                XCTAssertNil(text.range(of: "(null)"), "\(network): \(text)")
            }
        }
    }

    func testNetworkDisplayNamesAreTheEnglishNames() {
        XCTAssertEqual(WalletEnvironment.displayName(of: Network.mainnet), "Mainnet")
        XCTAssertEqual(WalletEnvironment.displayName(of: Network.testnet), "Testnet")
        XCTAssertEqual(WalletEnvironment.displayName(of: Network.devnet), "Devnet")
        XCTAssertEqual(WalletEnvironment.displayName(of: Network.regtest), "Regtest")
    }
}
