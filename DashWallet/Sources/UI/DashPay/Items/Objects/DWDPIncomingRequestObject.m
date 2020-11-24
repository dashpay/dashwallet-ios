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

@synthesize blockchainIdentity = _blockchainIdentity;
@synthesize username = _username;

- (instancetype)initWithFriendRequestEntity:(DSFriendRequestEntity *)friendRequestEntity
                         blockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self = [super init];
    if (self) {
        _blockchainIdentity = blockchainIdentity;
        _friendRequestEntity = friendRequestEntity;
    }
    return self;
}

- (instancetype)initWithBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self = [super init];
    if (self) {
        _blockchainIdentity = blockchainIdentity;
        _username = blockchainIdentity.currentDashpayUsername;
    }
    return self;
}

- (NSString *)username {
    if (_username == nil) {
        // incoming request, use source
        DSDashpayUserEntity *contact = self.friendRequestEntity.sourceContact;
        _username = [contact.username copy];
    }
    return _username;
}

- (NSString *)displayName {
    return nil;
}

- (NSAttributedString *)title {
    NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName : [UIFont dw_itemTitleFont]};
    return [[NSAttributedString alloc] initWithString:(self.displayName ?: self.username) ?: @"<unknown>" attributes:attributes];
}

- (NSString *)subtitle {
    return self.displayName ? self.username : nil;
}

- (DSFriendRequestEntity *)friendRequestToPay {
    return self.friendRequestEntity;
}

@end
