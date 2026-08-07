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
    /// `AccountTypeTagFFI` discriminants for the two address-carrying provider
    /// families (`rs-platform-wallet-ffi` `wallet_restore_types.rs`).
    private static let votingKeysTypeTag: UInt8 = 8
    private static let ownerKeysTypeTag: UInt8 = 9

    private let key: MNKey
    private let masterPath: String
    private let accountType: AccountType
    private let wallet: Wallet

    /// Index → base58 address of the LIVE provider pool, read once from the
    /// running `PlatformWalletManager` (see `loadLiveAddresses`). Empty when
    /// the account/pool isn't available.
    private let liveAddresses: [UInt32: String]

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

        // The derivation stack is a THROWAWAY key-wallet built from the
        // mnemonic (see `SwiftDashSDKHost.derivationWallet`) — it has never
        // processed a transaction, so its pools sit at the freshly-created
        // `DEFAULT_SPECIAL_GAP_LIMIT` depth. It is used ONLY for private-key
        // derivation, which works at any index; addresses come from the live
        // pool below.
        guard let (_, wallet, _) = SwiftDashSDKHost.shared.derivationWallet() else {
            return nil
        }

        // Ensure the provider account exists so private-key derivation can
        // resolve it.
        _ = try? wallet.getAccount(type: type)

        self.key = key
        self.masterPath = path
        self.accountType = type
        self.wallet = wallet
        self.liveAddresses = Self.loadLiveAddresses(for: key)
    }

    /// Snapshot the running wallet's provider address pool — the one SPV
    /// extends as ProRegTx/ProUpRegTx matches mark indexes used, and the one
    /// the Storage Explorer renders. Read once per deriver: the FFI returns
    /// the whole pool, so per-index lookups are dictionary hits.
    private static func loadLiveAddresses(for key: MNKey) -> [UInt32: String] {
        let typeTag: UInt8
        switch key {
        case .voting: typeTag = votingKeysTypeTag
        case .owner: typeTag = ownerKeysTypeTag
        case .operator, .evonodeOperator: return [:]
        }
        guard let manager = SwiftDashSDKHost.shared.manager,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
              let balance = manager.accountBalances(for: walletId)
                  .first(where: { $0.typeTag == typeTag })
        else { return [:] }

        var addresses: [UInt32: String] = [:]
        for pool in manager.accountAddressPools(for: walletId, balance: balance) {
            for info in pool.addresses where !info.address.isEmpty {
                addresses[info.addressIndex] = info.address
            }
        }
        return addresses
    }

    func wif(at index: UInt32) -> String? {
        guard let account = try? wallet.getAccount(type: accountType) else { return nil }
        return try? account.derivePrivateKeyWIF(wallet: wallet, masterPath: masterPath, index: index)
    }

    func privateKeyHex(at index: UInt32) -> String? {
        guard let wif = wif(at: index), let data = WIFParser.parseWIF(wif) else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    /// The pool address at `index`, from the running wallet's live provider
    /// pool. Reading the throwaway derivation wallet here instead would cap
    /// every consumer at that stack's initial 5-entry pool, hiding every
    /// masternode whose owner/voting key sits at a deeper index.
    func address(at index: UInt32) -> String? {
        liveAddresses[index]
    }

    /// Highest index the live pool holds, or nil when it's unavailable —
    /// lets the address-join scan the whole pool instead of a fixed window.
    var highestAddressIndex: UInt32? {
        liveAddresses.keys.max()
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
