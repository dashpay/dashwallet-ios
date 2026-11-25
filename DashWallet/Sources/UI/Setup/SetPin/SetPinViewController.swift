//
//  Created by Dash Core Group
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

import SwiftUI
import UIKit

/// Why a PIN is being set; it names the screen.
@objc(DWSetPinIntent)
enum SetPinIntent: Int {
    case createNewWallet
    case changePin
    /// A wallet exists but no PIN record does (partial keychain restore,
    /// interrupted setup) — there is no PIN to "change".
    case setPin
}

@objc(DWSetPinViewControllerDelegate)
protocol SetPinViewControllerDelegate: AnyObject {
    func setPinViewControllerDidCancel(_ controller: SetPinViewController)
    func setPinViewControllerDidSetPin(_ controller: SetPinViewController)
}

/// Hosts `SetPinView`, pushed in wallet setup and presented from Security
/// and the lock screen.
@objc(DWSetPinViewController)
final class SetPinViewController: UIViewController {
    @objc weak var delegate: SetPinViewControllerDelegate?

    private let viewModel = SetPinViewModel()

    @objc(controllerWithIntent:)
    static func controller(intent: SetPinIntent) -> SetPinViewController {
        SetPinViewController(intent: intent)
    }

    init(intent: SetPinIntent) {
        super.init(nibName: nil, bundle: nil)
        switch intent {
        case .createNewWallet:
            title = String(localized: "Create a New Wallet", comment: "")
        case .changePin:
            title = String(localized: "Change PIN", comment: "")
        case .setPin:
            title = String(localized: "Set PIN", comment: "")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(named: "SecondaryBackgroundColor")

        viewModel.onSet = { [weak self] in
            guard let self else { return }
            self.delegate?.setPinViewControllerDidSetPin(self)
        }
        viewModel.onCancel = { [weak self] in
            guard let self else { return }
            self.delegate?.setPinViewControllerDidCancel(self)
        }
        embedSwiftUI(SetPinView(viewModel: viewModel))
    }
}
