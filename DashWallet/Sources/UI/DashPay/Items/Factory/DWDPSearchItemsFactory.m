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

#import "DWDPSearchItemsFactory.h"

#import "DWEnvironment.h"

#import "DWDPEstablishedContactObject.h"
#import "DWDPNewIncomingRequestObject.h"
#import "DWDPPendingRequestObject.h"
#import "DWDPUserObject.h"

#if __has_include("dashpay-Swift.h")
#import "dashpay-Swift.h"
#elif __has_include("dashwallet-Swift.h")
#import "dashwallet-Swift.h"
#endif

@implementation DWDPSearchItemsFactory

- (id<DWDPBasicUserItem, DWDPBlockchainIdentityBackedItem>)itemForBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    DSBlockchainIdentityFriendshipStatus friendshipStatus = [myBlockchainIdentity friendshipStatusForRelationshipWithBlockchainIdentity:blockchainIdentity];

    switch (friendshipStatus) {
        case DSBlockchainIdentityFriendshipStatus_Unknown:
        case DSBlockchainIdentityFriendshipStatus_None:
            return [[DWDPUserObject alloc] initWithBlockchainIdentity:blockchainIdentity];
        case DSBlockchainIdentityFriendshipStatus_Outgoing:
            return [[DWDPPendingRequestObject alloc] initWithBlockchainIdentity:blockchainIdentity];
        case DSBlockchainIdentityFriendshipStatus_Incoming:
            return [[DWDPNewIncomingRequestObject alloc] initWithBlockchainIdentity:blockchainIdentity];
        case DSBlockchainIdentityFriendshipStatus_Friends:
            return [[DWDPEstablishedContactObject alloc] initWithBlockchainIdentity:blockchainIdentity];
    }
}

- (id<DWDPBasicUserItem, DWDPBlockchainIdentityBackedItem>)itemForPlatformUser:(DWPlatformUser *)platformUser {
    // Use PlatformService to determine friendship status
    PlatformService *platform = [DWEnvironment sharedInstance].platformService;
    DWPlatformFriendshipStatus status = [platform friendshipStatusWith:platformUser.identityId];

    // Create a local DSBlockchainIdentity for UI compatibility
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *identity = [wallet createBlockchainIdentityForUsername:platformUser.username];

    switch (status) {
        case DWPlatformFriendshipStatusNone:
            return [[DWDPUserObject alloc] initWithBlockchainIdentity:identity];
        case DWPlatformFriendshipStatusOutgoing:
            return [[DWDPPendingRequestObject alloc] initWithBlockchainIdentity:identity];
        case DWPlatformFriendshipStatusIncoming:
            return [[DWDPNewIncomingRequestObject alloc] initWithBlockchainIdentity:identity];
        case DWPlatformFriendshipStatusFriends:
            return [[DWDPEstablishedContactObject alloc] initWithBlockchainIdentity:identity];
    }
}

@end
