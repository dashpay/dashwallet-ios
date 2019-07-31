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

#import "DWHomeModel.h"

#import <mach-o/dyld.h>
#import <sys/stat.h>

#import <DashSync/DashSync.h>

#import "DWEnvironment.h"
#import "DWSyncModel.h"
#import "DWTransactionListDataSource.h"

NS_ASSUME_NONNULL_BEGIN

static BOOL IsJailbroken(void) {
    struct stat s;
    BOOL jailbroken = (stat("/bin/sh", &s) == 0) ? YES : NO; // if we can see /bin/sh, the app isn't sandboxed

    // some anti-jailbreak detection tools re-sandbox apps, so do a secondary check for any MobileSubstrate dyld images
    for (uint32_t count = _dyld_image_count(), i = 0; i < count && !jailbroken; i++) {
        if (strstr(_dyld_get_image_name(i), "MobileSubstrate"))
            jailbroken = YES;
    }

#if TARGET_IPHONE_SIMULATOR
    jailbroken = NO;
#endif

    return jailbroken;
}

@interface DWHomeModel ()

@property (strong, nonatomic) DSReachabilityManager *reachability;

@end

@implementation DWHomeModel

- (instancetype)init {
    self = [super init];
    if (self) {
        [self connectIfNeeded];

        _reachability = [DSReachabilityManager sharedManager];
        if (!_reachability.monitoring) {
            [_reachability startMonitoring];
        }

        _syncModel = [[DWSyncModel alloc] initWithReachability:_reachability];

        _allDataSource = [[DWTransactionListDataSource alloc] init];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(reachabilityDidChangeNotification)
                                   name:DSReachabilityDidChangeNotification
                                 object:nil];

        [notificationCenter addObserver:self
                               selector:@selector(applicationWillEnterForegroundNotification)
                                   name:UIApplicationWillEnterForegroundNotification
                                 object:nil];
    }
    return self;
}

- (BOOL)isJailbroken {
    return IsJailbroken();
}

- (BOOL)isWalletEmpty {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    const BOOL hasFunds = (wallet.totalReceived + wallet.totalSent > 0);

    return !hasFunds;
}

#pragma mark - Notifications

- (void)reachabilityDidChangeNotification {
    if (self.reachability.networkReachabilityStatus != DSReachabilityStatusNotReachable &&
        [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {

        [self connectIfNeeded];
    }
}

- (void)applicationWillEnterForegroundNotification {
    [self connectIfNeeded];
}

#pragma mark - Private

- (void)connectIfNeeded {
    // This method might be called from init. Don't use any instance variables

    if ([DWEnvironment sharedInstance].currentChain.hasAWallet) {
        // START_SYNC_ENTRY_POINT
        [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
    }
}

@end

NS_ASSUME_NONNULL_END
