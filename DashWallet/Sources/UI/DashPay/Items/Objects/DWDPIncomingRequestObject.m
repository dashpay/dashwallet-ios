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

#import "DWDPIncomingRequestObject.h"

#import <DashSync/DashSync.h>

#import "UIFont+DWDPItem.h"

@implementation DWDPIncomingRequestObject

@synthesize username = _username;

- (instancetype)initWithFriendRequestEntity:(DSFriendRequestEntity *)friendRequestEntity {
    self = [super init];
    if (self) {
        _friendRequestEntity = friendRequestEntity;
    }
    return self;
}

- (instancetype)initWithBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self = [super init];
    if (self) {
        _blockchainIdentity = blockchainIdentity;
        _username = blockchainIdentity.currentUsername;
    }
    return self;
}

- (NSString *)username {
    if (_username == nil) {
        // When initialized with DSBlockchainIdentity _username set upon init
        NSAssert(self.blockchainIdentity == nil, @"Inconsistent state");

        DSBlockchainIdentityEntity *blockchainIdentity = self.friendRequestEntity.sourceContact.associatedBlockchainIdentity;
        DSBlockchainIdentityUsernameEntity *username = blockchainIdentity.usernames.anyObject;
        _username = [username.stringValue copy];
    }
    return _username;
}

- (NSString *)displayName {
    return nil;
}

- (NSAttributedString *)title {
    NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName : [UIFont dw_itemTitleFont]};
    return [[NSAttributedString alloc] initWithString:self.displayName ?: self.username attributes:attributes];
}

- (NSString *)subtitle {
    return self.displayName ? self.username : nil;
}

@end
