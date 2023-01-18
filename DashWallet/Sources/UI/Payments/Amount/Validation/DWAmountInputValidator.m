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

#import "DWDecimalInputValidator.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAmountInputValidator ()

@property (strong, nonatomic) DWDecimalInputValidator *decimalValidator;
@property (copy, nonatomic) NSString *decimalSeparator;


@end

@implementation DWAmountInputValidator

- (instancetype)initWithType:(DWAmountInputValidatorType)type {
    return [self initWithType:type locale:nil];
}

- (instancetype)initWithType:(DWAmountInputValidatorType)type locale:(nullable NSLocale *)locale {
    self = [super init];
    if (self) {
        _type = type;

        _decimalValidator = [[DWDecimalInputValidator alloc] initWithLocale:locale];

        NSLocale *locale_ = locale ?: [NSLocale currentLocale];
        NSString *decimalSeparator = locale_.decimalSeparator;
        _decimalSeparator = decimalSeparator;

        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        numberFormatter.lenient = YES;
        numberFormatter.generatesDecimalNumbers = YES;
        numberFormatter.roundingMode = NSNumberFormatterRoundDown;
        numberFormatter.minimumIntegerDigits = 1;
        if (locale) {
            numberFormatter.locale = locale;
        }
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

- (nullable NSString *)stringFromNumberUsingInternalFormatter:(NSNumber *)number {
    return [self.numberFormatter stringFromNumber:number];
}

#pragma mark - DWInputValidator

- (nullable NSString *)validatedStringFromLastInputString:(NSString *)lastInputString range:(NSRange)range replacementString:(NSString *)string {
    return [self validatedStringFromLastInputString:lastInputString range:range replacementString:string numberFormatter:self.numberFormatter];
}

- (nullable NSString *)validatedStringFromLastInputString:(NSString *)lastInputString range:(NSRange)range replacementString:(NSString *)string numberFormatter:(NSNumberFormatter *)numberFormatter {
    NSString *validNumberString = [self.decimalValidator validatedStringFromLastInputString:lastInputString
                                                                                      range:range
                                                                          replacementString:string];
    if (!validNumberString) {
        return nil;
    }

    if (validNumberString.length == 0) {
        return validNumberString;
    }

    NSString *validAmountString = [self validatedAmountStringFromNumberString:validNumberString numberFormatter:numberFormatter];
    return validAmountString;
}

#pragma mark - Private

- (nullable NSString *)validatedAmountStringFromNumberString:(NSString *)validNumberString numberFormatter:(NSNumberFormatter *)numberFormatter {
    NSParameterAssert(validNumberString);

    NSNumberFormatter *nf = [numberFormatter copy];
    nf.numberStyle = NSNumberFormatterNoStyle;

    NSNumber *number = [nf numberFromString:validNumberString];
    if (number == nil) {
        return nil;
    }

    NSString *amountString = [nf stringFromNumber:number];
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
