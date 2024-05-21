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

extension HomeViewController: BackupInfoViewControllerDelegate {
    func showWalletBackupReminderIfNeeded() {
        guard model.shouldShowWalletBackupReminder else {
            return
        }

        let controller = BackupInfoViewController.controller(with: .reminder)
        controller.delegate = self

        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true) { [weak self] in
            guard let self = self else { return }
            if let navController = self.presentedViewController as? UINavigationController,
               let _ = navController.topViewController as? BackupInfoViewController {
                self.model.walletBackupReminderWasShown()
            }
        }
    }
}
