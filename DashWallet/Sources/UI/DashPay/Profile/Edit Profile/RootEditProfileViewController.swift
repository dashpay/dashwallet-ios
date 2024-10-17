//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#if DASHPAY
@objc(DWRootEditProfileViewControllerDelegate)
protocol RootEditProfileViewControllerDelegate: AnyObject {
    func editProfileViewController(_ controller: RootEditProfileViewController, updateDisplayName rawDisplayName: String, aboutMe rawAboutMe: String, avatarURLString: String?)
    func editProfileViewControllerDidCancel(_ controller: RootEditProfileViewController)
}

@objc(DWRootEditProfileViewController)
class RootEditProfileViewController: ActionButtonViewController, DWEditProfileViewControllerDelegate, DWSaveAlertViewControllerDelegate, NavigationBarDisplayable {
    
    var isBackButtonHidden: Bool = false
    
    @objc
    weak var delegate: RootEditProfileViewControllerDelegate?
    private var editController: DWEditProfileViewController!
    var blockchainIdentity: DSBlockchainIdentity? {
        return editController.blockchainIdentity
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Edit Profile", comment: "")
        
        let cancel = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonAction))
        self.navigationItem.leftBarButtonItem = cancel
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        setupContentView(contentView)
        
        self.editController = DWEditProfileViewController()
        self.editController.delegate = self
        self.dw_embedChild(self.editController, inContainer: contentView)
        
        self.editProfileViewControllerDidUpdate(self.editController)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override var actionButtonTitle: String {
        return NSLocalizedString("Save", comment: "")
    }
    
    @objc private func cancelButtonAction() {
        if self.editController.hasChanges() {
            let saveAlert = DWSaveAlertViewController()
            saveAlert.delegate = self
            self.present(saveAlert, animated: true, completion: nil)
        } else {
            self.delegate?.editProfileViewControllerDidCancel(self)
        }
    }
    
    @objc override func actionButtonAction(sender: UIView) {
        performSave()
    }
    
    private func performSave() {
        self.delegate?.editProfileViewController(self, updateDisplayName: self.editController.displayName, aboutMe: self.editController.aboutMe, avatarURLString: self.editController.avatarURLString)
    }
    
    // MARK: - DWEditProfileViewControllerDelegate
    
    func editProfileViewControllerDidUpdate(_ controller: DWEditProfileViewController) {
        self.actionButton?.isEnabled = controller.isValid
    }
    
    // MARK: - DWSaveAlertViewControllerDelegate
    
    func saveAlertViewControllerCancelAction(_ controller: DWSaveAlertViewController) {
        controller.dismiss(animated: true) {
            self.delegate?.editProfileViewControllerDidCancel(self)
        }
    }
    
    func saveAlertViewControllerOKAction(_ controller: DWSaveAlertViewController) {
        controller.dismiss(animated: true) {
            self.performSave()
        }
    }
    
    private func dw_embedChild(_ child: UIViewController, inContainer container: UIView) {
        addChild(child)
        container.addSubview(child.view)
        child.view.frame = container.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.didMove(toParent: self)
    }
}
#else
@objc(DWRootEditProfileViewControllerDelegate)
protocol RootEditProfileViewControllerDelegate: AnyObject { }
#endif
