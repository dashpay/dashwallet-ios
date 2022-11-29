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

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

#define LOG_SYNCING 0

#if LOG_SYNCING
#define DWSyncLog(frmt, ...) DSLog(frmt, ##__VA_ARGS__)
#else
#define DWSyncLog(frmt, ...)
#endif /* LOG_SYNCING */

__unused static NSString *SyncStateToString(DWSyncModelState state) {
    switch (state) {
        case DWSyncModelState_Syncing:
            return @"Syncing";
        case DWSyncModelState_SyncDone:
            return @"Done";
        case DWSyncModelState_SyncFailed:
            return @"Failed";
        case DWSyncModelState_NoConnection:
            return @"NoConnection";
    }
}

NSString *const DWSyncStateChangedNotification = @"DWSyncStateChangedNotification";
NSString *const DWSyncStateChangedFromStateKey = @"DWSyncStateChangedFromStateKey";

static NSTimeInterval const SYNC_LOOP_INTERVAL = 0.2;

// Wait for 2.5 seconds to update progress to the new peak value.
// Peak is considered to be a difference between progress values more than 10%.
static NSTimeInterval const PROGRESS_PEAK_DELAY = 3.25; // 3.25 sec
static float const MAX_PROGRESS_DELTA = 0.1;            // 10%

@interface DWSyncModel () <SyncingActivityMonitorObserver>

@property (nonatomic, strong) SyncingActivityMonitor *syncMonitor;

@property (nonatomic, assign) DWSyncModelState state;
@property (nonatomic, assign) float progress;

@end

@implementation DWSyncModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _syncMonitor = SyncingActivityMonitor.shared;
        [_syncMonitor addObserver:self];
    }
    return self;
}

- (void)dealloc {
    [_syncMonitor removeObserver:self];

    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)forceStartSyncingActivity {
    DWSyncLog(@"[DW Sync] forceStartSyncingActivity");

    [_syncMonitor forceStartSyncingActivity];
}

#pragma mark Private

- (void)setState:(DWSyncModelState)state {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    if (_state == state) {
        return;
    }

    DWSyncLog(@"[DW Sync] Sync state: %@ -> %@", SyncStateToString(previousState), SyncStateToString(state));
}

#pragma mark SyncingActivityMonitorObserver

- (void)syncingActivityMonitorProgressDidChange:(double)progress {
    self.progress = progress;
}

- (void)syncingActivityMonitorStateDidChangeWithPreviousState:(enum SyncingActivityMonitorState)previousState state:(enum SyncingActivityMonitorState)state {
    self.state = state;
}

@end

NS_ASSUME_NONNULL_END
