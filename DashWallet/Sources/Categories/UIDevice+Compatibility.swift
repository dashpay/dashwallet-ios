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

extension UIDevice {
    static var isIphone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    static var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    static var screenWidth: CGFloat { UIScreen.main.bounds.width }
    static var screenHeight: CGFloat { UIScreen.main.bounds.height }
    static var screenMaxLength: CGFloat { max(screenWidth, screenHeight) }

    static var isIphone5OrLess: Bool { isIphone && screenMaxLength <= 568.0 }
    static var isIphone6: Bool { isIphone && screenMaxLength <= 667.0 }
    static var isIphone6Plus: Bool { isIphone && screenMaxLength <= 736.0 }

    static var hasHomeIndicator: Bool { (UIApplication.shared.delegate?.window??.safeAreaInsets.bottom ?? 0) > 0 }
}



