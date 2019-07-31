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

#import "DWSyncModel.h"

#import <DashSync/DSNetworkActivityIndicatorManager.h>
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const SYNC_LOOP_INTERVAL = 0.2;
static NSUInteger const MAX_REACHABILITY_CHECKS_FAILURES = 3;
static double const SYNCING_COMPLETED_PROGRESS = 0.995;

@interface DWSyncModel ()

@property (readonly, nonatomic, strong) DSReachabilityManager *reachability;

@property (nonatomic, assign) DWSyncModelState state;
@property (nonatomic, assign) float progress;

@property (nonatomic, assign, getter=isSyncing) BOOL syncing;
@property (nonatomic, assign) NSUInteger numberOfFailedReachabilityChecks;

@end

@implementation DWSyncModel

- (instancetype)initWithReachability:(DSReachabilityManager *)reachability {
    self = [super init];
    if (self) {
        _reachability = reachability;

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(transactionManagerSyncStartedNotification)
                                   name:DSTransactionManagerSyncStartedNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(transactionManagerSyncFinishedNotification)
                                   name:DSTransactionManagerSyncFinishedNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(transactionManagerSyncFailedNotification)
                                   name:DSTransactionManagerSyncFailedNotification
                                 object:nil];

        if ([DWEnvironment sharedInstance].currentChainManager.peerManager.connected) {
            [self startSyncingActivity];
        }
    }
    return self;
}

#pragma mark Notifications

- (void)transactionManagerSyncStartedNotification {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [self startSyncingActivity];
}

- (void)transactionManagerSyncFinishedNotification {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    if (![self shouldStopSyncing]) {
        return;
    }

    [self stopSyncingActivityFailed:NO];

    // TODO
    // self.balance = [DWEnvironment sharedInstance].currentWallet.balance;
    // [self.receiveViewController updateAddress];
}

- (void)transactionManagerSyncFailedNotification {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    [self stopSyncingActivityFailed:YES];

    // TODO
    // [self.receiveViewController updateAddress];
}

#pragma mark Private

- (void)setSyncing:(BOOL)syncing {
    if (_syncing == syncing) {
        return;
    }

    _syncing = syncing;

    [UIApplication sharedApplication].idleTimerDisabled = syncing;

    if (syncing) {
        [DSNetworkActivityIndicatorManager increaseActivityCounter];
    }
    else {
        [DSNetworkActivityIndicatorManager decreaseActivityCounter];
    }
}

- (void)startSyncingActivity {
    if (self.syncing) {
        return;
    }

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncLoop) object:nil];
    self.numberOfFailedReachabilityChecks = 0;
    [self syncLoop];
}

- (void)stopSyncingActivityFailed:(BOOL)failed {
    if (!self.syncing) {
        return;
    }

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncLoop) object:nil];

    self.syncing = NO;

    if (failed) {
        self.state = DWSyncModelState_SyncFailed;
    }
    else {
        self.state = DWSyncModelState_SyncDone;
    }
}

- (void)syncLoop {
    if (self.reachability.networkReachabilityStatus == DSReachabilityStatusNotReachable) {
        if (self.numberOfFailedReachabilityChecks == MAX_REACHABILITY_CHECKS_FAILURES) {
            self.state = DWSyncModelState_NoConnection;

            return;
        }
        else {
            self.numberOfFailedReachabilityChecks += 1;
        }
    }
    else {
        self.numberOfFailedReachabilityChecks = 0;
    }

    const double progress = [self chainSyncProgress];
    if (progress < SYNCING_COMPLETED_PROGRESS) {
        self.syncing = YES;

        self.state = DWSyncModelState_Syncing;
        self.progress = progress;

        [self performSelector:@selector(syncLoop) withObject:nil afterDelay:SYNC_LOOP_INTERVAL];
    }
    else {
        self.state = DWSyncModelState_SyncDone;
        self.progress = 1.0;

        [self stopSyncingActivityFailed:NO];
    }
}

- (BOOL)shouldStopSyncing {
    const double progress = [self chainSyncProgress];

    if (progress > DBL_EPSILON && progress + DBL_EPSILON < 1.0) {
        return NO;
    }
    else {
        return YES;
    }
}

- (double)chainSyncProgress {
    const double progress = [DWEnvironment sharedInstance].currentChainManager.syncProgress;

    return progress;
}

@end

NS_ASSUME_NONNULL_END
