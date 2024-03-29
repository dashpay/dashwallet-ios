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

#import <Foundation/Foundation.h>

#import "DWInputValidator.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWAmountInputValidatorType) {
    DWAmountInputValidatorTypeDash,
    DWAmountInputValidatorTypeLocalCurrency,
};

@interface DWAmountInputValidator : NSObject <DWInputValidator>

@property (readonly, assign, nonatomic) DWAmountInputValidatorType type;
@property (nonatomic, copy) NSNumberFormatter *numberFormatter;

- (nullable NSString *)stringFromNumberUsingInternalFormatter:(NSNumber *)number;

- (instancetype)initWithType:(DWAmountInputValidatorType)type;
- (instancetype)initWithType:(DWAmountInputValidatorType)type locale:(nullable NSLocale *)locale NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
