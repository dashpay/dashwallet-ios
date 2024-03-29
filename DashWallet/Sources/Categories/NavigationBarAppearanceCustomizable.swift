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

// MARK: - NavigationBarAppearanceCustomizable

protocol NavigationBarAppearanceCustomizable: UIViewController {
    func animateNavigationBarAppearance()
    func setNavigationBarAppearance()
}

extension NavigationBarAppearanceCustomizable {
    func animateNavigationBarAppearance() {
        transitionCoordinator?.animate(alongsideTransition: { _ in
            self.setNavigationBarAppearance()
        })
    }

    func setNavigationBarAppearance() {
        /// NOP
    }
}

@objc
extension UINavigationBar {
    @objc
    func applyOpaqueAppearance(with color: UIColor, shadowColor: UIColor? = nil) {
        let standardAppearance = UINavigationBarAppearance()
        standardAppearance.configureWithOpaqueBackground()
        standardAppearance.backgroundColor = color
        standardAppearance.shadowColor = .clear

        let compactAppearance = standardAppearance.copy()
        let scrollAppearance = standardAppearance.copy()
        standardAppearance.shadowColor = shadowColor

        isTranslucent = true
        self.standardAppearance = standardAppearance
        scrollEdgeAppearance = scrollAppearance
        self.compactAppearance = compactAppearance

        if #available(iOS 15.0, *) {
            self.compactScrollEdgeAppearance = scrollAppearance
        }
    }

}

