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

#import "DWGlobalOptions.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

#define SHOULD_SIMULATE_BIOMETRICS 1
#define MIN_FAIL_COUNT_TO_WIPE 6

static NSTimeInterval const CHECK_INTERVAL = 1.0;

@interface DWLockScreenModel ()

@property (nonatomic, assign) BOOL checkingAuth;

@end

@implementation DWLockScreenModel

- (BOOL)isBiometricAuthenticationAllowed {
    return [DWGlobalOptions sharedInstance].biometricAuthEnabled &&
           [DWAuthenticationService shared].isBiometricAuthenticationAllowed;
}

- (LABiometryType)biometryType {
#if (TARGET_OS_SIMULATOR && SHOULD_SIMULATE_BIOMETRICS)
    return LABiometryTypeTouchID;
#else
    return [DWAuthenticationService shared].biometryType;
#endif /* (TARGET_OS_SIMULATOR && SHOULD_SIMULATE_BIOMETRICS) */
}

- (void)authenticateUsingBiometricsOnlyCompletion:(void (^)(BOOL authenticated))completion {
    [[DWAuthenticationService shared] authenticateUsingBiometricsOnly:^(BOOL authenticated) {
        if (completion) {
            completion(authenticated);
        }
    }];
}

- (void)startCheckingAuthState {
    if (self.checkingAuth) {
        return;
    }
    self.checkingAuth = YES;

    [self checkAuthState];
}

- (void)stopCheckingAuthState {
    self.checkingAuth = NO;

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkAuthState) object:nil];
}

- (BOOL)checkPin:(NSString *)inputPin {
    [self stopCheckingAuthState];

    BOOL isPinValid = [[DWAuthenticationService shared] verifyPinString:inputPin];
    if (!isPinValid) {
        [self startCheckingAuthState];
    }

    return isPinValid;
}

- (nullable NSString *)lockoutErrorMessage {
    return [DWAuthenticationService shared].lockoutErrorMessage;
}

- (BOOL)isAllowedToWipe {
    return [DWAuthenticationService shared].failCount >= MIN_FAIL_COUNT_TO_WIPE;
}

#pragma mark - Private

- (void)checkAuthState {
    if (!self.checkingAuth) {
        return;
    }

    DWAuthPrecheck *precheck = [[DWAuthenticationService shared] authenticationPrecheckObjc];

    [self.delegate lockScreenModel:self
        shouldContinueAuthentication:precheck.shouldContinueAuthentication
                       authenticated:NO
                       shouldLockout:precheck.shouldLockout
                     attemptsMessage:precheck.attemptsMessage];

    [self performSelector:@selector(checkAuthState)
               withObject:nil
               afterDelay:CHECK_INTERVAL];
}

@end

NS_ASSUME_NONNULL_END
