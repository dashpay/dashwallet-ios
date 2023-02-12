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

import Moya

// MARK: - CrowdNodeService

class CrowdNodeService {
    private var httpClient: CrowdNodeAPI {
        CrowdNodeAPI.shared
    }
}

extension CrowdNodeService {
    func getBalance(address: String) async throws -> CrowdNodeBalance {
        try await httpClient.request(.getBalance(address))
    }

    func getWithdrawalLimits(address: String) async throws -> [WithdrawalLimitPeriod: UInt64?] {
        let limits: [WithdrawalLimit] = try await httpClient.request(.getWithdrawalLimits(address))
        var map: [WithdrawalLimitPeriod: UInt64?] = [:]

        limits.forEach { limit in
            switch limit.key.lowercased() {
            case WithdrawalLimit.maxPerTxKey.lowercased():
                map[WithdrawalLimitPeriod.perTransaction] = limit.value.plainDashAmount()
            case WithdrawalLimit.maxPer1hKey.lowercased():
                map[WithdrawalLimitPeriod.perHour] = limit.value.plainDashAmount()
            case WithdrawalLimit.maxPer24hKey.lowercased():
                map[WithdrawalLimitPeriod.perDay] = limit.value.plainDashAmount()
            default:
                break
            }
        }

        return map
    }

    func isAddressInUse(address: String) async -> IsAddressInUse {
        do {
            return try await httpClient.request(.isAddressInUse(address))
        } catch {
            return IsAddressInUse(isInUse: false, primaryAddress: nil)
        }
    }

    func addressStatus(address: String) async -> String {
        do {
            let result: AddressStatus = try await httpClient.request(.addressStatus(address))
            return result.status
        } catch {
            return ""
        }
    }
    
    func sendSignedMessage(address: String, message: String, signature: String) async throws -> MessageStatus {
        let encodedSignature = signature.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        return try await httpClient.request(.sendSignedMessage(address: address, message: message, signature: encodedSignature!))
    }
    
    func isDefaultEmail(address: String) async -> Bool {
        do {
            let response: IsDefaultEmail = try await httpClient.request(.hasDefaultEmail(address))
            return response.isDefault
        } catch {
            return true
        }
    }
    
    func checkMessageStatus(id: Int, address: String) async -> MessageStatus? {
        do {
            let messages: [MessageStatus] = try await httpClient.request(.getMessages(address))
            let message = messages.first { $0.id == id }
            
            if message == nil {
                DSLogger.log("CrowdNode: got \(messages.count) messages, none with id \(id)")
                return nil
            } else {
                return message
            }
        } catch {
            return nil
        }
    }
}
