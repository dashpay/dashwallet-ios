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
#import "DWShortcutsModel.h"
#import "DWSyncModel.h"

#import <DashSync/DSBiometricsAuthenticator.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWRootModel ()

@property (nonatomic, strong) id<DWHomeProtocol> homeModel;
@property (nullable, nonatomic, strong) NSDate *lastActiveDate;

@end

@implementation DWRootModel

@synthesize currentNetworkDidChangeBlock;

- (instancetype)init {
    self = [super init];
    if (self) {
        _homeModel = [[DWHomeModel alloc] init];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(currentNetworkDidChangeNotification:)
                                                     name:DWCurrentNetworkDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (BOOL)hasAWallet {
    DSVersionManager *dashSyncVersionManager = [DSVersionManager sharedInstance];
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;

    return (chain.hasAWallet || ![dashSyncVersionManager noOldWallet]);
}

- (BOOL)walletOperationAllowed {
    return DSBiometricsAuthenticator.passcodeEnabled;
}

- (void)applicationDidEnterBackground {
    self.lastActiveDate = [NSDate date];
}

- (BOOL)shouldShowLockScreen {
    if (!self.hasAWallet) {
        return NO;
    }

    DWGlobalOptions *globalOptions = [DWGlobalOptions sharedInstance];
    if ([globalOptions lockScreenDisabled]) {
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

    return (interval > globalOptions.autoLockAppInterval);
}

- (void)setupDidFinish {
    [self.homeModel.shortcutsModel reloadShortcuts];
}

#pragma mark - Notifications

- (void)currentNetworkDidChangeNotification:(NSNotification *)notification {
    DWHomeModel *homeModel = [[DWHomeModel alloc] init];
    self.homeModel = homeModel;

    NSParameterAssert(self.currentNetworkDidChangeBlock);
    if (self.currentNetworkDidChangeBlock) {
        self.currentNetworkDidChangeBlock();
    }

    [homeModel forceStartSyncingActivity];
}

@end

NS_ASSUME_NONNULL_END
