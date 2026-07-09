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

#import <UIKit/UIApplication.h>

#import "AppDelegate.h"
#if DASHPAY
#import "DWDashPayConstants.h"
#import "DWDashPayModel.h"
#endif

#import "DWAppRootViewController.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWPayModel.h"
#import "DWReceiveModel.h"
#import "DWVersionManager.h"
#import "UIDevice+DashWallet.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeModel () <SyncingActivityMonitorObserver>

@property (nonatomic, strong) dispatch_queue_t queue;
@property (strong, nonatomic) DWNetworkReachability *reachability;
@property (nonatomic, strong) id<DWDashPayProtocol> dashPayModel;

@property (nonatomic, strong) SyncingActivityMonitor *syncMonitor;

@end

@implementation DWHomeModel

@synthesize payModel = _payModel;
@synthesize receiveModel = _receiveModel;
@synthesize dashPayModel = _dashPayModel;
@synthesize updatesObserver = _updatesObserver;


- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("DWHomeModel.queue", DISPATCH_QUEUE_SERIAL);

        _reachability = [DWNetworkReachability shared];
        if (!_reachability.isMonitoring) {
            [_reachability startMonitoring];
        }

        _syncMonitor = SyncingActivityMonitor.shared;
        [_syncMonitor addObserver:self];


#if DASHPAY
        _dashPayModel = [[DWDashPayModel alloc] init];
#endif /* DASHPAY_ENABLED */


        _receiveModel = [[DWReceiveModel alloc] init];
        [_receiveModel updateReceivingInfo];

        _payModel = [[DWPayModel alloc] init];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(walletBalanceDidChangeNotification)
                                   name:DWSwiftDashSDKWalletState.balanceDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(chainWalletsDidChangeNotification:)
                                   name:DSChainWalletsDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(willWipeWalletNotification)
                                   name:DWWillWipeWalletNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(fiatCurrencyDidChangeNotification)
                                   name:DWApp.fiatCurrencyDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(appDidUnlockNotification)
                                   name:DWAppDidUnlockNotification
                                 object:nil];

        NSDate *date = [NSDate new];
        [[DWGlobalOptions sharedInstance] setActivationDateForReclassifyYourTransactionsFlowIfNeeded:date];
        [[DWGlobalOptions sharedInstance] setActivationDateForHistoricalRates:date];
    }
    return self;
}

