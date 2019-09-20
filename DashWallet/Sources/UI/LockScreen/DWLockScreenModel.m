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

#import "DWLockScreenModel.h"

#import <DashSync/DSAuthenticationManager+Private.h>
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

#define SHOULD_SIMULATE_BIOMETRICS 1

@implementation DWLockScreenModel

- (BOOL)isBiometricAuthenticationAllowed {
    return [[DSAuthenticationManager sharedInstance] isBiometricAuthenticationAllowed];
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

- (void)authenticateUsingBiometricsOnlyCompletion:(void (^)(BOOL authenticated))completion {
    [[DSAuthenticationManager sharedInstance] authenticateUsingBiometricsOnlyWithPrompt:nil
                                                                             completion:^(BOOL authenticatedOrSuccess, BOOL cancelled) {
                                                                                 if (completion) {
                                                                                     completion(authenticatedOrSuccess);
                                                                                 }
                                                                             }];
}

- (BOOL)checkPin:(NSString *)inputPin {
    // TODO: refactor authentication logic into separate "action"
    // TODO: handle wrong attempts here
    NSError *error = nil;
    NSString *pin = [[DSAuthenticationManager sharedInstance] getPin:&error];
    if (error) {
        return NO;
    }

    BOOL isPinValid = [inputPin isEqualToString:pin];
    if (isPinValid) {
        DSAuthenticationManager *authManager = [DSAuthenticationManager sharedInstance];

        [authManager.failedPins removeAllObjects];
        authManager.didAuthenticate = YES;

        [authManager setFailCount:0];
        [authManager setFailHeight:0];

        [[DSChainsManager sharedInstance] resetSpendingLimitsIfAuthenticated];
        [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSince1970]
                                                  forKey:PIN_UNLOCK_TIME_KEY];
    }

    return isPinValid;
}

@end

NS_ASSUME_NONNULL_END
