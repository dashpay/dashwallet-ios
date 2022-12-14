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

import WatchKit

// MARK: - DWTxInfoDisplayableInterfaceController

protocol DWTxInfoDisplayableInterfaceController {
    func subscribeToTxNotifications()
    func unsubsribeFromTxNotifications()
}

// MARK: - WKInterfaceController + DWTxInfoDisplayableInterfaceController

extension WKInterfaceController: DWTxInfoDisplayableInterfaceController {
    func subscribeToTxNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self,
                                       selector: #selector(txReceived(_:)),
                                       name: DWWatchDataManager.WalletTxReceiveNotification,
                                       object: nil)
    }

    func unsubsribeFromTxNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self,
                                          name: DWWatchDataManager.WalletTxReceiveNotification,
                                          object: nil)
    }

    @objc private func txReceived(_ notification: Notification?) {
        if Thread.current != .main {
            DispatchQueue.main.async {
                self.txReceived(notification)
            }

            return
        }

        print("receive view controller received notification: \(String(describing: notification))")

        guard let userData = (notification as NSNotification?)?.userInfo,
              let noteString = userData[NSLocalizedDescriptionKey] as? String
        else {
            return
        }

        // We don't have separate localized strings for WatchApp Extension so far
        // and since "OK" is pretty international, just don't care about localization
        let alertAction = WKAlertAction(title: "OK",
                                        style: .cancel,
                                        handler: {
                                            self.dismiss()
                                        })
        presentAlert(withTitle: noteString,
                     message: nil,
                     preferredStyle: .alert,
                     actions: [alertAction])
    }
}
