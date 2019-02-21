//  
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWUpholdCVCInputValidator.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdCVCInputValidator ()

@property (strong, nonatomic) NSCharacterSet *validCharacterSet;

@end

@implementation DWUpholdCVCInputValidator

- (instancetype)init {
    self = [super init];
    if (self) {
        _validCharacterSet = [NSCharacterSet decimalDigitCharacterSet];
    }
    return self;
}

#pragma mark - DWUpholdInputValidator

- (nullable NSString *)validatedStringFromLastInputString:(NSString *)lastInputString range:(NSRange)range replacementString:(NSString *)string {
    NSParameterAssert(lastInputString);
    NSParameterAssert(string);
    
    BOOL isRemoving = string.length == 0;
    
    if (isRemoving && lastInputString.length < range.location + range.length) {
        return nil;
    }
    
    NSString *resultText = [lastInputString stringByReplacingCharactersInRange:range withString:string];
    if (isRemoving) {
        return resultText;
    }
    
    if (resultText.length > 4) { // same restriction on Uphold Website
        return nil;
    }
    
    NSCharacterSet *resultStringSet = [NSCharacterSet characterSetWithCharactersInString:resultText];
    
    BOOL stringIsValid = [self.validCharacterSet isSupersetOfSet:resultStringSet];
    if (!stringIsValid) {
        return nil;
    }
    
    return resultText;
}

@end

NS_ASSUME_NONNULL_END
