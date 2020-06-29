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

#import "DWDashPayContactsActions.h"
#import "DWDashPayContactsUpdater.h"
#import "DWEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileModel ()

@property (nonatomic, assign) DWUserProfileModelState state;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileModel

- (instancetype)initWithItem:(id<DWDPBasicItem>)item {
    self = [super init];
    if (self) {
        _item = item;
    }
    return self;
}

- (void)skipUpdating {
    self.state = DWUserProfileModelState_Done;
}

- (void)setState:(DWUserProfileModelState)state {
    _state = state;

    [self.delegate userProfileModelDidUpdateState:self];
}

- (NSString *)username {
    return self.item.username;
}

- (void)update {
    self.state = DWUserProfileModelState_Loading;

    __weak typeof(self) weakSelf = self;
    [[DWDashPayContactsUpdater sharedInstance] fetchWithCompletion:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.state = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;
    }];
}

- (DSBlockchainIdentityFriendshipStatus)friendshipStatus {
    if (self.state == DWUserProfileModelState_None || self.state == DWUserProfileModelState_Loading) {
        return DSBlockchainIdentityFriendshipStatus_Unknown;
    }

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    DSBlockchainIdentity *blockchainIdentity = self.item.blockchainIdentity;
    return [myBlockchainIdentity friendshipStatusForRelationshipWithBlockchainIdentity:blockchainIdentity];
}

- (void)sendContactRequest {
    self.state = DWUserProfileModelState_Loading;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    DSPotentialContact *potentialContact = [[DSPotentialContact alloc] initWithUsername:self.username];
    __weak typeof(self) weakSelf = self;
    [myBlockchainIdentity sendNewFriendRequestToPotentialContact:potentialContact
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

    __weak typeof(self) weakSelf = self;
    [DWDashPayContactsActions acceptContactRequest:self.item
                                        completion:^(BOOL success, NSArray<NSError *> *_Nonnull errors) {
                                            __strong typeof(weakSelf) strongSelf = weakSelf;
                                            if (!strongSelf) {
                                                return;
                                            }

                                            strongSelf.state = success ? DWUserProfileModelState_Done : DWUserProfileModelState_Error;
                                        }];
}

@end
