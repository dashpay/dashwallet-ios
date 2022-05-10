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

#import "DWToolsMenuModel.h"
#import "DWEnvironment.h"
#import "DWTransactionListDataProvider.h"

@interface DWToolsMenuModel ()
@property (readonly, nonatomic, strong) DWTransactionListDataProvider *dataProvider;
@end

@implementation DWToolsMenuModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _dataProvider = [[DWTransactionListDataProvider alloc] init];
    }
    return self;
}

- (void)generateCSVReportWithCompletionHandler:(void (^)(NSString *fileName, NSURL *file))completionHandler errorHandler:(void (^)(NSError *error))errorHandler {

    if ([DWEnvironment sharedInstance].currentChainManager.syncPhase != DSChainSyncPhase_Synced) {
        errorHandler([NSError errorWithDomain:@"DashWallet"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey : DSLocalizedString(@"Please wait until the wallet is fully synced before exporting your transaction history", nil)}]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<DSTransaction *> *transactions = [weakSelf transactions];

        DWTransactionListDataProvider *dataProvider = [[DWTransactionListDataProvider alloc] init];

        NSMutableString *csv = [NSMutableString new];

        NSString *headers = @"Date and time,Transaction Type,Sent Quantity,Sent Currency,Sending Source,Received Quantity,Received Currency,Receiving Destination,Fee,Fee Currency,Exchange Transaction ID,Blockchain Transaction Hash\n";
        [csv appendString:headers];

        for (DSTransaction *tx in transactions) {
            [csv appendString:[weakSelf csvRowForTransaction:tx]];
        }

        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        [dateFormatter setLocale:enUSPOSIXLocale];
        [dateFormatter setDateFormat:@"yyyy-MM-dd"];
        [dateFormatter setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]];

        NSDate *now = [NSDate date];
        NSString *iso8601String = [dateFormatter stringFromDate:now];
        NSString *fileName = [NSString stringWithFormat:@"report-%@.csv", iso8601String];

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDir = [paths objectAtIndex:0];
        NSString *filePath = [documentsDir stringByAppendingPathComponent:fileName];

        [csv writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        dispatch_async(dispatch_get_main_queue(), ^(void) {
            completionHandler(fileName, [NSURL fileURLWithPath:filePath]);
        });
    });
}

- (NSString *)csvRowForTransaction:(DSTransaction *)transaction {
    id<DWTransactionListDataItem> dataItem = [self.dataProvider transactionDataForTransaction:transaction];
    NSString *iso8601String = [self.dataProvider ISO8601StringForTransaction:transaction];


    NSString *transactionType = @"Income";
    NSString *sentQuantity = @"";
    NSString *sentCurrency = @"";
    NSString *sendingSource = [NSString new];
    NSString *receivedQuantity = [NSString new];
    NSString *receivedCurrency = [NSString new];
    NSString *receivingDestination = [NSString new];


    NSNumberFormatter *numberFormatter = [[DSPriceManager sharedInstance].dashFormat copy];
    numberFormatter.currencyCode = @"";
    numberFormatter.currencySymbol = @"";
    NSNumber *number = [(id)[NSDecimalNumber numberWithLongLong:dataItem.dashAmount]
        decimalNumberByMultiplyingByPowerOf10:-numberFormatter.maximumFractionDigits];
    NSString *formattedNumber = [numberFormatter stringFromNumber:number];

    switch (dataItem.direction) {
        case DSTransactionDirection_Moved: {
            break;
        }
        case DSTransactionDirection_Sent: {
            transactionType = @"Expense";
            sentQuantity = formattedNumber;
            sentCurrency = @"DASH";
            sendingSource = @"DASH Wallet";
            break;
        }
        case DSTransactionDirection_Received: {
            receivedQuantity = formattedNumber;
            receivedCurrency = @"DASH";
            receivingDestination = @"DASH Wallet";
            break;
        }
        case DSTransactionDirection_NotAccountFunds: {
            break;
        }
    }

    return [NSString stringWithFormat:@"%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@\n", iso8601String, transactionType, sentQuantity, sentCurrency, sendingSource, receivedQuantity, receivedCurrency, receivingDestination, @"", @"", @"", uint256_hex(transaction.txHash)];
}

- (NSArray<DSTransaction *> *)transactions {
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
