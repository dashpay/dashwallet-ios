//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWUserProfileDataSourceObject.h"

#import "DWDPAcceptedRequestNotificationObject.h"
#import "DWDPOutgoingRequestNotificationObject.h"
#import "DWDPTxObject.h"
#import "DWEnvironment.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileDataSourceObject ()

@property (readonly, nonatomic, assign) BOOL hasDataToShow;
@property (nullable, readonly, nonatomic, strong) NSFetchedResultsController *frc;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> txDataProvider;
@property (readonly, nonatomic, strong) DSIdentity *friendIdentity;

@property (readonly, nonatomic, strong) NSMutableArray<id<DWDPBasicItem>> *items;
@property (nullable, readonly, nonatomic, strong) DWDPAcceptedRequestNotificationObject *incomingNotification;
@property (nullable, readonly, nonatomic, strong) DWDPOutgoingRequestNotificationObject *outgoingNotification;
@property (nonatomic, assign) BOOL incomingNotificationAdded;
@property (nonatomic, assign) BOOL outgoingNotificationAdded;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileDataSourceObject

- (instancetype)initWithTxFRC:(NSFetchedResultsController *)frc
               txDataProvider:(id<DWTransactionListDataProviderProtocol>)txDataProvider
            friendToMeRequest:(nullable DSFriendRequestEntity *)friendToMe
            meToFriendRequest:(nullable DSFriendRequestEntity *)meToFriend
               friendIdentity:(DSIdentity *)friendIdentity
                   myIdentity:(DSIdentity *)myIdentity {
    self = [super init];
    if (self) {
        _frc = frc;
        _txDataProvider = txDataProvider;
        _friendIdentity = friendIdentity;
        _items = [NSMutableArray array];
        _hasDataToShow = (frc != nil) || (friendToMe != nil) || (meToFriend != nil);

        if (MOCK_DASHPAY) {
            _hasDataToShow = YES;
            _incomingNotification = [[DWDPAcceptedRequestNotificationObject alloc] initWithIdentity:friendIdentity];
        }

        BOOL isFriendInitiated;
        if (friendToMe && meToFriend) {
            isFriendInitiated = friendToMe.timestamp < meToFriend.timestamp;
        }
        else if (friendToMe) {
            isFriendInitiated = YES;
        }
        else {
            isFriendInitiated = NO;
        }

        if (friendToMe) {
            _incomingNotification =
                [[DWDPAcceptedRequestNotificationObject alloc] initWithFriendRequestEntity:friendToMe
                                                                                  identity:friendIdentity
                                                                         isInitiatedByThem:isFriendInitiated];
        }
        else if (!MOCK_DASHPAY) {
            // mark it as added to the list to skip
            _incomingNotificationAdded = YES;
        }

        if (meToFriend) {
            _outgoingNotification =
                [[DWDPOutgoingRequestNotificationObject alloc] initWithFriendRequestEntity:meToFriend
                                                                                  identity:friendIdentity
                                                                           isInitiatedByMe:!isFriendInitiated];
        }
        else {
            // mark it as added to the list to skip
            _outgoingNotificationAdded = YES;
        }
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // empty, _hasDataToShow == NO
    }
    return self;
}

- (BOOL)isEmpty {
    return self.count == 0;
}

- (NSUInteger)count {
    if (self.hasDataToShow == NO) {
        return 0;
    }

    NSUInteger count = self.frc.sections.firstObject.numberOfObjects;
    if (self.incomingNotification) {
        count += 1;
    }
    if (self.outgoingNotification) {
        count += 1;
    }
    return count;
}

- (id<DWDPBasicItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.hasDataToShow == NO) {
        NSAssert(NO, @"Invalid data source usage. Check `count` or `isEmpty` first.");
        return nil;
    }

    if (self.items.count == indexPath.item) {
        NSInteger item = indexPath.item;
        if (self.incomingNotification && self.incomingNotificationAdded) {
            item -= 1;
        }
        if (self.outgoingNotification && self.outgoingNotificationAdded) {
            item -= 1;
        }
        NSAssert(item >= 0, @"Inconsistent data source state: item index is out of bounds");

        const NSUInteger count = self.frc.sections.firstObject.numberOfObjects;
        if (item < count || MOCK_DASHPAY) {
            NSIndexPath *txIndexPath = [NSIndexPath indexPathForItem:item inSection:0];
            DSTxOutputEntity *txOutputEntity = [self.frc objectAtIndexPath:txIndexPath];
            DSTransaction *transaction = [txOutputEntity.transaction transaction];

            if (MOCK_DASHPAY) {
                DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
                NSString *address = @"yeRZBWYfeNE4yVUHV4ZLs83Ppn9aMRH57A"; // Testnet faucet address, used as a mocked address for a contact

                for (DSTransaction *tx in wallet.allTransactions) {
                    if ([tx.outputAddresses containsObject:address]) {
                        transaction = tx;
                        break;
                    }
                }
            }

            NSDate *txDate = [transaction date];

            if (MOCK_DASHPAY && transaction == nil) {
                txDate = [NSDate date];
            }

            DWDPTxObject *txObject = [[DWDPTxObject alloc] initWithTransaction:transaction
                                                                  dataProvider:self.txDataProvider
                                                                      identity:self.friendIdentity];

            if (self.incomingNotificationAdded == NO && [self isNotificationNewerThan:self.incomingNotification txDate:txDate]) {
                [self.items addObject:self.incomingNotification];
                self.incomingNotificationAdded = YES;

                // optimization: since we already have constructed DSTransaction add it to the list
                [self.items addObject:txObject];
            }
            if (self.outgoingNotificationAdded == NO && [self isNotificationNewerThan:self.outgoingNotification txDate:txDate]) {
                [self.items addObject:self.outgoingNotification];
                self.outgoingNotificationAdded = YES;

                // optimization: since we already have constructed DSTransaction add it to the list
                [self.items addObject:txObject];
            }
            else {
                [self.items addObject:txObject];
            }
        }
        else {
            [self appendAnyNotificationToTheItems];
        }
    }

    return self.items[indexPath.item];
}

- (void)appendAnyNotificationToTheItems {
    if (self.incomingNotification && self.outgoingNotification) {
        // incoming.date > outgoing.date
        const BOOL isIncomingNewer = ([self.incomingNotification.date compare:self.outgoingNotification.date] == NSOrderedDescending);
        // list is sorted by the most recent date, add one which is newer
        if (self.incomingNotificationAdded == NO && (isIncomingNewer || self.outgoingNotificationAdded == YES)) {
            [self.items addObject:self.incomingNotification];
            self.incomingNotificationAdded = YES;
        }
        else {
            NSAssert(self.outgoingNotificationAdded == NO, @"Outgoing notification has already been handled");
            [self.items addObject:self.outgoingNotification];
            self.outgoingNotificationAdded = YES;
        }
    }
    else if (self.incomingNotificationAdded == NO) {
        [self.items addObject:self.incomingNotification];
        self.incomingNotificationAdded = YES;
    }
    else if (self.outgoingNotificationAdded == NO) {
        [self.items addObject:self.outgoingNotification];
        self.outgoingNotificationAdded = YES;
    }
    else {
        NSAssert(NO, @"Inconsistent data source state. We should be able to add any of notifications.");
    }
}

- (BOOL)isNotificationNewerThan:(id<DWDPNotificationItem>)notification txDate:(NSDate *)txDate {
    NSParameterAssert(notification);
    NSParameterAssert(txDate);

    if (notification == nil) {
        return NO;
    }

    return ([notification.date compare:txDate] == NSOrderedDescending);
}

@end
