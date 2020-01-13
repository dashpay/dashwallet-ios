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

#import "DWEnvironment.h"
#import "DWTransactionListDataItem.h"
#import "NSAttributedString+DWBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBaseTransactionListDataProvider ()

@property (readonly, nonatomic, strong) NSDateFormatter *shortDateFormatter;
@property (readonly, nonatomic, strong) NSDateFormatter *longDateFormatter;

@end

@implementation DWBaseTransactionListDataProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _txDates = [NSMutableDictionary dictionary];

        NSLocale *locale = [NSLocale currentLocale];
        _shortDateFormatter = [[NSDateFormatter alloc] init];
        _shortDateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMdjmma"
                                                                         options:0
                                                                          locale:locale];
        _longDateFormatter = [[NSDateFormatter alloc] init];
        _longDateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"yyyyMMMdjmma"
                                                                        options:0
                                                                         locale:locale];
    }
    return self;
}

- (NSDate *)dateForTransaction:(DSTransaction *)transaction {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    NSTimeInterval now = [chain timestampForBlockHeight:TX_UNCONFIRMED];
    NSTimeInterval txTime = (transaction.timestamp > 1) ? transaction.timestamp : now;
    NSDate *txDate = [NSDate dateWithTimeIntervalSince1970:txTime];

    return txDate;
}

- (NSString *)formattedShortTxDate:(NSDate *)date {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger nowYear = [calendar component:NSCalendarUnitYear fromDate:[NSDate date]];
    NSInteger txYear = [calendar component:NSCalendarUnitYear fromDate:date];

    NSDateFormatter *desiredFormatter = (nowYear == txYear) ? self.shortDateFormatter : self.longDateFormatter;
    return [desiredFormatter stringFromDate:date];
}

- (NSString *)formattedLongTxDate:(NSDate *)date {
    return [self.longDateFormatter stringFromDate:date];
}

- (NSAttributedString *)dashAmountStringFrom:(id<DWTransactionListDataItem>)transactionData
                                        font:(UIFont *)font {
    const uint64_t dashAmount = transactionData.dashAmount;
    UIColor *tintColor = transactionData.dashAmountTintColor;

    NSNumberFormatter *numberFormatter = [DSPriceManager sharedInstance].dashFormat;

    NSNumber *number = [(id)[NSDecimalNumber numberWithLongLong:dashAmount]
        decimalNumberByMultiplyingByPowerOf10:-numberFormatter.maximumFractionDigits];
    NSString *formattedNumber = [numberFormatter stringFromNumber:number];
    NSString *symbol = transactionData.directionSymbol;
    NSString *string = [symbol stringByAppendingString:formattedNumber];

    return [NSAttributedString dw_dashAttributedStringForFormattedAmount:string tintColor:tintColor font:font];
}

@end

NS_ASSUME_NONNULL_END
