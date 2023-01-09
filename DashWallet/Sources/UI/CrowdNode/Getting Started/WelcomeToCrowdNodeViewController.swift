//
//  Created by Andrei Ashikhmin
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

import Combine

final class WelcomeToCrowdNodeViewController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()

    @IBOutlet var logoWrapper: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        logoWrapper.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.05, x: 0, y: 0, blur: 10)
        viewModel.didShowInfoScreen()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellableBag.removeAll()
    }

    @IBAction func continueAction() {
        navigationController?.replaceLast(with: GettingStartedViewController.controller())
    }

    @objc static func controller() -> WelcomeToCrowdNodeViewController {
        vc(WelcomeToCrowdNodeViewController.self, from: sb("CrowdNode"))
    }
}
