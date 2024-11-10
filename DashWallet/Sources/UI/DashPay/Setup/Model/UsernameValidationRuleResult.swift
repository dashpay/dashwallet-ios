//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

@objc(DWUsernameValidationRuleResult)
public enum UsernameValidationRuleResult: UInt {
    /// Empty icon, black text
    case empty = 0
    /// Activity indicator, black text
    case loading
    /// Checkmark, black text
    case valid
    /// Yellow warning sign
    case warning
    /// Red cross and black text
    case invalid
    /// Red cross and red text
    case invalidCritical
    /// Red cross and red text
    case error
    /// View is hidden
    case hidden
}
