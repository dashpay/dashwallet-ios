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
#import "DWDashPayContactsUpdater.h"
#import "DWDashPayModel.h"
#endif

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWPayModel.h"
#import "DWReceiveModel.h"
#import "DWTransactionListDataProvider.h"
#import "DWVersionManager.h"
#import "UIDevice+DashWallet.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeModel () <SyncingActivityMonitorObserver>

@property (nonatomic, strong) dispatch_queue_t queue;
@property (strong, nonatomic) DSReachabilityManager *reachability;
@property (readonly, nonatomic, strong) DWTransactionListDataProvider *dataProvider;

@property (nonatomic, strong) id<DWDashPayProtocol> dashPayModel;

@property (nonatomic, strong) SyncingActivityMonitor *syncMonitor;

@property (readonly, nonatomic, strong) NSArray<DSTransaction *> *dataSource;
@property (null_resettable, nonatomic, strong) NSArray<DSTransaction *> *receivedDataSource;
@property (null_resettable, nonatomic, strong) NSArray<DSTransaction *> *sentDataSource;
@property (null_resettable, nonatomic, strong) NSArray<DSTransaction *> *rewardsDataSource;

@property (nonatomic, assign) BOOL upgradedExtendedKeys;

@end

@implementation DWHomeModel

@synthesize payModel = _payModel;
@synthesize receiveModel = _receiveModel;
@synthesize dashPayModel = _dashPayModel;
@synthesize updatesObserver = _updatesObserver;
@synthesize allDataSource = _allDataSource;


- (instancetype)init {
    self = [super init];
    if (self) {
        [self startSyncIfNeeded];

        _queue = dispatch_queue_create("DWHomeModel.queue", DISPATCH_QUEUE_SERIAL);

        _reachability = [DSReachabilityManager sharedManager];
        if (!_reachability.monitoring) {
            [_reachability startMonitoring];
        }

        _syncMonitor = SyncingActivityMonitor.shared;
        [_syncMonitor addObserver:self];


        _dataProvider = [[DWTransactionListDataProvider alloc] init];


#if DASHPAY
        _dashPayModel = [[DWDashPayModel alloc] init];
#endif /* DASHPAY_ENABLED */

        // set empty datasource
        _allDataSource = @[];

        _receiveModel = [[DWReceiveModel alloc] init];
        [_receiveModel updateReceivingInfo];

        _payModel = [[DWPayModel alloc] init];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(reachabilityDidChangeNotification)
                                   name:DSReachabilityDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationWillEnterForegroundNotification)
                                   name:UIApplicationWillEnterForegroundNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(walletBalanceDidChangeNotification)
                                   name:DSWalletBalanceDidChangeNotification
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

        NSDate *date = [NSDate new];
        [[DWGlobalOptions sharedInstance] setActivationDateForReclassifyYourTransactionsFlowIfNeeded:date];
        [[DWGlobalOptions sharedInstance] setActivationDateForHistoricalRates:date];
    }
    return self;
}

- (void)dealloc {
    [_syncMonitor removeObserver:self];

    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)setUpdatesObserver:(nullable id<DWHomeModelUpdatesObserver>)updatesObserver {
    _updatesObserver = updatesObserver;

    if (self.allDataSource) {
        [updatesObserver homeModel:self didUpdate:self.dataSource shouldAnimate:NO];
    }
}

- (BOOL)isWalletEmpty {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    const BOOL hasFunds = (wallet.totalReceived + wallet.totalSent > 0);

    return !hasFunds;
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
    if (self.reachability.networkReachabilityStatus == DSReachabilityStatusNotReachable) {
        [self.reachability stopMonitoring];
        [self.reachability startMonitoring];
    }

    [self startSyncIfNeeded];
}

- (id<DWTransactionListDataProviderProtocol>)getDataProvider {
    return self.dataProvider;
}

- (void)walletBackupReminderWasShown {
    DWGlobalOptions *options = [DWGlobalOptions sharedInstance];

    NSAssert(options.walletBackupReminderWasShown == NO, @"Inconsistent state");

    options.walletBackupReminderWasShown = YES;
}

