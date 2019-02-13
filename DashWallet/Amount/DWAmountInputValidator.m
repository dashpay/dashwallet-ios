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

#import "DWAmountInputValidator.h"

#import <DashSync/DSWallet.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWAmountInputValidator ()

@property (copy, nonatomic) NSString *decimalSeparator;
@property (strong, nonatomic) NSCharacterSet *validCharacterSet;
@property (strong, nonatomic) NSNumberFormatter *numberFormatter;

@end

@implementation DWAmountInputValidator

- (instancetype)initWithType:(DWAmountInputValidatorType)type {
    self = [super init];
    if (self) {
        _type = type;

        NSLocale *locale = [NSLocale currentLocale];
        NSString *decimalSeparator = locale.decimalSeparator;
        _decimalSeparator = decimalSeparator;

        NSMutableCharacterSet *mutableCharacterSet = [NSMutableCharacterSet decimalDigitCharacterSet];
        [mutableCharacterSet addCharactersInString:decimalSeparator];
        _validCharacterSet = [mutableCharacterSet copy];

        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        numberFormatter.lenient = YES;
        numberFormatter.generatesDecimalNumbers = YES;
        numberFormatter.roundingMode = NSNumberFormatterRoundDown;
        switch (type) {
            case DWAmountInputValidatorTypeDash: {
                numberFormatter.maximumFractionDigits = 8;
                numberFormatter.maximum = @(MAX_MONEY / (int64_t)pow(10.0, numberFormatter.maximumFractionDigits));

                break;
            }
            case DWAmountInputValidatorTypeLocalCurrency: {
                numberFormatter.maximumFractionDigits = 2;

                break;
            }
        }
        _numberFormatter = numberFormatter;
    }
    return self;
}

- (nullable NSString *)validatedAmountForLastInputString:(NSString *)lastInputString range:(NSRange)range replacementString:(NSString *)string {
    NSString *validNumberString = [self validatedNumberStringFromLastInputString:lastInputString
                                                                           range:range
                                                               replacementString:string];
    if (!validNumberString) {
        return nil;
    }

    if (validNumberString.length == 0) {
        return validNumberString;
    }

    NSString *validAmountString = [self validatedAmountStringFromNumberString:validNumberString];
    return validAmountString;
}

#pragma mark - Private

- (nullable NSString *)validatedNumberStringFromLastInputString:(NSString *)lastInputString range:(NSRange)range replacementString:(NSString *)string {
    NSParameterAssert(lastInputString);
    NSParameterAssert(string);

    NSString *resultText = [lastInputString stringByReplacingCharactersInRange:range withString:string];
    if (string.length == 0) {
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

- (nullable NSString *)validatedAmountStringFromNumberString:(NSString *)validNumberString {
    NSParameterAssert(validNumberString);

    NSNumberFormatter *numberFormatter = self.numberFormatter;

    NSNumber *number = [numberFormatter numberFromString:validNumberString];
    if (number == nil) {
        return nil;
    }

    NSString *amountString = [numberFormatter stringFromNumber:number];
    if ([amountString isEqualToString:validNumberString]) {
        return amountString;
    }

    NSString *decimalSeparator = self.decimalSeparator;
    NSUInteger separatorIndex = [validNumberString rangeOfString:decimalSeparator].location;
    NSAssert(separatorIndex != NSNotFound, @"Unhandled input string");
    if (separatorIndex == NSNotFound) {
        return nil;
    }

    NSString *fractionPart = [validNumberString substringFromIndex:separatorIndex + 1];
    if (fractionPart.length > numberFormatter.maximumFractionDigits ||
        (fractionPart.length == numberFormatter.maximumFractionDigits && fractionPart.integerValue == 0)) {
        return nil;
    }

    NSString *integerPart = [validNumberString substringToIndex:separatorIndex];
    NSString *resultString = [NSString stringWithFormat:@"%@%@%@", integerPart, decimalSeparator, fractionPart];

    return resultString;
}

@end

NS_ASSUME_NONNULL_END
