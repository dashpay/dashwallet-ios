//
//  KeyToolsTests.swift
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

import SwiftData
import SwiftDashSDK
import XCTest
@testable import dashpay

@MainActor
final class KeyToolsTests: XCTestCase {
    // MARK: BIP44 account xpub

    // Bincode `ExtendedPubKey` encodings of the accounts of the all-`abandon`
    // test phrase, the form the SDK persists in `accountExtendedPubKeyBytes`,
    // from rust-dashcore key-wallet.
    private let testnetBIP44Account0 =
        "010306b037f60100028b42cd4776376c82791b494155151f56c2d7b471e0c7a526a7ce60dd872e38676b22c5123ba10adeaf4bfcbb45d1a02d828f25bf8646957a98d06287c4e2b850"
    private let testnetBIP44Account0Xpub =
        "tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba"
    private let testnetBIP44Account1 =
        "010306b037f6010102e33ff6cf05a02b7e86a0c642467a81eca94378e8ecb894a86aa61cd4bb6cfcaea09288f3a8d81cae308122fc4f188e263763a0f283a4624a04d8354ce88aa4a4"
    private let testnetBIP32Account0 =
        "010173c5da0a0100027f1d87730e460e921b382242911565bf93daf2081ed685b2edd1d01176b2c13cf1c03f5ff97108912fd56761d3fada8879e4173aba45f10da4bbd94b1c497160"
    private let testnetCoinJoinAccount0 =
        "0104ce779a78010003d34f244d2ba069e010860f4029fe2a69fa9f97b76003a42b8035a0bb9d4427ef87da1f77dccd9010219927dc01faa168bb51851f07ede6df86139fb518bb2481"
    private let mainnetBIP44Account0 =
        "000378bb198e01000380df7b326343660535342c6bd254207a8ebf994adf5fd98f3dfc67f9d678e126ee470b7c9fe2cae4719f9a0732c0863083d75b48158e7dbd843f2a77a1a23da0"

    private let walletId = Data(repeating: 1, count: 32)

    @discardableResult
    private func addAccount(
        to wallet: PersistentWallet,
        in context: ModelContext,
        type: UInt32,
        standardTag: UInt8 = 0,
        index: UInt32,
        xpubHex: String?
    ) throws -> PersistentAccount {
        let account = PersistentAccount(wallet: wallet, accountType: type, accountIndex: index, accountTypeName: "test")
        account.standardTag = standardTag
        account.accountExtendedPubKeyBytes = try xpubHex.map { try XCTUnwrap(Data(hex: $0)) }
        context.insert(account)
        return account
    }

    func testXpubComesFromTheBIP44AccountZeroRow() throws {
        let container = try DashModelContainer.inMemoryWithoutCloudKit()
        let context = container.mainContext
        let wallet = PersistentWallet(walletId: walletId, network: .testnet)
        let other = PersistentWallet(walletId: Data(repeating: 2, count: 32), network: .mainnet)
        context.insert(wallet)
        context.insert(other)
        // Each row differs from the BIP44 account 0 row of `wallet` in one field.
        try addAccount(to: wallet, in: context, type: 0, index: 1, xpubHex: testnetBIP44Account1)
        try addAccount(to: wallet, in: context, type: 0, standardTag: 1, index: 0, xpubHex: testnetBIP32Account0)
        try addAccount(to: wallet, in: context, type: 1, index: 0, xpubHex: testnetCoinJoinAccount0)
        try addAccount(to: other, in: context, type: 0, index: 0, xpubHex: mainnetBIP44Account0)
        try context.save()
        XCTAssertNil(ExtendedPublicKeysModel.loadBIP44AccountXpub(context: context, walletId: walletId))

        let account = try addAccount(to: wallet, in: context, type: 0, index: 0, xpubHex: nil)
        try context.save()
        XCTAssertNil(ExtendedPublicKeysModel.loadBIP44AccountXpub(context: context, walletId: walletId))

        account.accountExtendedPubKeyBytes = try XCTUnwrap(Data(hex: testnetBIP44Account0))
        try context.save()
        XCTAssertEqual(
            ExtendedPublicKeysModel.loadBIP44AccountXpub(context: context, walletId: walletId),
            testnetBIP44Account0Xpub)
    }
}
