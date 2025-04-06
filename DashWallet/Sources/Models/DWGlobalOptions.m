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

#import "DWGlobalOptions.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

// backward compatibility
static NSString *const LOCAL_NOTIFICATIONS_ENABLED_KEY = @"USER_DEFAULTS_LOCAL_NOTIFICATIONS_KEY";
static NSString *const LOCKSCREEN_DISABLED_KEY = @"org.dash.wallet.lockscreen-disabled";
static NSString *const SPENDING_CONFIRMATION_DISABLED_KEY = @"org.dash.wallet.spending-confirmation-disabled";

@implementation DWGlobalOptions

@dynamic walletNeedsBackup;
@dynamic balanceChangedDate;
@dynamic walletBackupReminderWasShown;
@dynamic biometricAuthConfigured;
@dynamic biometricAuthEnabled;
@dynamic autoLockAppInterval;
@dynamic shortcuts;
@dynamic balanceHidden;
@dynamic tapToHideBalanceShown;
@dynamic shouldDisplayOnboarding;
@dynamic paymentsScreenCurrentTab;
@dynamic resyncingWallet;
@dynamic selectedPaymentCurrency;
@dynamic shouldDisplayReclassifyYourTransactionsFlow;
@dynamic dateReclassifyYourTransactionsFlowActivated;
@dynamic dateHistoricalRatesActivated;
@dynamic exploreDashMerchantsInfoShown;
@dynamic coinbaseInfoShown;

#ifdef DASHPAY
@dynamic dashpayUsername;
@dynamic dashpayRegistrationCompleted;
@dynamic mostRecentViewedNotificationDate;
@dynamic shouldShowInvitationsBadge;
@dynamic dashPayRegistrationOpenedOnce;
@dynamic dpInvitationFlowEnabled;
@dynamic confirmationAcceptContactRequestIsOn;
#endif

#pragma mark - Init

- (instancetype)init {
    NSDictionary *defaults = @{
        DW_KEYPATH(self, selectedPaymentCurrency) : [NSNumber numberWithUnsignedInt:DWPaymentCurrencyDash],
        DW_KEYPATH(self, walletNeedsBackup) : @YES,
        DW_KEYPATH(self, userHasBalance) : @NO,
        DW_KEYPATH(self, localNotificationsEnabled) : @YES,
        DW_KEYPATH(self, autoLockAppInterval) : @60, // 1 min
        DW_KEYPATH(self, shouldDisplayOnboarding) : @YES,
        DW_KEYPATH(self, shouldDisplayReclassifyYourTransactionsFlow) : @YES,
        DW_KEYPATH(self, coinbaseInfoShown) : @NO,
#if DASHPAY
        DW_KEYPATH(self, confirmationAcceptContactRequestIsOn) : @YES,
#endif
    };

    self = [super initWithUserDefaults:nil defaults:defaults];
    return self;
}

+ (instancetype)sharedInstance {
    static DWGlobalOptions *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

#pragma mark - DSDynamicOptions

- (NSString *)defaultsKeyForPropertyName:(NSString *)propertyName {
    if ([propertyName isEqualToString:DW_KEYPATH(self, localNotificationsEnabled)]) {
        return LOCAL_NOTIFICATIONS_ENABLED_KEY;
    }

    return [NSString stringWithFormat:@"DW_GLOB_%@", propertyName];
}

#pragma mark - Non-dynamic

- (BOOL)lockScreenDisabled {
    NSError *error = nil;
    int64_t result = getKeychainInt(LOCKSCREEN_DISABLED_KEY, &error);
    if (error != nil) {
        return NO;
    }

    return (result == 1);
}

- (void)setLockScreenDisabled:(BOOL)lockScreenDisabled {
    setKeychainInt(lockScreenDisabled ? 1 : 0, LOCKSCREEN_DISABLED_KEY, NO);
}

- (BOOL)spendingConfirmationDisabled {
    NSError *error = nil;
    int64_t result = getKeychainInt(SPENDING_CONFIRMATION_DISABLED_KEY, &error);
    if (error != nil) {
        return NO;
    }

    return (result == 1);
}

- (void)setSpendingConfirmationDisabled:(BOOL)spendingConfirmationDisabled {
    setKeychainInt(spendingConfirmationDisabled ? 1 : 0, SPENDING_CONFIRMATION_DISABLED_KEY, NO);
}

- (void)setActivationDateForReclassifyYourTransactionsFlowIfNeeded:(NSDate *)date {
    if (self.dateReclassifyYourTransactionsFlowActivated == nil) {
        self.dateReclassifyYourTransactionsFlowActivated = date;
    }
}

- (void)setActivationDateForHistoricalRates:(NSDate *)date {
    if (self.dateHistoricalRatesActivated == nil) {
        self.dateHistoricalRatesActivated = date;
    }
}

#pragma mark - Methods

- (void)restoreToDefaults {
    self.walletNeedsBackup = YES;
    self.userHasBalance = NO;
    self.balanceChangedDate = nil;
    self.walletBackupReminderWasShown = NO;
    self.shortcuts = nil;
    self.localNotificationsEnabled = YES;
    self.balanceHidden = NO;
    self.tapToHideBalanceShown = NO;
    self.resyncingWallet = NO;
    self.selectedPaymentCurrency = DWPaymentCurrencyDash;
    self.shouldDisplayReclassifyYourTransactionsFlow = YES;
    self.dateReclassifyYourTransactionsFlowActivated = nil;
    self.dateHistoricalRatesActivated = nil;
    self.exploreDashMerchantsInfoShown = NO;
    self.coinbaseInfoShown = NO;

#ifdef DASHPAY
    self.dashpayUsername = nil;
    self.dashpayRegistrationCompleted = NO;
    self.mostRecentViewedNotificationDate = nil;
    self.dashPayRegistrationOpenedOnce = NO;
    self.confirmationAcceptContactRequestIsOn = YES;
#endif
}

@end

NS_ASSUME_NONNULL_END
