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

#import "DWHomeModelMock.h"

#import "DWBalanceDisplayOptionsMock.h"
#import "DWBalanceModel.h"
#import "DWEnvironment.h"
#import "DWPayModel.h"
#import "DWReceiveModel+Private.h"
#import "DWShortcutsModel.h"
#import "DWSyncModelMock.h"
#import "DWTransactionListDataProvider.h"
#import "DWTransactionListDataSource+DWProtected.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeModelMock ()

@property (readonly, nonatomic, strong) DWTransactionListDataProvider *dataProvider;

@property (nullable, nonatomic, strong) DWBalanceModel *balanceModel;

@property (readonly, nonatomic, strong) DWTransactionListDataSource *dataSource;
@property (nonatomic, strong) DWTransactionListDataSource *allDataSource;

@end

@implementation DWHomeModelMock

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
        _balanceModel = [[DWBalanceModel alloc] initWithValue:3.14 * DUFFS];
        _syncModel = [[DWSyncModelMock alloc] init];

        _dataProvider = [[DWTransactionListDataProvider alloc] init];

        // set empty datasource
        _allDataSource = [[DWTransactionListDataSource alloc] initWithTransactions:@[]
                                                                      dataProvider:_dataProvider];

        // TODO: mock
        _receiveModel = [[DWReceiveModel alloc] init];
        [_receiveModel updateReceivingInfo];

        _shortcutsModel = [[DWShortcutsModel alloc] init];

        // TODO: mock
        _payModel = [[DWPayModel alloc] init];

        _balanceDisplayOptions = [[DWBalanceDisplayOptionsMock alloc] init];
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
