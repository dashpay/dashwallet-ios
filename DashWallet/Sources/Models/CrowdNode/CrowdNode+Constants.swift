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

extension CrowdNode {
    private static let crowdNodeTestNetAddress = "yMY5bqWcknGy5xYBHSsh2xvHZiJsRucjuy"
    private static let crowdNodeMainNetAddress = "XjbaGWaGnvEtuQAUoBgDxJWe8ZNv45upG2"

    static var crowdNodeAddress: String {
        if DWEnvironment.sharedInstance().currentChain.isMainnet() {
            return crowdNodeMainNetAddress
        }
        else {
            return crowdNodeTestNetAddress
        }
    }

    private static let mainnetBaseUrl = "https://app.crowdnode.io/"
    private static let testnetBaseUrl = "https://test.crowdnode.io/"

    static var baseUrl: String {
        if DWEnvironment.sharedInstance().currentChain.isMainnet() {
            return mainnetBaseUrl
        }
        else {
            return testnetBaseUrl
        }
    }

    static let minimumRequiredDash: UInt64 = 1_000_000
    static let requiredForSignup = minimumRequiredDash - 100_000
    static let requiredForAcceptTerms: UInt64 = 100_000
    static let apiOffset: UInt64 = 20000
    static let minimumDeposit = UInt64(kOneDash / 2)
    static let minimumLeftoverBalance: UInt64 = 30_000

    static let notificationID = "CrowdNode"

    static let fundsOpenUrl = baseUrl + "FundsOpen/"
    static let websiteUrl = "https://crowdnode.io/"
    static let termsOfUseUrl = "https://crowdnode.io/terms/"
    static let privacyPolicyUrl = "https://crowdnode.io/privacy/"
    static let supportUrl = "https://knowledge.crowdnode.io/"
    static let withdrawalLimitsUrl = "https://knowledge.crowdnode.io/en/articles/6387601-api-withdrawal-limits"
}
