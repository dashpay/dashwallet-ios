//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

// MARK: - MessageLevel

enum MessageLevel {
    case success
    case info
    case warning
    case error
}

// MARK: - MessageDataProvider

protocol MessageDataProvider {
    var message: String { get }
    var level: MessageLevel { get }
}

// MARK: - MessageItem

struct MessageItem: MessageDataProvider {
    let message: String
    let level: MessageLevel
}

// MARK: - MessagePresentable

protocol MessagePresentable {
    func present(message: MessageDataProvider)
    func present(message: String, level: MessageLevel)
}

// MARK: - ErrorPresentable

protocol ErrorPresentable: MessagePresentable {
    func present(error: Error)
}

extension ErrorPresentable where Self: UIViewController {
    func present(message: MessageDataProvider) {
        present(message: message.message, level: message.level)
    }

    func present(message: String, level: MessageLevel) {
        showAlert(with: "Error", message: message)
    }
}
