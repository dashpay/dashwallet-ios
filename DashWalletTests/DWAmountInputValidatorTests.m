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

#define FS(fmt, sep) [NSString stringWithFormat:fmt, sep]

@interface DWAmountInputTestCase : NSObject

@property (copy, nonatomic) NSString *lastInput;
@property (assign, nonatomic) NSRange range;
@property (copy, nonatomic) NSString *string;

@property (nullable, copy, nonatomic) NSString *expectedResult;

@end

@implementation DWAmountInputTestCase

+ (instancetype)withLastInput:(NSString *)lastInput string:(NSString *)string expectedResult:(nullable NSString *)expectedResult {
    DWAmountInputTestCase *testCase = [DWAmountInputTestCase new];
    testCase.lastInput = lastInput;
    if (string.length > 0) { // append
        testCase.range = NSMakeRange(lastInput.length, 0);
    }
    else { // backspace
        if (lastInput.length > 1) {
            testCase.range = NSMakeRange(MAX(lastInput.length - 1, 0), 1);
        }
        else {
            testCase.range = NSMakeRange(0, 1);
        }
    }
    testCase.string = string;
    testCase.expectedResult = expectedResult;

    return testCase;
}

@end

#pragma mark - Test

@interface DWAmountInputValidatorTests : XCTestCase

@property (strong, nonatomic) DWAmountInputValidator *dashValidator;
@property (strong, nonatomic) DWAmountInputValidator *localCurrencyValidator;
@property (copy, nonatomic) NSArray<NSLocale *> *locales;

@end

@implementation DWAmountInputValidatorTests

- (void)setUp {
    NSMutableArray<NSLocale *> *filteredLocales = [NSMutableArray array];
    NSArray<NSString *> *identifiers = NSLocale.availableLocaleIdentifiers;
    for (NSString *identifier in identifiers) {
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
        if ([self isNonArabicDigitsLocale:locale]) {
            continue;
        }

        [filteredLocales addObject:locale];
    }
    self.locales = filteredLocales;

    self.dashValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeDash];
    self.localCurrencyValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeLocalCurrency];
}

- (void)testInitialInput {
    NSArray<DWAmountInputTestCase *> *testCases = @[
        [DWAmountInputTestCase withLastInput:@"" string:@"0" expectedResult:@"0"],
        [DWAmountInputTestCase withLastInput:@"" string:@"1" expectedResult:@"1"],
        [DWAmountInputTestCase withLastInput:@"" string:@"2" expectedResult:@"2"],
        [DWAmountInputTestCase withLastInput:@"" string:@"3" expectedResult:@"3"],
        [DWAmountInputTestCase withLastInput:@"" string:@"4" expectedResult:@"4"],
        [DWAmountInputTestCase withLastInput:@"" string:@"5" expectedResult:@"5"],
        [DWAmountInputTestCase withLastInput:@"" string:@"6" expectedResult:@"6"],
        [DWAmountInputTestCase withLastInput:@"" string:@"7" expectedResult:@"7"],
        [DWAmountInputTestCase withLastInput:@"" string:@"8" expectedResult:@"8"],
        [DWAmountInputTestCase withLastInput:@"" string:@"9" expectedResult:@"9"],
    ];

    for (NSLocale *locale in self.locales) {
        [self performTests:testCases locale:locale];
    }
}

- (void)testTwoNumbersInput {
    NSArray<DWAmountInputTestCase *> *testCases = @[
        [DWAmountInputTestCase withLastInput:@"0" string:@"0" expectedResult:@"0"],
        [DWAmountInputTestCase withLastInput:@"0" string:@"1" expectedResult:@"1"],
        [DWAmountInputTestCase withLastInput:@"0" string:@"4" expectedResult:@"4"],

        [DWAmountInputTestCase withLastInput:@"9" string:@"1" expectedResult:@"91"],
        [DWAmountInputTestCase withLastInput:@"8" string:@"2" expectedResult:@"82"],
        [DWAmountInputTestCase withLastInput:@"7" string:@"3" expectedResult:@"73"],
        [DWAmountInputTestCase withLastInput:@"6" string:@"4" expectedResult:@"64"],
        [DWAmountInputTestCase withLastInput:@"5" string:@"5" expectedResult:@"55"],
        [DWAmountInputTestCase withLastInput:@"4" string:@"6" expectedResult:@"46"],
        [DWAmountInputTestCase withLastInput:@"3" string:@"7" expectedResult:@"37"],
        [DWAmountInputTestCase withLastInput:@"2" string:@"8" expectedResult:@"28"],
        [DWAmountInputTestCase withLastInput:@"1" string:@"9" expectedResult:@"19"],
    ];

    for (NSLocale *locale in self.locales) {
        [self performTests:testCases locale:locale];
    }
}

