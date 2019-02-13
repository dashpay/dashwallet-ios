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

@interface DWAmountInputValidatorTests : XCTestCase

@property (strong, nonatomic) DWAmountInputValidator *dashValidator;
@property (strong, nonatomic) DWAmountInputValidator *localCurrencyValidator;

@end

@implementation DWAmountInputValidatorTests

- (void)setUp {
    self.dashValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeDash];
    self.localCurrencyValidator = [[DWAmountInputValidator alloc] initWithType:DWAmountInputValidatorTypeLocalCurrency];
}

- (void)testFirstInput {
    NSString *decimalSeparator = [NSLocale currentLocale].decimalSeparator;

    NSString *result = [self.dashValidator validatedAmountForLastInputString:@"" range:NSMakeRange(0, 0) replacementString:@"1"];
    XCTAssertEqualObjects(result, @"1");

    result = [self.localCurrencyValidator validatedAmountForLastInputString:@"" range:NSMakeRange(0, 0) replacementString:@"2"];
    XCTAssertEqualObjects(result, @"2");

    NSString *expectedResult = [NSString stringWithFormat:@"0%@", decimalSeparator];

    result = [self.dashValidator validatedAmountForLastInputString:@"" range:NSMakeRange(0, 0) replacementString:decimalSeparator];
    XCTAssertEqualObjects(result, expectedResult);

    result = [self.localCurrencyValidator validatedAmountForLastInputString:@"" range:NSMakeRange(0, 0) replacementString:decimalSeparator];
    XCTAssertEqualObjects(result, expectedResult);

    result = [self.dashValidator validatedAmountForLastInputString:@"" range:NSMakeRange(0, 0) replacementString:@"0"];
    XCTAssertEqualObjects(result, @"0");

    result = [self.localCurrencyValidator validatedAmountForLastInputString:@"" range:NSMakeRange(0, 0) replacementString:@"0"];
    XCTAssertEqualObjects(result, @"0");
}

- (void)testCorrectInput {
    NSString *decimalSeparator = [NSLocale currentLocale].decimalSeparator;

    NSString *result = [self.dashValidator validatedAmountForLastInputString:@"1" range:NSMakeRange(1, 0) replacementString:@"1"];
    XCTAssertEqualObjects(result, @"11");

    result = [self.localCurrencyValidator validatedAmountForLastInputString:@"2" range:NSMakeRange(1, 0) replacementString:@"2"];
    XCTAssertEqualObjects(result, @"22");

    NSString *expectedResult = [NSString stringWithFormat:@"1%@", decimalSeparator];

    result = [self.dashValidator validatedAmountForLastInputString:@"1" range:NSMakeRange(1, 0) replacementString:decimalSeparator];
    XCTAssertEqualObjects(result, expectedResult);

    result = [self.localCurrencyValidator validatedAmountForLastInputString:@"1" range:NSMakeRange(1, 0) replacementString:decimalSeparator];
    XCTAssertEqualObjects(result, expectedResult);

    expectedResult = [NSString stringWithFormat:@"0%@", decimalSeparator];
    result = [self.dashValidator validatedAmountForLastInputString:@"0" range:NSMakeRange(1, 0) replacementString:decimalSeparator];
    XCTAssertEqualObjects(result, expectedResult);

    result = [self.localCurrencyValidator validatedAmountForLastInputString:@"0" range:NSMakeRange(1, 0) replacementString:decimalSeparator];
    XCTAssertEqualObjects(result, expectedResult);

    result = [self.dashValidator validatedAmountForLastInputString:@"0" range:NSMakeRange(1, 0) replacementString:@"1"];
    XCTAssertEqualObjects(result, @"1");

    result = [self.localCurrencyValidator validatedAmountForLastInputString:@"0" range:NSMakeRange(1, 0) replacementString:@"2"];
    XCTAssertEqualObjects(result, @"2");
}

- (void)testLimitations {
    NSString *decimalSeparator = [NSLocale currentLocale].decimalSeparator;

    NSString *result = [self.dashValidator validatedAmountForLastInputString:@"21000000" range:NSMakeRange(8, 0) replacementString:@"1"];
    XCTAssertNil(result);

    result = [self.localCurrencyValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"0%@0", decimalSeparator] range:NSMakeRange(3, 0) replacementString:@"0"];
    XCTAssertNil(result);

    result = [self.dashValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"0%@0000000", decimalSeparator] range:NSMakeRange(9, 0) replacementString:@"0"];
    XCTAssertNil(result);

    result = [self.localCurrencyValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"1%@00", decimalSeparator] range:NSMakeRange(4, 0) replacementString:@"1"];
    XCTAssertNil(result);

    result = [self.dashValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"1%@00000000", decimalSeparator] range:NSMakeRange(10, 0) replacementString:@"1"];
    XCTAssertNil(result);
}

- (void)testRemoving {
    NSString *decimalSeparator = [NSLocale currentLocale].decimalSeparator;

    NSString *result = [self.dashValidator validatedAmountForLastInputString:@"1" range:NSMakeRange(0, 1) replacementString:@""];
    XCTAssertEqualObjects(result, @"");

    result = [self.localCurrencyValidator validatedAmountForLastInputString:@"2" range:NSMakeRange(0, 1) replacementString:@""];
    XCTAssertEqualObjects(result, @"");

    NSString *expectedResult = [NSString stringWithFormat:@"1%@0", decimalSeparator];

    result = [self.dashValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"1%@01", decimalSeparator] range:NSMakeRange(3, 1) replacementString:@""];
    XCTAssertEqualObjects(result, expectedResult);

    result = [self.localCurrencyValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"1%@01", decimalSeparator] range:NSMakeRange(3, 1) replacementString:@""];
    XCTAssertEqualObjects(result, expectedResult);

    expectedResult = [NSString stringWithFormat:@"1%@", decimalSeparator];
    result = [self.dashValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"1%@0", decimalSeparator] range:NSMakeRange(2, 1) replacementString:@""];
    XCTAssertEqualObjects(result, expectedResult);

    result = [self.localCurrencyValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"1%@0", decimalSeparator] range:NSMakeRange(2, 1) replacementString:@""];
    XCTAssertEqualObjects(result, expectedResult);
}

- (void)testInvalidInput {
    NSString *result = [self.dashValidator validatedAmountForLastInputString:@"" range:NSMakeRange(0, 0) replacementString:@"a"];
    XCTAssertNil(result);

    result = [self.localCurrencyValidator validatedAmountForLastInputString:@"" range:NSMakeRange(0, 0) replacementString:@"b"];
    XCTAssertNil(result);

    NSString *decimalSeparator = [NSLocale currentLocale].decimalSeparator;

    result = [self.dashValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"0%@", decimalSeparator] range:NSMakeRange(2, 0) replacementString:decimalSeparator];
    XCTAssertNil(result);

    result = [self.localCurrencyValidator validatedAmountForLastInputString:[NSString stringWithFormat:@"0%@", decimalSeparator] range:NSMakeRange(2, 0) replacementString:decimalSeparator];
    XCTAssertNil(result);
}

@end
