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

import Foundation

/// One value per notification class the app posts. The raw value doubles as
/// the `UNNotificationContent.threadIdentifier`, so Notification Center
/// stacks each topic into its own group, and as the category identifier the
/// topic's actions are registered under.
enum NotificationTopic: String, CaseIterable {
    case transactions
    case dashpay
    case crowdnode
    case swap
    case announcements
    case system
}
