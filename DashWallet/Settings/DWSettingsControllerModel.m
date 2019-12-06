//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWSettingsControllerModel.h"

#import "DSCurrencyPriceObject.h"

NS_ASSUME_NONNULL_BEGIN

#define ENABLED_ADVANCED_FEATURES @"ENABLED_ADVANCED_FEATURES"

@interface DWSettingsControllerModel ()

@end

@implementation DWSettingsControllerModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _hasTouchID = [DSAuthenticationManager sharedInstance].touchIdEnabled;
        _hasFaceID = [DSAuthenticationManager sharedInstance].faceIdEnabled;
    }
    return self;
}

- (BOOL)advancedFeaturesEnabled {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if ([userDefaults objectForKey:ENABLED_ADVANCED_FEATURES]) {
        return [userDefaults boolForKey:ENABLED_ADVANCED_FEATURES];
    }
    return NO;
}

- (NSString *)networkName {
    return [DWEnvironment sharedInstance].currentChain.name;
}

- (NSString *)localCurrencyCode {
    return [DSPriceManager sharedInstance].localCurrencyCode;
}

- (NSString *)biometricAuthSpendingLimit {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSChainsManager *chainsManager = [DSChainsManager sharedInstance];

    return [priceManager stringForDashAmount:chainsManager.spendingLimit];
}

- (BOOL)enableNotifications {
    return [[NSUserDefaults standardUserDefaults] boolForKey:USER_DEFAULTS_LOCAL_NOTIFICATIONS_KEY];
}

- (void)setEnableNotifications:(BOOL)enableNotifications {
    [[NSUserDefaults standardUserDefaults] setBool:enableNotifications forKey:USER_DEFAULTS_LOCAL_NOTIFICATIONS_KEY];
}

- (void)enableAdvancedFeatures {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:ENABLED_ADVANCED_FEATURES];
}

- (void)switchToMainnetWithCompletion:(void (^)(BOOL success))completion {
    [[DWEnvironment sharedInstance] switchToMainnetWithCompletion:completion];
}

- (void)switchToTestnetWithCompletion:(void (^)(BOOL success))completion {
    [[DWEnvironment sharedInstance] switchToTestnetWithCompletion:completion];
}

- (void)requestBiometricAuthSpendingLimitOptions:(void (^)(BOOL authenticated, NSArray<NSString *> *_Nullable options, NSUInteger selectedIndex))completion {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    DSChainsManager *chainsManager = [DSChainsManager sharedInstance];

    [authenticationManager authenticateWithPrompt:nil usingBiometricAuthentication:NO alertIfLockout:YES completion:^(BOOL authenticated, BOOL cancelled) {
        if (authenticated) {
            NSArray<NSString *> *options = [self biometricAuthSpendingLimitOptions];
            NSUInteger selectedIndex = (log10(chainsManager.spendingLimit) < 6) ? 0 : (NSUInteger)log10(chainsManager.spendingLimit) - 6;
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

- (void)setBiometricAuthSpendingLimitForOptionIndex:(NSUInteger)index {
    [[DSChainsManager sharedInstance] setSpendingLimitIfAuthenticated:(index > 0) ? pow(10, index + 6) : 0];
}

- (void)requestLocalCurrencyOptions:(void (^)(NSArray<NSString *> *_Nullable options, NSUInteger selectedIndex))completion {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSArray<NSString *> *options = [priceManager.prices valueForKeyPath:@"codeAndName"];
    DSCurrencyPriceObject *price = [priceManager priceForCurrencyCode:priceManager.localCurrencyCode];
    NSUInteger selectedIndex = price ? [priceManager.prices indexOfObject:price] : 0;
    if (completion) {
        completion(options, selectedIndex);
    }
}

- (void)setLocalCurrencyForOptionIndex:(NSUInteger)index {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    BOOL validIndex = index < priceManager.prices.count;
    NSAssert(validIndex, @"Invalid local currency option");
    if (validIndex) {
        DSCurrencyPriceObject *selectedPrice = priceManager.prices[index];
        priceManager.localCurrencyCode = selectedPrice.code;
    }
}

- (void)changePasscode {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    [authenticationManager setPinWithCompletion:nil];
}

- (void)rescanBlockchain {
    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
    [chainManager rescan];
}

#pragma mark - Private

- (NSArray<NSString *> *)biometricAuthSpendingLimitOptions {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSArray<NSString *> *options = @[
        NSLocalizedString(@"Always require passcode", nil),
        [NSString stringWithFormat:@"%@ (%@)",
                                   [priceManager stringForDashAmount:DUFFS / 10],
                                   [priceManager localCurrencyStringForDashAmount:DUFFS / 10]],
        [NSString stringWithFormat:@"%@ (%@)",
                                   [priceManager stringForDashAmount:DUFFS],
                                   [priceManager localCurrencyStringForDashAmount:DUFFS]],
        [NSString stringWithFormat:@"%@ (%@)",
                                   [priceManager stringForDashAmount:DUFFS * 10],
                                   [priceManager localCurrencyStringForDashAmount:DUFFS * 10]],
    ];

    return options;
}

@end

NS_ASSUME_NONNULL_END
