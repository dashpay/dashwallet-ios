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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DWTransactionListDataSource;
@class DWSyncModel;
@class DWHomeModel;
@class DWBalanceModel;
@class DWReceiveModel;
@class DWShortcutsModel;
@class DWPayModel;
@protocol DWTransactionListDataProviderProtocol;

typedef NS_ENUM(NSUInteger, DWHomeTxDisplayMode) {
    DWHomeTxDisplayMode_All,
    DWHomeTxDisplayMode_Received,
    DWHomeTxDisplayMode_Sent,
    DWHomeTxDisplayMode_Rewards,
};

@protocol DWHomeModelUpdatesObserver <NSObject>

- (void)homeModel:(DWHomeModel *)model
    didUpdateDataSource:(DWTransactionListDataSource *)dataSource
          shouldAnimate:(BOOL)shouldAnimate;

@end

@interface DWHomeModel : NSObject

@property (nonatomic, assign) DWHomeTxDisplayMode displayMode;

@property (readonly, nonatomic, strong) DWSyncModel *syncModel;
@property (readonly, nullable, nonatomic, strong) DWBalanceModel *balanceModel;
@property (readonly, nonatomic, strong) DWReceiveModel *receiveModel;
@property (readonly, nonatomic, strong) DWShortcutsModel *shortcutsModel;
@property (readonly, nonatomic, strong) DWPayModel *payModel;

@property (readonly, nonatomic, assign) BOOL shouldShowWalletBackupReminder;

@property (nullable, nonatomic, weak) id<DWHomeModelUpdatesObserver> updatesObserver;

@property (readonly, nonatomic, assign, getter=isJailbroken) BOOL jailbroken;
@property (readonly, nonatomic, assign, getter=isWalletEmpty) BOOL walletEmpty;

- (void)reloadShortcuts;

- (void)retrySyncing;

- (id<DWTransactionListDataProviderProtocol>)getDataProvider;

- (void)walletBackupReminderWasShown;

@end

NS_ASSUME_NONNULL_END
