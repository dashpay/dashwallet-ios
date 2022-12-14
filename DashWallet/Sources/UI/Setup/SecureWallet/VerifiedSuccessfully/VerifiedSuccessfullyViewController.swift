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

import Foundation

@objc(DWVerifiedSuccessfullyViewController)
final class VerifiedSuccessfullyViewController : UIViewController, NavigationFullscreenable {
    let requiresNoNavigationBar = true
    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
    @objc public weak var delegate: DWSecureWalletDelegate? = nil
    
    @IBOutlet var scrollView: UIScrollView!
    @IBOutlet var securityImageView: UIImageView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var descriptionLabel: UILabel!
    @IBOutlet var continueButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        scrollView.flashScrollIndicators()
    }

    @objc static func controller() -> VerifiedSuccessfullyViewController {
        let storyboard = UIStoryboard(name: "VerifiedSuccessfully", bundle: nil)
        return storyboard.instantiateInitialViewController() as! VerifiedSuccessfullyViewController
    }
    
    @IBAction func continueButtonAction() {
        delegate?.secureWalletRoutineDidFinish(self)
    }
}

extension VerifiedSuccessfullyViewController {
    private func setupView() {
        securityImageView.tintColor = UIColor.dw_dashBlue()
        titleLabel.text = NSLocalizedString("Verified Successfully", comment: "");
        descriptionLabel.text = NSLocalizedString("Your wallet is secured now. You can use your recovery phrase anytime to recover your account on another device.", comment: "")
        continueButton.setTitle(NSLocalizedString("Continue", comment: ""), for: .normal)

        titleLabel.font = UIFont.dw_font(forTextStyle: UIFont.TextStyle.title3)
        descriptionLabel.font = UIFont.dw_font(forTextStyle: UIFont.TextStyle.callout)
    }
}
