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

#import "DWTransactionListDataProvider.h"

#import <DashSync/DashSync.h>
#import <DashSync/UIImage+DSUtils.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *dateFormat(NSString *template) {
    NSString *format = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:[NSLocale currentLocale]];

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

@interface DWTransactionListDataProvider ()

@property (nonatomic, strong) NSMutableDictionary *txDates;
@property (nonatomic, strong) NSDateFormatter *monthDayHourFormatter;
@property (nonatomic, strong) NSDateFormatter *yearMonthDayHourFormatter;

@property (nonatomic, strong) NSNumberFormatter *dashNumberFormatter;


@end

@implementation DWTransactionListDataProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _txDates = [NSMutableDictionary dictionary];

        _monthDayHourFormatter = [NSDateFormatter new];
        _monthDayHourFormatter.dateFormat = dateFormat(@"Mdjmma");
        _yearMonthDayHourFormatter = [NSDateFormatter new];
        _yearMonthDayHourFormatter.dateFormat = dateFormat(@"yyMdja");

        _dashNumberFormatter = [[DSPriceManager sharedInstance].dashFormat copy];
        _dashNumberFormatter.positiveFormat = [_dashNumberFormatter.positiveFormat
            stringByReplacingCharactersInRange:[_dashNumberFormatter.positiveFormat rangeOfString:@"#"]
                                    withString:@"+#"];
    }
    return self;
}

#pragma mark - DWTransactionListDataProviderProtocol

- (NSString *)dateForTransaction:(DSTransaction *)tx {
    NSString *date = self.txDates[uint256_obj(tx.txHash)];
    if (date) {
        return date;
    }

    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    NSTimeInterval now = [chain timestampForBlockHeight:TX_UNCONFIRMED];

    NSTimeInterval txTime = (tx.timestamp > 1) ? tx.timestamp : now;
    NSDate *txDate = [NSDate dateWithTimeIntervalSince1970:txTime];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger nowYear = [calendar component:NSCalendarUnitYear fromDate:[NSDate date]];
    NSInteger txYear = [calendar component:NSCalendarUnitYear fromDate:txDate];

    NSDateFormatter *desiredFormatter = (nowYear == txYear) ? self.monthDayHourFormatter : self.yearMonthDayHourFormatter;
    date = [desiredFormatter stringFromDate:txDate];

    if (tx.blockHeight != TX_UNCONFIRMED) {
        self.txDates[uint256_obj(tx.txHash)] = date;
    }

    return date;
}

- (NSAttributedString *)stringForDashAmount:(uint64_t)dashAmount
                                  tintColor:(UIColor *)tintColor
                                       font:(UIFont *)font {
    NSNumber *number = [(id)[NSDecimalNumber numberWithLongLong:dashAmount]
        decimalNumberByMultiplyingByPowerOf10:-self.dashNumberFormatter.maximumFractionDigits];
    NSString *string = [self.dashNumberFormatter stringFromNumber:number];

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:string];

    const NSRange range = [attributedString.string rangeOfString:DASH];
    const BOOL dashSymbolFound = range.location != NSNotFound;
    NSAssert(dashSymbolFound, @"Dash number formatter invalid");
    if (dashSymbolFound) {
        const CGFloat scaleFactor = 0.665;
        const CGFloat side = font.pointSize * scaleFactor;
        const CGSize symbolSize = CGSizeMake(side, side);
        NSTextAttachment *dashSymbol = [[NSTextAttachment alloc] init];
        dashSymbol.bounds = CGRectMake(0, 0, symbolSize.width, symbolSize.height);
        dashSymbol.image = [[UIImage imageNamed:@"Dash-Light"] ds_imageWithTintColor:tintColor];
        NSAttributedString *dashSymbolAttributedString = [NSAttributedString attributedStringWithAttachment:dashSymbol];

        [attributedString replaceCharactersInRange:range withAttributedString:dashSymbolAttributedString];

        const NSRange fullRange = NSMakeRange(0, attributedString.length);
        [attributedString addAttribute:NSForegroundColorAttributeName value:tintColor range:fullRange];
        [attributedString addAttribute:NSFontAttributeName value:font range:fullRange];
    }
    return [attributedString copy];
}

@end

NS_ASSUME_NONNULL_END
