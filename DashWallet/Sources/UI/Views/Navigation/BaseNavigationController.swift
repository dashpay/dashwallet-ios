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

enum NavigationBarDisplayStyle
{
    case hidden
    case shown
}

protocol NavigationBarDisplayable: UIViewController {
    var isBackButtonHidden: Bool { get }
    var preferredNavigationBarDisplayStyle: NavigationBarDisplayStyle { get }
}

extension NavigationBarDisplayable {
    var isBackButtonHidden: Bool { false }
    var preferredNavigationBarDisplayStyle: NavigationBarDisplayStyle { .shown }
}

@objc class BaseNavigationController: UINavigationController {
    private weak var _delegate: UINavigationControllerDelegate?
    override weak var delegate: UINavigationControllerDelegate? {
        set {
            _delegate = newValue
        }
        get {
            return _delegate
        }
    }
    
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        
        let arrow = UIImage(systemName: "arrow.backward")
        self.navigationBar.backIndicatorImage = arrow
        self.navigationBar.backIndicatorTransitionMaskImage = arrow
        self.navigationBar.tintColor = .black
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func responds(to aSelector: Selector!) -> Bool {
        return super.responds(to: aSelector) || (_delegate?.responds(to: aSelector!) ?? false)
    }
    
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if _delegate?.responds(to: aSelector!) ?? false {
            return _delegate
        }else{
            return super.forwardingTarget(for: aSelector)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        super.delegate = self
    }
}

extension BaseNavigationController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        var hideBackButton = viewController == navigationController.viewControllers.first
        var hideNavigationBar = false
        
        if let viewController = viewController as? NavigationBarDisplayable {
            hideBackButton = viewController.isBackButtonHidden
            hideNavigationBar = viewController.preferredNavigationBarDisplayStyle == .hidden
        }
        
        if delegate?.responds(to: #function) ?? false {
            delegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
        }
    
        navigationController.setNavigationBarHidden(hideNavigationBar, animated: animated)
        viewController.navigationItem.setHidesBackButton(hideBackButton, animated: animated)
        viewController.navigationItem.backButtonDisplayMode = .minimal
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
}

extension UIViewController {
    var previousControllerOnNavigationStack: UIViewController? {
        navigationController?.controller(before: self)
    }
}
