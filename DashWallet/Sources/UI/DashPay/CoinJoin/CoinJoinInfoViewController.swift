//  
//  Created by Andrei Ashikhmin
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

class CoinJoinInfoViewController: UIViewController {
    private let viewModel = CoinJoinLevelViewModel.shared
    
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var subtitleLabel: UILabel!
    @IBOutlet private var description1: UILabel!
    @IBOutlet private var description2: UILabel!
    @IBOutlet private var description3: UILabel!
    @IBOutlet private var continueButton: UIButton!
    
    @objc
    static func controller() -> CoinJoinInfoViewController {
        vc(CoinJoinInfoViewController.self, from: sb("CoinJoin"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.infoShown = true
        configureHierarchy()
    }

    @IBAction
    func continueButtonAction() {
        self.navigationController?.replaceLast(with: CoinJoinLevelsViewController.controller())
    }
}

extension CoinJoinInfoViewController {
    private func configureHierarchy() {
        titleLabel.text = NSLocalizedString("CoinJoin", comment: "CoinJoin")
        subtitleLabel.text = NSLocalizedString("Mixing your Dash coins will make your transactions more private", comment: "CoinJoin")
        description1.text = NSLocalizedString("You will only be able to spend Dash that has been mixed when this is turned on. This can be turned off at any time.", comment: "Coinbase")
        description2.text = NSLocalizedString("Newly received Dash will be automatically mixed when the wallet is opened", comment: "Coinbase")
        description3.text = NSLocalizedString("Turning this feature on will result a higher battery usage", comment: "Coinbase")
        continueButton.setTitle(NSLocalizedString("Continue", comment: ""), for: .normal)
    }
}
