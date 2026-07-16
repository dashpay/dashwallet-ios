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
    case publicKey
    case publicKeyLegacy
    case platformNodeId
    case tenderdashNodeKey
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
        case .publicKey:
            return NSLocalizedString("Public key", comment: "")
        case .publicKeyLegacy:
            return NSLocalizedString("Public key (legacy)", comment: "")
        case .platformNodeId:
            return NSLocalizedString("Platform Node ID", comment: "")
        case .tenderdashNodeKey:
            return NSLocalizedString("Tenderdash node key (base64)", comment: "")
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
        case .operator:
            return [.publicKey, .publicKeyLegacy, .privateKey]
        case .evonodeOperator:
            return [.platformNodeId, .publicKey, .privateKey, .tenderdashNodeKey]
        }
    }
}

// MARK: - DerivationPathKeysModel

@MainActor
final class DerivationPathKeysModel {
    let key: MNKey

    let infoItems: [DerivationPathInfo]

    var visibleIndexes: Int

    private let usage: MasternodeKeyUsage
    private let ecdsaDeriver: MasternodeProviderKeyDeriver?
    private let providerDeriver: ProviderKeyDeriver?

    init(key: MNKey) {
        self.key = key
        infoItems = key.infos
        usage = MasternodeKeyUsage.resolve()
        visibleIndexes = usage.firstUnusedIndex(for: key)
        switch key {
        case .owner, .voting:
            ecdsaDeriver = MasternodeProviderKeyDeriver(key: key)
            providerDeriver = nil
        case .operator, .evonodeOperator:
            ecdsaDeriver = nil
            providerDeriver = ProviderKeyDeriver(key: key)
        }
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

    func usageInfoForKey(at index: Int) -> String {
        guard let use = usage.use(for: key, at: index) else {
            return NSLocalizedString("Not yet used", comment: "")
        }
        guard let service = use.serviceAddress, !service.isEmpty else {
            return NSLocalizedString("Used", comment: "")
        }
        if use.revoked {
            return NSLocalizedString("Previously used at: ", comment: "") + service
        }
        return NSLocalizedString("Used at: ", comment: "") + service
    }

    func itemForInfo(_ info: DerivationPathInfo, atIndex index: Int) -> DerivationPathKeysItem {
        let unavailable = NSLocalizedString("Not available", comment: "")
        let index = UInt32(index)
        let value: String?
        switch info {
        case .address:
            value = ecdsaDeriver?.address(at: index)
        case .privateKey:
            switch key {
            case .owner, .voting:
                value = ecdsaDeriver?.privateKeyHex(at: index)
            case .operator, .evonodeOperator:
                value = providerDeriver?.key(at: index)?.privateKeyHex
            }
        case .wifPrivateKey:
            value = ecdsaDeriver?.wif(at: index)
        case .publicKey:
            value = providerDeriver?.key(at: index)?.publicKeyHex
        case .publicKeyLegacy:
            value = providerDeriver?.key(at: index)?.legacyPublicKeyHex
        case .platformNodeId:
            value = providerDeriver?.key(at: index)?.nodeIdHex
        case .tenderdashNodeKey:
            value = providerDeriver?.tenderdashNodeKeyBase64(at: index)
        }
        return DerivationPathKeysItem(info: info, value: value ?? unavailable)
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
/// Internal (not private): `MasternodeKeyUsage` reuses `address(at:)` for
/// its owner/voting address join.
@MainActor
final class MasternodeProviderKeyDeriver {
    private let key: MNKey
    private let masterPath: String
    private let accountType: AccountType
    private let wallet: Wallet
    private let manager: WalletManager
    private let walletId: Data

    init?(key: MNKey) {
        guard let network = SwiftDashSDKHost.shared.runningNetwork else {
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
        case .operator, .evonodeOperator:
            // BLS / Ed25519 families derive through `ProviderKeyDeriver`
            // (the platform-wallet FFI), not the key-wallet path surface.
            return nil
        }

        guard let (manager, wallet, walletId) = SwiftDashSDKHost.shared.derivationWallet() else {
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
        case .operator, .evonodeOperator:
            account = nil
        }

        guard let pool = account?.getAddressPool(type: .single) ?? account?.getExternalAddressPool(),
              let info = try? pool.getAddress(at: index) else {
            return nil
        }
        return info.address
    }
}

// MARK: - ProviderKeyDeriver

/// Derives masternode Operator (BLS) and Evonode Operator (Ed25519
/// platform-node) keys through the platform-wallet FFI
/// (`ManagedPlatformWallet.providerKeyAtIndex`). All derivation and
/// serialization (modern + legacy BLS encodings, the platform node id)
/// happens on the Rust side; results are memoized per index because the
/// Ed25519 family pulls the wallet seed through the mnemonic resolver on
/// every call.
@MainActor
private final class ProviderKeyDeriver {
    private let kind: ManagedPlatformWallet.ProviderKeyKind
    private let wallet: ManagedPlatformWallet
    private var cache: [UInt32: ManagedPlatformWallet.ProviderDerivedKey] = [:]

    init?(key: MNKey) {
        switch key {
        case .operator:
            kind = .operatorBLS
        case .evonodeOperator:
            kind = .platformNodeEdDSA
        case .owner, .voting:
            return nil
        }
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            return nil
        }
        self.wallet = wallet
    }

    func key(at index: UInt32) -> ManagedPlatformWallet.ProviderDerivedKey? {
        if let cached = cache[index] {
            return cached
        }
        // The screen is auth-gated and shows private-key rows for every
        // family, so derive with the private scalar included up front.
        guard let derived = try? wallet.providerKeyAtIndex(
            kind: kind,
            index: index,
            includePrivate: true
        ) else {
            return nil
        }
        cache[index] = derived
        return derived
    }

    /// The Ed25519 platform-node key in dashmate's "Enter Ed25519 node key"
    /// format: base64 of the 64-byte `priv(32) ‖ pub(32)` concatenation.
    /// Pure re-encoding of the two hex strings the FFI returned — no crypto.
    func tenderdashNodeKeyBase64(at index: UInt32) -> String? {
        guard kind == .platformNodeEdDSA,
              let derived = key(at: index),
              let privateHex = derived.privateKeyHex,
              let priv = Data(hex: privateHex), priv.count == 32,
              let pub = Data(hex: derived.publicKeyHex), pub.count == 32 else {
            return nil
        }
        return (priv + pub).base64EncodedString()
    }
}
