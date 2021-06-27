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

#import "DWAllowedCharactersUsernameValidationRule.h"

#import "DWUsernameValidationRule+Protected.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAllowedCharactersUsernameValidationRule ()

@property (readonly, strong, nonatomic) NSCharacterSet *illegalChars;

@end

NS_ASSUME_NONNULL_END

@implementation DWAllowedCharactersUsernameValidationRule

- (instancetype)init {
    self = [super init];
    if (self) {
        NSCharacterSet *allowedCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"];
        _illegalChars = [allowedCharacterSet invertedSet];
    }
    return self;
}

- (NSString *)title {
    return NSLocalizedString(@"Letters and numbers only", @"Validation rule");
}

- (void)validateText:(NSString *)text {
    if (text.length == 0) {
        self.validationResult = DWUsernameValidationRuleResultEmpty;
        return;
    }

    BOOL hasIllegalCharacter = [text rangeOfCharacterFromSet:self.illegalChars].location != NSNotFound;
    self.validationResult = hasIllegalCharacter ? DWUsernameValidationRuleResultInvalid : DWUsernameValidationRuleResultValid;
}

@end
