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

static NSString *DWTxDateFormat(NSString *tmplate) {
    NSString *format = [NSDateFormatter dateFormatFromTemplate:tmplate options:0 locale:[NSLocale currentLocale]];

    format = [format stringByReplacingOccurrencesOfString:@", " withString:@" "];
    format = [format stringByReplacingOccurrencesOfString:@" a" withString:@"a"];
    format = [format stringByReplacingOccurrencesOfString:@"hh" withString:@"h"];
    format = [format stringByReplacingOccurrencesOfString:@" ha" withString:@"@ha"];
    format = [format stringByReplacingOccurrencesOfString:@"HH" withString:@"H"];
    format = [format stringByReplacingOccurrencesOfString:@"H '" withString:@"H'"];
    format = [format stringByReplacingOccurrencesOfString:@"H " withString:@"H'h' "];
    format = [format stringByReplacingOccurrencesOfString:@"H"
                                               withString:@"H'h'"
                                                  options:NSBackwardsSearch | NSAnchoredSearch
                                                    range:NSMakeRange(0, format.length)];
    return format;
}

@interface DWBaseTransactionListDataProvider ()

@property (readonly, nonatomic, strong) NSDateFormatter *monthDayHourFormatter;
@property (readonly, nonatomic, strong) NSDateFormatter *yearMonthDayHourFormatter;

@end

@implementation DWBaseTransactionListDataProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _txDates = [NSMutableDictionary dictionary];

        _monthDayHourFormatter = [NSDateFormatter new];
        _monthDayHourFormatter.dateFormat = DWTxDateFormat(@"Mdjmma");
        _yearMonthDayHourFormatter = [NSDateFormatter new];
        _yearMonthDayHourFormatter.dateFormat = DWTxDateFormat(@"yyMdja");
    }
    return self;
}

- (NSString *)formattedTxDateForTimestamp:(NSTimeInterval)timestamp {
    NSDate *txDate = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger nowYear = [calendar component:NSCalendarUnitYear fromDate:[NSDate date]];
    NSInteger txYear = [calendar component:NSCalendarUnitYear fromDate:txDate];

    NSDateFormatter *desiredFormatter = (nowYear == txYear) ? self.monthDayHourFormatter : self.yearMonthDayHourFormatter;
    return [desiredFormatter stringFromDate:txDate];
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
