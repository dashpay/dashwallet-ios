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
import SwiftUI

@objc(DWContactsPlaceholderViewController)
class ContactsPlaceholderViewController: ActionButtonViewController {
    
    // MARK: - Properties
    
    private let dashPayModel: DWDashPayProtocol
    private let dashPayReady: DWDashPayReadyProtocol
    
    #if DASHPAY
    var shouldShowMixDashDialog: Bool {
        get { CoinJoinService.shared.mode == .none || !UsernamePrefs.shared.mixDashShown }
        set(value) { UsernamePrefs.shared.mixDashShown = !value }
    }

    var shouldShowDashPayInfo: Bool {
        get { !UsernamePrefs.shared.joinDashPayInfoShown }
        set(value) { UsernamePrefs.shared.joinDashPayInfoShown = !value }
    }
    #endif
    
    // MARK: - Initializers
    
    @objc
    init(dashPayModel: DWDashPayProtocol, dashPayReady: DWDashPayReadyProtocol) {
        self.dashPayModel = dashPayModel
        self.dashPayReady = dashPayReady
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable, message: "init(coder:) is not available. Use init(dashPayModel:dashPayReady:) instead.")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @available(*, unavailable, message: "init(nibName:bundle:) is not available. Use init(dashPayModel:dashPayReady:) instead.")
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        fatalError("init(nibName:bundle:) has not been implemented")
    }
    
    // MARK: - Overrides
    
    override var actionButtonTitle: String {
        return NSLocalizedString("Upgrade", comment: "Title for the upgrade action button")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
        setupNotifications()
        update()
    }
    
    // MARK: - Setup Methods
    
    private func setupView() {
        view.backgroundColor = UIColor.dw_secondaryBackground()
        
        let imageView = UIImageView(image: UIImage(named: "contacts_placeholder_icon"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.dw_font(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.text = NSLocalizedString("Upgrade to Evolution", comment: "Title label text")
        titleLabel.textColor = UIColor.dw_darkTitle()
        titleLabel.numberOfLines = 0
        
        let descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.textAlignment = .center
        descriptionLabel.font = UIFont.dw_font(forTextStyle: .subheadline)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.text = NSLocalizedString("Create your Username, find friends & family with their usernames and add them to your contacts", comment: "Description label text")
        descriptionLabel.textColor = UIColor.dw_tertiaryText()
        descriptionLabel.numberOfLines = 0
        
        let verticalStackView = UIStackView(arrangedSubviews: [imageView, titleLabel, descriptionLabel])
        verticalStackView.translatesAutoresizingMaskIntoConstraints = false
        verticalStackView.axis = .vertical
        verticalStackView.spacing = 4.0
        verticalStackView.setCustomSpacing(26.0, after: imageView)
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = view.backgroundColor
        contentView.addSubview(verticalStackView)
        
        NSLayoutConstraint.activate([
            verticalStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            verticalStackView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: verticalStackView.bottomAnchor),
            verticalStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: verticalStackView.trailingAnchor)
        ])
        
        setupContentView(contentView)
    }
    
    private func setupNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self,
                                       selector: #selector(update),
                                       name: .DWDashPayRegistrationStatusUpdatedNotification,
                                       object: nil)
    }
    
    // MARK: - Actions
    
    @objc override func actionButtonAction(sender: UIView) {
        if shouldShowMixDashDialog {
            self.showMixDashDialog(sender)
        } else if shouldShowDashPayInfo {
            self.showDashPayInfo()
        } else {
            self.navigateToCreateUsername()
        }
    }
    
    private func showMixDashDialog(_ sender: UIView) {
        let swiftUIView = MixDashDialog(
            positiveAction: {
                let controller = CoinJoinLevelsViewController.controller(isFullScreen: true)
                self.present(controller, animated: true, completion: nil)
            }, negativeAction: {
                if UsernamePrefs.shared.joinDashPayInfoShown {
                    self.navigateToCreateUsername()
                } else {
                    UsernamePrefs.shared.joinDashPayInfoShown = true
                    self.showDashPayInfo()
                }
            }
        )
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(260)
        
        present(hostingController, animated: true, completion: nil)
    }
 
    private func showDashPayInfo() {
        let swiftUIView = JoinDashPayInfoDialog() {
            self.navigateToCreateUsername()
        }
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(600)
        present(hostingController, animated: true, completion: nil)
    }
    
    @objc func update() {
        actionButton?.isEnabled = dashPayReady.shouldShowCreateUserNameButton()
    }
    
    private func navigateToCreateUsername() {
        let controller = CreateUsernameViewController(dashPayModel: self.dashPayModel,
                                                     invitationURL: nil,
                                                   definedUsername: nil)
        controller.modalPresentationStyle = .fullScreen
        self.present(controller, animated: true, completion: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let DWDashPayRegistrationStatusUpdatedNotification = Notification.Name("DWDashPayRegistrationStatusUpdatedNotification")
    // static let DWDashPayAvailabilityStatusUpdatedNotification = Notification.Name("DWDashPayAvailabilityStatusUpdatedNotification")
}
