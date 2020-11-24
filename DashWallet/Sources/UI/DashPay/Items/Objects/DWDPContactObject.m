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

#import "DWDPContactObject.h"

#import <DashSync/DashSync.h>

#import "DWEnvironment.h"
#import "UIFont+DWDPItem.h"

@implementation DWDPContactObject

@synthesize displayName = _displayName;

- (instancetype)initWithDashpayUserEntity:(DSDashpayUserEntity *)userEntity {
    self = [super init];
    if (self) {
        _userEntity = userEntity;
        _blockchainIdentity = [userEntity.associatedBlockchainIdentity blockchainIdentity];
    }
    return self;
}

- (NSString *)username {
    if (_username == nil) {
        _username = [self.userEntity.username copy];
    }
    return _username;
}

- (NSString *)displayName {
    if (_displayName == nil) {
        _displayName = [self.userEntity.displayName copy];
    }
    return _displayName;
}

- (NSAttributedString *)title {
    NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName : [UIFont dw_itemTitleFont]};
    return [[NSAttributedString alloc] initWithString:(self.displayName ?: self.username) ?: @"<unknown>" attributes:attributes];
}

- (NSString *)subtitle {
    return self.displayName ? self.username : nil;
}

- (DSFriendRequestEntity *)friendRequestToPay {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:
                                              @"destinationContact.associatedBlockchainIdentity.uniqueID == %@",
                                              myBlockchainIdentity.uniqueIDData];
    DSFriendRequestEntity *friendRequest = [[self.userEntity.outgoingRequests filteredSetUsingPredicate:predicate] anyObject];
    return friendRequest;
}

@end
