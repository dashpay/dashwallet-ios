//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWLengthUsernameValidationRule.h"

#import "DWDashPayConstants.h"
#import "DWUsernameValidationRule+Protected.h"

@implementation DWLengthUsernameValidationRule

- (NSString *)title {
    return [NSString stringWithFormat:NSLocalizedString(@"Between %ld and %ld characters", @"Validation rule: Between 3 and 24 characters"), DW_MIN_USERNAME_LENGTH, DW_MAX_USERNAME_LENGTH];
}

- (void)validateText:(NSString *)text {
    const NSUInteger length = text.length;
    if (length == 0) {
        self.validationResult = DWUsernameValidationRuleResultEmpty;
        return;
    }

    BOOL isValid = length >= DW_MIN_USERNAME_LENGTH && length <= DW_MAX_USERNAME_LENGTH;

    self.validationResult = isValid ? DWUsernameValidationRuleResultValid : DWUsernameValidationRuleResultInvalid;
}

@end
