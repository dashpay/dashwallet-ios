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
#import "DWBalanceDisplayOptions.h"
#import "DWBalanceModel.h"
#import "DWDashPayConstants.h"
#import "DWDashPayContactsUpdater.h"
#import "DWDashPayModel.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWPayModel.h"
#import "DWReceiveModel.h"
#import "DWShortcutsModel.h"
#import "DWSyncModel.h"
#import "DWTransactionListDataProvider.h"
#import "DWTransactionListDataSource+DWProtected.h"
#import "DWVersionManager.h"
#import "UIDevice+DashWallet.h"

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

@interface DWHomeModel () <DWShortcutsModelDataSource>

@property (nonatomic, strong) dispatch_queue_t queue;
@property (strong, nonatomic) DSReachabilityManager *reachability;
@property (readonly, nonatomic, strong) DWTransactionListDataProvider *dataProvider;

@property (nullable, nonatomic, strong) DWBalanceModel *balanceModel;
@property (nonatomic, strong) id<DWDashPayProtocol> dashPayModel;

@property (readonly, nonatomic, strong) DWTransactionListDataSource *dataSource;
@property (nonatomic, strong) DWTransactionListDataSource *allDataSource;
@property (null_resettable, nonatomic, strong) DWTransactionListDataSource *receivedDataSource;
@property (null_resettable, nonatomic, strong) DWTransactionListDataSource *sentDataSource;
@property (null_resettable, nonatomic, strong) DWTransactionListDataSource *rewardsDataSource;

@property (nonatomic, assign) BOOL upgradedExtendedKeys;

@end

@implementation DWHomeModel

@synthesize balanceDisplayOptions = _balanceDisplayOptions;
@synthesize displayMode = _displayMode;
@synthesize payModel = _payModel;
@synthesize receiveModel = _receiveModel;
@synthesize dashPayModel = _dashPayModel;
@synthesize shortcutsModel = _shortcutsModel;
@synthesize syncModel = _syncModel;
@synthesize updatesObserver = _updatesObserver;

- (instancetype)init {
    self = [super init];
    if (self) {
        [self startSyncIfNeeded];

        _queue = dispatch_queue_create("DWHomeModel.queue", DISPATCH_QUEUE_SERIAL);

        _reachability = [DSReachabilityManager sharedManager];
        if (!_reachability.monitoring) {
            [_reachability startMonitoring];
        }

        _dataProvider = [[DWTransactionListDataProvider alloc] init];

        _syncModel = [[DWSyncModel alloc] initWithReachability:_reachability];

#if DASHPAY_ENABLED
        _dashPayModel = [[DWDashPayModel alloc] init];
#endif /* DASHPAY_ENABLED */

        // set empty datasource
        _allDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:@[]
                                                                registrationStatus:[_dashPayModel registrationStatus]
                                                                      dataProvider:_dataProvider];

        _receiveModel = [[DWReceiveModel alloc] init];
        [_receiveModel updateReceivingInfo];

        _shortcutsModel = [[DWShortcutsModel alloc] initWithDataSource:self];

        _payModel = [[DWPayModel alloc] init];

        _balanceDisplayOptions = [[DWBalanceDisplayOptions alloc] init];

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
                               selector:@selector(transactionManagerTransactionStatusDidChangeNotification)
                                   name:DSTransactionManagerTransactionStatusDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(syncStateChangedNotification)
                                   name:DWSyncStateChangedNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(chainWalletsDidChangeNotification:)
                                   name:DSChainWalletsDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(dashPayRegistrationStatusUpdatedNotification)
                                   name:DWDashPayRegistrationStatusUpdatedNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(willWipeWalletNotification)
                                   name:DWWillWipeWalletNotification
                                 object:nil];

        [self reloadTxDataSource];
    }
    return self;
}

- (void)dealloc {
    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

- (void)setUpdatesObserver:(nullable id<DWHomeModelUpdatesObserver>)updatesObserver {
    _updatesObserver = updatesObserver;

    if (self.allDataSource) {
        [updatesObserver homeModel:self didUpdateDataSource:self.dataSource shouldAnimate:NO];
    }
}

- (void)setDisplayMode:(DWHomeTxDisplayMode)displayMode {
    if (_displayMode == displayMode) {
        return;
    }

    _displayMode = displayMode;

    [self.updatesObserver homeModel:self didUpdateDataSource:self.dataSource shouldAnimate:YES];
}

- (BOOL)isJailbroken {
    return IsJailbroken();
}

- (BOOL)isWalletEmpty {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    const BOOL hasFunds = (wallet.totalReceived + wallet.totalSent > 0);

    return !hasFunds;
}

- (DWTransactionListDataSource *)dataSource {
    switch (self.displayMode) {
        case DWHomeTxDisplayMode_All:
            return self.allDataSource;
        case DWHomeTxDisplayMode_Received:
            return self.receivedDataSource;
        case DWHomeTxDisplayMode_Sent:
            return self.sentDataSource;
        case DWHomeTxDisplayMode_Rewards:
            return self.rewardsDataSource;
    }
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

- (void)reloadShortcuts {
    [self.shortcutsModel reloadShortcuts];
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
                                                                  [self reloadShortcuts];
                                                              }
                                                          }];
                       }];

    return YES;
}

