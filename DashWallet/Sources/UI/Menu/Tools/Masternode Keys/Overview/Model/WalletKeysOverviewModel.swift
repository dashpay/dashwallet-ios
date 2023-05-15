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

// MARK: - MNKey

enum MNKey: CaseIterable {
    case owner
    case voting
    case `operator`
    case hpmnOperator
}

extension MNKey {
    var title: String {
        switch self {
        case .owner:
            return NSLocalizedString("Owner Keys", comment: "")
        case .voting:
            return NSLocalizedString("Voting Keys", comment: "")
        case .operator:
            return NSLocalizedString("Operator Keys", comment: "")
        case .hpmnOperator:
            return NSLocalizedString("HPMN Operator Keys", comment: "")
        }
    }
}

// MARK: - WalletKeysOverviewModel

final class WalletKeysOverviewModel {
    var items: [MNKey] = MNKey.allCases

    let ownerDerivationPath: DSAuthenticationKeysDerivationPath
    let votingDerivationPath: DSAuthenticationKeysDerivationPath
    let operatorDerivationPath: DSAuthenticationKeysDerivationPath
    let hpmnOperatorDerivationPath: DSAuthenticationKeysDerivationPath

    init() {
        let wallet = DWEnvironment.sharedInstance().currentWallet
        let factory = DSDerivationPathFactory.sharedInstance()!

        ownerDerivationPath = factory.providerOwnerKeysDerivationPath(for: wallet)
        votingDerivationPath = factory.providerVotingKeysDerivationPath(for: wallet)
        operatorDerivationPath = factory.providerOperatorKeysDerivationPath(for: wallet)
        hpmnOperatorDerivationPath = operatorDerivationPath
        // hpmnOperatorDerivationPath = factory.platformNodeKeysDerivationPath(for: wallet) //We will use it in another branch
    }

    func derivationPath(for type: MNKey) -> DSAuthenticationKeysDerivationPath {
        switch type {
        case .owner:
            return ownerDerivationPath
        case .voting:
            return votingDerivationPath
        case .operator:
            return operatorDerivationPath
        case .hpmnOperator:
            return hpmnOperatorDerivationPath
        }
    }

    func keyCount(for type: MNKey) -> Int {
        let derivationPath = derivationPath(for: type)
        let firstUnusedIndex = derivationPath.firstUnusedIndex();

        // NOTE: Always show at least one key
        return Int(max(firstUnusedIndex, 1))
    }

    func usedCount(for type: MNKey) -> Int {
        let derivationPath = derivationPath(for: type)
        return derivationPath.usedAddresses.count
    }
}
