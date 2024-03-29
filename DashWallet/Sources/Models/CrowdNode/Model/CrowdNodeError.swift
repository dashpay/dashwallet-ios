//
//  Created by Andrei Ashikhmin
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

// MARK: - CrowdNode.Error

extension CrowdNode {
    enum Error: Swift.Error, LocalizedError {
        case signUp
        case deposit
        case withdraw
        case withdrawLimit(amount: UInt64, period: WithdrawalLimitPeriod)
        case restoreLinked(state: OnlineAccountState)
        case missingPrimary
        case messageStatus(error: String)

        var errorDescription: String {
            switch self {
            case .signUp:
                return NSLocalizedString("We couldn’t create your CrowdNode account.", comment: "CrowdNode")
            case .deposit:
                return NSLocalizedString("We couldn’t make a deposit to your CrowdNode account.", comment: "CrowdNode")
            case .withdraw:
                return NSLocalizedString("We couldn’t withdraw from your CrowdNode account.", comment: "CrowdNode")
            case .restoreLinked(let state):
                return "Invalid state found in tryRestoreLinkedOnlineAccount: \(state)"
            case .messageStatus(let error):
                return error
            default:
                return ""
            }
        }
    }
}

// MARK: - SendCoinsService.Error

extension SendCoinsService {
    enum Error: Swift.Error {
        case notEnoughFunds(selected: UInt64, amount: UInt64, fee: UInt64)
    }
}
