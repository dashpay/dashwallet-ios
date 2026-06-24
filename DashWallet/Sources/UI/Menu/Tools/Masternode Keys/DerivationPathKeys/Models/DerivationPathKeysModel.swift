//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import Foundation
import SwiftDashSDK

// MARK: - DerivationPathKeysItem

struct DerivationPathKeysItem {
    let title: String
    let value: String

    init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    init(info: DerivationPathInfo, value: String) {
        title = info.title
        self.value = value
    }
}

// MARK: - DerivationPathInfo

enum DerivationPathInfo {
    case address
    case privateKey
    case wifPrivateKey
}

extension DerivationPathInfo {
    var title: String {
        switch self {
        case .address:
            return NSLocalizedString("Address", comment: "")
        case .privateKey:
            return NSLocalizedString("Private key", comment: "")
        case .wifPrivateKey:
            return NSLocalizedString("WIF Private key", comment: "")
        }
    }
}

extension MNKey {
    var infos: [DerivationPathInfo] {
        switch self {
        case .owner:
            return [.address, .privateKey, .wifPrivateKey]
        case .voting:
            return [.address, .privateKey, .wifPrivateKey]
        }
    }
}

// MARK: - DerivationPathKeysModel

@MainActor
final class DerivationPathKeysModel {
    let key: MNKey

    let infoItems: [DerivationPathInfo]

    var visibleIndexes: Int = 0

    private let deriver: MasternodeProviderKeyDeriver?

    init(key: MNKey) {
        self.key = key
        infoItems = key.infos
        deriver = MasternodeProviderKeyDeriver(key: key)
    }

    func showNextKey() {
        visibleIndexes += 1
    }
}

// MARK: UI Helper
extension DerivationPathKeysModel {
    var title: String {
        key.title
    }

    var numberOfSections: Int {
        visibleIndexes + 1
    }

    var numberIfItems: Int {
        infoItems.count
    }

    func itemForInfo(_ info: DerivationPathInfo, atIndex index: Int) -> DerivationPathKeysItem {
        let unavailable = NSLocalizedString("Not available", comment: "")
        let value: String
        switch info {
        case .address:
            value = deriver?.address(at: UInt32(index)) ?? unavailable
        case .privateKey:
            value = deriver?.privateKeyHex(at: UInt32(index)) ?? unavailable
        case .wifPrivateKey:
            value = deriver?.wif(at: UInt32(index)) ?? unavailable
        }
        return DerivationPathKeysItem(info: info, value: value)
    }
}

// MARK: - MasternodeProviderKeyDeriver

/// Derives masternode provider Owner/Voting keys (ECDSA) from SwiftDashSDK,
/// replacing DashSync's `DSAuthenticationKeysDerivationPath`.
///
/// Paths match DashSync's `DSAuthenticationKeysDerivationPath` exactly:
/// voting `m/9'/<coin>'/3'/1'`, owner `m/9'/<coin>'/3'/2'` (ECDSA, fully
/// hardened account path, soft key index; coin = 5' mainnet / 1' testnet).
///
/// Only Owner/Voting are supported — Operator (BLS) and HPMN/Platform (EdDSA)
/// were removed because the FFI doesn't export their per-index public keys.
@MainActor
private final class MasternodeProviderKeyDeriver {
    private let key: MNKey
    private let masterPath: String
    private let accountType: AccountType
    private let wallet: Wallet
    private let manager: WalletManager
    private let walletId: Data

    init?(key: MNKey) {
        guard let hostWalletId = SwiftDashSDKHost.shared.wallet?.walletId,
              let network = SwiftDashSDKHost.shared.runningNetwork else {
            return nil
        }

        let coinType = (network == .mainnet) ? "5'" : "1'"
        let path: String
        let type: AccountType
        switch key {
        case .voting:
            path = "m/9'/\(coinType)/3'/1'"
            type = .providerVotingKeys
        case .owner:
            path = "m/9'/\(coinType)/3'/2'"
            type = .providerOwnerKeys
        }

        guard let mnemonic = try? WalletStorage().retrieveMnemonic(for: hostWalletId),
              let manager = try? WalletManager(network: network),
              let walletId = try? manager.addWallet(mnemonic: mnemonic),
              let wallet = (try? manager.getWallet(id: walletId)) ?? nil else {
            return nil
        }

        // Ensure the provider account exists so the managed collection can vend
        // its address pool.
        _ = try? wallet.getAccount(type: type)

        self.key = key
        self.masterPath = path
        self.accountType = type
        self.manager = manager
        self.wallet = wallet
        self.walletId = walletId
    }

    func wif(at index: UInt32) -> String? {
        guard let account = try? wallet.getAccount(type: accountType) else { return nil }
        return try? account.derivePrivateKeyWIF(wallet: wallet, masterPath: masterPath, index: index)
    }

    func privateKeyHex(at index: UInt32) -> String? {
        guard let wif = wif(at: index), let data = WIFParser.parseWIF(wif) else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    func address(at index: UInt32) -> String? {
        guard let collection = manager.getManagedAccountCollection(walletId: walletId) else {
            return nil
        }

        let account: ManagedAccount?
        switch key {
        case .voting:
            account = collection.getProviderVotingKeysAccount()
        case .owner:
            account = collection.getProviderOwnerKeysAccount()
        }

        guard let pool = account?.getAddressPool(type: .single) ?? account?.getExternalAddressPool(),
              let info = try? pool.getAddress(at: index) else {
            return nil
        }
        return info.address
    }
}
