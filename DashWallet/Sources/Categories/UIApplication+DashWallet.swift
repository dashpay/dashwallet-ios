//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import Darwin
import MachO.dyld

@objc
extension UIApplication {
    @objc
    static var isJailbroken: Bool {
        var s = stat()
        let jailbroken = stat("/bin/sh", &s) == 0 // if we can see /bin/sh, the app isn't sandboxed

        // some anti-jailbreak detection tools re-sandbox apps, so do a secondary check for any MobileSubstrate dyld images
        let count = _dyld_image_count()
        for i in 0..<count {
            if let name = String(validatingUTF8: _dyld_get_image_name(i)), name.contains("MobileSubstrate") {
                return true
            }
        }

        #if targetEnvironment(simulator)
        return false
        #else
        return jailbroken
        #endif
    }

}
