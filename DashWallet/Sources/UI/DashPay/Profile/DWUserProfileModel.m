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

#import "DWUserProfileModel.h"

#import "DWEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileModel ()

@property (nonatomic, assign) DWUserProfileModelState state;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileModel

- (instancetype)initWithBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self = [super init];
    if (self) {
        _blockchainIdentity = blockchainIdentity;
    }
    return self;
}

- (void)setState:(DWUserProfileModelState)state {
    _state = state;

    [self.delegate userProfileModelDidUpdateState:self];
}

- (NSString *)username {
    return self.blockchainIdentity.currentUsername;
}

- (void)update {
    self.state = DWUserProfileModelState_Loading;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *mineBlockchainIdentity = wallet.defaultBlockchainIdentity;
    __weak typeof(self) weakSelf = self;
    [mineBlockchainIdentity fetchContactRequests:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.state = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;
    }];
}

- (DSBlockchainIdentityFriendshipStatus)friendshipStatus {
    if (self.state != DWUserProfileModelState_Done) {
        return DSBlockchainIdentityFriendshipStatus_Unknown;
    }

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *mineBlockchainIdentity = wallet.defaultBlockchainIdentity;
    return [mineBlockchainIdentity friendshipStatusForRelationshipWithBlockchainIdentity:self.blockchainIdentity];
}

- (void)sendContactRequest {
    self.state = DWUserProfileModelState_Loading;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *mineBlockchainIdentity = wallet.defaultBlockchainIdentity;
    DSPotentialContact *potentialContact = [[DSPotentialContact alloc] initWithUsername:self.username];
    __weak typeof(self) weakSelf = self;
    [mineBlockchainIdentity sendNewFriendRequestToPotentialContact:potentialContact
                                                        completion:
                                                            ^(BOOL success, NSArray<NSError *> *_Nullable errors) {
                                                                __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                if (!strongSelf) {
                                                                    return;
                                                                }

                                                                strongSelf.state = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;
                                                            }];
}

- (void)acceptContactRequest {
    self.state = DWUserProfileModelState_Loading;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *mineBlockchainIdentity = wallet.defaultBlockchainIdentity;
    __weak typeof(self) weakSelf = self;
    [mineBlockchainIdentity acceptFriendRequestFromBlockchainIdentity:self.blockchainIdentity
                                                           completion:^(BOOL success, NSArray<NSError *> *errors) {
                                                               __strong typeof(weakSelf) strongSelf = weakSelf;
                                                               if (!strongSelf) {
                                                                   return;
                                                               }

                                                               strongSelf.state = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;
                                                           }];
}

@end
