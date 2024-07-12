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

protocol DWDashPaySetupFlowControllerDelegate: AnyObject {
    func dashPaySetupFlowController(_ controller: DashPaySetupFlowController, didConfirmUsername username: String)
}

@objc(DWDashPaySetupFlowController)
class DashPaySetupFlowController: UIViewController, NavigationFullscreenable, DWCreateUsernameViewControllerDelegate, DWConfirmUsernameViewControllerDelegate, DWUsernamePendingViewControllerDelegate, DWRegistrationCompletedViewControllerDelegate {

    private(set) var dashPayModel: DWDashPayProtocol
    private(set) var invitationURL: URL?
    private(set) var definedUsername: String?
    weak var confirmationDelegate: DWDashPaySetupFlowControllerDelegate?

    private var headerView: DWUsernameHeaderView!
    private var contentView: UIView!
    private var headerHeightConstraint: NSLayoutConstraint!

    private var containerController: DWContainerViewController!
    private var createUsernameViewController: DWCreateUsernameViewController!

    @objc
    init(dashPayModel: DWDashPayProtocol, invitationURL: URL?, definedUsername: String?) {
        self.dashPayModel = dashPayModel
        self.invitationURL = invitationURL
        self.definedUsername = definedUsername
        super.init(nibName: nil, bundle: nil)
    }

    init(confirmationDelegate: DWDashPaySetupFlowControllerDelegate) {
        self.dashPayModel = DWDashPaySetupModel()
        self.confirmationDelegate = confirmationDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.clipsToBounds = true
        view.backgroundColor = UIColor.dw_secondaryBackground()

        view.addSubview(contentView)
        view.addSubview(headerView)

        let isLandscape = view.bounds.width > view.bounds.height
        let headerHeight = isLandscape ? LandscapeHeaderHeight() : HeaderHeight()
        headerView.landscapeMode = isLandscape
        headerHeightConstraint = headerView.heightAnchor.constraint(equalToConstant: headerHeight)
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            headerHeightConstraint,
            contentView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])

        containerController = DWContainerViewController()
        embedChild(containerController, in: contentView)

        NotificationCenter.default.addObserver(self, selector: #selector(registrationStatusUpdatedNotification), name: NSNotification.Name.DWDashPayRegistrationStatusUpdated, object: nil)

        setCurrentStateController()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
            let isLandscape = size.width > size.height
            self.headerView.landscapeMode = isLandscape
            self.headerHeightConstraint.constant = isLandscape ? LandscapeHeaderHeight() : HeaderHeight()
        })
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        headerView.showInitialAnimation()
    }

    // MARK: - DWNavigationFullscreenable

    var requiresNoNavigationBar: Bool {
        return true
    }

    // MARK: - Private

    @objc private func registrationStatusUpdatedNotification() {
        if MOCK_DASHPAY.boolValue {
            setCurrentStateController()
            return
        }

        if let lastRegistrationError = dashPayModel.lastRegistrationError {
            dw_displayErrorModally(lastRegistrationError)
        }

        setCurrentStateController()
    }

    private func setCurrentStateController() {
        if let definedUsername = definedUsername {
            createUsername(definedUsername)
            return
        }

        if dashPayModel.registrationStatus == nil || dashPayModel.registrationStatus?.failed == true {
            showCreateUsernameController()
            return
        }

        if dashPayModel.registrationStatus?.state != .done {
            showPendingController(dashPayModel.username)
        } else {
            showRegistrationCompletedController(dashPayModel.username)
        }
    }

    private func createUsername(_ username: String) {
        guard let invitationURL = invitationURL else { return }
        
        dashPayModel.createUsername(username, invitation: invitationURL)
        showPendingController(username)
    }

    private func showPendingController(_ username: String?) {
        guard let username = username else { return }
        
        if MOCK_DASHPAY.boolValue {
            DWGlobalOptions.sharedInstance().dashpayUsername = username
            showRegistrationCompletedController(username)
            return
        }

        let controller = DWUsernamePendingViewController()
        controller.username = username
        controller.delegate = self
        headerView.titleBuilder = { controller.attributedTitle() }
        containerController.transition(to: controller)
    }

    private func showCreateUsernameController() {
        createUsernameViewController = DWCreateUsernameViewController(dashPayModel: dashPayModel)
        createUsernameViewController.delegate = self
        headerView.titleBuilder = { self.createUsernameViewController.attributedTitle() }
        containerController.transition(to: createUsernameViewController)
    }

    private func showRegistrationCompletedController(_ username: String?) {
        guard let username = username else { return }
        assert(username.count > 1, "Invalid username")

        headerView.configurePlanetsView(withUsername: username)

        let controller = DWRegistrationCompletedViewController()
        controller.username = username
        controller.delegate = self
        headerView.titleBuilder = { NSAttributedString() }
        containerController.transition(to: controller)
    }

    // MARK: - Actions

    @objc private func cancelButtonAction() {
        if containerController.currentController is DWRegistrationCompletedViewController {
            dashPayModel.completeRegistration()
        }

        dismiss(animated: true, completion: nil)
    }

    // MARK: - DWCreateUsernameViewControllerDelegate

    func createUsernameViewController(_ controller: DWCreateUsernameViewController, registerUsername username: String) {
        if dashPayModel.shouldPresentRegistrationPaymentConfirmation() {
            let confirmController = DWConfirmUsernameViewController(username: username)
            confirmController.delegate = self
            present(confirmController, animated: true, completion: nil)
        } else {
            createUsername(username)
        }
    }

    // MARK: - DWConfirmUsernameViewControllerDelegate

    func confirmUsernameViewControllerDidConfirm(_ controller: DWConfirmUsernameViewController) {
        let username = controller.username
        controller.dismiss(animated: true) {
            if let delegate = self.confirmationDelegate {
                delegate.dashPaySetupFlowController(self, didConfirmUsername: username)
            } else {
                self.createUsername(username)
            }
        }
    }

    // MARK: - DWUsernamePendingViewControllerDelegate

    func usernamePendingViewControllerAction(_ controller: UIViewController) {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - DWRegistrationCompletedViewControllerDelegate

    func registrationCompletedViewControllerAction(_ controller: UIViewController) {
        dashPayModel.completeRegistration()
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Helper Methods

    private func embedChild(_ viewController: UIViewController, in containerView: UIView) {
        addChild(viewController)
        containerView.addSubview(viewController.view)
        viewController.view.frame = containerView.bounds
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        viewController.didMove(toParent: self)
    }
}

// Helper functions
private func HeaderHeight() -> CGFloat {
    return 231.0
}

private func LandscapeHeaderHeight() -> CGFloat {
    return 158.0
}
