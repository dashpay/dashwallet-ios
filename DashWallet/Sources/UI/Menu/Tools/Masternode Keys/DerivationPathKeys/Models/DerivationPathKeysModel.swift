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
    /// Owner/voting only — it carries the address pool the ECDSA rows join
    /// against. Its keys come from the same resolver as `providerResolver`.
    private let ecdsaDeriver: MasternodeProviderKeyDeriver?
    /// Operator/evonode-operator only — these families have no address rows,
    /// so they talk to the resolver directly.
    private let providerResolver: ProviderKeyResolver?

    init(key: MNKey) {
        self.key = key
        infoItems = key.infos
        usage = MasternodeKeyUsage.resolve()
        visibleIndexes = usage.firstUnusedIndex(for: key)
        switch key {
        case .owner, .voting:
            ecdsaDeriver = MasternodeProviderKeyDeriver(key: key)
            providerResolver = nil
        case .operator:
            ecdsaDeriver = nil
            providerResolver = ProviderKeyResolver(kind: .operatorBLS)
        case .evonodeOperator:
            ecdsaDeriver = nil
            providerResolver = ProviderKeyResolver(kind: .platformNodeEdDSA)
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
                value = providerResolver?.key(at: index)?.privateKeyHex
            }
        case .wifPrivateKey:
            value = ecdsaDeriver?.wif(at: index)
        case .publicKey:
            value = providerResolver?.key(at: index)?.publicKeyHex
        case .publicKeyLegacy:
            value = providerResolver?.key(at: index)?.legacyPublicKeyHex
        case .platformNodeId:
            value = providerResolver?.key(at: index)?.nodeIdHex
        case .tenderdashNodeKey:
            value = providerResolver?.tenderdashNodeKeyBase64(at: index)
        }
        return DerivationPathKeysItem(info: info, value: value ?? unavailable)
    }
}

// MARK: - MasternodeProviderKeyDeriver

/// Derives masternode provider Owner/Voting keys (ECDSA) from SwiftDashSDK,
/// replacing DashSync's `DSAuthenticationKeysDerivationPath`.
///
/// The DIP-3 voting and owner account paths (ECDSA, fully hardened account
/// path, soft key index) are resolved Rust-side: `providerKeyAtIndex` derives
/// every private key, and the addresses come from the running wallet's pool.
/// Composing the account path app-side is what let it be applied twice and
/// produced keys off the intended branch.
///
/// Internal (not private): `MasternodeKeyUsage` reuses `address(at:)` for
/// its owner/voting address join.
@MainActor
final class MasternodeProviderKeyDeriver {
    /// `AccountTypeTagFFI` discriminants for the two address-carrying provider
    /// families (`rs-platform-wallet-ffi` `wallet_restore_types.rs`).
    private static let votingKeysTypeTag: UInt8 = 8
    private static let ownerKeysTypeTag: UInt8 = 9

    /// Owner/voting derivation moved Rust-side (platform#4338) and the
    /// key-wallet path surface it used to go through was withdrawn
    /// (platform#4339), so the private keys below come from exactly the same
    /// resolver the operator/platform families use — not a second copy of it.
    private let keyResolver: ProviderKeyResolver

    /// Index → base58 address of the running wallet's provider pool,
    /// snapshotted once at init. Empty when the wallet has no provider account
    /// yet, such as a just-imported wallet whose registration hasn't completed.
    private let poolAddresses: [UInt32: String]

    init?(key: MNKey) {
        let kind: ManagedPlatformWallet.ProviderKeyKind
        switch key {
        case .voting:
            kind = .votingECDSA
        case .owner:
            kind = .ownerECDSA
        case .operator, .evonodeOperator:
            // BLS / Ed25519 families have no address rows, so they use
            // `ProviderKeyResolver` directly rather than this wrapper.
            return nil
        }

        guard let keyResolver = ProviderKeyResolver(kind: kind) else {
            return nil
        }

        self.poolAddresses = Self.loadLiveAddresses(for: key)
        self.keyResolver = keyResolver
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
        keyResolver.key(at: index)?.privateKeyWIF
    }

    func privateKeyHex(at index: UInt32) -> String? {
        keyResolver.key(at: index)?.privateKeyHex
    }

    /// The address at `index` of the running wallet's provider pool.
    func address(at index: UInt32) -> String? {
        poolAddresses[index]
    }

    /// Highest index the snapshotted pool holds, or nil when no pool could be
    /// read — lets the address joins walk the real pool rather than a fixed
    /// window, and skip entirely when there is nothing to walk.
    var highestAddressIndex: UInt32? {
        poolAddresses.keys.max()
    }
}

// MARK: - ProviderKeyResolver

/// Memoised access to one masternode provider family's keys through
/// `ManagedPlatformWallet.providerKeyAtIndex`.
///
/// All derivation and serialization happens Rust-side — the DIP-3 path, the
/// modern + legacy BLS encodings, the platform node id — and the resolver
/// cross-checks the derived key against the account xpub. Composing the path
/// app-side is what previously let the account path be applied twice
/// (`Account.derivePrivateKeyWIF`, withdrawn in platform#4339): the keys were
/// well-formed, which is why the screen looked right, but they came off the
/// wrong branch.
///
/// This is the single entry point for all four families. Both the ECDSA
/// owner/voting deriver and the BLS/Ed25519 rows previously carried their own
/// copy of this call and its cache.
///
/// Memoised because the Ed25519 family pulls the wallet seed through the
/// mnemonic resolver on every call.
@MainActor
private final class ProviderKeyResolver {
    private let kind: ManagedPlatformWallet.ProviderKeyKind
    private let wallet: ManagedPlatformWallet
    private var cache: [UInt32: ManagedPlatformWallet.ProviderDerivedKey] = [:]

    init?(kind: ManagedPlatformWallet.ProviderKeyKind) {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            return nil
        }
        self.kind = kind
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
