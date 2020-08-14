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

#import "DWMaxLengthUsernameValidationRule.h"

#import "DWDashPayConstants.h"
#import "DWUsernameValidationRule+Protected.h"

@implementation DWMaxLengthUsernameValidationRule

- (NSString *)title {
    return [NSString stringWithFormat:NSLocalizedString(@"Maximum %ld characters", @"Validation rule: Maximum 24 characters"), DW_MAX_USERNAME_LENGTH];
}

- (void)validateText:(NSString *)text {
    self.validationResult = text.length <= DW_MAX_USERNAME_LENGTH ? DWUsernameValidationRuleResultHidden : DWUsernameValidationRuleResultInvalid;
}

@end
