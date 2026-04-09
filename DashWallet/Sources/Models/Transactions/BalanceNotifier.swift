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
import Combine

@objc(DWBalanceNotifier)
class DWBalanceNotifier: NSObject {

    // Combine subscriptions to SwiftDashSDKWalletState's balance publisher.
    private var cancellableBag = Set<AnyCancellable>()

    // the most recent balance as received by notification
    private var balance = UInt64.max

    // MARK: Public

    @objc
    func setupNotifications() {
        balance = UInt64.max // this gets set in `updateBalance` (called in applicationDidBecomActive)

        // Subscribe to SwiftDashSDKWalletState's balance publisher.
        // After M6 retired DashSync's SPV, the legacy
        // DSWalletBalanceChangedNotification no longer fires.
        // Function #5 follow-up.
        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.walletBalanceDidChange()
            }
            .store(in: &cancellableBag)
    }

    @objc
    func updateBalance() {
        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self, self.balance == UInt64.max else {
                return
            }
            self.balance = SwiftDashSDKWalletState.shared.balance?.total ?? 0
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

    private func walletBalanceDidChange() {
        let currentBalance = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        let application = UIApplication.shared

        if balance < currentBalance {
            let notificationsEnabled = DWGlobalOptions.sharedInstance().localNotificationsEnabled
            let received = currentBalance - balance
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
                            DSLogger.log("DWBalanceNotifier: sent local notification")
                        }
                    }
                }
            }

            #if !IGNORE_WATCH_TARGET
            // send a custom notification to the watch if the watch app is up
            DWPhoneWCSessionManager.sharedInstance().notifyTransactionString(noteText)
            #endif
        }

        balance = currentBalance
    }

    deinit {
        cancellableBag.removeAll()
    }
}

