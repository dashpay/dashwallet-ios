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

#import "DWEnvironment.h"
#import "DWSyncModel.h"
#import "DWTransactionListDataSource.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeModel ()

@property (strong, nonatomic) DSReachabilityManager *reachability;

@end

@implementation DWHomeModel

- (instancetype)init {
    self = [super init];
    if (self) {
        // START_SYNC_ENTRY_POINT
        [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];

        _reachability = [DSReachabilityManager sharedManager];
        if (!_reachability.monitoring) {
            [_reachability startMonitoring];
        }

        _syncModel = [[DWSyncModel alloc] initWithReachability:_reachability];

        _allDataSource = [[DWTransactionListDataSource alloc] init];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reachabilityDidChangeNotification)
                                                     name:DSReachabilityDidChangeNotification
                                                   object:nil];
    }
    return self;
}

#pragma mark - Notifications

- (void)reachabilityDidChangeNotification {
    if ([DWEnvironment sharedInstance].currentChain.hasAWallet &&
        self.reachability.networkReachabilityStatus != DSReachabilityStatusNotReachable &&
        [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {

        // START_SYNC_ENTRY_POINT
        [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
    }
}

@end

NS_ASSUME_NONNULL_END
