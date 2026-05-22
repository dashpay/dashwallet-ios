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

#import "DWDPUpdateProfileModel.h"

#import "DWEnvironment.h"
#import "dashwallet-Swift.h"

// if MOCK_DASHPAY
#import "DWDashPayConstants.h"
#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPUpdateProfileModel ()

@property (nonatomic, assign) DWDPUpdateProfileModelState state;
@property (readonly, nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPUpdateProfileModel

- (DSBlockchainIdentity *)blockchainIdentity {
    if (MOCK_DASHPAY) {
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;
        
        if (username != nil) {
            return [[DWEnvironment sharedInstance].currentWallet createBlockchainIdentityForUsername:username];
        }
    }
    
    return [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
}

- (void)updateWithDisplayName:(NSString *)rawDisplayName
                      aboutMe:(NSString *)rawAboutMe
              avatarURLString:(nullable NSString *)avatarURLString
                  avatarImage:(nullable UIImage *)avatarImage {
    // Stash the prepared payload for `-retry` (DashSync path) and
    // for the SDK branch below. `displayName` is normalised to empty
    // string when it equals the bare username (legacy DashSync
    // convention: "displayName same as username means no override").
    DSBlockchainIdentity *dashSyncIdentity = self.blockchainIdentity;
    NSString *displayName = rawDisplayName;
    NSString *referenceUsername = dashSyncIdentity.currentDashpayUsername
        ?: DWCurrentUserIdentityInfo.shared.username;
    if (referenceUsername != nil && [rawDisplayName isEqualToString:referenceUsername]) {
        displayName = @"";
    }
    displayName = [displayName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSString *aboutMe = [rawAboutMe stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSString *avatar = avatarURLString;
    if (avatar.length == 0) {
        avatar = nil;
    }

    // Row #17 proper: branch on the wallet's identity provenance.
    // DashSync-side identities keep the legacy state-transition
    // write path. SDK-only identities (no DashSync footprint) go
    // through `DWProfileUpdateBridge` which calls
    // `wallet.updateDashPayProfile` / `createDashPayProfile`.
    if (dashSyncIdentity != nil) {
        [dashSyncIdentity updateDashpayProfileWithDisplayName:displayName
                                                publicMessage:aboutMe
                                              avatarURLString:avatar];
        [self retry];
        return;
    }

    self.state = DWDPUpdateProfileModelState_Loading;
    __weak typeof(self) weakSelf = self;
    [DWProfileUpdateBridge.shared
        updateProfileWithDisplayName:displayName
                       publicMessage:aboutMe
                           avatarURL:avatar
                         avatarImage:avatarImage
                          completion:^(NSError *_Nullable error) {
                              __strong typeof(weakSelf) strongSelf = weakSelf;
                              if (!strongSelf) {
                                  return;
                              }
                              strongSelf.state = (error == nil)
                                  ? DWDPUpdateProfileModelState_Ready
                                  : DWDPUpdateProfileModelState_Error;
                          }];
}

- (void)retry {
    self.state = DWDPUpdateProfileModelState_Loading;

    __weak typeof(self) weakSelf = self;
    [self.blockchainIdentity signAndPublishProfileWithCompletion:^(BOOL success, BOOL cancelled, NSError *_Nonnull error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.state = success ? DWDPUpdateProfileModelState_Ready : DWDPUpdateProfileModelState_Error;
    }];
}

- (void)reset {
    self.state = DWDPUpdateProfileModelState_Ready;
}

@end