- (void)dealloc {
    [_syncMonitor removeObserver:self];

    DWLog(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)setUpdatesObserver:(nullable id<DWHomeModelUpdatesObserver>)updatesObserver {
    _updatesObserver = updatesObserver;
}

- (BOOL)isWalletEmpty {
    // Gate for the jailbreak warning copy. The old DashSync read
    // (wallet.totalReceived + totalSent) froze at M6 and never saw SDK-era
    // funds; the live SDK balance answers the same "anything at stake?"
    // question.
    return DWSwiftDashSDKWalletState.currentTotalBalance == 0;
}

- (BOOL)shouldShowWalletBackupReminder {
    DWGlobalOptions *options = [DWGlobalOptions sharedInstance];
    if (!options.walletNeedsBackup) {
        return NO;
    }

    if (options.walletBackupReminderWasShown) {
        return NO;
    }

    NSDate *balanceChangedDate = options.balanceChangedDate;
    if (balanceChangedDate == nil) {
        return NO;
    }

    NSDate *now = [NSDate date];

    const NSTimeInterval secondsSinceBalanceChanged =
        now.timeIntervalSince1970 - balanceChangedDate.timeIntervalSince1970;

    // Show wallet backup reminder after 24h since balance has been changed
    return (secondsSinceBalanceChanged > DAY_TIME_INTERVAL);
}

- (void)registerForPushNotifications {
    [[AppDelegate appDelegate] registerForPushNotifications];
}

- (void)retrySyncing {
    if (!self.reachability.isReachable) {
        [self.reachability stopMonitoring];
        [self.reachability startMonitoring];
    }
}

- (void)walletBackupReminderWasShown {
    DWGlobalOptions *options = [DWGlobalOptions sharedInstance];

    NSAssert(options.walletBackupReminderWasShown == NO, @"Inconsistent state");

    options.walletBackupReminderWasShown = YES;
}

- (void)walletDidWipe {
#if DASHPAY
    self.dashPayModel = [[DWDashPayModel alloc] init];
#endif /* DASHPAY_ENABLED */
}

- (void)checkCrowdNodeState {
    if (SyncingActivityMonitor.shared.state == SyncingActivityMonitorStateSyncDone) {
        [CrowdNodeObjcWrapper restoreState];

        if ([CrowdNodeObjcWrapper isInterrupted]) {
            DWAuthenticationService *authManager = [DWAuthenticationService shared];
            // Mirrors the didAuthenticate / lockScreenDisabled reads of
            // -[DWRootModel shouldShowLockScreen]: before the first unlock the
            // lock screen is (or is about to be) up, and the signup resume's
            // PIN gate must never stack a prompt on top of it. The deferred
            // resume re-runs via DWAppDidUnlockNotification below.
            BOOL awaitingFirstUnlock = authManager.usesAuthentication && !authManager.didAuthenticate && ![[DWGlobalOptions sharedInstance] lockScreenDisabled];
            if (awaitingFirstUnlock) {
                return;
            }

            // Continue signup
            [CrowdNodeObjcWrapper continueInterrupted];
        }
    }
}

- (void)appDidUnlockNotification {
    [self checkCrowdNodeState];
}

#pragma mark - DWDashPayReadyProtocol

#if DASHPAY
- (BOOL)shouldShowCreateUserNameButton {
    if (!self.reachability.isReachable) {
        return NO;
    }

    // The old `chain.isEvolutionEnabled` gate was constant-false at runtime
    // (the pod hardcodes NO and MOCK_DASHPAY is hardcoded YES) — deleted, not
    // ported. Revisit real Platform-availability gating with C10.

    // username is registered / in progress
    if (self.dashPayModel.registrationStatus != nil) {
        return NO;
    }

    if (self.dashPayModel.registrationCompleted) {
        return NO;
    }

    // TODO: add check if appropriate spork is on
    BOOL canRegisterUsername = YES;
    const uint64_t balanceValue = DWSwiftDashSDKWalletState.currentTotalBalance;
    BOOL isEnoughBalance = balanceValue >= DWDP_MIN_BALANCE_TO_CREATE_USERNAME;
    BOOL isSynced = [SyncingActivityMonitor shared].state == SyncingActivityMonitorStateSyncDone;
    return canRegisterUsername && isSynced && isEnoughBalance;
}

- (void)handleDeeplink:(NSURL *)url
            completion:(void (^)(BOOL success,
                                 NSString *_Nullable errorTitle,
                                 NSString *_Nullable errorMessage))completion {
    [self.dashPayModel verifyDeeplink:url completion:completion];
}
#endif

#pragma mark - Notifications

- (void)walletBalanceDidChangeNotification {
    [self.receiveModel updateReceivingInfo];
}

- (void)fiatCurrencyDidChangeNotification {
    [self.receiveModel updateReceivingInfo];
    ;
}

- (void)chainWalletsDidChangeNotification:(NSNotification *)notification {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSChain *notificationChain = notification.userInfo[DSChainManagerNotificationChainKey];
    if (notificationChain && notificationChain == chain) {
        [self.receiveModel updateReceivingInfo];
    }
}

- (void)willWipeWalletNotification {
#if DASHPAY
    // Row #18: contact syncing is owned by the SDK DashPay sync loop
    // (PlatformAddressSyncCoordinator); no app-side updater to stop.
#endif
}

#pragma mark SyncingActivityMonitorObserver

- (void)syncingActivityMonitorProgressDidChange:(double)progress {
}

- (void)syncingActivityMonitorStateDidChangeWithPreviousState:(enum SyncingActivityMonitorState)previousState state:(enum SyncingActivityMonitorState)state {
    BOOL isSynced = state == SyncingActivityMonitorStateSyncDone;

    if (isSynced) {
        [self.dashPayModel updateUsernameStatus];

        if (self.dashPayModel.username != nil) {
            [self.receiveModel updateReceivingInfo];
#if DASHPAY
            // Row #18: contact syncing is owned by the SDK DashPay sync loop.
#endif
        }

        [self checkCrowdNodeState];
    }

    [self.receiveModel updateReceivingInfo];
}

@end

NS_ASSUME_NONNULL_END
