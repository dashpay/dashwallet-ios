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

#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

#define SHOULD_SIMULATE_BIOMETRICS 1

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
    LAContext *context = [[LAContext alloc] init];
    BOOL available = [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:nil];

    return available;
#endif /* (TARGET_OS_SIMULATOR && SHOULD_SIMULATE_BIOMETRICS) */
}

- (LABiometryType)biometryType {
#if (TARGET_OS_SIMULATOR && SHOULD_SIMULATE_BIOMETRICS)
    return LABiometryTypeTouchID;
#else
    LAContext *context = [[LAContext alloc] init];
    [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:nil];

    return context.biometryType;
#endif /* (TARGET_OS_SIMULATOR && SHOULD_SIMULATE_BIOMETRICS) */
}

- (void)enableBiometricAuth:(void (^)(void))completion {
    NSParameterAssert(completion);

    LAContext *context = [[LAContext alloc] init];
    NSString *reason = nil;
    switch (context.biometryType) {
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

    [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
            localizedReason:reason
                      reply:^(BOOL success, NSError *_Nullable error) {
                          [DWGlobalOptions sharedInstance].biometricAuthConfigured = YES;
                          [DWGlobalOptions sharedInstance].biometricAuthEnabled = success;

                          [[DSChainsManager sharedInstance] setSpendingLimitIfAuthenticated:success ? DUFFS : 0];

                          dispatch_async(dispatch_get_main_queue(), completion);
                      }];
}

- (void)disableBiometricAuth {
    [DWGlobalOptions sharedInstance].biometricAuthConfigured = YES;
}

@end

NS_ASSUME_NONNULL_END
