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

class CoinJoinLevelsViewController: UIViewController {
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var intermediateBox: UIView!
    @IBOutlet private var intermediateTitle: UILabel!
    @IBOutlet private var intermediateDescription: UILabel!
    @IBOutlet private var intermediateTime: UILabel!
    @IBOutlet private var advancedBox: UIView!
    @IBOutlet private var advancedTitle: UILabel!
    @IBOutlet private var advancedDescription: UILabel!
    @IBOutlet private var advancedTime: UILabel!
    @IBOutlet private var continueButton: UIButton!
    
    @objc
    static func controller() -> CoinJoinLevelsViewController {
        vc(CoinJoinLevelsViewController.self, from: sb("CoinJoin"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }

    @IBAction
    func continueButtonAction() {
        
    }
}

extension CoinJoinLevelsViewController {
    private func configureHierarchy() {
        titleLabel.text = NSLocalizedString("Select mixing level", comment: "CoinJoin")
        intermediateTitle.text = NSLocalizedString("Intermediate", comment: "CoinJoin")
        intermediateDescription.text = NSLocalizedString("Advanced users who have a very high level of technical expertise can determine your transaction history", comment: "Coinbase")
        intermediateTime.text = NSLocalizedString("up to 30 minutes", comment: "CoinJoin")
        
        advancedTitle.text = NSLocalizedString("Advanced", comment: "CoinJoin")
        advancedDescription.text = NSLocalizedString("It would be very difficult for advanced users with any level of technical expertise to determine your transaction history", comment: "Coinbase")
        advancedTime.text = NSLocalizedString("Multiple hours", comment: "CoinJoin")
        
        continueButton.setTitle(NSLocalizedString("Continue", comment: ""), for: .normal)
        
        intermediateBox.layer.cornerRadius = 14
        intermediateBox.layer.borderWidth = 1.5
        intermediateBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
        let intermediateTap = UITapGestureRecognizer(target: self, action: #selector(selectIntermediate))
        intermediateBox.addGestureRecognizer(intermediateTap)
        
        advancedBox.layer.cornerRadius = 14
        advancedBox.layer.borderWidth = 1.5
        advancedBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
        let advancedTap = UITapGestureRecognizer(target: self, action: #selector(selectAdvanced))
        advancedBox.addGestureRecognizer(advancedTap)
    }
    
    @objc
    private func selectIntermediate() {
        intermediateBox.layer.borderColor = UIColor.dw_dashBlue().cgColor
        advancedBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
    }
    
    @objc
    private func selectAdvanced() {
        intermediateBox.layer.borderColor = UIColor.dw_separatorLine().cgColor
        advancedBox.layer.borderColor = UIColor.dw_dashBlue().cgColor
    }
}
