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

#import "DWSetPinModel.h"

#import "dashwallet-Swift.h"
#import <DashSync/DSAuthenticationManager+Private.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWSetPinModel

- (void)dealloc {
    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

+ (BOOL)shouldSetPin {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    NSError *error = nil;
    BOOL hasPin = [authenticationManager hasPin:&error];
    if (error) {
        return NO;
    }
    return !hasPin;
}

- (BOOL)setPin:(NSString *)pin {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];

    // Capture the current PIN BEFORE setupNewPin overwrites it. Will be
    // empty/nil during first-time setup (no PIN yet) — that case is
    // handled by skipping the SwiftDashSDK mirror entirely below.
    NSError *getPinError = nil;
    NSString *oldPin = [authenticationManager getPin:&getPinError];

    BOOL success = [authenticationManager setupNewPin:pin];
    if (!success) {
        return NO;
    }

    // Mirror the PIN change into SwiftDashSDK so its encrypted seed
    // can still be decrypted after the change. Self-discriminates:
    //   - oldPin empty/nil → first-time setup (intent: createNewWallet),
    //     no SwiftDashSDK seed exists yet; the wallet creator will
    //     populate it later in the onboarding flow with the new PIN.
    //   - old == new → no-op "change", nothing to do.
    // Both branches fall through this single guard.
    if (oldPin.length > 0 && ![oldPin isEqualToString:pin]) {
        [DWSwiftDashSDKPinChanger changePinFrom:oldPin to:pin];
    }

    return YES;
}

@end

NS_ASSUME_NONNULL_END
