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

#import "DWPaymentCurrency.h"
#import <DSDynamicOptions/DSDynamicOptions.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A centralized place of User Defaults shared among several parts of the app

 To add a new option: add a property with UsedDefaults-supported type and mark it as @dynamic
 in the implementation
 */
@interface DWGlobalOptions : DSDynamicOptions

@property (nonatomic, assign) BOOL walletNeedsBackup;
@property (nonatomic, assign) BOOL userHasBalance;
@property (nullable, nonatomic, strong) NSDate *balanceChangedDate;
@property (nonatomic, assign) BOOL walletBackupReminderWasShown;

@property (nonatomic, assign) BOOL biometricAuthConfigured;
@property (nonatomic, assign) BOOL biometricAuthEnabled;


/// Value in seconds
@property (nonatomic, assign) NSInteger autoLockAppInterval;

@property (nullable, nonatomic, copy) NSArray<NSNumber *> *shortcuts;

@property (nonatomic, assign) BOOL localNotificationsEnabled;

@property (nonatomic, assign) BOOL balanceHidden;

@property (nonatomic, assign) BOOL shouldDisplayOnboarding;
@property (nonatomic, assign) BOOL shouldDisplayReclassifyYourTransactionsFlow;
@property (nullable, nonatomic, strong) NSDate *dateReclassifyYourTransactionsFlowActivated;
@property (nonatomic, assign) NSInteger paymentsScreenCurrentTab;

@property (nullable, nonatomic, copy) NSString *dashpayUsername;
@property (nonatomic, assign) BOOL dashpayRegistrationCompleted;
@property (nullable, nonatomic, strong) NSDate *mostRecentViewedNotificationDate;

@property (nonatomic, assign, getter=isResyncingWallet) BOOL resyncingWallet;

@property (nonatomic, assign) DWPaymentCurrency selectedPaymentCurrency;

@property (nonatomic, assign) BOOL exploreDashMerchantsInfoShown;

@property (nonatomic, assign) BOOL crowdNodeInfoShown;

@property (nonatomic, assign) BOOL coinbaseInfoShown;
// Non-dynamic

- (BOOL)lockScreenDisabled;
- (void)setLockScreenDisabled:(BOOL)lockScreenDisabled;

- (BOOL)spendingConfirmationDisabled;
- (void)setSpendingConfirmationDisabled:(BOOL)spendingConfirmationDisabled;

- (void)setActivationDateForReclassifyYourTransactionsFlowIfNeeded:(NSDate *)date;
// Methods

- (void)restoreToDefaults;

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
