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

#import "DWDashPayProtocol.h"
#import "DWDashPayReadyProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@protocol DWHomeProtocol;
@class DSTransaction;
@protocol DWPayModelProtocol;
@protocol DWReceiveModelProtocol;
@protocol DWTransactionListDataProviderProtocol;

@protocol DWHomeModelUpdatesObserver <NSObject>
- (void)homeModelDidChangeInnerModels:(id<DWHomeProtocol>)model;
@end

@protocol DWHomeProtocol <DWDashPayReadyProtocol>

@property (nullable, nonatomic, weak) id<DWHomeModelUpdatesObserver> updatesObserver;

@property (readonly, nonatomic, strong) id<DWPayModelProtocol> payModel;
@property (readonly, nonatomic, strong) id<DWReceiveModelProtocol> receiveModel;
@property (readonly, nonatomic, strong) id<DWDashPayProtocol> dashPayModel;

@property (nonatomic, strong) NSArray<DSTransaction *> *allDataSource;

@property (readonly, nonatomic, assign) BOOL shouldShowWalletBackupReminder;

@property (readonly, nonatomic, assign, getter=isWalletEmpty) BOOL walletEmpty;
@property (readonly, nonatomic, assign, getter=isAllowedToShowReclassifyYourTransactions) BOOL allowedToShowReclassifyYourTransactions;

- (void)walletBackupReminderWasShown;

- (void)registerForPushNotifications;

/// Returns `YES` if the upgrade process was initiated
- (BOOL)performOnSetupUpgrades;

- (id<DWTransactionListDataProviderProtocol>)getDataProvider;

- (void)walletDidWipe;

- (void)retrySyncing;
- (void)checkCrowdNodeState;

#if DASHPAY
- (void)handleDeeplink:(NSURL *)url
            completion:(void (^)(DSTransaction *_Nullable assetLockTx,
                                 NSString *_Nullable errorTitle,
                                 NSString *_Nullable errorMessage))completion;
#endif

@end

NS_ASSUME_NONNULL_END
