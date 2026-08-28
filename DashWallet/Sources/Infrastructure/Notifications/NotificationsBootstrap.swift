//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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
import UserNotifications

/// The one Objective-C-visible seam the composition root (`AppDelegate`)
/// uses to build the notifications graph. Constructs each component exactly
/// once, wires `NotificationLifecycle` in as the notification-center
/// delegate, registers the categories, and injects the dispatcher into the
/// posting sites that predate it.
@objc(DWNotificationsBootstrap)
@MainActor
final class NotificationsBootstrap: NSObject {
    let store: NotifiedEventStore
    let permissionCoordinator: NotificationPermissionCoordinator
    let dispatcher: NotificationDispatcher
    let router: NotificationRouter
    let lifecycle: NotificationLifecycle
    /// Posts a notification per newly persisted incoming transaction.
    let transactionProducer: TransactionNotificationProducer

    @objc
    init(window: UIWindow) {
        let client = SystemUserNotificationCenterClient()
        let store = NotifiedEventStore.onSharedDatabase()
        let permissionCoordinator = NotificationPermissionCoordinator(client: client)
        let dispatcher = NotificationDispatcher(client: client,
                                                store: store,
                                                permissions: permissionCoordinator)
        let router = NotificationRouter(presentingController: { [weak window] in
            window?.rootViewController
        })
        let lifecycle = NotificationLifecycle(client: client, store: store, router: router)

        self.store = store
        self.permissionCoordinator = permissionCoordinator
        self.dispatcher = dispatcher
        self.router = router
        self.lifecycle = lifecycle
        self.transactionProducer = TransactionNotificationProducer(dispatcher: dispatcher,
                                                                   store: store)
        super.init()

        UNUserNotificationCenter.current().delegate = lifecycle
        dispatcher.registerCategories()
        transactionProducer.start()

        // `CrowdNode.shared` is created before this graph exists (in
        // `didFinishLaunching`), so its posting seam is injected statically
        // instead of adding another global.
        CrowdNode.notificationDispatcher = dispatcher
    }

    /// The OS-authorization request path `AppDelegate` exposes to the home
    /// screen's first-appearance prompt. Delegates to the permission
    /// coordinator; must be called on the main thread (it is — the chain is
    /// `HomeViewController` → `DWHomeModel` → `AppDelegate` → here).
    @objc
    func registerForPushNotifications() {
        permissionCoordinator.requestAuthorizationIfNeeded()
    }
}