- (void)forceStartSyncingActivity {
    DWSyncModel *syncModel = (DWSyncModel *)self.syncModel;
    NSAssert([syncModel isKindOfClass:DWSyncModel.class], @"Internal inconsistency");
    [syncModel forceStartSyncingActivity];

    [self updateBalance];
    [self reloadTxDataSource];
}

- (void)walletDidWipe {
#if DASHPAY_ENABLED
    self.dashPayModel = [[DWDashPayModel alloc] init];
#endif /* DASHPAY_ENABLED */
}

#pragma mark - DWShortcutsModelDataSource

- (BOOL)shouldShowCreateUserNameButton {
    if (self.reachability.networkReachabilityStatus == DSReachabilityStatusNotReachable) {
        return NO;
    }

    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    if (chain.isEvolutionEnabled == NO) {
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
    BOOL isSynced = self.syncModel.state == DWSyncModelState_SyncDone;
    return canRegisterUsername && isSynced && isEnoughBalance;
}

#pragma mark - Notifications

- (void)reachabilityDidChangeNotification {
    [self reloadShortcuts];

    if (self.reachability.networkReachabilityStatus != DSReachabilityStatusNotReachable &&
        [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {

        [self startSyncIfNeeded];
    }

    DWSyncModel *syncModel = (DWSyncModel *)self.syncModel;
    NSAssert([syncModel isKindOfClass:DWSyncModel.class], @"Internal inconsistency");
    [syncModel reachabilityStatusDidChange];
}

- (void)walletBalanceDidChangeNotification {
    [self updateBalance];

    [self reloadTxDataSource];
}

- (void)transactionManagerTransactionStatusDidChangeNotification {
    [self reloadTxDataSource];
}

- (void)applicationWillEnterForegroundNotification {
    [self startSyncIfNeeded];
    [self.balanceDisplayOptions hideBalanceIfNeeded];
}

- (void)syncStateChangedNotification {
    BOOL isSynced = self.syncModel.state == DWSyncModelState_SyncDone;
    if (isSynced) {
        [self.dashPayModel updateUsernameStatus];

        if (self.dashPayModel.username != nil) {
            [self.receiveModel updateReceivingInfo];
            [[DWDashPayContactsUpdater sharedInstance] beginUpdating];
        }
    }

    [self updateBalance];
    [self reloadTxDataSource];
}

- (void)chainWalletsDidChangeNotification:(NSNotification *)notification {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSChain *notificationChain = notification.userInfo[DSChainManagerNotificationChainKey];
    if (notificationChain && notificationChain == chain) {
        [self updateBalance];
    }
}

- (void)dashPayRegistrationStatusUpdatedNotification {
    [self reloadTxDataSource];

    [[DWDashPayContactsUpdater sharedInstance] beginUpdating];
}

- (void)willWipeWalletNotification {
    [[DWDashPayContactsUpdater sharedInstance] endUpdating];
}

#pragma mark - Private

- (DWTransactionListDataSource *)receivedDataSource {
    if (_receivedDataSource == nil) {
        NSArray<DSTransaction *> *transactions = [self filterTransactions:self.allDataSource.items
                                                           forDisplayMode:DWHomeTxDisplayMode_Received];
        _receivedDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:transactions
                                                                     registrationStatus:[self.dashPayModel registrationStatus]
                                                                           dataProvider:self.dataProvider];
    }

    return _receivedDataSource;
}

- (DWTransactionListDataSource *)sentDataSource {
    if (_sentDataSource == nil) {
        NSArray<DSTransaction *> *transactions = [self filterTransactions:self.allDataSource.items
                                                           forDisplayMode:DWHomeTxDisplayMode_Sent];
        _sentDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:transactions
                                                                 registrationStatus:[self.dashPayModel registrationStatus]
                                                                       dataProvider:self.dataProvider];
    }

    return _sentDataSource;
}

- (DWTransactionListDataSource *)rewardsDataSource {
    if (_rewardsDataSource == nil) {
        NSArray<DSTransaction *> *transactions = [self filterTransactions:self.allDataSource.items
                                                           forDisplayMode:DWHomeTxDisplayMode_Rewards];
        _rewardsDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:transactions
                                                                    registrationStatus:[self.dashPayModel registrationStatus]
                                                                          dataProvider:self.dataProvider];
    }

    return _rewardsDataSource;
}

