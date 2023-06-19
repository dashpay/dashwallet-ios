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

NS_ASSUME_NONNULL_BEGIN

@interface DWDPUpdateProfileModel ()

@property (nonatomic, assign) DWDPUpdateProfileModelState state;
@property (readonly, nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPUpdateProfileModel

- (DSBlockchainIdentity *)blockchainIdentity {
    return [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
}

- (void)updateWithDisplayName:(NSString *)rawDisplayName
                      aboutMe:(NSString *)rawAboutMe
              avatarURLString:(nullable NSString *)avatarURLString {
    NSString *displayName = rawDisplayName;
    if ([rawDisplayName isEqualToString:self.blockchainIdentity.currentDashpayUsername]) {
        displayName = @"";
    }
    displayName = [displayName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSString *aboutMe = [rawAboutMe stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSString *avatar = avatarURLString;
    if (avatar.length == 0) {
        avatar = nil;
    }

    [self.blockchainIdentity updateDashpayProfileWithDisplayName:displayName
                                                   publicMessage:aboutMe
                                                 avatarURLString:avatar];

    [self retry];
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
