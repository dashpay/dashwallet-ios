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

@synthesize identity = _identity;
@synthesize username = _username;

- (instancetype)initWithFriendRequestEntity:(DSFriendRequestEntity *)friendRequestEntity
                                   identity:(DSIdentity *)identity {
    self = [super init];
    if (self) {
        _identity = identity;
        _friendRequestEntity = friendRequestEntity;
    }
    return self;
}

- (instancetype)initWithIdentity:(DSIdentity *)identity {
    self = [super init];
    if (self) {
        _identity = identity;
        _username = identity.currentDashpayUsername;
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
    if (_username == nil) {
        BOOL hasDisplayName = _identity.displayName.length > 0;
        _username = hasDisplayName ? [_identity.displayName copy] : nil;
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
    return self.friendRequestEntity;
}

@end
