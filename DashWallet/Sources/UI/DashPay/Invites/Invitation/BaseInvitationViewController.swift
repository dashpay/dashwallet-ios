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

class InvitationSourceItem: NSObject, UIActivityItemSource
{
    let url: URL
    
    init(with url: URL) {
        self.url = url
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return NSLocalizedString("DashPay Invitation", comment: "")
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return self.url
    }
}


@objc class BaseInvitationViewController: UIViewController {
    internal var topView: BaseInvitationTopView!
    internal var actionsView: DWInvitationActionsView!
    internal var invitationView: UIView!
    internal var buttonsView: UIStackView!
    internal var sendButton: DWActionButton!
    private var bottomConstraint:  NSLayoutConstraint!
    
    internal let invitation: DSBlockchainInvitation
    internal let fullLink: String
    internal var invitationURL: URL!
    
    internal var index: Int
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
    
    @objc public init(with invitation: DSBlockchainInvitation, fullLink: String, index: Int = 0) {
        self.invitation = invitation
        self.fullLink = fullLink
        self.index = index
        
        super.init(nibName: nil, bundle: nil)
        
        let wallet = DWEnvironment.sharedInstance().currentWallet
        let myBlockchainIdentity: DSBlockchainIdentity = wallet.defaultBlockchainIdentity!
        
        DWInvitationLinkBuilder.dynamicLink(from: fullLink, myBlockchainIdentity: myBlockchainIdentity, completion: { [weak self] url in
            self?.invitationURL = url ?? URL(string: fullLink)
        })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    //MARK: Actions
    
    @objc func sendButtonAction() {
        let invitationURL = self.invitationURL!
        
        let imageSize: CGSize = CGSize(width: 320, height: 440)
        let messageView = DWInvitationMessageView(frame: CGRect(x: 0, y: -1000, width: imageSize.width, height: imageSize.height))
        self.view.window?.addSubview(messageView)
        
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let image = renderer.image { ctx in
            messageView.drawHierarchy(in: messageView.bounds, afterScreenUpdates: true)
        }
        messageView.removeFromSuperview()
        
        let shareItem = InvitationSourceItem(with: invitationURL)
    
        let sharingController = UIActivityViewController(activityItems: [ shareItem, image ], applicationActivities: nil)
        self.present(sharingController, animated: true)
    }
    
    @objc func previewButtonAction() {
        let previewController = DWInvitationPreviewViewController()
        self.present(previewController, animated: true)
    }
    
    @objc func profileAction() {
        let item = DWDPUserObject(blockchainIdentity: invitation.identity)
        let payModel = DWPayModel()
        let dataProvider = DWTransactionListDataProviderStub()
        
        let profileController = DWUserProfileViewController(item: item, payModel: payModel, dataProvider: dataProvider, shouldSkipUpdating: true, shownAfterPayment: false)
        self.navigationController?.pushViewController(profileController, animated: true)
    }
    
    //MARK: Hierarchy
    
    internal func configureInvitationView() {
        invitationView = UIView()
        invitationView.translatesAutoresizingMaskIntoConstraints = false
        
        configureTopView()
        
        if invitation.identity.isRegistered {
            topView.previewButton.isHidden = true
        }else{
            configureActionsView()
        }
    }
    
    internal func configureTopView() {
        self.topView = InvitationTopView(index: index)
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
    
    internal func configureActionsView() {
        actionsView = DWInvitationActionsView(frame: .zero)
        actionsView.translatesAutoresizingMaskIntoConstraints = false
        actionsView.delegate = self
        invitationView.addSubview(actionsView)
        
        NSLayoutConstraint.activate([
            actionsView.topAnchor.constraint(equalTo: self.topView.bottomAnchor, constant: 20),
            actionsView.leadingAnchor.constraint(equalTo: self.invitationView.leadingAnchor),
            actionsView.trailingAnchor.constraint(equalTo: self.invitationView.trailingAnchor),
            actionsView.bottomAnchor.constraint(equalTo: self.invitationView.bottomAnchor),
        ])
    }
    
    internal func configureButtonsView() {
        buttonsView = UIStackView()
        buttonsView.axis = .vertical
        buttonsView.spacing = 8
        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(buttonsView)
        
        if invitation.identity.isRegistered
        {
            let tap = UITapGestureRecognizer(target: self, action: #selector(profileAction))
            let view = InvitationBottomView(invitation: invitation)
            view.addGestureRecognizer(tap)
            buttonsView.addArrangedSubview(view)
        }else{
            sendButton = DWActionButton()
            sendButton.translatesAutoresizingMaskIntoConstraints = false
            sendButton.setTitle(NSLocalizedString("Send again", comment: ""), for: .normal)
            sendButton.addTarget(self, action: #selector(sendButtonAction), for: .touchUpInside)
            buttonsView.addArrangedSubview(sendButton)
            
            NSLayoutConstraint.activate([
                sendButton.heightAnchor.constraint(equalToConstant: 50)
            ])
        }
    }
    
    private func configureBottomView() {
        
    }
    
    internal func configureHierarchy() {
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(contentView)
        
        configureButtonsView()
        
        self.bottomConstraint = self.view.layoutMarginsGuide.bottomAnchor.constraint(equalTo: self.buttonsView.bottomAnchor, constant: 16)
        
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.trailingAnchor),
            
            self.buttonsView.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 10),
            self.buttonsView.leadingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.leadingAnchor),
            self.buttonsView.trailingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.trailingAnchor),
            
            bottomConstraint,
        ])
    
        let scrollingController = DWScrollingViewController()
        scrollingController.keyboardNotificationsEnabled = false
        self.dw_embedChild(scrollingController, inContainer: contentView)
        
        configureInvitationView()
        
        scrollingController.contentView.dw_embedSubview(self.invitationView)
        scrollingController.scrollView.showsVerticalScrollIndicator = false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
        
        let wallet = DWEnvironment.sharedInstance().currentWallet
        let myBlockchainIdentity = wallet.defaultBlockchainIdentity!
        topView.update(with: myBlockchainIdentity, invitation: invitation)
        
        self.actionsView?.tagTextField.text = invitation.tag;
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.ka_startObservingKeyboardNotifications()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        self.invitation.updateInWallet()
        self.ka_stopObservingKeyboardNotifications()
    }
        
    override func ka_keyboardShowOrHideAnimation(withHeight height: CGFloat, animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        self.bottomConstraint.constant = height > 0 ? height : 16
        self.view.layoutIfNeeded()
    }
}

extension BaseInvitationViewController: DWInvitationActionsViewDelegate {
    func invitationActionsViewCopyButtonAction(_ view: DWInvitationActionsView) {
        UIPasteboard.general.string = invitationURL.absoluteString
    }
    
    func invitationActionsView(_ view: DWInvitationActionsView, didChangeTag tag: String) {
        invitation.tag = tag
    }
}
