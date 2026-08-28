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
import UserNotifications

@objc(DWBalanceNotifier)
class DWBalanceNotifier: NSObject {

    // Combine subscriptions to SwiftDashSDKWalletState's balance publisher.
    private var cancellableBag = Set<AnyCancellable>()

    // the most recent balance as received by notification
    private var balance = UInt64.max

    private let dispatcher: NotificationDispatcher
    private let permissionCoordinator: NotificationPermissionCoordinator

    init(dispatcher: NotificationDispatcher,
         permissionCoordinator: NotificationPermissionCoordinator) {
        self.dispatcher = dispatcher
        self.permissionCoordinator = permissionCoordinator
        super.init()
    }

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
        permissionCoordinator.requestAuthorizationIfNeeded()
    }

    // MARK: Private

    private func walletBalanceDidChange() {
        let currentBalance = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        let application = UIApplication.shared

        if balance < currentBalance {
            let received = currentBalance - balance
            let isCrowdNode = received == (ApiCode.depositReceived.rawValue + CrowdNode.apiOffset)

            let notification: AppNotification
            if isCrowdNode {
                notification = AppNotification(
                    id: CrowdNode.notificationID,
                    topic: .crowdnode,
                    title: nil,
                    body: NSLocalizedString("Your deposit to CrowdNode is received.", comment: "CrowdNode"),
                    sound: .default,
                    route: .staking,
                    foregroundBehavior: .banner)
            } else {
                let receivedAmountText = received.formattedDashAmount
                let receivedInFiatText = CurrencyExchanger.shared.fiatAmountString(for: received.dashAmount)
                notification = AppNotification(
                    // Unique per event: a shared identifier made every new
                    // payment silently replace the previous banner instead
                    // of stacking.
                    id: "tx.\(UUID().uuidString)",
                    topic: .transactions,
                    title: nil,
                    body: String(format: NSLocalizedString("Received %@ (%@)", comment: ""), receivedAmountText, receivedInFiatText),
                    // The bundled resource is "coinflip.aiff" — without the
                    // extension the sound name does not resolve and iOS
                    // delivers the notification silently.
                    sound: UNNotificationSound(named: UNNotificationSoundName(rawValue: "coinflip.aiff")),
                    route: nil,
                    foregroundBehavior: .banner)
            }

            // post a local notification if in the background or it's a
            // CrowdNode notification; the dispatcher applies the permission
            // gate and dedup
            if application.applicationState == .background || application.applicationState == .inactive || isCrowdNode {
                Task { [dispatcher] in
                    await dispatcher.post(notification)
                }
            }

            #if !IGNORE_WATCH_TARGET
            // send a custom notification to the watch if the watch app is up
            DWPhoneWCSessionManager.sharedInstance().notifyTransactionString(notification.body)
            #endif
        }

        balance = currentBalance
    }

    deinit {
        cancellableBag.removeAll()
    }
}
