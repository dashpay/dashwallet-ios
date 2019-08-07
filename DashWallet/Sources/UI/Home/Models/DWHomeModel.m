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
#import <UIKit/UIApplication.h>

#import "DWBalanceModel.h"
#import "DWEnvironment.h"
#import "DWSyncModel.h"
#import "DWTransactionListDataProvider.h"
#import "DWTransactionListDataSource+DWProtected.h"
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

@interface DWHomeModel ()

@property (strong, nonatomic) DSReachabilityManager *reachability;
@property (readonly, nonatomic, strong) DWTransactionListDataProvider *dataProvider;

//@property (nonatomic, assign) DWHomeTxDisplayMode displayMode;
@property (nonatomic, strong) DWBalanceModel *balanceModel;

@property (nonatomic, strong) DWTransactionListDataSource *allDataSource;
@property (null_resettable, nonatomic, strong) DWTransactionListDataSource *receivedDataSource;
@property (null_resettable, nonatomic, strong) DWTransactionListDataSource *sentDataSource;

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

        _dataProvider = [[DWTransactionListDataProvider alloc] init];

        _syncModel = [[DWSyncModel alloc] initWithReachability:_reachability];

        // set empty datasource
        _allDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:@[]
                                                                      dataProvider:_dataProvider];

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
                               selector:@selector(syncFinishedNotification)
                                   name:DWSyncFinishedNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(chainWalletsDidChangeNotification:)
                                   name:DSChainWalletsDidChangeNotification
                                 object:nil];

        [self reloadTxDataSource];
    }
    return self;
}

- (void)setUpdatesObserver:(nullable id<DWHomeModelUpdatesObserver>)updatesObserver {
    _updatesObserver = updatesObserver;

    if (self.allDataSource) {
        [updatesObserver homeModel:self didUpdateDataSourceShouldAnimate:NO];
    }
}

- (void)setDisplayMode:(DWHomeTxDisplayMode)displayMode {
    if (_displayMode == displayMode) {
        return;
    }

    _displayMode = displayMode;

    [self.updatesObserver homeModel:self didUpdateDataSourceShouldAnimate:YES];
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
    }
}

- (DWTransactionListDataSource *)receivedDataSource {
    if (_receivedDataSource == nil) {
        NSArray<DSTransaction *> *transactions = [self filterTransactions:self.allDataSource.items
                                                           forDisplayMode:DWHomeTxDisplayMode_Received];
        _receivedDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:transactions
                                                                           dataProvider:self.dataProvider];
    }

    return _receivedDataSource;
}

- (DWTransactionListDataSource *)sentDataSource {
    if (_sentDataSource == nil) {
        NSArray<DSTransaction *> *transactions = [self filterTransactions:self.allDataSource.items
                                                           forDisplayMode:DWHomeTxDisplayMode_Sent];
        _sentDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:transactions
                                                                       dataProvider:self.dataProvider];
    }

    return _sentDataSource;
}

#pragma mark - Notifications

- (void)reachabilityDidChangeNotification {
    if (self.reachability.networkReachabilityStatus != DSReachabilityStatusNotReachable &&
        [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {

        [self connectIfNeeded];
    }
}

- (void)walletBalanceDidChangeNotification {
    if (self.syncModel.state != DWSyncModelState_Syncing) {
        [self updateBalance];
    }

    [self reloadTxDataSource];
}

- (void)transactionManagerTransactionStatusDidChangeNotification {
    [self reloadTxDataSource];
}

- (void)applicationWillEnterForegroundNotification {
    [self connectIfNeeded];
}

- (void)syncFinishedNotification {
    [self updateBalance];
    [self reloadTxDataSource];
}

- (void)chainWalletsDidChangeNotification:(NSNotification *)notification {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSChain *notificationChain = notification.userInfo[DSChainManagerNotificationChainKey];
    if (notificationChain && notificationChain == chain) {
        [self updateBalance];

        // TODO: impl (perhaps, not here)
        //        if (chain.wallets.count == 0) { //a wallet was deleted, we need to go back to wallet nav
        //            [self showNewWalletController];
        //        }
    }
}

#pragma mark - Private

- (void)connectIfNeeded {
    // This method might be called from init. Don't use any instance variables

    if ([DWEnvironment sharedInstance].currentChain.hasAWallet) {
        // START_SYNC_ENTRY_POINT
        [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
    }
}

- (void)reloadTxDataSource {
    if (self.syncModel.state == DWSyncModelState_Syncing) {
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

        NSArray<DSTransaction *> *transactions = account.allTransactions;

        BOOL shouldAnimate = YES;
        DSTransaction *prevTransaction = self.dataSource.items.firstObject;
        if (!prevTransaction || prevTransaction == transactions.firstObject) {
            shouldAnimate = NO;
        }

        self.allDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:transactions
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

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.updatesObserver homeModel:self didUpdateDataSourceShouldAnimate:shouldAnimate];
        });
    });
}

- (void)updateBalance {
    // TODO: impl
    // [self.receiveViewController updateAddress];

    uint64_t balanceValue = [DWEnvironment sharedInstance].currentWallet.balance;
    if (self.balanceModel &&
        balanceValue > self.balanceModel.value &&
        [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
        [[UIDevice currentDevice] dw_playCoinSound];
    }

    self.balanceModel = [[DWBalanceModel alloc] initWithValue:balanceValue];
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
        if ((displayMode == DWHomeTxDisplayMode_Sent && sent > 0) ||
            (displayMode == DWHomeTxDisplayMode_Received && sent == 0)) {
            [mutableTransactions addObject:tx];
        }
    }

    return [mutableTransactions copy];
}

@end

NS_ASSUME_NONNULL_END
