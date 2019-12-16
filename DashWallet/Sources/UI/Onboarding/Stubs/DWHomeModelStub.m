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

#import "DWBalanceDisplayOptionsStub.h"
#import "DWBalanceModel.h"
#import "DWEnvironment.h"
#import "DWPayModelStub.h"
#import "DWReceiveModelStub.h"
#import "DWShortcutsModel.h"
#import "DWSyncModelStub.h"
#import "DWTransactionListDataProviderStub.h"
#import "DWTransactionListDataSource+DWProtected.h"
#import "DWTransactionStub.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeModelStub ()

@property (readonly, nonatomic, strong) DWTransactionListDataProviderStub *dataProvider;

@property (nullable, nonatomic, strong) DWBalanceModel *balanceModel;

@property (readonly, nonatomic, strong) DWTransactionListDataSource *dataSource;
@property (nonatomic, strong) DWTransactionListDataSource *allDataSource;

@end

@implementation DWHomeModelStub

@synthesize balanceDisplayOptions = _balanceDisplayOptions;
@synthesize displayMode = _displayMode;
@synthesize payModel = _payModel;
@synthesize receiveModel = _receiveModel;
@synthesize shortcutsModel = _shortcutsModel;
@synthesize syncModel = _syncModel;
@synthesize updatesObserver = _updatesObserver;

- (instancetype)init {
    self = [super init];
    if (self) {
        _balanceModel = [[DWBalanceModel alloc] initWithValue:42 * DUFFS];
        _syncModel = [[DWSyncModelStub alloc] init];
        _dataProvider = [[DWTransactionListDataProviderStub alloc] init];

        NSArray<DWTransactionStub *> *txs = [DWTransactionStub stubs];
        _allDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:txs
                                                                      dataProvider:_dataProvider];

        _receiveModel = [[DWReceiveModelStub alloc] init];
        _shortcutsModel = [[DWShortcutsModel alloc] init];
        _payModel = [[DWPayModelStub alloc] init];
        _balanceDisplayOptions = [[DWBalanceDisplayOptionsStub alloc] init];
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

- (BOOL)isJailbroken {
    return NO;
}

- (BOOL)isWalletEmpty {
    return NO;
}

- (void)reloadShortcuts {
    [self.shortcutsModel reloadShortcuts];
}

- (void)retrySyncing {
}

- (id<DWTransactionListDataProviderProtocol>)getDataProvider {
    return self.dataProvider;
}

- (void)walletBackupReminderWasShown {
}

@end

NS_ASSUME_NONNULL_END
