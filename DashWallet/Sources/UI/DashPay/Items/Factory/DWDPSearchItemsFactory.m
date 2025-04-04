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

@implementation DWDPSearchItemsFactory

- (id<DWDPBasicUserItem, DWDPIdentityBackedItem>)itemForIdentity:(DSIdentity *)identity {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSIdentity *myIdentity = wallet.defaultIdentity;
    DSIdentityFriendshipStatus friendshipStatus = [myIdentity friendshipStatusForRelationshipWithIdentity:identity];

    switch (friendshipStatus) {
        case DSIdentityFriendshipStatus_Unknown:
        case DSIdentityFriendshipStatus_None:
            return [[DWDPUserObject alloc] initWithIdentity:identity];
        case DSIdentityFriendshipStatus_Outgoing:
            return [[DWDPPendingRequestObject alloc] initWithIdentity:identity];
        case DSIdentityFriendshipStatus_Incoming:
            return [[DWDPNewIncomingRequestObject alloc] initWithIdentity:identity];
        case DSIdentityFriendshipStatus_Friends:
            return [[DWDPEstablishedContactObject alloc] initWithIdentity:identity];
    }
}

@end
