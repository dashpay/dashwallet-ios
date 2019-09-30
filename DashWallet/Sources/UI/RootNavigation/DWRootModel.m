//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWRootModel.h"

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWHomeModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWRootModel ()

@property (nullable, nonatomic, strong) NSDate *lastActiveDate;

@end

@implementation DWRootModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _homeModel = [[DWHomeModel alloc] init];
    }
    return self;
}

- (BOOL)hasAWallet {
    DSVersionManager *dashSyncVersionManager = [DSVersionManager sharedInstance];
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;

    return (chain.hasAWallet || ![dashSyncVersionManager noOldWallet]);
}

- (BOOL)walletOperationAllowed {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    return authenticationManager.passcodeEnabled;
}

- (void)applicationDidEnterBackground {
    self.lastActiveDate = [NSDate date];
}

- (BOOL)shouldShowLockScreen {
    if (!self.hasAWallet) {
        return NO;
    }

    DSAuthenticationManager *authManager = [DSAuthenticationManager sharedInstance];
    const BOOL didAuthenticate = authManager.didAuthenticate;
    if (didAuthenticate) {
        return NO;
    }

    if (!self.lastActiveDate) {
        return (didAuthenticate == NO);
    }

    NSDate *now = [NSDate date];
    const NSTimeInterval interval = [now timeIntervalSince1970] - [self.lastActiveDate timeIntervalSince1970];

    return (interval > [DWGlobalOptions sharedInstance].autoLockAppInterval);
}

@end

NS_ASSUME_NONNULL_END
