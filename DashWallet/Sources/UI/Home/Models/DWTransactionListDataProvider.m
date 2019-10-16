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

#import "NSAttributedString+DWBuilder.h"
#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *TxDateFormat(NSString *template) {
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

#pragma mark - Data Item


@interface DWTransactionListDataItemObject : NSObject <DWTransactionListDataItem>

@property (nonatomic, strong) NSArray<NSString *> *outputReceiveAddresses;
@property (nonatomic, strong) NSArray<NSString *> *inputSendAddresses;
@property (nonatomic, assign) uint64_t dashAmount;
@property (nonatomic, assign) DSTransactionDirection direction;
@property (nonatomic, strong) UIColor *dashAmountTintColor;
@property (nonatomic, copy) NSString *fiatAmount;

@end

@implementation DWTransactionListDataItemObject

@end

#pragma mark - Provider

@interface DWTransactionListDataProvider ()

@property (nonatomic, strong) NSMutableDictionary *txDates;
@property (nonatomic, strong) NSDateFormatter *monthDayHourFormatter;
@property (nonatomic, strong) NSDateFormatter *yearMonthDayHourFormatter;

@end

@implementation DWTransactionListDataProvider

- (instancetype)init {
    self = [super init];
    if (self) {
        _txDates = [NSMutableDictionary dictionary];

        _monthDayHourFormatter = [NSDateFormatter new];
        _monthDayHourFormatter.dateFormat = TxDateFormat(@"Mdjmma");
        _yearMonthDayHourFormatter = [NSDateFormatter new];
        _yearMonthDayHourFormatter.dateFormat = TxDateFormat(@"yyMdja");
    }
    return self;
}

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

#pragma mark - DWTransactionListDataProviderProtocol

- (NSString *)dateForTransaction:(DSTransaction *)transaction {
    NSString *date = self.txDates[uint256_obj(transaction.txHash)];
    if (date) {
        return date;
    }

    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    NSTimeInterval now = [chain timestampForBlockHeight:TX_UNCONFIRMED];

    NSTimeInterval txTime = (transaction.timestamp > 1) ? transaction.timestamp : now;
    NSDate *txDate = [NSDate dateWithTimeIntervalSince1970:txTime];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger nowYear = [calendar component:NSCalendarUnitYear fromDate:[NSDate date]];
    NSInteger txYear = [calendar component:NSCalendarUnitYear fromDate:txDate];

    NSDateFormatter *desiredFormatter = (nowYear == txYear) ? self.monthDayHourFormatter : self.yearMonthDayHourFormatter;
    date = [desiredFormatter stringFromDate:txDate];

    if (transaction.blockHeight != TX_UNCONFIRMED) {
        self.txDates[uint256_obj(transaction.txHash)] = date;
    }

    return date;
}

- (id<DWTransactionListDataItem>)transactionDataForTransaction:(DSTransaction *)transaction {
    // inherited from DWTxDetailViewController `- (void)setTransaction:(DSTransaction *)transaction`

    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSAccount *account = transaction.account;


    DSTransactionDirection transactionDirection = [account directionOfTransaction:transaction];
    uint64_t dashAmount;
    UIColor *tintColor = nil;

    DWTransactionListDataItemObject *dataItem = [[DWTransactionListDataItemObject alloc] init];

    dataItem.direction = transactionDirection;

    switch (transactionDirection) {
        case DSTransactionDirection_Moved: {
            dataItem.dashAmount = [account amountReceivedFromTransactionOnExternalAddresses:transaction];
            dataItem.dashAmountTintColor = [UIColor dw_quaternaryTextColor];

            break;
        }
        case DSTransactionDirection_Sent: {
            dataItem.dashAmount = [account amountSentByTransaction:transaction] - [account amountReceivedFromTransaction:transaction] - transaction.feeUsed;
            dataItem.dashAmountTintColor = [UIColor dw_darkTitleColor];

            break;
        }
        case DSTransactionDirection_Received: {
            dataItem.dashAmount = [account amountReceivedFromTransaction:transaction];
            dataItem.dashAmountTintColor = [UIColor dw_dashBlueColor];

            break;
        }
    }

    dataItem.inputSendAddresses = transaction.inputAddresses;
    dataItem.outputReceiveAddresses = [account externalAddressesOfTransaction:transaction];

    dataItem.fiatAmount = [priceManager localCurrencyStringForDashAmount:dataItem.dashAmount];


    return dataItem;
}

- (NSAttributedString *)dashAmountStringFrom:(id<DWTransactionListDataItem>)transactionData
                                        font:(UIFont *)font {
    const uint64_t dashAmount = transactionData.dashAmount;
    UIColor *tintColor = transactionData.dashAmountTintColor;

    NSNumberFormatter *numberFormatter = [DSPriceManager sharedInstance].dashFormat;

    NSNumber *number = [(id)[NSDecimalNumber numberWithLongLong:dashAmount]
        decimalNumberByMultiplyingByPowerOf10:-numberFormatter.maximumFractionDigits];
    NSString *formattedNumber = [numberFormatter stringFromNumber:number];
    NSString *symbol = nil;
    switch (transactionData.direction) {
        case DSTransactionDirection_Moved:
            symbol = @"⟲";
            break;
        case DSTransactionDirection_Received:
            symbol = @"+";
            break;
        case DSTransactionDirection_Sent:
            symbol = @"-";
            break;
    }
    NSString *string = [symbol stringByAppendingString:formattedNumber];

    return [NSAttributedString dw_dashAttributedStringForFormattedAmount:string tintColor:tintColor font:font];
}

#pragma mark - Private

- (NSMutableArray<NSString *> *)inputsForTransaction:(DSTransaction *)transaction {
    NSMutableArray<NSString *> *inputs = [NSMutableArray array];

    for (NSString *inputAddress in transaction.inputAddresses) {
        if (![inputs containsObject:inputAddress]) {
            [inputs addObject:inputAddress];
        }
    }

    return inputs;
}

@end

NS_ASSUME_NONNULL_END
