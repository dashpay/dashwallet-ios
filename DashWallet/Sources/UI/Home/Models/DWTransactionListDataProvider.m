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

@property (nonatomic, copy) NSString *address;
@property (nonatomic, assign) uint64_t dashAmount;
@property (nonatomic, assign, getter=isSent) BOOL sent;
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

    const uint64_t sent = [account amountSentByTransaction:transaction];
    const uint64_t received = [account amountReceivedFromTransaction:transaction];

    uint64_t dashAmount;
    UIColor *tintColor = nil;
    BOOL treatAsSent;
    if (sent > 0 && received == sent) {
        // moved
        dashAmount = sent;
        tintColor = [UIColor dw_darkTitleColor];
        treatAsSent = YES;
    }
    else if (sent > 0) {
        // sent
        dashAmount = received - sent;
        tintColor = [UIColor dw_darkTitleColor];
        treatAsSent = YES;
    }
    else {
        // received
        dashAmount = received;
        tintColor = [UIColor dw_dashBlueColor];
        treatAsSent = NO;
    }

    DWTransactionListDataItemObject *dataItem = [[DWTransactionListDataItemObject alloc] init];

    if (treatAsSent) {
        NSMutableArray<NSString *> *outputs = [self outputsForTransaction:transaction
                                                                     sent:sent
                                                                 received:received];
        dataItem.address = outputs.firstObject;
    }
    else {
        NSMutableArray<NSString *> *inputs = [self inputsForTransaction:transaction];
        dataItem.address = inputs.firstObject;
    }

    dataItem.dashAmount = dashAmount;
    dataItem.sent = treatAsSent;
    dataItem.dashAmountTintColor = tintColor;
    dataItem.fiatAmount = [priceManager localCurrencyStringForDashAmount:dashAmount];

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
    NSString *string = nil;
    if (transactionData.isSent) {
        string = formattedNumber;
    }
    else {
        string = [@"+" stringByAppendingString:formattedNumber];
    }

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

- (NSMutableArray<NSString *> *)outputsForTransaction:(DSTransaction *)transaction
                                                 sent:(uint64_t)sent
                                             received:(uint64_t)received {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSAccount *account = transaction.account;

    const uint64_t fee = [account feeForTransaction:transaction];

    NSMutableArray<NSString *> *outputs = [NSMutableArray array];

    NSUInteger outputAmountIndex = 0;

    for (NSString *address in transaction.outputAddresses) {
        NSData *script = transaction.outputScripts[outputAmountIndex];

        if (address == (id)[NSNull null]) {
            if (sent > 0) {
                if ([script UInt8AtOffset:0] == OP_RETURN) {
                    UInt8 length = [script UInt8AtOffset:1];
                    if ([script UInt8AtOffset:2] == OP_SHAPESHIFT) {
                        NSMutableData *data = [NSMutableData data];
                        uint8_t v = BITCOIN_PUBKEY_ADDRESS;
                        [data appendBytes:&v length:1];
                        NSData *addressData = [script subdataWithRange:NSMakeRange(3, length - 1)];

                        [data appendData:addressData];
                        [outputs addObject:[NSString base58checkWithData:data]];
                    }
                }
                else {
                    [outputs addObject:NSLocalizedString(@"unknown address", nil)];
                }
            }
        }
        else if ([transaction isKindOfClass:DSProviderRegistrationTransaction.class] && [((DSProviderRegistrationTransaction *)transaction).masternodeHoldingWallet containsHoldingAddress:address]) {
            if (sent == 0 || received + MASTERNODE_COST + fee == sent) {
                [outputs addObject:address];
            }
        }
        else if ([account containsAddress:address]) {
            if (sent == 0 || received == sent) {
                [outputs addObject:address];
            }
        }
        else if (sent > 0) {
            [outputs addObject:address];
        }
    }

    return outputs;
}

@end

NS_ASSUME_NONNULL_END
