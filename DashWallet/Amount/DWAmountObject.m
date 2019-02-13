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

#import "DWAmountObject.h"

#import <DashSync/DSPriceManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWAmountObject

- (instancetype)initWithDashAmountString:(NSString *)dashAmountString {
    self = [super init];
    if (self) {
        _amountInternalRepresentation = [dashAmountString copy];

        if (dashAmountString.length == 0) {
            dashAmountString = @"0";
        }

        NSDecimalNumber *dashNumber = [NSDecimalNumber decimalNumberWithString:dashAmountString locale:[NSLocale currentLocale]];
        NSParameterAssert(dashNumber);
        NSDecimalNumber *duffsNumber = (NSDecimalNumber *)[NSDecimalNumber numberWithLongLong:DUFFS];
        int64_t plainAmount = [dashNumber decimalNumberByMultiplyingBy:duffsNumber].longLongValue;
        _plainAmount = plainAmount;

        DSPriceManager *priceManager = [DSPriceManager sharedInstance];
        NSString *dashFormatted = [priceManager.dashFormat stringFromNumber:dashNumber];

        _dashFormatted = [self.class formattedAmountWithInputString:dashAmountString
                                                    formattedString:dashFormatted
                                                    numberFormatter:priceManager.dashFormat];
        _localCurrencyFormatted = [priceManager localCurrencyStringForDashAmount:plainAmount];
    }
    return self;
}

- (instancetype)initWithLocalAmountString:(NSString *)localAmountString {
    self = [super init];
    if (self) {
        _amountInternalRepresentation = [localAmountString copy];

        if (localAmountString.length == 0) {
            localAmountString = @"0";
        }

        NSDecimalNumber *localNumber = [NSDecimalNumber decimalNumberWithString:localAmountString locale:[NSLocale currentLocale]];
        NSParameterAssert(localNumber);

        DSPriceManager *priceManager = [DSPriceManager sharedInstance];
        NSAssert(priceManager.localCurrencyDashPrice, @"Prices should be loaded");
        NSString *localCurrencyFormatted = [priceManager.localFormat stringFromNumber:localNumber];
        uint64_t plainAmount = [priceManager amountForLocalCurrencyString:localCurrencyFormatted];

        _plainAmount = plainAmount;
        _dashFormatted = [priceManager stringForDashAmount:plainAmount];
        _localCurrencyFormatted = [self.class formattedAmountWithInputString:localAmountString
                                                             formattedString:localCurrencyFormatted
                                                             numberFormatter:priceManager.localFormat];
    }
    return self;
}

- (instancetype)initAsLocalWithPreviousAmount:(DWAmountObject *)previousAmount {
    self = [super init];
    if (self) {
        _plainAmount = previousAmount.plainAmount;
        _amountInternalRepresentation = [self.class rawAmountStringFromFormattedString:previousAmount.localCurrencyFormatted];
        _dashFormatted = [previousAmount.dashFormatted copy];
        _localCurrencyFormatted = [previousAmount.localCurrencyFormatted copy];
    }
    return self;
}

- (instancetype)initAsDashWithPreviousAmount:(DWAmountObject *)previousAmount {
    self = [super init];
    if (self) {
        _plainAmount = previousAmount.plainAmount;
        _amountInternalRepresentation = [self.class rawAmountStringFromFormattedString:previousAmount.dashFormatted];
        _dashFormatted = [previousAmount.dashFormatted copy];
        _localCurrencyFormatted = [previousAmount.localCurrencyFormatted copy];
    }
    return self;
}

#pragma mark - Private

+ (NSString *)rawAmountStringFromFormattedString:(NSString *)formattedString {
    NSLocale *locale = [NSLocale currentLocale];
    NSString *decimalSeparator = locale.decimalSeparator;
    NSMutableCharacterSet *allowedCharacterSet = [NSMutableCharacterSet decimalDigitCharacterSet];
    [allowedCharacterSet addCharactersInString:decimalSeparator];

    NSString *result = [[formattedString componentsSeparatedByCharactersInSet:[allowedCharacterSet invertedSet]]
        componentsJoinedByString:@""];

    return result;
}

+ (NSString *)formattedAmountWithInputString:(NSString *)inputString
                             formattedString:(NSString *)formattedString
                             numberFormatter:(NSNumberFormatter *)numberFormatter {
    NSAssert(numberFormatter.numberStyle == NSNumberFormatterCurrencyStyle, @"Invalid number formatter");

    NSString *decimalSeparator = [NSLocale currentLocale].decimalSeparator;
    NSAssert([numberFormatter.decimalSeparator isEqualToString:decimalSeparator], @"Custom decimal separators are not supported");
    NSUInteger inputSeparatorIndex = [inputString rangeOfString:decimalSeparator].location;
    if (inputSeparatorIndex == NSNotFound) {
        return formattedString;
    }

    NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    NSRange currencySymbolRange = [formattedString rangeOfString:numberFormatter.currencySymbol];
    NSAssert(currencySymbolRange.location != NSNotFound, @"Invalid formatted string");

    BOOL isCurrencySymbolAtTheBeginning = currencySymbolRange.location == 0;
    NSString *currencySymbolNumberSeparator = @"";
    if (isCurrencySymbolAtTheBeginning) {
        currencySymbolNumberSeparator = [formattedString substringWithRange:NSMakeRange(currencySymbolRange.length, 1)];
    }
    else {
        currencySymbolNumberSeparator = [formattedString substringWithRange:NSMakeRange(currencySymbolRange.location - 1, 1)];
    }
    if ([currencySymbolNumberSeparator rangeOfCharacterFromSet:whitespaceCharacterSet].location == NSNotFound) {
        currencySymbolNumberSeparator = @"";
    }

    NSString *formattedStringWithoutCurrency =
        [[formattedString stringByReplacingCharactersInRange:currencySymbolRange withString:@""]
            stringByTrimmingCharactersInSet:whitespaceCharacterSet];

    NSString *inputFractionPartWithSeparator = [inputString substringFromIndex:inputSeparatorIndex];
    NSUInteger formattedSeparatorIndex = [formattedStringWithoutCurrency rangeOfString:decimalSeparator].location;
    if (formattedSeparatorIndex == NSNotFound) {
        formattedSeparatorIndex = formattedStringWithoutCurrency.length;
        formattedStringWithoutCurrency = [formattedStringWithoutCurrency stringByAppendingString:decimalSeparator];
    }
    NSRange formattedFractionPartRange = NSMakeRange(formattedSeparatorIndex, formattedStringWithoutCurrency.length - formattedSeparatorIndex);

    NSString *formattedStringWithFractionInput = [formattedStringWithoutCurrency stringByReplacingCharactersInRange:formattedFractionPartRange withString:inputFractionPartWithSeparator];

    NSString *result = nil;
    if (isCurrencySymbolAtTheBeginning) {
        result = [NSString stringWithFormat:@"%@%@%@",
                                            numberFormatter.currencySymbol,
                                            currencySymbolNumberSeparator,
                                            formattedStringWithFractionInput];
    }
    else {
        result = [NSString stringWithFormat:@"%@%@%@",
                                            formattedStringWithFractionInput,
                                            currencySymbolNumberSeparator,
                                            numberFormatter.currencySymbol];
    }

    return result;
}

@end

NS_ASSUME_NONNULL_END
