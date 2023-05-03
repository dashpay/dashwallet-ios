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

enum DerivationPathInfo: CaseIterable {
    case address
    case publicKey
    case privateKey
    case wifPrivateKey
}

extension DerivationPathInfo {
    var title: String {
        switch self {
        case .address:
            return NSLocalizedString("Address", comment: "")
        case .publicKey:
            return NSLocalizedString("Public key", comment: "")
        case .privateKey:
            return NSLocalizedString("Private key", comment: "")
        case .wifPrivateKey:
            return NSLocalizedString("WIF Private key", comment: "")
        }
    }
}

// MARK: - DerivationPathKeysModel

final class DerivationPathKeysModel {
    let key: MNKey
    let derivationPath: DSAuthenticationKeysDerivationPath

    let infoItems = DerivationPathInfo.allCases

    var visibleIndexes: Int

    init(key: MNKey, derivationPath: DSAuthenticationKeysDerivationPath) {
        self.key = key
        self.derivationPath = derivationPath
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
        let used = derivationPath.addressIsUsed(at: UInt32(index))

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

    func itemForInfo(_ info: DerivationPathInfo, atIndex index: Int) -> DerivationPathKeysItem {
        let wallet = DWEnvironment.sharedInstance().currentWallet

        switch info {
        case .address:
            let address = derivationPath.address(at: UInt32(index))
            return DerivationPathKeysItem(info: info, value: address)
        case .publicKey:
            let publicKeyData = derivationPath.publicKeyData(at: UInt32(index))
            return DerivationPathKeysItem(info: info, value: publicKeyData.hexEncodedString())
        case .privateKey:
            return autoreleasepool {
                guard let phrase = wallet.seedPhraseIfAuthenticated() else {
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                let seed = DSBIP39Mnemonic.sharedInstance()!.deriveKey(fromPhrase: phrase, withPassphrase: nil)

                let key = self.derivationPath.privateKey(at: UInt32(index), fromSeed: seed)!

                return DerivationPathKeysItem(info: info, value: key.secretKeyString)
            }
        case .wifPrivateKey:
            return autoreleasepool {
                guard let phrase = wallet.seedPhraseIfAuthenticated() else {
                    return DerivationPathKeysItem(info: info, value: NSLocalizedString("Not available", comment: ""))
                }
                let seed = DSBIP39Mnemonic.sharedInstance()!.deriveKey(fromPhrase: phrase, withPassphrase: nil)

                let key = self.derivationPath.privateKey(at: UInt32(index), fromSeed: seed)!

                return DerivationPathKeysItem(info: info, value: key.serializedPrivateKey(for: wallet.chain)!)
            }
        }
    }
}