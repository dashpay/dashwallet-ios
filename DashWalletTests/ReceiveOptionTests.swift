//
//  ReceiveOptionTests.swift
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

import XCTest
@testable import dashpay

/// `ReceiveOption` is Receive's own option type: its chain cases map to
/// `ChainNetwork` and back, and Identity maps to no chain, so it can never
/// reach Send, Home or Internal transfer (ADR-0035).
final class ReceiveOptionTests: XCTestCase {
    func testEveryChainNetworkRoundTripsThroughReceiveOption() {
        for network in ChainNetwork.allCases {
            XCTAssertEqual(ReceiveOption(network).chainNetwork, network)
        }
    }

    func testChainOptionsMapToTheirChain() {
        XCTAssertEqual(ReceiveOption.core.chainNetwork, .core)
        XCTAssertEqual(ReceiveOption.shielded.chainNetwork, .shielded)
        XCTAssertEqual(ReceiveOption.platform.chainNetwork, .platform)
    }

    func testIdentityMapsToNoChain() {
        XCTAssertNil(ReceiveOption.identity.chainNetwork)
    }

    func testChainNetworkStillListsOnlyTheThreeChains() {
        XCTAssertEqual(ChainNetwork.allCases, [.core, .platform, .shielded])
    }

    func testChainOptionsKeepTheChainTitles() {
        for network in ChainNetwork.allCases {
            XCTAssertEqual(ReceiveOption(network).title, network.title)
        }
    }
}
