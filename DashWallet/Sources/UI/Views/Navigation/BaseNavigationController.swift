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

// MARK: - NavigationStackControllable

protocol NavigationStackControllable: UIViewController {
    func shouldPopViewController() -> Bool
}

// MARK: - NavigationBarDisplayable

protocol NavigationBarDisplayable: UIViewController {
    var isBackButtonHidden: Bool { get }
    var isNavigationBarHidden: Bool { get }
}

// MARK: - NavigationFullscreenable

@objc(DWNavigationFullscreenable)
protocol NavigationFullscreenable: AnyObject {
    var requiresNoNavigationBar: Bool { get }
}

extension NavigationBarDisplayable {
    var isBackButtonHidden: Bool { false }
    var isNavigationBarHidden: Bool { false }
}

// MARK: - BaseNavigationController

@objc(DWNavigationController)
class BaseNavigationController: UINavigationController {
    private weak var _delegate: UINavigationControllerDelegate?
    override weak var delegate: UINavigationControllerDelegate? {
        set {
            _delegate = newValue
        }
        get {
            _delegate
        }
    }

    private var isPushAnimationInProgress = false

    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)

        interactivePopGestureRecognizer?.delegate = self
        navigationBar.tintColor = .black
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (_delegate?.responds(to: aSelector!) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if _delegate?.responds(to: aSelector!) ?? false {
            return _delegate
        } else {
            return super.forwardingTarget(for: aSelector)
        }
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        isPushAnimationInProgress = true

        super.pushViewController(viewController, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        super.delegate = self

        view.backgroundColor = .dw_secondaryBackground()
        navigationBar.applyOpaqueAppearance(with: .dw_secondaryBackground(), shadowColor: .dw_separatorLine())
    }
}

// MARK: Actions

extension BaseNavigationController {
    @objc
    func backButtonAction() {
        guard let topViewController = topViewController as? NavigationStackControllable else {
            popViewController(animated: true)
            return
        }

        if topViewController.shouldPopViewController() {
            popViewController(animated: true)
        }
    }
}

// MARK: UINavigationControllerDelegate

extension BaseNavigationController: UINavigationControllerDelegate {

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        var hideBackButton = viewController == navigationController.viewControllers.first
        var hideNavigationBar = false

        if let viewController = viewController as? NavigationBarDisplayable {
            hideBackButton = viewController.isBackButtonHidden
            hideNavigationBar = viewController.isNavigationBarHidden
        } else if let vc = viewController as? NavigationFullscreenable {
            hideNavigationBar = vc.requiresNoNavigationBar
        }

        delegate?.navigationController?(navigationController, willShow: viewController, animated: animated)

        if !hideBackButton && viewController.navigationItem.leftBarButtonItem == nil {
            let backButton = UIButton(type: .custom)
            backButton.frame = .init(x: 0, y: 0, width: 30, height: 30)
            backButton.setImage(UIImage(systemName: "arrow.backward"), for: .normal)
            backButton.tintColor = .dw_label()
            backButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
            backButton.addTarget(self, action: #selector(backButtonAction), for: .touchUpInside)
            let item = UIBarButtonItem(customView: backButton)

            viewController.navigationItem.leftBarButtonItem = item
            viewController.navigationItem.leftItemsSupplementBackButton = false
        }

        viewController.navigationItem.hidesBackButton = true

        if let vc = viewController as? NavigationBarAppearanceCustomizable {
            vc.setNavigationBarAppearance()
        }

        navigationController.setNavigationBarHidden(hideNavigationBar, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        isPushAnimationInProgress = false

        if let vc = viewController as? NavigationBarAppearanceCustomizable {
            vc.setNavigationBarAppearance()
        }
    }
}

extension UINavigationController {
    var previousController: UIViewController? {
        viewControllers.count > 1 ? viewControllers[viewControllers.count - 2] : nil
    }

    func controller(before controller: UIViewController) -> UIViewController? {
        guard let index = viewControllers.firstIndex(of: controller), index >= 1 else { return nil }
        return viewControllers[index - 1]
    }

    func controller<T>(by type: T.Type) -> UIViewController? {
        viewControllers.first(where: { $0 is T })
    }
}

extension UIViewController {
    var previousControllerOnNavigationStack: UIViewController? {
        navigationController?.controller(before: self)
    }
}

// MARK: - BaseNavigationController + UIGestureRecognizerDelegate

extension BaseNavigationController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == interactivePopGestureRecognizer else {
            return true
        }

        return viewControllers.count > 1 && isPushAnimationInProgress == false
    }
}
