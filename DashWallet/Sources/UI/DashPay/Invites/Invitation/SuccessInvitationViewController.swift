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

@objc protocol SuccessInvitationViewControllerDelegate: AnyObject {

@objc func successInvitationViewControllerDidSelectLater(controller: SuccessInvitationViewController)

}

@objc class SuccessInvitationViewController: BaseInvitationViewController {
    @objc weak var delegate: SuccessInvitationViewControllerDelegate?
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .default
    }
    
    @objc func laterButtonAction() {
        delegate?.successInvitationViewControllerDidSelectLater(controller: self)
    }
    
    override func configureTopView() {
        self.topView = SuccessInvitationTopView(frame: .zero)
        topView.translatesAutoresizingMaskIntoConstraints = false
        topView.layer.cornerRadius = 8.0
        topView.layer.masksToBounds = true
        topView.previewButton.addTarget(self, action: #selector(previewButtonAction), for: .touchUpInside)
        
        invitationView.addSubview(topView)
        
        NSLayoutConstraint.activate([
            topView.heightAnchor.constraint(equalTo: topView.widthAnchor, multiplier: 0.88),
            topView.topAnchor.constraint(equalTo: invitationView.topAnchor, constant: 23),
            topView.leadingAnchor.constraint(equalTo: invitationView.leadingAnchor),
            topView.trailingAnchor.constraint(equalTo: invitationView.trailingAnchor),
        ])
    }
    
    override func configureButtonsView() {
        super.configureButtonsView()
        
        sendButton.setTitle(NSLocalizedString("Send Invitation", comment: ""), for: .normal)
        
        let laterButton = DWActionButton()
        laterButton.translatesAutoresizingMaskIntoConstraints = false
        laterButton.inverted = true
        laterButton.setTitle(NSLocalizedString("Maybe later", comment: ""), for: .normal)
        laterButton.addTarget(self, action: #selector(laterButtonAction), for: .touchUpInside)
        buttonsView.addArrangedSubview(laterButton)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.topView.viewWillAppear()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.topView.viewDidAppear()
    }
}
