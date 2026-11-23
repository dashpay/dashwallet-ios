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

// MARK: - ActionButtonProtocol

protocol ActionButtonProtocol: AnyObject {
    var isEnabled: Bool { get set }
    var isHidden: Bool { get set }
}

// MARK: - ActionButton + ActionButtonProtocol

extension ActionButton: ActionButtonProtocol { }

// MARK: - ActivityIndicatorPreviewing

protocol ActivityIndicatorPreviewing: AnyObject {
    func showActivityIndicator()
    func hideActivityIndicator()
}

// MARK: - ActionButtonViewController

class ActionButtonViewController: BaseViewController, ActivityIndicatorPreviewing {
    public weak var actionButton: ActionButtonProtocol?

    internal var isKeyboardNotificationsEnabled = false
    internal var showsActionButton: Bool { true }
    internal var actionButtonTitle: String! {
        fatalError("Must be overriden in subclass")
    }

    internal var actionButtonDisabledTitle: String? { actionButtonTitle }

    internal var stackView: UIStackView!
    internal var buttonContainer: UIView!
    private var button: ActionButton!
    private var contentBottomConstraint: NSLayoutConstraint!

    func setupContentView(_ view: UIView) {
        stackView.insertArrangedSubview(view, at: 0)
    }

    func showActivityIndicator() {
        button.showActivityIndicator()
    }

    func hideActivityIndicator() {
        button.hideActivityIndicator()
    }

    @objc
    func actionButtonAction(sender: UIView) { }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if isKeyboardNotificationsEnabled {
            // pre-layout view to avoid undesired animation if the keyboard is shown while appearing
            view.layoutSubviews()
            ka_startObservingKeyboardNotifications()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }
}

extension ActionButtonViewController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        stackView = ActionButtonStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.preservesSuperviewLayoutMargins = true
        stackView.backgroundColor = .dw_secondaryBackground()
        view.addSubview(stackView)

        if showsActionButton {
            configureActionButton()
        }

        let safeAreaGuide = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: safeAreaGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureActionButton() {
        buttonContainer = UIView()
        buttonContainer.backgroundColor = .dw_secondaryBackground()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(buttonContainer)

        button = ActionButton()
        button.setTitle(actionButtonTitle, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(actionButtonAction(sender:)), for: .touchUpInside)

        if _SNAPSHOT {
            button?.accessibilityIdentifier = "action_button"
        }

        buttonContainer.addSubview(button)
        actionButton = button

        let marginsGuide = view.layoutMarginsGuide

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: buttonContainer.topAnchor, constant: 0),
            button.bottomAnchor.constraint(equalTo: buttonContainer.safeAreaLayoutGuide.bottomAnchor, constant: 0),
            button.leadingAnchor.constraint(equalTo: marginsGuide.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: marginsGuide.trailingAnchor),
            button.heightAnchor.constraint(equalToConstant: 46),

        ])

        actionButton?.isEnabled = false
    }

    private func reloadActionButtonTitles() {
        button.setTitle(actionButtonTitle, for: .normal)
        button.setTitle(actionButtonDisabledTitle, for: .disabled)
    }
}

extension ActionButtonViewController {
    override func ka_keyboardShowOrHideAnimation(withHeight height: CGFloat, animationDuration: TimeInterval,
                                                 animationCurve: UIView.AnimationCurve) {
        let padding = deviceSpecificBottomPadding()
        contentBottomConstraint.constant = height + padding
        view.layoutSubviews()
    }
}

extension ActionButtonViewController {
    private func deviceSpecificBottomPadding() -> CGFloat {
        15
    }
}

// MARK: - ActionButtonStackView

private final class ActionButtonStackView: UIStackView {

    /// We need this in order to always have safeAreaInsets.bottom > 0.
    /// When we are on device with home button, we use it as a bottom padding for the content
    override var safeAreaInsets: UIEdgeInsets {
        let defaultnsets = UIEdgeInsets(top: 0, left: 0, bottom: 15, right: 0)

        guard let superview, superview.safeAreaInsets.bottom > 0 else {
            return defaultnsets
        }

        return superview.safeAreaInsets
    }
}
