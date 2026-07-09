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
#import "dashwallet-Swift.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

// backward compatibility
static NSString *const LOCAL_NOTIFICATIONS_ENABLED_KEY = @"USER_DEFAULTS_LOCAL_NOTIFICATIONS_KEY";
static NSString *const LOCKSCREEN_DISABLED_KEY = @"org.dash.wallet.lockscreen-disabled";
static NSString *const SPENDING_CONFIRMATION_DISABLED_KEY = @"org.dash.wallet.spending-confirmation-disabled";

// Legacy app-global UserDefaults keys for the two per-wallet flags. Written by
// the DSDynamicOptions default registration (`DW_GLOB_<property>`); still read
// as the migration source and as the fallback when no wallet is active yet
// (onboarding sets these before a wallet id exists). Not deleted — kept dormant.
static NSString *const LEGACY_WALLET_NEEDS_BACKUP_KEY = @"DW_GLOB_walletNeedsBackup";
static NSString *const LEGACY_USER_HAS_BALANCE_KEY = @"DW_GLOB_userHasBalance";

// Per-wallet key prefixes: the effective key is `<prefix><walletIdHex>`,
// scoped by the active wallet (`DWWalletEnvironment.activeWalletIdHex`).
static NSString *const PER_WALLET_NEEDS_BACKUP_PREFIX = @"DW_WALLET_NEEDS_BACKUP_";
static NSString *const PER_WALLET_HAS_BALANCE_PREFIX = @"DW_WALLET_HAS_BALANCE_";

@implementation DWGlobalOptions

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
@dynamic shortcutBannerState;

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
        DW_KEYPATH(self, shortcutBannerState) : @0,
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

#pragma mark - Per-wallet flags (walletNeedsBackup / userHasBalance)

// These two flags describe a per-wallet fact (does THIS wallet need a backup;
// does THIS wallet hold a balance), not an app-global preference. They are
// scoped by the active walletId so switching wallets shows the correct state.
//
// Storage: `<prefix><activeWalletIdHex>` in UserDefaults, resolved live on
// every access (DSDynamicOptions reads UserDefaults live; there is no in-memory
// cache to invalidate on wallet switch — the next read simply resolves the new
// active wallet's key). One-time migration: on first read for a wallet whose
// per-wallet key is absent, seed it from the legacy app-global key's effective
// value, so an existing single-wallet install keeps its backup/balance state.
// The legacy key stays put (dormant) and remains the fallback while no wallet
// is active yet — onboarding sets these flags before a wallet id is resolved.

/// The active wallet's per-wallet key for `prefix`, or nil when no wallet is
/// active yet (fresh install / post-wipe window) — callers fall back to the
/// legacy global key in that case.
- (nullable NSString *)perWalletKeyWithPrefix:(NSString *)prefix {
    NSString *walletIdHex = (NSString *)DWWalletEnvironment.activeWalletIdHex;
    if (walletIdHex.length == 0) {
        return nil;
    }
    return [prefix stringByAppendingString:walletIdHex];
}

/// Read a per-wallet BOOL flag. With no active wallet, reads the legacy global
/// key directly. With an active wallet, reads the per-wallet key — seeding it
/// once from the legacy key's effective value when it has never been written.
- (BOOL)perWalletBoolForPrefix:(NSString *)prefix legacyKey:(NSString *)legacyKey {
    NSUserDefaults *defaults = self.userDefaults;
    NSString *key = [self perWalletKeyWithPrefix:prefix];
    if (key == nil) {
        return [defaults boolForKey:legacyKey];
    }
    if ([defaults objectForKey:key] == nil) {
        // First read for this wallet: seed from the legacy global value (which
        // carries the registered default, e.g. walletNeedsBackup = YES).
        BOOL seeded = [defaults boolForKey:legacyKey];
        [defaults setBool:seeded forKey:key];
        return seeded;
    }
    return [defaults boolForKey:key];
}

/// Write a per-wallet BOOL flag. With no active wallet, writes the legacy
/// global key (so onboarding's pre-wallet writes are preserved and later
/// seeded into the per-wallet key on first read once a wallet is active).
- (void)setPerWalletBool:(BOOL)value forPrefix:(NSString *)prefix legacyKey:(NSString *)legacyKey {
    NSUserDefaults *defaults = self.userDefaults;
    NSString *key = [self perWalletKeyWithPrefix:prefix];
    [defaults setBool:value forKey:(key ?: legacyKey)];
}

- (BOOL)walletNeedsBackup {
    return [self perWalletBoolForPrefix:PER_WALLET_NEEDS_BACKUP_PREFIX
                              legacyKey:LEGACY_WALLET_NEEDS_BACKUP_KEY];
}

- (void)setWalletNeedsBackup:(BOOL)walletNeedsBackup {
    [self setPerWalletBool:walletNeedsBackup
                 forPrefix:PER_WALLET_NEEDS_BACKUP_PREFIX
                 legacyKey:LEGACY_WALLET_NEEDS_BACKUP_KEY];
}

- (BOOL)userHasBalance {
    return [self perWalletBoolForPrefix:PER_WALLET_HAS_BALANCE_PREFIX
                              legacyKey:LEGACY_USER_HAS_BALANCE_KEY];
}

- (void)setUserHasBalance:(BOOL)userHasBalance {
    [self setPerWalletBool:userHasBalance
                 forPrefix:PER_WALLET_HAS_BALANCE_PREFIX
                 legacyKey:LEGACY_USER_HAS_BALANCE_KEY];
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
    self.shortcutBannerState = 0;

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
