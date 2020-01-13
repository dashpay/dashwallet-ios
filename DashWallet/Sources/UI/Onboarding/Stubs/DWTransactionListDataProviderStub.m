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

#import "DWTransactionListDataProviderStub.h"

#import <DashSync/DashSync.h>

#import "DWTransactionStub.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWTransactionListDataProviderStub

- (NSString *)shortDateStringForTransaction:(DWTransactionStub *)transaction {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:transaction.timestamp];
    return [self formattedShortTxDate:date];
}

- (NSString *)longDateStringForTransaction:(DSTransaction *)transaction {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:transaction.timestamp];
    return [self formattedLongTxDate:date];
}

- (id<DWTransactionListDataItem>)transactionDataForTransaction:(DWTransactionStub *)transaction {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];

    DWTransactionListDataItemObject *dataItem = [[DWTransactionListDataItemObject alloc] init];
    dataItem.direction = transaction.direction;
    dataItem.dashAmount = transaction.dashAmount;
    dataItem.fiatAmount = [priceManager localCurrencyStringForDashAmount:dataItem.dashAmount];

    return dataItem;
}

@end

NS_ASSUME_NONNULL_END
