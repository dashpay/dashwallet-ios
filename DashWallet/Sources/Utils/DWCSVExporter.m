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
#import "DSTransaction+DashWallet.h"
#import "DWEnvironment.h"
#import "dashwallet-Swift.h"

@interface DWCSVExporter ()

+ (NSString *)generateFileName;
+ (NSString *)csvStringForTransactions:(NSArray<DSTransaction *> *)transactions andUserInfos:(NSDictionary<NSData *, TxUserInfo *> *)userInfos;
+ (NSString *)csvRowForTransaction:(DSTransaction *)transaction andUserInfo:(TxUserInfo *__nullable)userInfo;
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

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<DSTransaction *> *transactions = [DWCSVExporter transactions];
        NSDictionary<NSData *, TxUserInfo *> *userInfos = [[TxUserInfoDAOImpl shared] dictionaryOfAllItems];

        NSString *csv = [DWCSVExporter csvStringForTransactions:transactions andUserInfos:userInfos];

        NSString *fileName = [DWCSVExporter generateFileName];

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

+ (NSString *)csvStringForTransactions:(NSArray<DSTransaction *> *)transactions andUserInfos:(NSDictionary<NSData *, TxUserInfo *> *)userInfos {

    NSMutableString *csv = [NSMutableString new];

    NSString *header = @"Date and time,Transaction Type,Sent Quantity,Sent Currency,Sending Source,Received Quantity,Received Currency,Receiving Destination,Fee,Fee Currency,Exchange Transaction ID,Blockchain Transaction Hash\n";
    [csv appendString:header];

    for (DSTransaction *tx in transactions) {
        TxUserInfo *userInfo = userInfos[[tx txHashData]];
        [csv appendString:[DWCSVExporter csvRowForTransaction:tx andUserInfo:userInfo]];
    }

    return [NSString stringWithString:csv];
}

+ (NSString *)csvRowForTransaction:(DSTransaction *)transaction andUserInfo:(TxUserInfo *__nullable)userInfo {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSAccount *currentAccount = [DWEnvironment sharedInstance].currentAccount;
    DSAccount *account = [transaction.accounts containsObject:currentAccount] ? currentAccount : nil;

    DSTransactionDirection transactionDirection = account ? [transaction direction] : DSTransactionDirection_NotAccountFunds;

    // Return empty string for internal transactions
    if (transactionDirection == DSTransactionDirection_Moved ||
        transactionDirection == DSTransactionDirection_NotAccountFunds) {
        return @"";
    }

    NSString *iso8601String = transaction.formattedISO8601TxDate;
    NSString *taxCategoryString = [transaction defaultTaxCategoryString];

    if (userInfo != nil) {
        taxCategoryString = [userInfo taxCategoryString];
    }

    NSString *kCurrency = @"DASH";
    NSString *kSource = @"DASH";

    NSString *transactionType = [NSString new];
    NSString *sentQuantity = [NSString new];
    NSString *sentCurrency = [NSString new];
    NSString *sendingSource = [NSString new];
    NSString *receivedQuantity = [NSString new];
    NSString *receivedCurrency = [NSString new];
    NSString *receivingDestination = [NSString new];

    uint64_t fee = transactionDirection == DSTransactionDirection_Sent ? transaction.feeUsed : 0;
    uint64_t dashAmount = transaction.dashAmount + fee;

    NSNumberFormatter *numberFormatter = [DSPriceManager sharedInstance].csvDashFormat;
    NSNumber *number = [(id)[NSDecimalNumber numberWithLongLong:dashAmount]
        decimalNumberByMultiplyingByPowerOf10:-numberFormatter.maximumFractionDigits];
    NSString *formattedNumber = [numberFormatter stringFromNumber:number];

    NSData *txIdData = [NSData dataWithBytes:transaction.txHash.u8 length:sizeof(UInt256)].reverse;
    NSString *transactionId = [NSString hexWithData:txIdData];

    switch (transactionDirection) {
        case DSTransactionDirection_Sent: {
            transactionType = taxCategoryString;
            sentQuantity = formattedNumber;
            sentCurrency = kCurrency;
            sendingSource = kSource;
            break;
        }
        case DSTransactionDirection_Received: {
            transactionType = taxCategoryString;
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
