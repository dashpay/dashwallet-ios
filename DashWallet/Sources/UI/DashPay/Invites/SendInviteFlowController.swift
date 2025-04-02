//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

@objc(DWSendInviteFlowControllerDelegate)
protocol SendInviteFlowControllerDelegate: AnyObject {
    func sendInviteFlowControllerDidFinish(_ controller: SendInviteFlowController)
}

@objc(DWSendInviteFlowController)
class SendInviteFlowController: BaseInvitesViewController {
    
    @objc weak var delegate: SendInviteFlowControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let controller = DWSendInviteFirstStepViewController()
        controller.delegate = self
        controller.navigationItem.leftBarButtonItem = cancelBarButton()
        let navigation = BaseNavigationController(rootViewController: controller)
        dw_embedChild(navigation)
    }
    
    private func cancelBarButton() -> UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .cancel, 
                             target: self, 
                             action: #selector(cancelButtonAction))
    }
    
    @objc private func cancelButtonAction() {
        dismiss(animated: true, completion: nil)
    }
    
    private func showSuccessInvitation(_ invitation: DSBlockchainInvitation, fullLink: String) {
        let invitationController = SuccessInvitationViewController(with: invitation, 
                                                                  fullLink: fullLink, 
                                                                  index: 0)
        invitationController.delegate = self
        let modal = DWFullScreenModalControllerViewController(controller: invitationController)
        modal.delegate = self
        modal.title = NSLocalizedString("Invitation", comment: "")
        modal.modalPresentationStyle = .fullScreen
        present(modal, animated: true, completion: nil)
    }
}

// MARK: - DWSendInviteFirstStepViewControllerDelegate

extension SendInviteFlowController: DWSendInviteFirstStepViewControllerDelegate {
    func sendInviteFirstStepViewControllerNewInviteAction(_ controller: DWSendInviteFirstStepViewController) {
        runInvitationFlow { [weak self] link, invitation in
            let controller = BaseInvitationViewController(with: invitation, fullLink: link, index: 0)
            controller.title = NSLocalizedString("Invite", comment: "")
            controller.hidesBottomBarWhenPushed = true
            controller.view.backgroundColor = UIColor.dw_secondaryBackground()
            self?.present(controller, animated: true)
        }
    }
}

// MARK: - DWFullScreenModalControllerViewControllerDelegate

extension SendInviteFlowController: DWFullScreenModalControllerViewControllerDelegate {
    func fullScreenModalControllerViewControllerDidCancel(_ controller: DWFullScreenModalControllerViewController) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.delegate?.sendInviteFlowControllerDidFinish(self)
        }
    }
}

// MARK: - SuccessInvitationViewControllerDelegate

extension SendInviteFlowController: SuccessInvitationViewControllerDelegate {
    func successInvitationViewControllerDidSelectLater(controller: SuccessInvitationViewController) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.delegate?.sendInviteFlowControllerDidFinish(self)
        }
    }
} 
