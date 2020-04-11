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

#import "DWBiometricAuthModel.h"

#import <DashSync/DSBiometricsAuthenticator.h>
#import <DashSync/DashSync.h>

#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

#define SHOULD_SIMULATE_BIOMETRICS 1

static uint64_t const DEFAULT_BIOMETRIC_SPENDING_LIMIT = DUFFS / 2; // 0.5 Dash

@implementation DWBiometricAuthModel

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

+ (BOOL)shouldEnableBiometricAuthentication {
    return ![DWGlobalOptions sharedInstance].biometricAuthConfigured;
}

+ (BOOL)biometricAuthenticationAvailable {
#if (TARGET_OS_SIMULATOR && SHOULD_SIMULATE_BIOMETRICS)
    return YES;
#else
    return DSBiometricsAuthenticator.biometricsAuthenticationEnabled;
#endif /* (TARGET_OS_SIMULATOR && SHOULD_SIMULATE_BIOMETRICS) */
}

- (LABiometryType)biometryType {
#if (TARGET_OS_SIMULATOR && SHOULD_SIMULATE_BIOMETRICS)
    return LABiometryTypeTouchID;
#else
    return DSBiometricsAuthenticator.biometryType;
#endif /* (TARGET_OS_SIMULATOR && SHOULD_SIMULATE_BIOMETRICS) */
}

- (void)enableBiometricAuth:(void (^)(BOOL success))completion {
    NSParameterAssert(completion);

    NSString *reason = nil;
    switch (DSBiometricsAuthenticator.biometryType) {
        case LABiometryTypeTouchID:
            reason = NSLocalizedString(@"Enable Touch ID", nil);
            break;
        case LABiometryTypeFaceID:
            reason = NSLocalizedString(@"Enable Face ID", nil);
            break;
        default:
            reason = @" ";
            break;
    }

    [DSBiometricsAuthenticator
        performBiometricsAuthenticationWithReason:reason
                                    fallbackTitle:nil
                                       completion:^(DSBiometricsAuthenticationResult result) {
                                           const BOOL success = result == DSBiometricsAuthenticationResultSucceeded;
                                           [DWGlobalOptions sharedInstance].biometricAuthConfigured = YES;
                                           [DWGlobalOptions sharedInstance].biometricAuthEnabled = success;

                                           const uint64_t spendingLimit = success ? DEFAULT_BIOMETRIC_SPENDING_LIMIT : 0;
                                           [[DSAuthenticationManager sharedInstance]
                                               setBiometricSpendingLimitIfAuthenticated:spendingLimit];

                                           completion(success);
                                       }];
}

- (void)disableBiometricAuth {
    [DWGlobalOptions sharedInstance].biometricAuthConfigured = YES;
}

@end

NS_ASSUME_NONNULL_END
