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

final class GettingStartedViewController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()
    
    @IBOutlet var logoWrapper: UIView!
    @IBOutlet var newAccountButton: UIControl!
    @IBOutlet var newAccountTitle: UILabel!
    @IBOutlet var newAccountIcon: UIImageView!
    @IBOutlet var balanceHint: UIView!
    @IBOutlet var passphraseHint: UIView!
    @IBOutlet var linkAccountButton: UIControl!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureObservers()
    }
    
    @IBAction func newAccountAction() {
        self.navigationController?.pushViewController(NewAccountViewController.controller(), animated: true)
    }
    
    @IBAction func linkAccountAction() {
        print("CrowdNode: linkAccountAction")
    }
    
    @objc static func controller() -> GettingStartedViewController {
        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "GettingStartedViewController") as! GettingStartedViewController
        return vc
    }
}

extension GettingStartedViewController {
    private func configureHierarchy() {
        logoWrapper.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.05, x: 0, y: 0, blur: 10)
        newAccountButton.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)
        linkAccountButton.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)
        
        let options = DWGlobalOptions.sharedInstance()
        let walletNeedsBackup = options.walletNeedsBackup
        self.refreshCreateAccountButton(walletNeedsBackup, viewModel.hasEnoughBalance)
        self.passphraseHint.isHidden = !walletNeedsBackup
        let passhraseHintHeight = CGFloat(walletNeedsBackup ? 45 : 0)
        self.passphraseHint.heightAnchor.constraint(equalToConstant: passhraseHintHeight).isActive = true
    }
    
    private func configureObservers() {
        viewModel.$hasEnoughBalance
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] enoughBalance in
                guard let wSelf = self else { return }
                
                let needsBackup = DWGlobalOptions.sharedInstance().walletNeedsBackup
                wSelf.refreshCreateAccountButton(needsBackup, enoughBalance)
                wSelf.balanceHint.isHidden = enoughBalance
                let balanceHintHeight = CGFloat(enoughBalance ? 0 : 45)
                wSelf.balanceHint.heightAnchor.constraint(equalToConstant: balanceHintHeight).isActive = true
            })
            .store(in: &cancellableBag)
    }
    
    private func refreshCreateAccountButton(_ needsBackup: Bool, _ enoughBalance: Bool) {
        let isEnabled = !needsBackup && enoughBalance
        self.newAccountButton.isEnabled = isEnabled
        self.newAccountTitle.alpha = isEnabled ? 1.0 : 0.2
        self.newAccountIcon.alpha = isEnabled ? 1.0 : 0.2
    }
}