- (void)startSyncIfNeeded {
    // This method might be called from init. Don't use any instance variables

    if ([DWEnvironment sharedInstance].currentChain.hasAWallet) {
        // START_SYNC_ENTRY_POINT
        [[DWEnvironment sharedInstance].currentChainManager startSync];
    }
}

- (void)reloadTxDataSource {
    dispatch_async(self.queue, ^{
        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;

        NSString *sortKey = DW_KEYPATH(DSTransaction.new, timestamp);

        //Timestamps are set to 0 if the transaction hasn't yet been confirmed, they should be at the top of the list if this is the case
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:sortKey
                                                                         ascending:NO
                                                                        comparator:^NSComparisonResult(id _Nonnull obj1, id _Nonnull obj2) {
                                                                            if ([obj1 unsignedIntValue] == 0) {
                                                                                if ([obj2 unsignedIntValue] == 0) {
                                                                                    return NSOrderedSame;
                                                                                }
                                                                                else {
                                                                                    return NSOrderedDescending;
                                                                                }
                                                                            }
                                                                            else if ([obj2 unsignedIntValue] == 0) {
                                                                                return NSOrderedAscending;
                                                                            }
                                                                            else {
                                                                                return [(NSNumber *)obj1 compare:obj2];
                                                                            }
                                                                        }];
        DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
        NSArray<DSTransaction *> *transactions = [account.allTransactions sortedArrayUsingDescriptors:@[ sortDescriptor ]];

        BOOL shouldAnimate = YES;
        DSTransaction *prevTransaction = self.dataSource.items.firstObject;
        if (!prevTransaction || prevTransaction == transactions.firstObject) {
            shouldAnimate = NO;
        }

        self.allDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:transactions
                                                                    registrationStatus:self.dashPayModel.registrationStatus
                                                                          dataProvider:self.dataProvider];
        self.receivedDataSource = nil;
        self.sentDataSource = nil;

        // pre-filter while in background queue
        if (self.displayMode == DWHomeTxDisplayMode_Received) {
            [self receivedDataSource];
        }
        else if (self.displayMode == DWHomeTxDisplayMode_Sent) {
            [self sentDataSource];
        }
        else if (self.displayMode == DWHomeTxDisplayMode_Rewards) {
            [self rewardsDataSource];
        }

        DWTransactionListDataSource *datasource = self.dataSource;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.updatesObserver homeModel:self didUpdateDataSource:datasource shouldAnimate:shouldAnimate];
        });
    });
}

- (void)updateBalance {
    [self.receiveModel updateReceivingInfo];

    uint64_t balanceValue = [DWEnvironment sharedInstance].currentWallet.balance;
    if (self.balanceModel &&
        balanceValue > self.balanceModel.value &&
        self.balanceModel.value > 0 &&
        [UIApplication sharedApplication].applicationState != UIApplicationStateBackground &&
        self.syncModel.progress > 0.995) {
        [[UIDevice currentDevice] dw_playCoinSound];
    }

    self.balanceModel = [[DWBalanceModel alloc] initWithValue:balanceValue];

    DWGlobalOptions *options = [DWGlobalOptions sharedInstance];
    if (balanceValue > 0 && options.walletNeedsBackup && !options.balanceChangedDate) {
        options.balanceChangedDate = [NSDate date];
    }

    [self reloadShortcuts];
}

- (NSArray<DSTransaction *> *)filterTransactions:(NSArray<DSTransaction *> *)allTransactions
                                  forDisplayMode:(DWHomeTxDisplayMode)displayMode {
    NSAssert(displayMode != DWHomeTxDisplayMode_All, @"All transactions should not be filtered");
    if (displayMode == DWHomeTxDisplayMode_All) {
        return allTransactions;
    }

    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    NSMutableArray<DSTransaction *> *mutableTransactions = [NSMutableArray array];

    for (DSTransaction *tx in allTransactions) {
        uint64_t sent = [account amountSentByTransaction:tx];
        if (displayMode == DWHomeTxDisplayMode_Sent && sent > 0) {
            [mutableTransactions addObject:tx];
        }
        else if (displayMode == DWHomeTxDisplayMode_Received && sent == 0 && ![tx isKindOfClass:[DSCoinbaseTransaction class]]) {
            [mutableTransactions addObject:tx];
        }
        else if (displayMode == DWHomeTxDisplayMode_Rewards && sent == 0 && [tx isKindOfClass:[DSCoinbaseTransaction class]]) {
            [mutableTransactions addObject:tx];
        }
    }

    return [mutableTransactions copy];
}

@end

NS_ASSUME_NONNULL_END
