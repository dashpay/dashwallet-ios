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
import UIKit

@objc
extension UIApplication {
    /// Advisory only: it runs in-process on the device it judges, so anything
    /// able to read the keychain can also make it return `false`.
    @objc
    static var isJailbroken: Bool {
        // macOS lets a sandboxed app stat system paths, so the probe below flags
        // every Mac; "Designed for iPad" is neither simulator nor macCatalyst
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        return false
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return false
        }

        var s = stat()
        let jailbroken = stat("/bin/sh", &s) == 0 // if we can see /bin/sh, the app isn't sandboxed

        // some anti-jailbreak detection tools re-sandbox apps, so do a secondary check for any MobileSubstrate dyld images
        let count = _dyld_image_count()
        for i in 0..<count {
            if let name = String(validatingUTF8: _dyld_get_image_name(i)), name.contains("MobileSubstrate") {
                return true
            }
        }

        return jailbroken
        #endif
    }

}
