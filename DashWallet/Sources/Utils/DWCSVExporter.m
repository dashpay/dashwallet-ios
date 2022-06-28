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

#import "DWCSVExporter.h"
#import "DWEnvironment.h"
#import "DWTransactionListDataProvider.h"

@interface DWCSVExporter ()

+ (NSString *)generateFileName;
+ (NSString *)csvStringForTransactions:(NSArray<DSTransaction *> *)transactions;
+ (NSString *)csvRowForTransaction:(DSTransaction *)transaction;
+ (NSArray<DSTransaction *> *)transactions;

@end

@implementation DWCSVExporter

+ (void)generateCSVReportWithCompletionHandler:(void (^)(NSString *fileName, NSURL *file))completionHandler errorHandler:(void (^)(NSError *error))errorHandler {

    if ([DWEnvironment sharedInstance].currentChainManager.syncPhase != DSChainSyncPhase_Synced) {
        errorHandler([NSError errorWithDomain:@"DashWallet"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey : DSLocalizedString(@"Please wait until the wallet is fully synced before exporting your transaction history", nil)}]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<DSTransaction *> *transactions = [weakSelf transactions];

        NSString *csv = [weakSelf csvStringForTransactions:transactions];

        NSString *fileName = [weakSelf generateFileName];

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDir = [paths objectAtIndex:0];
        NSString *filePath = [documentsDir stringByAppendingPathComponent:fileName];

        [csv writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        dispatch_async(dispatch_get_main_queue(), ^(void) {
            completionHandler(fileName, [NSURL fileURLWithPath:filePath]);
        });
    });
}

+ (NSString *)generateFileName {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    [dateFormatter setLocale:enUSPOSIXLocale];
    [dateFormatter setDateFormat:@"yyyy-MM-dd"];
    [dateFormatter setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]];

    NSDate *now = [NSDate date];
    NSString *iso8601String = [dateFormatter stringFromDate:now];
    NSString *fileName = [NSString stringWithFormat:@"report-%@.csv", iso8601String];

    return fileName;
}

+ (NSString *)csvStringForTransactions:(NSArray<DSTransaction *> *)transactions {
    DWTransactionListDataProvider *dataProvider = [[DWTransactionListDataProvider alloc] init];

    NSMutableString *csv = [NSMutableString new];

    NSString *header = @"Date and time,Transaction Type,Sent Quantity,Sent Currency,Sending Source,Received Quantity,Received Currency,Receiving Destination,Fee,Fee Currency,Exchange Transaction ID,Blockchain Transaction Hash\n";
    [csv appendString:header];

    for (DSTransaction *tx in transactions) {
        [csv appendString:[self csvRowForTransaction:tx usingDataProvider:dataProvider]];
    }

    return [NSString stringWithString:csv];
}

+ (NSString *)csvRowForTransaction:(DSTransaction *)transaction usingDataProvider:(DWTransactionListDataProvider *)dataProvider {
    id<DWTransactionListDataItem> dataItem = [dataProvider transactionDataForTransaction:transaction];

    // Return empty string for internal transactions
    if (dataItem.direction == DSTransactionDirection_Moved || dataItem.direction == DSTransactionDirection_NotAccountFunds) {
        return @"";
    }

    NSString *iso8601String = [dataProvider ISO8601StringForTransaction:transaction];

    NSString *kCurrency = @"DASH";
    NSString *kSource = @"DASH";
    NSString *kExpense = @"Expense";
    NSString *kIncome = @"Income";

    NSString *transactionType = [NSString new];
    NSString *sentQuantity = [NSString new];
    NSString *sentCurrency = [NSString new];
    NSString *sendingSource = [NSString new];
    NSString *receivedQuantity = [NSString new];
    NSString *receivedCurrency = [NSString new];
    NSString *receivingDestination = [NSString new];

    uint64_t dashAmount = dataItem.dashAmount + (dataItem.direction == DSTransactionDirection_Sent ? [transaction feeUsed] : 0);

    NSNumberFormatter *numberFormatter = [DSPriceManager sharedInstance].csvDashFormat;
    NSNumber *number = [(id)[NSDecimalNumber numberWithLongLong:dashAmount]
        decimalNumberByMultiplyingByPowerOf10:-numberFormatter.maximumFractionDigits];
    NSString *formattedNumber = [numberFormatter stringFromNumber:number];

    NSData *txIdData = [NSData dataWithBytes:transaction.txHash.u8 length:sizeof(UInt256)].reverse;
    NSString *transactionId = [NSString hexWithData:txIdData];

    switch (dataItem.direction) {
        case DSTransactionDirection_Sent: {
            transactionType = kExpense;
            sentQuantity = formattedNumber;
            sentCurrency = kCurrency;
            sendingSource = kSource;
            break;
        }
        case DSTransactionDirection_Received: {
            transactionType = kIncome;
            receivedQuantity = formattedNumber;
            receivedCurrency = kCurrency;
            receivingDestination = kSource;
            break;
        }
        default: {
            break;
        }
    }

    return [NSString stringWithFormat:@"%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@\n", iso8601String, transactionType, sentQuantity, sentCurrency, sendingSource, receivedQuantity, receivedCurrency, receivingDestination, @"", @"", @"", transactionId];
}

+ (NSArray<DSTransaction *> *)transactions {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;

    NSString *sortKey = DW_KEYPATH(DSTransaction.new, timestamp);

    // Timestamps are set to 0 if the transaction hasn't yet been confirmed, they should be at the top of the list if this is the case
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:sortKey
                                                                     ascending:YES
                                                                    comparator:^NSComparisonResult(id _Nonnull obj1, id _Nonnull obj2) {
                                                                        if ([obj1 unsignedIntValue] == 0) {
                                                                            if ([obj2 unsignedIntValue] == 0) {
                                                                                return NSOrderedSame;
                                                                            }
                                                                            else {
                                                                                return NSOrderedDescending;
                                                                            }
                                                                        }
                                                                        else if ([obj2 unsignedIntValue] == 0) {
                                                                            return NSOrderedAscending;
                                                                        }
                                                                        else {
                                                                            return [(NSNumber *)obj1 compare:obj2];
                                                                        }
                                                                    }];
    NSArray<DSTransaction *> *transactions = [wallet.allTransactions sortedArrayUsingDescriptors:@[ sortDescriptor ]];
    return transactions;
}

@end
