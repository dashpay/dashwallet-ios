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

    /// Groups transaction notifications into one Notification Center stack
    /// and lets `AppDelegate` clear exactly this thread when the app opens.
    @objc static let transactionsThreadIdentifier = "transactions"

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
        NotificationCenter.default.post(name: .willRequestOSPermission, object: nil)
        let options: UNAuthorizationOptions = [.badge, .sound, .alert]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .didRequestOSPermission, object: nil)
            }
            // `localNotificationsEnabled` is the user's in-app preference and
            // stays untouched here — mirroring the OS grant into it silently
            // re-enabled notifications the user had switched off in Settings.
            DWLogger.log("DWBalanceNotifier: register for notifications result \(granted), error \(String(describing: error))")
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
                // Unique per event: a shared identifier made every new payment
                // silently replace the previous banner instead of stacking.
                identifier = "tx.\(UUID().uuidString)"
                // The bundled resource is "coinflip.aiff" — without the
                // extension the sound name does not resolve and iOS delivers
                // the notification silently.
                sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "coinflip.aiff"))
                let receivedAmountText = received.formattedDashAmount
                let receivedInFiatText = CurrencyExchanger.shared.fiatAmountString(for: received.dashAmount)
                noteText = String(format: NSLocalizedString("Received %@ (%@)", comment: ""), receivedAmountText, receivedInFiatText)
            }

            DWLogger.log("DWBalanceNotifier: local notifications enabled = \(notificationsEnabled)")

            // send a local notification if in the background or it's a CrowdNode notification
            if application.applicationState == .background || application.applicationState == .inactive || isCrowdNode {
                if notificationsEnabled {
                    let content = UNMutableNotificationContent()
                    content.body = noteText
                    content.sound = sound
                    content.badge = NSNumber(value: application.applicationIconBadgeNumber + 1)
                    if !isCrowdNode {
                        content.threadIdentifier = Self.transactionsThreadIdentifier
                    }

                    // Deliver immediately — a delayed trigger races the user's
                    // return to the foreground.
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

                    // schedule localNotification
                    let center = UNUserNotificationCenter.current()
                    center.add(request) { error in
                        if let error {
                            DWLogger.log("DWBalanceNotifier: failed to send local notification: \(error)")
                        } else {
                            DWLogger.log("DWBalanceNotifier: sent local notification")
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
