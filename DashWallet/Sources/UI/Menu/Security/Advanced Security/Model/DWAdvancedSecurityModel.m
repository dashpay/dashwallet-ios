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

#import "DWAdvancedSecurityModel.h"

#import <DashSync/DSBiometricsAuthenticator.h>
#import <DashSync/DashSync.h>

#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

uint64_t const DW_DEFAULT_BIOMETRICS_SPENDING_LIMIT = DUFFS / 2;

@implementation DWAdvancedSecurityModel

@synthesize lockTimerTimeInterval = _lockTimerTimeInterval;

- (instancetype)init {
    self = [super initWithHasTouchID:DSBiometricsAuthenticator.touchIDEnabled
                           hasFaceID:DSBiometricsAuthenticator.faceIDEnabled];
    if (self) {
        DWGlobalOptions *globalOptions = [DWGlobalOptions sharedInstance];
        _lockTimerTimeInterval = @(globalOptions.autoLockAppInterval);
        NSAssert([self.lockTimerTimeIntervals indexOfObject:_lockTimerTimeInterval] != NSNotFound,
                 @"Internal inconsistency");
    }
    return self;
}

- (DWSecurityLevel)securityLevel {
    NSInteger lockTime;
    if (!self.autoLogout) {
        lockTime = NSIntegerMax;
    }
    else {
        lockTime = self.lockTimerTimeInterval.integerValue;
    }

    uint64_t spendingConfirmation;
    if (!self.spendingConfirmationEnabled) {
        spendingConfirmation = UINT64_MAX;
    }
    else {
        spendingConfirmation = self.spendingConfirmationLimit.longLongValue;
    }

    return [self securityLevelForLockTime:lockTime spendingConfirmation:spendingConfirmation];
}

#pragma mark - Lock Screen

- (BOOL)autoLogout {
    return ![[DWGlobalOptions sharedInstance] lockScreenDisabled];
}

- (void)setAutoLogout:(BOOL)autoLogout {
    [[DWGlobalOptions sharedInstance] setLockScreenDisabled:!autoLogout];
}

- (void)setLockTimerTimeInterval:(NSNumber *)lockTimerTimeInterval {
    _lockTimerTimeInterval = lockTimerTimeInterval;

    [DWGlobalOptions sharedInstance].autoLockAppInterval = lockTimerTimeInterval.integerValue;
}

#pragma mark - Spending Confirmation

- (BOOL)spendingConfirmationEnabled {
    return ![[DWGlobalOptions sharedInstance] spendingConfirmationDisabled];
}

- (void)setSpendingConfirmationEnabled:(BOOL)spendingConfirmationEnabled {
    [[DWGlobalOptions sharedInstance] setSpendingConfirmationDisabled:!spendingConfirmationEnabled];
}

- (BOOL)canConfigureSpendingConfirmation {
    return [DWGlobalOptions sharedInstance].biometricAuthEnabled;
}

- (NSNumber *)spendingConfirmationLimit {
    DSChainsManager *chainsManager = [DSChainsManager sharedInstance];
    const uint64_t value = chainsManager.spendingLimit;
    return @(value);
}

- (void)setSpendingConfirmationLimit:(NSNumber *)spendingConfirmationLimit {
    const long long limit = spendingConfirmationLimit.longLongValue;
    [[DSChainsManager sharedInstance] setSpendingLimitIfAuthenticated:limit];
}

#pragma mark - Actions

- (void)resetToDefault {
    self.autoLogout = YES;
    self.lockTimerTimeInterval = @(60);

    self.spendingConfirmationEnabled = YES;
    self.spendingConfirmationLimit = @(DW_DEFAULT_BIOMETRICS_SPENDING_LIMIT);
}

#pragma mark - Private

/// Max value for a type considered as Disabled state
- (DWSecurityLevel)securityLevelForLockTime:(NSInteger)lockTime
                       spendingConfirmation:(uint64_t)spendingConfirmation {
    // Wallet Level Authentication | OFF / Spending Confirmation | OFF = NONE
    if (lockTime == NSIntegerMax && spendingConfirmation == UINT64_MAX) {
        return DWSecurityLevel_None;
    }

    // Wallet Level Authentication | ON / Spending Confirmation | ON / Lock Timer | OFF = VERY HIGH
    if (lockTime == 0 && spendingConfirmation == 0) {
        return DWSecurityLevel_VeryHigh;
    }

    // Wallet Level Authentication | ON / Spending Confirmation | ON = HIGH
    if (lockTime != NSIntegerMax && spendingConfirmation != UINT64_MAX) {
        return DWSecurityLevel_High;
    }

    // Wallet Level Authentication | ON / Spending Confirmation | OFF / Lock Timer | 1 hr-24 hr = LOW
    if (lockTime >= 60 * 60 && spendingConfirmation == UINT64_MAX) {
        return DWSecurityLevel_Low;
    }

    // Wallet Level Authentication | ON / Spending Confirmation | OFF / Lock Timer | OFF - <1 hr = MED
    // Wallet Level Authentication | OFF / Spending Confirmation | ON = MED
    // Wallet Level Authentication | ON / Spending Confirmation | OFF = MED

    return DWSecurityLevel_Medium;
}

@end

NS_ASSUME_NONNULL_END
