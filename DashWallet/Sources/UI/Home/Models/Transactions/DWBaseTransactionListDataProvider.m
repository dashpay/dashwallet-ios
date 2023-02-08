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

#import "DWBaseTransactionListDataProvider.h"

#import "DWDateFormatter.h"
#import "DWEnvironment.h"
#import "DWTransactionListDataItem.h"
#import "NSAttributedString+DWBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWBaseTransactionListDataProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _txDates = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)dashAmountStringFrom:(id<DWTransactionListDataItem>)transactionData {
    const uint64_t dashAmount = transactionData.dashAmount;

    NSNumberFormatter *numberFormatter = [DSPriceManager sharedInstance].dashFormat;

    NSNumber *number = [(id)[NSDecimalNumber numberWithLongLong:dashAmount]
        decimalNumberByMultiplyingByPowerOf10:-numberFormatter.maximumFractionDigits];
    NSString *formattedNumber = [numberFormatter stringFromNumber:number];
    NSString *symbol = transactionData.directionSymbol;
    NSString *string = [symbol stringByAppendingString:formattedNumber];
    return string;
}

- (NSAttributedString *)dashAmountStringFrom:(id<DWTransactionListDataItem>)transactionData
                                        font:(UIFont *)font {
    UIColor *tintColor = transactionData.dashAmountTintColor;
    return [self dashAmountStringFrom:transactionData tintColor:tintColor font:font];
}

- (NSAttributedString *)dashAmountStringFrom:(id<DWTransactionListDataItem>)transactionData
                                   tintColor:(UIColor *)color
                                        font:(UIFont *)font {
    NSString *amount = [self dashAmountStringFrom:transactionData];
    return [NSAttributedString dw_dashAttributedStringForFormattedAmount:amount tintColor:color font:font];
}

@end

NS_ASSUME_NONNULL_END
