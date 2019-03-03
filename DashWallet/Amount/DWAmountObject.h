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

NS_ASSUME_NONNULL_BEGIN

@class DWAmountInputValidator;

@interface DWAmountObject : NSObject

@property (readonly, copy, nonatomic) NSAttributedString *dashAttributedString;
@property (readonly, copy, nonatomic) NSAttributedString *localCurrencyAttributedString;

@property (readonly, copy, nonatomic) NSString *dashFormatted;
@property (readonly, copy, nonatomic) NSString *localCurrencyFormatted;

@property (readonly, copy, nonatomic) NSString *amountInternalRepresentation;
@property (readonly, assign, nonatomic) int64_t plainAmount;


/**
 @return Object that internally represents Dash amount
 */
- (instancetype)initWithDashAmountString:(NSString *)dashAmountString;
/**
 @return Object that internally represents local currency amount
 */
- (nullable instancetype)initWithLocalAmountString:(NSString *)localAmountString;

/**
 @return Object that internally represents local currency amount
 */
- (instancetype)initAsLocalWithPreviousAmount:(DWAmountObject *)previousAmount
                       localCurrencyValidator:(DWAmountInputValidator *)localCurrencyValidator;
/**
 @return Object that internally represents Dash amount
 */
- (instancetype)initAsDashWithPreviousAmount:(DWAmountObject *)previousAmount
                               dashValidator:(DWAmountInputValidator *)dashValidator;

/**
 @return Object that internally represents Dash amount
 */
- (instancetype)initWithPlainAmount:(uint64_t)plainAmount;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
