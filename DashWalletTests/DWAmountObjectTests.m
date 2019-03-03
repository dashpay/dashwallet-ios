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

#import <XCTest/XCTest.h>

#import "DWAmountInputValidator.h"
#import "DWAmountObject.h"

@interface DWAmountObject (Testable)

+ (nullable NSString *)currencySymbolFromFormattedString:(NSString *)formattedString numberFormatter:(NSNumberFormatter *)numberFormatter;

+ (NSString *)formattedAmountWithInputString:(NSString *)inputString
                             formattedString:(NSString *)formattedString
                             numberFormatter:(NSNumberFormatter *)numberFormatter
                                      locale:(NSLocale *)locale;

+ (NSString *)rawAmountStringFromFormattedString:(NSString *)formattedString
                                 numberFormatter:(NSNumberFormatter *)numberFormatter
                                       validator:(DWAmountInputValidator *)validator
                                          locale:(NSLocale *)locale;

@end

@interface DWAmountObjectTests : XCTestCase

@end

@implementation DWAmountObjectTests

- (void)testAssumptionThatCurrencySymbolIsEitherAtTheBeginningOrAtTheEnd {
    NSString *const CurrencySymbol = @"¤";
    NSString *const NullAndLeftToRight = @"\U0000200e";
    NSArray<NSString *> *identifiers = NSLocale.availableLocaleIdentifiers;
    for (NSString *identifier in identifiers) {
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
        XCTAssertNotNil(locale);

        NSNumberFormatter *numberFormatter = [self numberFormatterForLocale:locale];
        XCTAssertNotNil(numberFormatter);

        NSString *format = numberFormatter.positiveFormat;
        NSRange currencySymbolRange = [format rangeOfString:CurrencySymbol];
        XCTAssert(currencySymbolRange.location != NSNotFound, @"Invalid number format");

        BOOL isCurrencySymbolAtTheBeginning = currencySymbolRange.location == 0;
        BOOL isCurrencySymbolAtTheEnd = (currencySymbolRange.location + currencySymbolRange.length) == format.length;

        if (!isCurrencySymbolAtTheBeginning && !isCurrencySymbolAtTheEnd) {
            // skip check for Persian formats "fa", "fa_IR"
            if ([format hasPrefix:NullAndLeftToRight]) {
                XCTAssert([identifier isEqualToString:@"fa"] || [identifier isEqualToString:@"fa_IR"]);
                continue;
            }
        }

        XCTAssert(isCurrencySymbolAtTheBeginning || isCurrencySymbolAtTheEnd,
                  @"Invalid number format %@ for locale %@", format, identifier);
    }
}

- (void)testExtractingCurrencySymbol {
    NSArray<NSNumber *> *numbers = @[ @0, @2, @300, @0.1, @0.09, @1.0, @1.0003, @10.79 ];
    NSArray<NSString *> *identifiers = NSLocale.availableLocaleIdentifiers;
    for (NSString *identifier in identifiers) {
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
        XCTAssertNotNil(locale);

        NSNumberFormatter *numberFormatter = [self numberFormatterForLocale:locale];
        XCTAssertNotNil(numberFormatter);

        for (NSNumber *number in numbers) {
            NSString *formattedNumber = [numberFormatter stringFromNumber:number];
            NSString *currencySymbol = [DWAmountObject currencySymbolFromFormattedString:formattedNumber numberFormatter:numberFormatter];

            if (currencySymbol.length == 0) {
                // skip check for "Cape Verde" as they have empty currency symbol
                if ([identifier hasSuffix:@"_CV"]) {
                    continue;
                }
            }

            XCTAssert(currencySymbol.length > 0,
                      @"Failed for %@ (%@): '%@' (symbol %@)",
                      identifier, number, formattedNumber, numberFormatter.currencySymbol);
            XCTAssert(currencySymbol.length < formattedNumber.length,
                      @"Failed for %@ (%@): '%@' (symbol %@)",
                      identifier, number, formattedNumber, numberFormatter.currencySymbol);
        }
    }
}

