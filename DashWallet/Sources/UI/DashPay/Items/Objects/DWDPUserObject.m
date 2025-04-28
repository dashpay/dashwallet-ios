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

#import "DWDPUserObject.h"

#import <DashSync/DashSync.h>

#import "DWEnvironment.h"
#import "UIFont+DWDPItem.h"

@implementation DWDPUserObject

@synthesize identity = _identity;
@synthesize username = _username;
@synthesize displayName = _displayName;

- (instancetype)initWithIdentity:(DSIdentity *)identity {
    self = [super init];
    if (self) {
        _identity = identity;
        _username = identity.currentDashpayUsername;
    }
    return self;
}

- (instancetype)initWithFriendRequestEntity:(DSFriendRequestEntity *)friendRequestEntity
                                   identity:(DSIdentity *)identity {
    self = [super init];
    if (self) {
        _identity = identity;
        _friendRequestEntity = friendRequestEntity;
    }
    return self;
}

- (NSString *)displayName {
    if (_displayName == nil) {
        BOOL hasDisplayName = _identity.displayName.length > 0;
        _displayName = hasDisplayName ? _identity.displayName : nil;
    }

    return _displayName;
}

- (NSString *)username {
    if (_username == nil) {
        // outgoing request, use destination
        DSDashpayUserEntity *contact = self.friendRequestEntity.destinationContact;
        _username = [contact.username copy];
    }
    return _username;
}

- (NSAttributedString *)title {
    NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName : [UIFont dw_itemTitleFont]};
    return [[NSAttributedString alloc] initWithString:(self.displayName ?: self.username) ?: @"<Fetching Contact>" attributes:attributes];
}

- (NSString *)subtitle {
    return self.displayName ? self.username : nil;
}

- (DSFriendRequestEntity *)friendRequestToPay {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSIdentity *myIdentity = wallet.defaultIdentity;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:
                                              @"destinationContact.associatedBlockchainIdentity.uniqueID == %@",
                                              uint256_data(myIdentity.uniqueID)];
    DSFriendRequestEntity *friendRequest = [[self.identity.matchingDashpayUserInViewContext.outgoingRequests filteredSetUsingPredicate:predicate] anyObject];
    return friendRequest;
}

@end
