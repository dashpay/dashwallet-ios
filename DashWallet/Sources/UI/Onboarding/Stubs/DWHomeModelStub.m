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

#import "DWHomeModelStub.h"

#import "DWDashPayModel.h"
#import "DWEnvironment.h"
#import "DWPayModelStub.h"
#import "DWReceiveModelStub.h"
#import "DWTransactionListDataProviderStub.h"
#import "DWTransactionStub.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeModelStub () <DWBalanceViewDataSource>

@property (readonly, nonatomic, copy) NSArray<DWTransactionStub *> *stubTxs;

@property (readonly, nonatomic, strong) DWTransactionListDataProviderStub *dataProvider;

@property (readonly, nonatomic, strong) DWTransactionListDataSource *dataSource;

@end

@implementation DWHomeModelStub

@synthesize displayMode = _displayMode;
@synthesize payModel = _payModel;
@synthesize receiveModel = _receiveModel;
@synthesize dashPayModel = _dashPayModel;
@synthesize updatesObserver = _updatesObserver;
@synthesize allDataSource = _allDataSource;
@synthesize allowedToShowReclassifyYourTransactions = _allowedToShowReclassifyYourTransactions;

- (instancetype)init {
    self = [super init];
    if (self) {
        _dataProvider = [[DWTransactionListDataProviderStub alloc] init];

        _stubTxs = [DWTransactionStub stubs];

        _receiveModel = [[DWReceiveModelStub alloc] init];
#if DASHPAY_ENABLED
        _dashPayModel = [[DWDashPayModel alloc] init]; // TODO: DP consider using stub
#endif                                                 /* DASHPAY_ENABLED */
        _payModel = [[DWPayModelStub alloc] init];
        _allowedToShowReclassifyYourTransactions = NO;

        [self updateBalance];
        [self reloadTxDataSource];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(walletBalanceDidChangeNotification)
                                                     name:DSWalletBalanceDidChangeNotification
                                                   object:nil];
    }
    return self;
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

- (DWTransactionListDataSource *)dataSource {
    return self.allDataSource;
}

- (BOOL)shouldShowWalletBackupReminder {
    return NO;
}

- (BOOL)isWalletEmpty {
    return NO;
}

- (void)retrySyncing {
}

- (void)registerForPushNotifications {
}

- (id<DWTransactionListDataProviderProtocol>)getDataProvider {
    return self.dataProvider;
}

- (void)walletBackupReminderWasShown {
}

- (BOOL)performOnSetupUpgrades {
    return NO;
}

- (void)walletDidWipe {
}

#pragma mark - DWShortcutsModelDataSource

- (BOOL)shouldShowCreateUserNameButton {
    return NO;
}

#pragma mark - Private

- (void)walletBalanceDidChangeNotification {
    [self updateBalance];

    [self reloadTxDataSource];
}

- (void)updateBalance {
}

- (void)reloadTxDataSource {
    self.allDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:self.stubTxs
                                                                registrationStatus:[self.dashPayModel registrationStatus]];

    [self.updatesObserver homeModel:self didUpdateDataSource:self.dataSource shouldAnimate:NO];
}

@end

NS_ASSUME_NONNULL_END
