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

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileDataSourceObject ()

@property (nullable, readonly, nonatomic, strong) NSFetchedResultsController *frc;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> txDataProvider;
@property (readonly, nonatomic, strong) DSBlockchainIdentity *friendBlockchainIdentity;

@property (readonly, nonatomic, strong) NSMutableArray<id<DWDPBasicItem>> *items;
@property (nullable, readonly, nonatomic, strong) DWDPAcceptedRequestNotificationObject *incomingNotification;
@property (nullable, readonly, nonatomic, strong) DWDPOutgoingRequestNotificationObject *outgoingNotification;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileDataSourceObject

- (instancetype)initWithTxFRC:(NSFetchedResultsController *)frc
               txDataProvider:(id<DWTransactionListDataProviderProtocol>)txDataProvider
            friendToMeRequest:(nullable DSFriendRequestEntity *)friendToMe
            meToFriendRequest:(nullable DSFriendRequestEntity *)meToFriend
     friendBlockchainIdentity:(DSBlockchainIdentity *)friendBlockchainIdentity
         myBlockchainIdentity:(DSBlockchainIdentity *)myBlockchainIdentity {
    self = [super init];
    if (self) {
        _frc = frc;
        _txDataProvider = txDataProvider;
        _friendBlockchainIdentity = friendBlockchainIdentity;
        _items = [NSMutableArray array];

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
                                                                        blockchainIdentity:friendBlockchainIdentity
                                                                         isInitiatedByThem:isFriendInitiated];
        }

        if (meToFriend) {
            _outgoingNotification =
                [[DWDPOutgoingRequestNotificationObject alloc] initWithFriendRequestEntity:meToFriend
                                                                        blockchainIdentity:myBlockchainIdentity
                                                                           isInitiatedByMe:!isFriendInitiated];
        }
    }
    return self;
}

- (BOOL)isEmpty {
    return self.count == 0;
}

- (NSUInteger)count {
    if (self.frc == nil) {
        return 0;
    }

    NSUInteger count = self.frc.sections.firstObject.numberOfObjects;
    //    if (self.incomingNotification) {
    //        count += 1;
    //    }
    //    if (self.outgoingNotification) {
    //        count += 1;
    //    }
    return count;
}

- (id<DWDPBasicItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.frc == nil) {
        return nil;
    }

    if (self.items.count == indexPath.item) {
        DSTxOutputEntity *txOutputEntity = [self.frc objectAtIndexPath:indexPath];
        DSTransaction *transaction = [txOutputEntity.transaction transaction];
        DWDPTxObject *txObject = [[DWDPTxObject alloc] initWithTransaction:transaction
                                                              dataProvider:self.txDataProvider
                                                                  username:self.friendBlockchainIdentity.currentUsername];
        [self.items addObject:txObject];
    }

    return self.items[indexPath.item];
}

@end
