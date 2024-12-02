//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

import UIKit

extension UIViewController {
    @objc
    func showTxFilter(sender: UIView,
                     displayModeCallback: @escaping (HomeTxDisplayMode) -> Void,
                     shouldShowRewards: Bool) {
        let title = NSLocalizedString("Filter Transactions", comment: "")
        let alert = UIAlertController(title: title,
                                    message: nil,
                                    preferredStyle: .actionSheet)
        
        let allAction = UIAlertAction(
            title: NSLocalizedString("All", comment: ""),
            style: .default) { _ in
                displayModeCallback(.all)
            }
        alert.addAction(allAction)
        
        let receivedAction = UIAlertAction(
            title: NSLocalizedString("Received", comment: ""),
            style: .default) { _ in
                displayModeCallback(.received)
            }
        alert.addAction(receivedAction)
        
        let account = DWEnvironment.sharedInstance().currentAccount
        if shouldShowRewards && account.hasCoinbaseTransaction {
            let rewardsAction = UIAlertAction(
                title: NSLocalizedString("Rewards", comment: ""),
                style: .default) { _ in
                    displayModeCallback(.rewards)
                }
            alert.addAction(rewardsAction)
        }
        
        let sentAction = UIAlertAction(
            title: NSLocalizedString("Sent", comment: ""),
            style: .default) { _ in
                displayModeCallback(.sent)
            }
        alert.addAction(sentAction)
        
        let cancelAction = UIAlertAction(
            title: NSLocalizedString("Cancel", comment: ""),
            style: .cancel)
        alert.addAction(cancelAction)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            alert.popoverPresentationController?.sourceView = sender
            alert.popoverPresentationController?.sourceRect = sender.bounds
        }
        
        present(alert, animated: true)
    }
}
