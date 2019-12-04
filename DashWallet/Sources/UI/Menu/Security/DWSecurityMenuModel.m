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

#import "DWSecurityMenuModel.h"

#import <DashSync/DSAuthenticationManager+Private.h>
#import <DashSync/DashSync.h>

#import "DWBalanceDisplayOptions.h"
#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBiometricsOption : NSObject <DWSelectorFormItem>

@property (readonly, nonatomic, assign) uint64_t value;

@end

@implementation DWBiometricsOption

@synthesize title = _title;

- (instancetype)initWithTitle:(NSString *)title value:(uint64_t)value {
    self = [super init];
    if (self) {
        _title = title;
        _value = value;
    }
    return self;
}

@end

#pragma mark - Model

static uint64_t const BIOMETRICS_ENABLED_SPENDING_LIMIT = 1; // 1 DUFF
static uint64_t const BIOMETRICS_DISABLED_SPENDING_LIMIT = 0;

@interface DWSecurityMenuModel ()

@property (assign, nonatomic) BOOL biometricsEnabled;
@property (readonly, strong, nonatomic) DWBalanceDisplayOptions *balanceDisplayOptions;

@end

@implementation DWSecurityMenuModel

- (instancetype)initWithBalanceDisplayOptions:(DWBalanceDisplayOptions *)balanceDisplayOptions {
    self = [super init];
    if (self) {
        _balanceDisplayOptions = balanceDisplayOptions;

        _hasTouchID = [DSAuthenticationManager sharedInstance].touchIdEnabled;
        _hasFaceID = [DSAuthenticationManager sharedInstance].faceIdEnabled;
    }
    return self;
}

- (BOOL)biometricsEnabled {
    return [DWGlobalOptions sharedInstance].biometricAuthEnabled;
}

- (void)setBiometricsEnabled:(BOOL)biometricsEnabled {
    [DWGlobalOptions sharedInstance].biometricAuthEnabled = biometricsEnabled;
    [[DSChainsManager sharedInstance] setSpendingLimitIfAuthenticated:biometricsEnabled ? DUFFS : BIOMETRICS_DISABLED_SPENDING_LIMIT];
}

- (BOOL)balanceHidden {
    return [DWGlobalOptions sharedInstance].balanceHidden;
}

- (void)setBalanceHidden:(BOOL)balanceHidden {
    [DWGlobalOptions sharedInstance].balanceHidden = balanceHidden;
    self.balanceDisplayOptions.balanceHidden = balanceHidden;
}

- (NSString *)biometricAuthSpendingLimit {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSChainsManager *chainsManager = [DSChainsManager sharedInstance];

    uint64_t spendingLimit = chainsManager.spendingLimit;
    if (spendingLimit == BIOMETRICS_ENABLED_SPENDING_LIMIT) {
        // display it as 0
        spendingLimit = 0;
    }

    return [priceManager stringForDashAmount:spendingLimit];
}

- (void)changePinContinueBlock:(void (^)(BOOL allowed))continueBlock {
    [[DSAuthenticationManager sharedInstance]
              authenticateWithPrompt:nil
        usingBiometricAuthentication:NO
                      alertIfLockout:YES
                          completion:^(BOOL authenticated, BOOL cancelled) {
                              if (continueBlock) {
                                  DSAuthenticationManager *authManager = [DSAuthenticationManager sharedInstance];
                                  authManager.didAuthenticate = NO;

                                  continueBlock(authenticated);
                              }
                          }];
}

- (void)setupNewPin:(NSString *)pin {
    DSAuthenticationManager *authManager = [DSAuthenticationManager sharedInstance];
    __unused BOOL success = [authManager setupNewPin:pin];
    NSAssert(success, @"Pin setup failed");
}

- (void)setBiometricsEnabled:(BOOL)enabled completion:(void (^)(BOOL success))completion {
    if (enabled) {
        DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
        [authenticationManager authenticateWithPrompt:nil
                         usingBiometricAuthentication:NO
                                       alertIfLockout:YES
                                           completion:^(BOOL authenticatedOrSuccess, BOOL cancelled) {
                                               if (authenticatedOrSuccess) {
                                                   self.biometricsEnabled = YES;
                                               }

                                               if (completion) {
                                                   completion(authenticatedOrSuccess);
                                               }
                                           }];
    }
    else {
        self.biometricsEnabled = NO;
        if (completion) {
            completion(YES);
        }
    }
}

- (void)requestBiometricsSpendingLimitOptions:(void (^)(BOOL authenticated, NSArray<id<DWSelectorFormItem>> *_Nullable options, NSUInteger selectedIndex))completion {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    DSChainsManager *chainsManager = [DSChainsManager sharedInstance];

    [authenticationManager
              authenticateWithPrompt:nil
        usingBiometricAuthentication:NO
                      alertIfLockout:YES
                          completion:^(BOOL authenticated, BOOL cancelled) {
                              if (authenticated) {
                                  NSArray<id<DWSelectorFormItem>> *options = [self biometricsSpendingLimitOptions];
                                  const uint64_t limit = chainsManager.spendingLimit;
                                  NSUInteger selectedIndex;
                                  if (limit <= BIOMETRICS_ENABLED_SPENDING_LIMIT) {
                                      selectedIndex = 0;
                                  }
                                  else {
                                      selectedIndex = (NSUInteger)log10(limit) - 6;
                                  }
                                  if (completion) {
                                      completion(YES, options, selectedIndex);
                                  }
                              }
                              else {
                                  if (completion) {
                                      completion(NO, nil, NSNotFound);
                                  }
                              }
                          }];
}

- (void)setBiometricsSpendingLimitForOption:(id<DWSelectorFormItem>)option {
    DWBiometricsOption *biometricOption = (DWBiometricsOption *)option;
    NSAssert([biometricOption isKindOfClass:DWBiometricsOption.class], @"Invalid option");
    const uint64_t limit = biometricOption.value;
    [[DSChainsManager sharedInstance] setSpendingLimitIfAuthenticated:limit];
}

#pragma mark - Private

- (void)resetCurrentPin {
}

- (NSArray<id<DWSelectorFormItem>> *)biometricsSpendingLimitOptions {
    NSMutableArray<id<DWSelectorFormItem>> *options = [NSMutableArray array];

    DWBiometricsOption *option =
        [[DWBiometricsOption alloc] initWithTitle:NSLocalizedString(@"Always require passcode", nil)
                                            value:BIOMETRICS_ENABLED_SPENDING_LIMIT];
    [options addObject:option];

    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    const uint64_t values[] = {DUFFS / 10, DUFFS, DUFFS * 10};
    for (int i = 0; i < 3; i++) {
        const uint64_t value = values[i];
        NSString *title = [NSString stringWithFormat:@"%@ (%@)",
                                                     [priceManager stringForDashAmount:value],
                                                     [priceManager localCurrencyStringForDashAmount:value]];
        DWBiometricsOption *option = [[DWBiometricsOption alloc] initWithTitle:title value:value];
        [options addObject:option];
    }

    return [options copy];
}

@end

NS_ASSUME_NONNULL_END