- (void)testFractionalInput {
    for (NSLocale *locale in self.locales) {
        NSString *sep = locale.decimalSeparator;

        NSArray<DWAmountInputTestCase *> *testCases = @[
            [DWAmountInputTestCase withLastInput:@"" string:sep expectedResult:FS(@"0%@", sep)],

            [DWAmountInputTestCase withLastInput:@"0" string:sep expectedResult:FS(@"0%@", sep)],
            [DWAmountInputTestCase withLastInput:@"1" string:sep expectedResult:FS(@"1%@", sep)],
            [DWAmountInputTestCase withLastInput:@"2" string:sep expectedResult:FS(@"2%@", sep)],
            [DWAmountInputTestCase withLastInput:@"3" string:sep expectedResult:FS(@"3%@", sep)],
            [DWAmountInputTestCase withLastInput:@"4" string:sep expectedResult:FS(@"4%@", sep)],
            [DWAmountInputTestCase withLastInput:@"5" string:sep expectedResult:FS(@"5%@", sep)],
            [DWAmountInputTestCase withLastInput:@"6" string:sep expectedResult:FS(@"6%@", sep)],
            [DWAmountInputTestCase withLastInput:@"7" string:sep expectedResult:FS(@"7%@", sep)],
            [DWAmountInputTestCase withLastInput:@"8" string:sep expectedResult:FS(@"8%@", sep)],
            [DWAmountInputTestCase withLastInput:@"9" string:sep expectedResult:FS(@"9%@", sep)],

            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"0" expectedResult:FS(@"0%@0", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"1" expectedResult:FS(@"0%@1", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"2" expectedResult:FS(@"0%@2", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"3" expectedResult:FS(@"0%@3", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"4" expectedResult:FS(@"0%@4", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"5" expectedResult:FS(@"0%@5", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"6" expectedResult:FS(@"0%@6", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"7" expectedResult:FS(@"0%@7", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"8" expectedResult:FS(@"0%@8", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@", sep) string:@"9" expectedResult:FS(@"0%@9", sep)],

            [DWAmountInputTestCase withLastInput:FS(@"123%@", sep) string:@"4" expectedResult:FS(@"123%@4", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"10000%@", sep) string:@"5" expectedResult:FS(@"10000%@5", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@0", sep) string:@"1" expectedResult:FS(@"0%@01", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"4%@3", sep) string:@"2" expectedResult:FS(@"4%@32", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"2%@1", sep) string:@"0" expectedResult:FS(@"2%@10", sep)],
        ];

        [self performTests:testCases locale:locale];
    }
}

- (void)testMaximumLimits {
    for (NSLocale *locale in self.locales) {
        NSString *sep = locale.decimalSeparator;

        NSArray<DWAmountInputTestCase *> *testCases = @[
            [DWAmountInputTestCase withLastInput:FS(@"0%@0", sep) string:@"0" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:FS(@"1%@00", sep) string:@"1" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:FS(@"2%@34", sep) string:@"5" expectedResult:nil],
        ];
        [self performLocalCurrencyValidatorTests:testCases locale:locale];

        testCases = @[
            [DWAmountInputTestCase withLastInput:FS(@"0%@00000000", sep) string:@"0" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:FS(@"1%@00000000", sep) string:@"1" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:FS(@"2%@34361738", sep) string:@"5" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:@"21000000" string:@"1" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:@"21000000" string:@"0" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:@"21000000" string:sep expectedResult:FS(@"21000000%@", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"21000000%@", sep) string:@"0" expectedResult:FS(@"21000000%@0", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"21000000%@", sep) string:@"1" expectedResult:nil],
        ];
        [self performDashValidatorTests:testCases locale:locale];
    }
}

- (void)testRemoving {
    for (NSLocale *locale in self.locales) {
        NSString *sep = locale.decimalSeparator;

        NSArray<DWAmountInputTestCase *> *testCases = @[
            [DWAmountInputTestCase withLastInput:FS(@"1%@01", sep) string:@"" expectedResult:FS(@"1%@0", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"1%@0", sep) string:@"" expectedResult:FS(@"1%@", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"1%@", sep) string:@"" expectedResult:@"1"],
            [DWAmountInputTestCase withLastInput:@"1" string:@"" expectedResult:@""],
            [DWAmountInputTestCase withLastInput:@"0" string:@"" expectedResult:@""],
        ];
        [self performTests:testCases locale:locale];
    }
}

- (void)testInvalidInput {
    for (NSLocale *locale in self.locales) {
        NSString *sep = locale.decimalSeparator;

        NSArray<DWAmountInputTestCase *> *testCases = @[
            [DWAmountInputTestCase withLastInput:@"" string:@"" expectedResult:nil],

            [DWAmountInputTestCase withLastInput:@"" string:@"a" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:@"1" string:@"-" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:@"2" string:@"+" expectedResult:nil],
            [DWAmountInputTestCase withLastInput:@"3" string:@"$" expectedResult:nil],

            [DWAmountInputTestCase withLastInput:FS(@"1%@", sep) string:sep expectedResult:nil],
            [DWAmountInputTestCase withLastInput:FS(@"1%@2", sep) string:sep expectedResult:nil],
            [DWAmountInputTestCase withLastInput:FS(@"23%@45", sep) string:sep expectedResult:nil],
        ];
        [self performTests:testCases locale:locale];
    }
}

- (void)testCopyPasteInput {
    for (NSLocale *locale in self.locales) {
        NSString *sep = locale.decimalSeparator;

        NSArray<DWAmountInputTestCase *> *testCases = @[
            [DWAmountInputTestCase withLastInput:@"0" string:@"00" expectedResult:@"0"],
            [DWAmountInputTestCase withLastInput:@"0" string:@"001" expectedResult:@"1"],
            [DWAmountInputTestCase withLastInput:@"0" string:@"10" expectedResult:@"10"],
            [DWAmountInputTestCase withLastInput:@"10" string:@"20" expectedResult:@"1020"],
            [DWAmountInputTestCase withLastInput:@"10" string:@"020" expectedResult:@"10020"],
            [DWAmountInputTestCase withLastInput:@"10" string:FS(@"%@02", sep) expectedResult:FS(@"10%@02", sep)],
            [DWAmountInputTestCase withLastInput:FS(@"0%@1", sep) string:FS(@"0%@1", sep) expectedResult:nil],
        ];
        [self performTests:testCases locale:locale];
    }
}

#pragma mark - Private

- (void)performTests:(NSArray<DWAmountInputTestCase *> *)testCases locale:(NSLocale *)locale {
    [self performDashValidatorTests:testCases locale:locale];
    [self performLocalCurrencyValidatorTests:testCases locale:locale];
}

- (void)performDashValidatorTests:(NSArray<DWAmountInputTestCase *> *)testCases locale:(NSLocale *)locale {
    for (DWAmountInputTestCase *test in testCases) {
        DWAmountInputValidator *validator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeDash
                                                                                  locale:locale];
        XCTAssertNotNil(validator);
        [self checkTestCase:test validator:validator locale:locale];
    }
}

- (void)performLocalCurrencyValidatorTests:(NSArray<DWAmountInputTestCase *> *)testCases locale:(NSLocale *)locale {
    for (DWAmountInputTestCase *test in testCases) {
        DWAmountInputValidator *validator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeLocalCurrency
                                                                                  locale:locale];
        XCTAssertNotNil(validator);
        [self checkTestCase:test validator:validator locale:locale];
    }
}

- (void)checkTestCase:(DWAmountInputTestCase *)testCase validator:(DWAmountInputValidator *)validator locale:(NSLocale *)locale {
    NSString *result = [validator validatedStringFromLastInputString:testCase.lastInput
                                                               range:testCase.range
                                                   replacementString:testCase.string];

    if (testCase.expectedResult) {
        XCTAssertEqualObjects(result, testCase.expectedResult,
                              @"Last input: %@ Replacement string: %@ Result: %@ Expected: %@ Locale: %@",
                              testCase.lastInput, testCase.string, result, testCase.expectedResult, locale.localeIdentifier);
    }
    else {
        XCTAssertNil(result,
                     @"Last input: %@ Replacement string: %@ Result: %@ Expected: %@ Locale: %@",
                     testCase.lastInput, testCase.string, result, testCase.expectedResult, locale.localeIdentifier);
    }
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
