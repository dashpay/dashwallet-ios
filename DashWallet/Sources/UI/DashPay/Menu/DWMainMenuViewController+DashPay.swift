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

import UIKit

extension DWMainMenuViewController: RootEditProfileViewControllerDelegate {
    func editProfileViewController(_ controller: RootEditProfileViewController, updateDisplayName rawDisplayName: String, aboutMe rawAboutMe: String, avatarURLString: String?) {
        guard let view = self.view as? DWMainMenuContentView else { return }
        view.userModel.updateModel.update(withDisplayName: rawDisplayName, aboutMe: rawAboutMe, avatarURLString: avatarURLString)
        controller.dismiss(animated: true, completion: nil)
        
        if MOCK_DASHPAY.boolValue {
            BuyCreditsModel.currentCredits -= 0.25
            let heading: String
            let message: String
            
            if BuyCreditsModel.currentCredits <= 0 {
                heading = NSLocalizedString("Your credit balance has been fully depleted", comment: "")
                message = NSLocalizedString("You can continue to use DashPay for payments but you cannot update your profile or add more contacts until you top up your credit balance", comment: "")
            } else if BuyCreditsModel.currentCredits <= 0.25 {
                heading = NSLocalizedString("Your credit balance is low", comment: "")
                message = NSLocalizedString("Top-up your credits to continue making changes to your profile and adding contacts", comment: "")
            } else {
                return
            }
            
            showModalDialog(style: .warning, icon: .system("exclamationmark.triangle.fill"), heading: heading, textBlock1: message, positiveButtonText: NSLocalizedString("Buy credits", comment: ""), positiveButtonAction: {

                let vc = BuyCreditsViewController {
                    self.showToast(text: "Successful purchase", icon: .system("checkmark.circle.fill"), duration: 2)
                }
                let navigationController = BaseNavigationController(rootViewController: vc)
                self.present(navigationController, animated: true)
            }, negativeButtonText: NSLocalizedString("Maybe later", comment: ""))
        }
    }
    
    func editProfileViewControllerDidCancel(_ controller: RootEditProfileViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
}
