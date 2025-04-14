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
        _identity = [userEntity.associatedBlockchainIdentity identity];
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
        NSString *userName = [self.userEntity.displayName copy];
        _displayName = [userName isEqualToString:@""] ? nil : userName;
    }
    return _displayName;
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
                                              myIdentity.uniqueIDData];
    DSFriendRequestEntity *friendRequest = [[self.userEntity.outgoingRequests filteredSetUsingPredicate:predicate] anyObject];
    return friendRequest;
}

@end
