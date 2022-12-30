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

@objc
extension UIViewController {
    @objc func topController() -> UIViewController {
        if let vc = self as? UITabBarController {
            if let vc = vc.selectedViewController {
                return vc.topController()
            }

            return vc
        } else if let vc = self as? UINavigationController {
            if let vc = vc.visibleViewController {
                return vc.topController()
            }

            return vc
        } else if let vc = presentedViewController {
            return vc
        }

        return self
    }
}
