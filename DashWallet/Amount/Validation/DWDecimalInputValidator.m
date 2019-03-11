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

#import "DWDecimalInputValidator.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDecimalInputValidator ()

@property (copy, nonatomic) NSString *decimalSeparator;
@property (strong, nonatomic) NSCharacterSet *validCharacterSet;

@end

@implementation DWDecimalInputValidator

- (instancetype)init {
    return [self initWithLocale:nil];
}

- (instancetype)initWithLocale:(nullable NSLocale *)locale {
    self = [super init];
    if (self) {
        NSLocale *locale_ = locale ?: [NSLocale currentLocale];
        NSString *decimalSeparator = locale_.decimalSeparator;
        _decimalSeparator = decimalSeparator;
        
        NSMutableCharacterSet *mutableCharacterSet = [NSMutableCharacterSet decimalDigitCharacterSet];
        [mutableCharacterSet addCharactersInString:decimalSeparator];
        _validCharacterSet = [mutableCharacterSet copy];
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
    
    NSString *decimalSeparator = self.decimalSeparator;
    NSCharacterSet *resultStringSet = [NSCharacterSet characterSetWithCharactersInString:resultText];
    
    BOOL stringIsValid = [self.validCharacterSet isSupersetOfSet:resultStringSet];
    if (!stringIsValid) {
        return nil;
    }
    
    if ([string isEqualToString:decimalSeparator] && [lastInputString containsString:decimalSeparator]) {
        return nil;
    }
    
    if ([resultText isEqualToString:decimalSeparator]) {
        resultText = [@"0" stringByAppendingString:decimalSeparator];
        
        return resultText;
    }
    
    if (resultText.length == 2) {
        NSString *zeroAndDecimalSeparator = [@"0" stringByAppendingString:decimalSeparator];
        if ([[resultText substringToIndex:1] isEqualToString:@"0"] &&
            ![resultText isEqualToString:zeroAndDecimalSeparator]) {
            resultText = [resultText substringWithRange:NSMakeRange(1, 1)];
            
            return resultText;
        }
    }
    
    return resultText;
}

@end

NS_ASSUME_NONNULL_END
