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

// MARK: - DeepLinkRoute

/// Typed destination a notification tap navigates to. Codable so it survives
/// the round trip through `UNNotificationContent.userInfo` (as JSON `Data`).
enum DeepLinkRoute: Codable, Equatable {
    case home
    case transactionDetail(txid: Data)
    /// CrowdNode.
    case staking
    case swapOrder(id: String)
    /// The DashPay bell screen.
    case dashPayNotifications
    /// An external or announcement link (the "action"/"url" payload contract).
    case url(URL)
}

extension DeepLinkRoute {
    /// The value for `userInfo[NotificationUserInfoKey.route]`.
    func encodedForUserInfo() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Decodes a route previously written by `encodedForUserInfo()`.
    /// `nil` for notifications that carry none (legacy or foreign requests).
    static func decode(fromUserInfo userInfo: [AnyHashable: Any]) -> DeepLinkRoute? {
        guard let data = userInfo[NotificationUserInfoKey.route] as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(DeepLinkRoute.self, from: data)
    }
}
