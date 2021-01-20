//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWFirstUsernameSymbolValidationRule.h"

#import "DWUsernameValidationRule+Protected.h"

@implementation DWFirstUsernameSymbolValidationRule

- (NSString *)title {
    return NSLocalizedString(@"Must start with a letter or number", @"Validation rule");
}

- (void)validateText:(NSString *)text {
    if (text.length == 0) {
        self.validationResult = DWUsernameValidationRuleResultEmpty;
        return;
    }

    // The user should be able use a hyphen anywhere in the username except the first or last characters
    if ([text hasPrefix:@"-"] || [text hasSuffix:@"-"]) {
        self.validationResult = DWUsernameValidationRuleResultInvalid;
        return;
    }

    self.validationResult = DWUsernameValidationRuleResultValid;
}


@end
