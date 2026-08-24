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

#import "DWRecoverModel.h"

#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const DW_WIPE = @"wipe";
NSString *const DW_WIPE_STRONG = @"exterminate!";
NSString *const DW_WATCH = @"watch";
NSInteger const DW_PHRASE_MIN_LENGTH = 12;
NSInteger const DW_PHRASE_MULTIPLE = 3;

@implementation DWRecoverModel

- (instancetype)initWithAction:(DWRecoverAction)action {
    self = [super init];
    if (self) {
        _action = action;
    }
    return self;
}

- (void)dealloc {
    DWLog(@"☠️ %@", NSStringFromClass(self.class));
}

- (BOOL)hasWallet {
    return DWWalletEnvironment.hasWallet;
}

- (BOOL)hasPinSet {
    return [[DWAuthenticationService shared] hasPin];
}

// `isWalletEmpty`, wipe/reset-PIN phrase authorization, and mnemonic helpers
// live in DWRecoverModel+Mnemonic.swift.

- (void)wipeWallet {
    DWSwiftDashSDKWalletWipeAuthorization authorization =
        self.action == DWRecoverAction_SupportWipe
            ? DWSwiftDashSDKWalletWipeAuthorizationConfirmedDeleteAll
            : DWSwiftDashSDKWalletWipeAuthorizationRecoveryFlow;
    [DWSwiftDashSDKWalletWiper
        wipeWalletWithAuthorization:authorization];
}

- (NSString *)wipeAcceptPhrase {
    return NSLocalizedString(@"I accept that I will lose my coins if I no longer possess the recovery phrase", nil);
}

@end

NS_ASSUME_NONNULL_END
