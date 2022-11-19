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

protocol NavigationBarDisplayable
{
    var isBackButtonHidden: Bool { get }
    var preferredNavigationBarDisplayStyle: NavigationBarDisplayStyle { get }
}

extension NavigationBarDisplayable
{
    var isBackButtonHidden: Bool { false }
    var preferredNavigationBarDisplayStyle: NavigationBarDisplayStyle { .shown }
}

@objc class BaseNavigationController: UINavigationController {
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        
        let arrow = UIImage(systemName: "arrow.backward")
        self.navigationBar.backIndicatorImage = arrow
        self.navigationBar.backIndicatorTransitionMaskImage = arrow
        self.navigationBar.tintColor = .black
        self.navigationItem.backButtonDisplayMode = .minimal
//        let appearance = self.navigationBar.standardAppearance
//        appearance.setBackIndicatorImage(arrow, transitionMaskImage: arrow)
//        appearance.shadowImage = nil
//        appearance.shadowColor = nil
//        appearance.backgroundColor = .dw_secondaryBackground()
//
//        self.navigationBar.scrollEdgeAppearance = appearance
//        self.navigationBar.compactAppearance = appearance
//        self.navigationBar.standardAppearance = appearance
//        if #available(iOS 15.0, *) {
//           self.navigationBar.compactScrollEdgeAppearance = appearance
//        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension UINavigationController {
    var previousController: UIViewController? {
        viewControllers.count > 1 ? viewControllers[viewControllers.count - 2] : nil
    }
    
    func controller(before controller: UIViewController) -> UIViewController? {
        guard let index = viewControllers.firstIndex(of: controller), index >= 1 else { return nil }
        return viewControllers[index]
    }
}

extension UIViewController {
    var previousControllerOnNavigationStack: UIViewController? {
        navigationController?.controller(before: self)
    }
}
