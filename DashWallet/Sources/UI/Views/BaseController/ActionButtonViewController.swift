//  
//  Created by tkhp
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

protocol ActionButtonProtocol: AnyObject {
    var isEnabled: Bool { get set }
}

extension DWActionButton: ActionButtonProtocol {}
extension UIBarButtonItem: ActionButtonProtocol {}

class ActionButtonViewController: BaseViewController {
    public weak var actionButton: ActionButtonProtocol?
    
    internal var isKeyboardNotificationsEnabled: Bool = false
    internal var showsActionButton: Bool { return true }
    internal var isActionButtonInNavigationBar: Bool { return false }
    internal var actionButtonTitle: String? {
        fatalError("Must be overriden in subclass")
        return nil
    }
    
    internal var actionButtonDisabledTitle: String? { actionButtonTitle }
    
    private var stackView: UIStackView!
    private var button: DWActionButton!
    private var barButton: UIBarButtonItem!
    private var contentBottomConstraint: NSLayoutConstraint!
    
    func setupContentView(_ view: UIView) {
        stackView.insertArrangedSubview(view, at: 0)
    }
    
    func showActivityIndicator() {
        if (self.isActionButtonInNavigationBar) {
            let activityIndicator = configuredActivityIndicator()
            activityIndicator.startAnimating()
            activityIndicator.sizeToFit()
            let barButtonItem = UIBarButtonItem(customView: activityIndicator)
            self.navigationItem.rightBarButtonItem = barButtonItem
        }else{
            self.button.showActivityIndicator()
        }
    }
    
    func hideActivityIndicator() {
        if (self.isActionButtonInNavigationBar) {
            self.navigationItem.rightBarButtonItem = self.barButton
        }else{
            self.button.hideActivityIndicator()
        }
    }
    
    @objc func actionButtonAction(sender: UIView) {
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if (self.isKeyboardNotificationsEnabled) {
            // pre-layout view to avoid undesired animation if the keyboard is shown while appearing
            view.layoutSubviews()
            self.ka_startObservingKeyboardNotifications()
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (self.isKeyboardNotificationsEnabled) {
            self.ka_stopObservingKeyboardNotifications()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
    }
}

extension ActionButtonViewController {
    private func configureHierarchy() {
        self.stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .equalSpacing
        stackView.spacing = 0
        view.addSubview(stackView)
        
        if showsActionButton {
            configureActionButton()
        }
        
        let safeAreaGuide = self.view.safeAreaLayoutGuide;
        
        let bottomPadding = deviceSpecificBottomPadding()
        self.contentBottomConstraint = safeAreaGuide.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: bottomPadding)
                                        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: safeAreaGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            self.contentBottomConstraint
        ])
    }
    
    private func configureActionButton() {
        if isActionButtonInNavigationBar {
            self.barButton = UIBarButtonItem(title: actionButtonTitle, style: .plain, target: self, action: #selector(actionButtonAction(sender:)))
            self.navigationItem.rightBarButtonItem = barButton
            self.actionButton = barButton
        }else{
            let buttonContainer = UIView()
            buttonContainer.backgroundColor = .dw_background()
            buttonContainer.translatesAutoresizingMaskIntoConstraints = false
            self.stackView.addArrangedSubview(buttonContainer)
            
            self.button = DWActionButton(frame: .zero)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle(actionButtonTitle, for: .normal)
            button.setTitle(actionButtonDisabledTitle, for: .disabled)
            button.addTarget(self, action: #selector(actionButtonAction(sender:)), for: .touchUpInside)
            buttonContainer.addSubview(self.button)
            self.actionButton = button
            
            let marginsGuide = self.view.layoutMarginsGuide;
           
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: buttonContainer.topAnchor, constant: 0),
                button.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: 0),
                button.leadingAnchor.constraint(equalTo: marginsGuide.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: marginsGuide.trailingAnchor),
                button.heightAnchor.constraint(equalToConstant: 46)
                
            ])
        }
        
        self.actionButton?.isEnabled = false
    }
    
    private func reloadActionButtonTitles() {
        if (!isActionButtonInNavigationBar) {
            button.setTitle(actionButtonTitle, for: .normal)
            button.setTitle(actionButtonDisabledTitle, for: .disabled)
        }
    }
}

extension ActionButtonViewController {
    override func ka_keyboardShowOrHideAnimation(withHeight height: CGFloat, animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        let padding = deviceSpecificBottomPadding()
        contentBottomConstraint.constant = height + padding
        view.layoutSubviews()
    }
}

extension ActionButtonViewController {
    private func configuredActivityIndicator() -> UIActivityIndicatorView {
        let activityIndicatorView = UIActivityIndicatorView(style: .medium)
        activityIndicatorView.color = .dw_tint()
        return activityIndicatorView
    }
    
    private func deviceSpecificBottomPadding() -> CGFloat {
        if isActionButtonInNavigationBar {
            return 0
        }else{
            return DWBaseViewController.deviceSpecificBottomPadding()
        }
    }
}
