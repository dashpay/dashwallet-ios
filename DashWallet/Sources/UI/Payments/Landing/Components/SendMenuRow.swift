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

/// What a Send menu row does when tapped. The view layer maps each case to
/// the destination it already opens.
enum SendMenuAction: Equatable {
    case openContactFlow
    case openAddressScreen
    case openQRScanner
}

/// The rows of the Send tab menu (SCR-01), in display order.
enum SendMenuRow {
    case sendToUsername
    case sendToAddress
    case scanQR

    static var allRows: [SendMenuRow] { [.sendToUsername, .sendToAddress, .scanQR] }

    var title: String {
        switch self {
        case .sendToUsername: return NSLocalizedString("Send to username", comment: "Payments")
        case .sendToAddress: return NSLocalizedString("Send to Dash address", comment: "Payments")
        case .scanQR: return NSLocalizedString("Scan Dash QR", comment: "Payments")
        }
    }

    var action: SendMenuAction {
        switch self {
        case .sendToUsername: return .openContactFlow
        case .sendToAddress: return .openAddressScreen
        case .scanQR: return .openQRScanner
        }
    }
}
