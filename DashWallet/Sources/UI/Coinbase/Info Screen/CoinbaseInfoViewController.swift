//
//  Created by Pavel Tikhonenko
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

// MARK: - CoinbaseInfoViewController

class CoinbaseInfoViewController: UIViewController {

    @IBOutlet var contentView: UIView!
    @IBOutlet var actionButton: UIButton!
    @IBOutlet var hairline: UIView!

    @IBAction
    func gotItAction() {
        dismiss(animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }

    class func controller() -> CoinbaseInfoViewController {
        vc(CoinbaseInfoViewController.self, from: sb("Coinbase"))
    }
}

extension CoinbaseInfoViewController {
    private func configureHierarchy() {
        definesPresentationContext = true
        view.backgroundColor = .black.withAlphaComponent(0.4)

        contentView.layer.cornerRadius = 15
        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .white
    }
}