- (void)testWYSIWYGForInputWithFractions {
    NSArray<NSString *> *inputFormats = @[
        @"0%@0",
        @"3%@",
        @"4%@0",
        @"56%@00",
        @"123%@45",
        @"34%@70",
    ];

    NSSet *weirdLocaleIdentifiers = [NSSet setWithObjects:@"fr_CH", @"kea_CV", @"pt_CV", nil];

    NSArray<NSString *> *identifiers = NSLocale.availableLocaleIdentifiers;
    for (NSString *identifier in identifiers) {
        if ([weirdLocaleIdentifiers containsObject:identifier]) {
            continue;
        }

        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
        XCTAssertNotNil(locale);
        if ([self isNonArabicDigitsLocale:locale]) {
            continue;
        }

        NSNumberFormatter *numberFormatter = [self numberFormatterForLocale:locale];
        numberFormatter.roundingMode = NSNumberFormatterRoundDown;
        XCTAssertNotNil(numberFormatter);

        for (NSString *inputFormat in inputFormats) {
            NSString *input = [NSString stringWithFormat:inputFormat, locale.decimalSeparator];
            NSDecimalNumber *inputNumber = [NSDecimalNumber decimalNumberWithString:input locale:locale];
            XCTAssertNotNil(inputNumber);

            NSString *formattedInput = [numberFormatter stringFromNumber:inputNumber];

            NSString *wysiwygResult = [DWAmountObject formattedAmountWithInputString:input
                                                                     formattedString:formattedInput
                                                                     numberFormatter:numberFormatter
                                                                              locale:locale];
            NSRange inputStringRange = [wysiwygResult rangeOfString:input];
            XCTAssert(inputStringRange.location != NSNotFound,
                      @"Failed with input %@ result %@ for %@", input, wysiwygResult, identifier);
        }
    }
}

- (void)testRawAmountStringExtraction {
    NSArray<NSNumber *> *numbers = @[ @0, @2, @300, @0.1, @0.09, @1.0, @1.0003, @10.79 ];
    NSArray<NSString *> *identifiers = NSLocale.availableLocaleIdentifiers;
    for (NSString *identifier in identifiers) {
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
        XCTAssertNotNil(locale);
        if ([self isNonArabicDigitsLocale:locale]) {
            continue;
        }

        NSNumberFormatter *numberFormatter = [self numberFormatterForLocale:locale];
        XCTAssertNotNil(numberFormatter);

        for (NSNumber *number in numbers) {
            NSString *formattedString = [numberFormatter stringFromNumber:number];
            if ([identifier isEqualToString:@"he"]) {
                // for some reason NSNumberFormatter can't convert its output back to number for Hebrew locale
                // [numberFormatter numberFromString:formattedString] is nil
                continue;
            }

            DWAmountInputValidator *validator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeLocalCurrency
                                                                                      locale:locale];
            NSString *rawNumberString = [DWAmountObject rawAmountStringFromFormattedString:formattedString
                                                                           numberFormatter:numberFormatter
                                                                                 validator:validator
                                                                                    locale:locale];
            NSDecimalNumber *numberFromRaw = [NSDecimalNumber decimalNumberWithString:rawNumberString locale:locale];

            NSString *formattedFromRaw = [numberFormatter stringFromNumber:numberFromRaw];

            XCTAssertEqualObjects(formattedString, formattedFromRaw,
                                  @"Failed for input %@ raw %@ locale %@",
                                  formattedString, rawNumberString, identifier);
        }
    }
}

#pragma mark - Private

- (NSNumberFormatter *)numberFormatterForLocale:(NSLocale *)locale {
    // same NSNumberFormatter configuration as in DSPriceManager
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.lenient = YES;
    numberFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
    numberFormatter.generatesDecimalNumbers = YES;
    numberFormatter.locale = locale;

    return numberFormatter;
}

- (BOOL)isNonArabicDigitsLocale:(NSLocale *)locale {
    NSCharacterSet *arabicDigitsSet = [NSCharacterSet characterSetWithCharactersInString:@"1234567890"];
    NSDecimalNumber *testNumber = [NSDecimalNumber decimalNumberWithString:@"1234567890"];
    NSNumberFormatter *testNumberFormatter = [[NSNumberFormatter alloc] init];
    testNumberFormatter.locale = locale;
    NSCharacterSet *testResultSet = [NSCharacterSet characterSetWithCharactersInString:[testNumberFormatter stringFromNumber:testNumber]];
    return ([testResultSet isSupersetOfSet:arabicDigitsSet] == NO);
}

@end
