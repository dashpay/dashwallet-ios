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
    case keyId
    case privatePublicKeysBase64
    case address
    case publicKey
    case publicKeyLegacy
    case privateKey
    case wifPrivateKey
}

extension DerivationPathInfo {
    var title: String {
        switch self {
        case .keyId:
            return NSLocalizedString("Key Id", comment: "")
        case .privatePublicKeysBase64:
            return NSLocalizedString("Private / Public Keys (base64)", comment: "")
        case .address:
            return NSLocalizedString("Address", comment: "")
        case .publicKey:
            return NSLocalizedString("Public key", comment: "")
        case .publicKeyLegacy:
            return NSLocalizedString("Public key (legacy)", comment: "")
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
        case .operator:
            return [.publicKey, .publicKeyLegacy, .privateKey]
        case .hpmnOperator:
            return [.keyId, .privatePublicKeysBase64]
        }
    }
}

// MARK: - DerivationPathKeysModel

final class DerivationPathKeysModel {
    let key: MNKey
    let derivationPath: DSAuthenticationKeysDerivationPath

    let infoItems: [DerivationPathInfo]

    var visibleIndexes: Int
    
    lazy var seed: Data? = {
        guard let phrase = DWEnvironment.sharedInstance().currentWallet.seedPhraseIfAuthenticated() else { return nil }
        return DSBIP39Mnemonic.sharedInstance()!.deriveKey(fromPhrase: phrase, withPassphrase: nil)
    }()


    init(key: MNKey, derivationPath: DSAuthenticationKeysDerivationPath) {
        self.key = key
        self.derivationPath = derivationPath
        infoItems = key.infos
        visibleIndexes = Int(derivationPath.firstUnusedIndex())
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
        let address = derivationPath.address(at: IndexPath(index: index))
        let used = derivationPath.addressIsUsed(address)

        if used {
            if let localMasternode = derivationPath.chain.chainManager!.masternodeManager.localMasternode(using: UInt32(index), at: derivationPath) {
                return NSLocalizedString("Used at: ", comment: "") + localMasternode.ipAddressAndIfNonstandardPortString
            } else {
                guard let localMasternodesArray = derivationPath.chain.chainManager!.masternodeManager.localMasternodesPreviously(using: UInt32(index), at: derivationPath) else {
                    return NSLocalizedString("Not yet used", comment: "")
                }

                if localMasternodesArray.count == 1 {
                    let localMasternode = localMasternodesArray.first!
                    return NSLocalizedString("Previously used at: ", comment: "") + localMasternode.ipAddressAndIfNonstandardPortString
                } else if localMasternodesArray.isEmpty {
                    return NSLocalizedString("Used", comment: "")
                } else {
                    let localMasternode = localMasternodesArray.last!
                    return NSLocalizedString("Previously used at: ", comment: "") + localMasternode.ipAddressAndIfNonstandardPortString
                }
            }
        } else {
            return NSLocalizedString("Not yet used", comment: "")
        }
    }

    func privateKeyAtIndexPath(_ path: IndexPath) -> UnsafeMutablePointer<Result_ok_dash_spv_crypto_keys_key_OpaqueKey_err_dash_spv_crypto_keys_KeyError>? {
        guard let seed = seed else {
            return nil
        }
        return derivationPath.privateKey(at: path, fromSeed: seed)
    }

    func itemForInfo(_ info: DerivationPathInfo, atIndex index: Int) -> DerivationPathKeysItem {
        let wallet = DWEnvironment.sharedInstance().currentWallet
        let indexPath = IndexPath(index: index)
        let index = UInt32(index)
        return autoreleasepool {
            switch info {
            case .address:
                let address = derivationPath.address(at: indexPath)
                return DerivationPathKeysItem(info: info, value: address)
            case .publicKey:
                guard let opaqueKey = privateKeyAtIndexPath(indexPath) else {
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                guard let key = opaqueKey.pointee.ok else {
                    Result_ok_dash_spv_crypto_keys_key_OpaqueKey_err_dash_spv_crypto_keys_KeyError_destroy(opaqueKey)
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                let keyString = DSKeyManager.blsPublicKeySerialize(key, legacy: false)
                Result_ok_dash_spv_crypto_keys_key_OpaqueKey_err_dash_spv_crypto_keys_KeyError_destroy(opaqueKey)
                return DerivationPathKeysItem(info: info, value: keyString.lowercased())
            case .publicKeyLegacy:
                guard let opaqueKey = privateKeyAtIndexPath(indexPath) else {
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                guard let key = opaqueKey.pointee.ok else {
                    Result_ok_dash_spv_crypto_keys_key_OpaqueKey_err_dash_spv_crypto_keys_KeyError_destroy(opaqueKey)
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                let keyString = DSKeyManager.blsPublicKeySerialize(key, legacy: true)
                Result_ok_dash_spv_crypto_keys_key_OpaqueKey_err_dash_spv_crypto_keys_KeyError_destroy(opaqueKey)
                return DerivationPathKeysItem(info: info, value: keyString.lowercased())
            case .privateKey:
                guard let opaqueKey = privateKeyAtIndexPath(indexPath) else {
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                guard let key = opaqueKey.pointee.ok else {
                    Result_ok_dash_spv_crypto_keys_key_OpaqueKey_err_dash_spv_crypto_keys_KeyError_destroy(opaqueKey)
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                let keyString = DSKeyManager.secretKeyHexString(key)
                return DerivationPathKeysItem(info: info, value: keyString)
            case .wifPrivateKey:
                guard let opaqueKey = privateKeyAtIndexPath(indexPath) else {
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                guard let key = opaqueKey.pointee.ok else {
                    Result_ok_dash_spv_crypto_keys_key_OpaqueKey_err_dash_spv_crypto_keys_KeyError_destroy(opaqueKey)
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                let keyString = DSKeyManager.serializedPrivateKey(key, chainType: wallet.chain.chainType)
                return DerivationPathKeysItem(info: info, value: keyString)
            case .keyId:
                var keyId = derivationPath.keyId(at: index)
                let hexString = NSData(bytes: &keyId, length: MemoryLayout<UInt160>.size).hexString()
                return DerivationPathKeysItem(info: info, value: hexString.lowercased())

            case .privatePublicKeysBase64:
                guard let opaqueKey = privateKeyAtIndexPath(indexPath) else {
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                guard let key = opaqueKey.pointee.ok else {
                    Result_ok_dash_spv_crypto_keys_key_OpaqueKey_err_dash_spv_crypto_keys_KeyError_destroy(opaqueKey)
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }

                let privateKeyData = DSKeyManager.privateKeyData(key)
                let pubKeyData = self.derivationPath.publicKeyData(at: indexPath)!
                let data = privateKeyData + pubKeyData
                return DerivationPathKeysItem(info: info, value: data.base64EncodedString())
            }
        }
    }
}
