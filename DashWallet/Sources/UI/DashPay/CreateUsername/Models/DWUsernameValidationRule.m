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

#import "DWUsernameValidationRule.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUsernameValidationRule ()

@property (nonatomic, copy) DWUsernameValidationRuleResult (^validationBlock)(NSString *_Nullable text);

@end

NS_ASSUME_NONNULL_END

@implementation DWUsernameValidationRule

- (instancetype)initWithTitle:(NSString *)title
              validationBlock:(DWUsernameValidationRuleResult (^)(NSString *_Nullable))validationBlock {
    self = [super init];
    if (self) {
        _title = [title copy];
        _validationBlock = [validationBlock copy];
    }
    return self;
}

- (DWUsernameValidationRuleResult)validateText:(NSString *_Nullable)text {
    return self.validationBlock(text);
}

@end