- (BOOL)performOnSetupUpgrades {
    if (self.upgradedExtendedKeys) {
        return NO;
    }

    self.upgradedExtendedKeys = YES;

    DSVersionManager *dashSyncVersionManager = [DSVersionManager sharedInstance];
    NSArray *wallets = [DWEnvironment sharedInstance].allWallets;

    [dashSyncVersionManager
        upgradeExtendedKeysForWallets:wallets
                          withMessage:NSLocalizedString(@"Please enter PIN to upgrade wallet", nil)
                       withCompletion:^(BOOL success, BOOL neededUpgrade, BOOL authenticated, BOOL cancelled) {
                           DWVersionManager *dashwalletVersionManager = [DWVersionManager sharedInstance];
                           [dashwalletVersionManager
                               checkPassphraseWasShownCorrectlyForWallet:wallets.firstObject
                                                          withCompletion:^(BOOL needsCheck, BOOL authenticated, BOOL cancelled, NSString *_Nullable seedPhrase) {
                                                              if (needsCheck) {
                                                                  // Show backup reminder shortcut
                                                                  [DWGlobalOptions sharedInstance].walletNeedsBackup = YES;
                                                                  [self.updatesObserver homeModelWantToReloadShortcuts:self];
                                                              }
                                                          }];
                       }];

    return YES;
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
            // Continue signup
            [CrowdNodeObjcWrapper continueInterrupted];
        }
    }
}

#pragma mark - DWDashPayReadyProtocol

#if DASHPAY
- (BOOL)shouldShowCreateUserNameButton {
    if (self.reachability.networkReachabilityStatus == DSReachabilityStatusNotReachable) {
        return NO;
    }

    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    if (chain.isEvolutionEnabled == NO && !MOCK_DASHPAY) {
        return NO;
    }

    // username is registered / in progress
    if (self.dashPayModel.registrationStatus != nil) {
        return NO;
    }

    if (self.dashPayModel.registrationCompleted) {
        return NO;
    }

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    // TODO: add check if appropriate spork is on
    BOOL canRegisterUsername = YES;
    const uint64_t balanceValue = wallet.balance;
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

- (void)reachabilityDidChangeNotification {
    [self.updatesObserver homeModelWantToReloadShortcuts:self];

    if (self.reachability.networkReachabilityStatus != DSReachabilityStatusNotReachable &&
        [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {

        [self startSyncIfNeeded];
    }
}

- (void)walletBalanceDidChangeNotification {
    [self updateBalance];
}

- (void)applicationWillEnterForegroundNotification {
    [self startSyncIfNeeded];
}

- (void)fiatCurrencyDidChangeNotification {
    [self updateBalance];
    [self.updatesObserver homeModelDidChangeInnerModels:self];
}

- (void)chainWalletsDidChangeNotification:(NSNotification *)notification {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSChain *notificationChain = notification.userInfo[DSChainManagerNotificationChainKey];
    if (notificationChain && notificationChain == chain) {
        [self updateBalance];
    }
}

- (void)willWipeWalletNotification {
#if DASHPAY
    [[DWDashPayContactsUpdater sharedInstance] endUpdating];
#endif
}

#pragma mark - Private

- (void)startSyncIfNeeded {
    // This method might be called from init. Don't use any instance variables

    if ([DWEnvironment sharedInstance].currentChain.hasAWallet) {
        // START_SYNC_ENTRY_POINT
        [[DWEnvironment sharedInstance].currentChainManager startSync];
    }
}

- (void)updateBalance {
    [self.receiveModel updateReceivingInfo];
    [self.updatesObserver homeModelWantToReloadShortcuts:self];
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
            [[DWDashPayContactsUpdater sharedInstance] beginUpdating];
#endif
        }

        [self checkCrowdNodeState];
    }

    [self updateBalance];
}

@end

NS_ASSUME_NONNULL_END
