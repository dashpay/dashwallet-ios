//
//  Created by tkhp
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

@objc(DWBalanceNotifier)
class DWBalanceNotifier: NSObject {

    // the nsnotificationcenter observer for wallet balance
    private var balanceObserver: Any?

    // the most recent balance as received by notification
    private var balance = UInt64.max

    // MARK: Public

    @objc
    func setupNotifications() {
        balance = UInt64.max // this gets set in `updateBalance` (called in applicationDidBecomActive)

        let notificationCenter = NotificationCenter.default

        balanceObserver = notificationCenter.addObserver(forName: NSNotification.Name("DSWalletBalanceChangedNotification"),
                                                         object: nil,
                                                         queue: nil) { [weak self] note in
            self?.walletBalanceDidChangeNotification(note: note)
        }
    }

    @objc
    func updateBalance() {
        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self, self.balance == UInt64.max else {
                return
            }
            self.balance = DWEnvironment.sharedInstance().currentWallet.balance
        }
    }

    @objc
    func registerForPushNotifications() {
        NotificationCenter.default.post(name: NSNotification.Name("org.dash.will-request-permission-notification"), object: nil)
        let options: UNAuthorizationOptions = [.badge, .sound, .alert]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("org.dash.did-request-permission-notification"), object: nil)
            }
            DWGlobalOptions.sharedInstance().localNotificationsEnabled = granted
            DSLogger.log("DWBalanceNotifier: register for notifications result \(granted), error \(String(describing: error))")
        }
    }

    // MARK: Private

    private func walletBalanceDidChangeNotification(note: Notification) {
        let wallet = DWEnvironment.sharedInstance().currentWallet
        let application = UIApplication.shared

        if balance < wallet.balance {
            let notificationsEnabled = DWGlobalOptions.sharedInstance().localNotificationsEnabled
            let received = wallet.balance - balance
            var noteText = ""
            var identifier = ""
            var sound: UNNotificationSound?
            let isCrowdNode = received == (ApiCode.depositReceived.rawValue + CrowdNode.apiOffset)

            if isCrowdNode {
                identifier = CrowdNode.notificationID
                sound = UNNotificationSound.default
                noteText = NSLocalizedString("Your deposit to CrowdNode is received.", comment: "CrowdNode")
            } else {
                identifier = "Now"
                sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "coinflip"))
                let receivedAmountText = received.formattedDashAmount
                let receivedInFiatText = CurrencyExchanger.shared.fiatAmountString(for: received.dashAmount)
                noteText = String(format: NSLocalizedString("Received %@ (%@)", comment: ""), receivedAmountText, receivedInFiatText)
            }

            DSLogger.log("DWBalanceNotifier: local notifications enabled = \(notificationsEnabled)")

            // send a local notification if in the background or it's a CrowdNode notification
            if application.applicationState == .background || application.applicationState == .inactive || isCrowdNode {
                if notificationsEnabled {
                    let content = UNMutableNotificationContent()
                    content.body = noteText
                    content.sound = sound
                    content.badge = NSNumber(value: application.applicationIconBadgeNumber + 1)

                    // Deliver the notification in one second.
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                    // schedule localNotification
                    let center = UNUserNotificationCenter.current()
                    center.add(request) { error in
                        if let error {
                            DSLogger.log("DWBalanceNotifier: failed to send local notification: \(error)")
                        } else {
                            DSLogger.log("DWBalanceNotifier: sent local notification \(note)")
                        }
                    }
                }
            }

            #if !IGNORE_WATCH_TARGET
            // send a custom notification to the watch if the watch app is up
            DWPhoneWCSessionManager.sharedInstance().notifyTransactionString(noteText)
            #endif
        }

        balance = wallet.balance
    }

    deinit {
        if let observer = balanceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

