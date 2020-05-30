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

#import "DWDPContactRequestActions.h"

#import "DWDPBlockchainIdentityBackedItem.h"
#import "DWDPFriendRequestBackedItem.h"
#import "DWEnvironment.h"

@implementation DWDPContactRequestActions

+ (void)acceptContactRequest:(id<DWDPBasicItem>)item
                  completion:(void (^)(BOOL success, NSArray<NSError *> *errors))completion {
    const BOOL isBlockchainIdentityBacked = [item conformsToProtocol:@protocol(DWDPBlockchainIdentityBackedItem)];
    const BOOL isFriendRequestBacked = [item conformsToProtocol:@protocol(DWDPFriendRequestBackedItem)];
    NSAssert(isBlockchainIdentityBacked || isFriendRequestBacked, @"Invalid item to accept contact request");

    if (isBlockchainIdentityBacked) {
        id<DWDPBlockchainIdentityBackedItem> backedItem = (id<DWDPBlockchainIdentityBackedItem>)item;
        [self acceptContactRequestFromBlockchainIdentity:backedItem.blockchainIdentity completion:completion];
    }
    else if (isFriendRequestBacked) {
        id<DWDPFriendRequestBackedItem> backedItem = (id<DWDPFriendRequestBackedItem>)item;
        [self acceptContactRequestFromFriendRequest:backedItem.friendRequestEntity completion:completion];
    }
}

#pragma mark - Private

+ (void)acceptContactRequestFromBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity
                                        completion:(void (^)(BOOL success, NSArray<NSError *> *errors))completion {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *mineBlockchainIdentity = wallet.defaultBlockchainIdentity;
    [mineBlockchainIdentity acceptFriendRequestFromBlockchainIdentity:blockchainIdentity completion:completion];
}

+ (void)acceptContactRequestFromFriendRequest:(DSFriendRequestEntity *)friendRequest
                                   completion:(void (^)(BOOL success, NSArray<NSError *> *errors))completion {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *mineBlockchainIdentity = wallet.defaultBlockchainIdentity;
    [mineBlockchainIdentity acceptFriendRequest:friendRequest completion:completion];
}

@end
