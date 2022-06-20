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

#import "DWEnvironment.h"
#import "DWTransactionListDataItemObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTransactionListDataProvider ()

@property (nonatomic, assign) uint32_t blockHeightValue;

@end

@implementation DWTransactionListDataProvider

- (void)dealloc {
    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

#pragma mark - DWTransactionListDataProviderProtocol

- (NSString *)shortDateStringForTransaction:(DSTransaction *)transaction {
    NSString *dateString = self.txDates[uint256_obj(transaction.txHash)];
    if (dateString) {
        return dateString;
    }

    NSDate *date = [self dateForTransaction:transaction];
    dateString = [self formattedShortTxDate:date];

    if (transaction.blockHeight != TX_UNCONFIRMED) {
        self.txDates[uint256_obj(transaction.txHash)] = dateString;
    }

    return dateString;
}

- (NSString *)longDateStringForTransaction:(DSTransaction *)transaction {
    NSDate *date = [self dateForTransaction:transaction];
    return [self formattedLongTxDate:date];
}

- (NSString *)ISO8601StringForTransaction:(DSTransaction *)transaction {
    NSDate *date = [self dateForTransaction:transaction];
    return [self formattedISO8601TxDate:date];
}

- (id<DWTransactionListDataItem>)transactionDataForTransaction:(DSTransaction *)transaction {

    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSAccount *currentAccount = [DWEnvironment sharedInstance].currentAccount;
    DSAccount *account = [transaction.accounts containsObject:currentAccount] ? currentAccount : nil;

    DSTransactionDirection transactionDirection = account ? [chain directionOfTransaction:transaction] : DSTransactionDirection_NotAccountFunds;
    uint64_t dashAmount;

    DWTransactionListDataItemObject *dataItem = [[DWTransactionListDataItemObject alloc] init];

    dataItem.direction = transactionDirection;

    switch (transactionDirection) {
        case DSTransactionDirection_Moved: {
            dataItem.dashAmount = [account amountReceivedFromTransactionOnExternalAddresses:transaction];
            dataItem.outputReceiveAddresses = [account externalAddressesOfTransaction:transaction];
            break;
        }
        case DSTransactionDirection_Sent: {
            dataItem.dashAmount = [chain amountSentByTransaction:transaction] - [chain amountReceivedFromTransaction:transaction] - transaction.feeUsed;
            dataItem.outputReceiveAddresses = [account externalAddressesOfTransaction:transaction];
            break;
        }
        case DSTransactionDirection_Received: {
            dataItem.dashAmount = [account amountReceivedFromTransaction:transaction];
            dataItem.outputReceiveAddresses = [account externalAddressesOfTransaction:transaction];
            break;
        }
        case DSTransactionDirection_NotAccountFunds: {
            dataItem.dashAmount = 0;
            if ([transaction isKindOfClass:[DSProviderRegistrationTransaction class]]) {
                DSProviderRegistrationTransaction *registrationTransaction = (DSProviderRegistrationTransaction *)transaction;
                dataItem.specialInfoAddresses = @{registrationTransaction.ownerAddress : @0, registrationTransaction.operatorAddress : @1, registrationTransaction.votingAddress : @2};
            }
            else if ([transaction isKindOfClass:[DSProviderUpdateRegistrarTransaction class]]) {
                DSProviderUpdateRegistrarTransaction *updateRegistrarTransaction = (DSProviderUpdateRegistrarTransaction *)transaction;
                dataItem.specialInfoAddresses = @{updateRegistrarTransaction.operatorAddress : @1, updateRegistrarTransaction.votingAddress : @2};
            }
            break;
        }
    }

    if ([transaction isKindOfClass:[DSCoinbaseTransaction class]]) {
        dataItem.transactionType = DWTransactionType_Reward;
    }
    else if ([transaction isKindOfClass:[DSProviderRegistrationTransaction class]]) {
        dataItem.transactionType = DWTransactionType_MasternodeRegistration;
    }
    else if ([transaction isKindOfClass:[DSProviderUpdateRegistrarTransaction class]]) {
        dataItem.transactionType = DWTransactionType_MasternodeUpdate;
    }
    else if ([transaction isKindOfClass:[DSProviderUpdateServiceTransaction class]]) {
        dataItem.transactionType = DWTransactionType_MasternodeUpdate;
    }
    else if ([transaction isKindOfClass:[DSProviderUpdateRevocationTransaction class]]) {
        dataItem.transactionType = DWTransactionType_MasternodeRevoke;
    }
    else if ([transaction isKindOfClass:[DSCreditFundingTransaction class]]) {
        dataItem.transactionType = DWTransactionType_BlockchainIdentityRegistration;
    }
    else {
        dataItem.transactionType = DWTransactionType_Classic;
    }

    if (![transaction isKindOfClass:[DSCoinbaseTransaction class]]) {
        NSMutableSet *inputAddressesWithNulls = [NSMutableSet setWithArray:transaction.inputAddresses];
        [inputAddressesWithNulls removeObject:[NSNull null]];
        dataItem.inputSendAddresses = [inputAddressesWithNulls allObjects];
    }
    else {
        // Don't show input addresses for coinbase
        dataItem.inputSendAddresses = [NSArray array];
    }
    dataItem.fiatAmount = [priceManager localCurrencyStringForDashAmount:dataItem.dashAmount];

    const uint32_t blockHeight = [self blockHeight];
    const BOOL instantSendReceived = transaction.instantSendReceived;
    const BOOL processingInstantSend = transaction.hasUnverifiedInstantSendLock;
    const BOOL confirmed = transaction.confirmed;
    uint32_t confirms = (transaction.blockHeight > blockHeight) ? 0 : (blockHeight - transaction.blockHeight) + 1;
    if ((transactionDirection == DSTransactionDirection_Sent || transactionDirection == DSTransactionDirection_Moved) && confirms == 0 && ![account transactionIsValid:transaction]) {
        dataItem.state = DWTransactionState_Invalid;
    }
    else if (transactionDirection == DSTransactionDirection_Received) {
        if (!instantSendReceived && confirms == 0 && [account transactionIsPending:transaction]) {
            // should be very hard to get here, a miner would have to include a non standard transaction into a block
            dataItem.state = DWTransactionState_Locked;
        }
        else if (!instantSendReceived && confirms == 0 && ![account transactionIsVerified:transaction]) {
            dataItem.state = DWTransactionState_Processing;
        }
        else if ([account transactionOutputsAreLocked:transaction]) {
            dataItem.state = DWTransactionState_Locked;
        }
        else if (!instantSendReceived && !confirmed) {
            NSTimeInterval transactionAge = [NSDate timeIntervalSince1970] - transaction.timestamp; // we check the transaction age, as we might still be waiting on a transaction lock, 1 second seems like a good wait time
            if (confirms == 0 && (processingInstantSend || transactionAge < 1.0)) {
                dataItem.state = DWTransactionState_Processing;
            }
            else {
                dataItem.state = DWTransactionState_Confirming;
            }
        }
    }
    else if (transactionDirection != DSTransactionDirection_NotAccountFunds) {
        if (!instantSendReceived && confirms == 0 && ![account transactionIsVerified:transaction]) {
            dataItem.state = DWTransactionState_Processing;
        }
    }

    return dataItem;
}

#pragma mark - Private

- (uint32_t)blockHeight {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    const uint32_t lastHeight = chain.lastTerminalBlockHeight;

    if (lastHeight > self.blockHeightValue) {
        self.blockHeightValue = lastHeight;
    }

    return self.blockHeightValue;
}

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
