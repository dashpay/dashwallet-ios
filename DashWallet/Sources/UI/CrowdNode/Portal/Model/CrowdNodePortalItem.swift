//  
//  Created by Andrei Ashikhmin
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

enum CrowdNodePortalItem: CaseIterable {
    case deposit
    case withdraw
    case onlineAccount
    case support
}

extension CrowdNodePortalItem {
    var title: String {
        switch self {
        case .deposit:
            return NSLocalizedString("Deposit", comment: "CrowdNode Portal")
        case .withdraw:
            return NSLocalizedString("Withdraw", comment: "CrowdNode Portal")
        case .onlineAccount:
            return NSLocalizedString("Create Online Account", comment: "CrowdNode Portal")
        case .support:
            return NSLocalizedString("CrowdNode Support", comment: "CrowdNode Portal")
        }
    }

    var subtitle: String {
        switch self {
        case .deposit:
            return NSLocalizedString("DashWallet ➝ CrowdNode", comment: "CrowdNode Portal")
        case .withdraw:
            return NSLocalizedString("CrowdNode ➝ DashWallet", comment: "CrowdNode Portal")
        case .onlineAccount:
            return NSLocalizedString("Protect your savings", comment: "CrowdNode Portal")
        case .support:
            return ""
        }
    }

    var icon: String {
        switch self {
        case .deposit:
            return "image.crowdnode.deposit"
        case .withdraw:
            return "image.crowdnode.withdraw"
        case .onlineAccount:
            return "image.crowdnode.online"
        case .support:
            return "image.crowdnode.support"
        }
    }

    var iconCircleColor: UIColor {
        switch self {
        case .deposit:
            return UIColor.systemGreen

        default:
            return UIColor.dw_dashBlue()
        }
    }

    func isDisabled(_ crowdNodeBalance: UInt64, _ walletBalance: UInt64, _ isLinkingInProgress: Bool) -> Bool {
        switch self {
        case .deposit:
            return walletBalance <= 0 || isLinkingInProgress

        case .withdraw:
            return crowdNodeBalance <= 0 || walletBalance < CrowdNode.minimumLeftoverBalance || isLinkingInProgress

        default:
            return false
        }
    }

    func info(_ crowdNodeBalance: UInt64, _ onlineAccountState: CrowdNode.OnlineAccountState) -> String {
        switch self {
        case .deposit:
            let negligibleAmount = CrowdNode.minimumDeposit / 50
            let minimumDeposit = DSPriceManager.sharedInstance().string(forDashAmount: Int64(CrowdNode.minimumDeposit))!

            if crowdNodeBalance < negligibleAmount {
                return String.localizedStringWithFormat(NSLocalizedString("Deposit at least %@ to start earning", comment: "CrowdNode Portal"), minimumDeposit)
            } else {
                return String.localizedStringWithFormat(NSLocalizedString("Deposit %@ to start earning", comment: "CrowdNode Portal"), minimumDeposit)
            }
        case .withdraw:
//            if onlineAccountState == .confirming {
                return NSLocalizedString("Verification Required", comment: "CrowdNode Portal")
//            } else if onlineAccountState == .validating {
//                return NSLocalizedString("Validating address…", comment: "CrowdNode Portal")
//            } else {
//                return ""
//            }
        default:
            return ""
        }
    }
    
    var infoBackgroundColor: UIColor {
        switch self {
        case .deposit:
            return UIColor.dw_dashBlue().withAlphaComponent(0.08)
        default:
            return UIColor(red: 0.949, green: 0.949, blue: 0.949, alpha: 1)
        }
    }
    
    var infoTextColor: UIColor {
        switch self {
        case .deposit:
            return UIColor.dw_dashBlue()
        default:
            return UIColor.systemRed
        }
    }
    
    func infoActionButton(for state: CrowdNode.OnlineAccountState) -> String {
        if self == .withdraw {//&& state == .confirming {
            return NSLocalizedString("Verify", comment: "CrowdNode Portal")
        }
        
        return ""
    }
}
