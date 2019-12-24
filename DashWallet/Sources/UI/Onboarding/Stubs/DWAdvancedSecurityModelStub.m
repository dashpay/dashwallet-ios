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

#import "DWAdvancedSecurityModelStub.h"

#import <DashSync/DashSync.h>

#import "DWBiometricAuthModel.h"
#import "DevicesCompatibility.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWAdvancedSecurityModelStub

- (instancetype)init {
    DWBiometricAuthModel *authModel = [[DWBiometricAuthModel alloc] init];
    const LABiometryType biometryType = authModel.biometryType;
    BOOL hasTouchID = biometryType == LABiometryTypeTouchID;
    BOOL hasFaceID = biometryType == LABiometryTypeFaceID;
#if SNAPSHOT
    if (DEVICE_HAS_HOME_INDICATOR) {
        hasTouchID = NO;
        hasFaceID = YES;
    }
    else {
        hasTouchID = YES;
        hasFaceID = NO;
    }
#endif /* SNAPSHOT */
    self = [super initWithHasTouchID:hasTouchID hasFaceID:hasFaceID];
    return self;
}

- (DWSecurityLevel)securityLevel {
    return DWSecurityLevel_High;
}

#pragma mark - Lock Screen

- (BOOL)autoLogout {
    return YES;
}

- (void)setAutoLogout:(BOOL)autoLogout {
}

- (NSNumber *)lockTimerTimeInterval {
    return @(60);
}

- (void)setLockTimerTimeInterval:(NSNumber *)lockTimerTimeInterval {
}

#pragma mark - Spending Confirmation

- (BOOL)spendingConfirmationEnabled {
    return YES;
}

- (void)setSpendingConfirmationEnabled:(BOOL)spendingConfirmationEnabled {
}

- (BOOL)canConfigureSpendingConfirmation {
#if SNAPSHOT
    return YES;
#else
    return DWBiometricAuthModel.biometricAuthenticationAvailable;
#endif /* SNAPSHOT */
}

- (NSNumber *)spendingConfirmationLimit {
    return @(DUFFS / 2);
}

- (void)setSpendingConfirmationLimit:(NSNumber *)spendingConfirmationLimit {
}

#pragma mark - Actions

- (void)resetToDefault {
}

@end

NS_ASSUME_NONNULL_END
