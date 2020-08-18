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

#import "DWFrequentContactsDataSource.h"

#import "DWEnvironment.h"

#import "DWDPContactObject.h"

@interface DWFrequentContactsDataSource ()

@property (nonatomic, copy) NSArray<id<DWDPBasicUserItem>> *items;

@end

@implementation DWFrequentContactsDataSource

- (void)updateItems {
    NSMutableArray *items = [NSMutableArray array];

    DSBlockchainIdentity *blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    DSDashpayUserEntity *dashpayUser = blockchainIdentity.matchingDashpayUserInViewContext;

    NSUInteger count = 4;
    NSArray<DSDashpayUserEntity *> *activeSent =
        [dashpayUser mostActiveFriends:DSDashpayUserEntityFriendActivityType_OutgoingTransactions
                                 count:count
                             ascending:NO];
    NSArray<DSDashpayUserEntity *> *activeReceived =
        [dashpayUser mostActiveFriends:DSDashpayUserEntityFriendActivityType_IncomingTransactions
                                 count:count
                             ascending:NO];

    NSUInteger sent = 0;
    NSUInteger received = 0;
    NSMutableSet<NSManagedObjectID *> *used = [NSMutableSet set];
    while (items.count < count && (sent < activeSent.count || received < activeReceived.count)) {
        DSDashpayUserEntity *user = nil;
        if (sent < activeSent.count) {
            user = activeSent[sent];
            sent++;
        }
        else if (received < activeReceived.count) {
            user = activeReceived[received];
            received++;
        }

        if (user && ![used containsObject:user.objectID]) {
            DWDPContactObject *item = [[DWDPContactObject alloc] initWithDashpayUserEntity:user];
            // this user can be a "pending request" and we can't pay to them
            BOOL canPayToUser = [item friendRequestToPay] != nil;
            if (canPayToUser) {
                [items addObject:item];
                [used addObject:user.objectID];
            }
        }
    }

    self.items = items;
}

@end
