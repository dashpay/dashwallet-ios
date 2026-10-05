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

import UIKit

final class SuccessfulOperationStatusViewController: ActionButtonViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }

    @IBOutlet var contentView: UIView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var descriptionLabel: UILabel!

    var closeHandler: (() -> ())?

    /// The screen is a wallet send's result (a Coinbase transfer from the
    /// wallet): while it is visible it holds its exits — and with them the
    /// app's routing and tab bar (`ExitHold`) — so an incoming link or a tab
    /// change cannot hide it before Close. Off for transfers made through the
    /// Coinbase API, whose wait this does not concern.
    var holdsExitsWhileShown = false
    private var exitHold: ExitHold?

    var headerText: String! {
        didSet {
            titleLabel?.text = headerText
        }
    }

    var descriptionText: String! {
        didSet {
            descriptionLabel?.text = descriptionText
        }
    }

    override var actionButtonTitle: String? {
        NSLocalizedString("Close", comment: "Action Button")
    }

    override func actionButtonAction(sender: UIView) {
        closeHandler?()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.text = headerText
        descriptionLabel.text = descriptionText
        actionButton?.isEnabled = true

        setupContentView(contentView)

        stackView.backgroundColor = .dw_background()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if holdsExitsWhileShown, exitHold == nil {
            exitHold = ExitHold(on: self)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        exitHold?.release()
        exitHold = nil
    }
}
