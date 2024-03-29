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

final class FailedOperationStatusViewController: BaseViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var descriptionLabel: UILabel!
    @IBOutlet var contactSupportButton: TintedButton!
    @IBOutlet var cancelButton: UIButton!
    @IBOutlet var retryButton: UIButton!

    var cancelHandler: (() -> ())?
    var retryHandler: (() -> ())?
    var supportHandler: (() -> ())?

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

    var supportButtonText: String! {
        didSet {
            contactSupportButton?.setTitle(supportButtonText, for: .normal)
        }
    }

    @IBAction
    func retryAction() {
        retryHandler?()
    }

    @IBAction
    func supportAction() {
        supportHandler?()
    }

    @IBAction
    func cancelAction() {
        cancelHandler?()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.text = headerText
        descriptionLabel.text = descriptionText

        contactSupportButton.configuration?.buttonSize = .small
        contactSupportButton.setTitle(supportButtonText, for: .normal)

        cancelButton.setTitle(NSLocalizedString("Cancel", comment: "Coinbase"), for: .normal)
        retryButton.setTitle(NSLocalizedString("Retry", comment: "Coinbase"), for: .normal)
    }
}
