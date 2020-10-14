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
#import <DashSync/DSDataController.h>
#import <DashSync/DashSync.h>

#import "DWAdvancedSecurityModel.h"
#import "DWBalanceDisplayOptionsProtocol.h"
#import "DWBiometricAuthModel.h"
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

@interface DWSecurityMenuModel ()

@property (assign, nonatomic) BOOL biometricsEnabled;
@property (readonly, strong, nonatomic) id<DWBalanceDisplayOptionsProtocol> balanceDisplayOptions;
@property (readonly, nonatomic, strong) DWBiometricAuthModel *biometricAuthModel;

@end

@implementation DWSecurityMenuModel

- (instancetype)initWithBalanceDisplayOptions:(id<DWBalanceDisplayOptionsProtocol>)balanceDisplayOptions {
    self = [super init];
    if (self) {
        _balanceDisplayOptions = balanceDisplayOptions;

        _biometricAuthModel = [[DWBiometricAuthModel alloc] init];

        const LABiometryType biometryType = _biometricAuthModel.biometryType;
        _hasTouchID = biometryType == LABiometryTypeTouchID;
        _hasFaceID = biometryType == LABiometryTypeFaceID;
    }
    return self;
}

- (BOOL)biometricsEnabled {
    return [DWGlobalOptions sharedInstance].biometricAuthEnabled;
}

- (void)setBiometricsEnabled:(BOOL)biometricsEnabled {
    [DWGlobalOptions sharedInstance].biometricAuthEnabled = biometricsEnabled;

    const uint64_t limit = biometricsEnabled ? DW_DEFAULT_BIOMETRICS_SPENDING_LIMIT : 0;
    [[DSAuthenticationManager sharedInstance] setBiometricSpendingLimitIfAuthenticated:limit];
}

- (BOOL)balanceHidden {
    return [DWGlobalOptions sharedInstance].balanceHidden;
}

- (void)setBalanceHidden:(BOOL)balanceHidden {
    [DWGlobalOptions sharedInstance].balanceHidden = balanceHidden;
    self.balanceDisplayOptions.balanceHidden = balanceHidden;
}

- (void)changePinContinueBlock:(void (^)(BOOL allowed))continueBlock {
    [[DSAuthenticationManager sharedInstance]
              authenticateWithPrompt:nil
        usingBiometricAuthentication:NO
                      alertIfLockout:YES
                          completion:^(BOOL authenticated, BOOL usedBiometrics, BOOL cancelled) {
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
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    [authenticationManager
              authenticateWithPrompt:nil
        usingBiometricAuthentication:NO
                      alertIfLockout:YES
                          completion:^(BOOL authenticatedOrSuccess, BOOL usedBiometrics, BOOL cancelled) {
                              if (authenticatedOrSuccess) {
                                  if (enabled) {
                                      __weak typeof(self) weakSelf = self;
                                      [self.biometricAuthModel enableBiometricAuth:^(BOOL success) {
                                          __strong typeof(weakSelf) strongSelf = weakSelf;
                                          if (!strongSelf) {
                                              return;
                                          }

                                          strongSelf.biometricsEnabled = success;

                                          if (completion) {
                                              completion(success);
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
                              else {
                                  if (completion) {
                                      completion(NO);
                                  }
                              }
                          }];
}

+ (void)hardReset {
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);

    NSArray *secItemClasses = @[ (__bridge id)kSecClassGenericPassword,
                                 (__bridge id)kSecClassInternetPassword,
                                 (__bridge id)kSecClassCertificate,
                                 (__bridge id)kSecClassKey,
                                 (__bridge id)kSecClassIdentity ];
    for (id secItemClass in secItemClasses) {
        NSDictionary *spec = @{(__bridge id)kSecClass : secItemClass};
        SecItemDelete((__bridge CFDictionaryRef)spec);
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtURL:[DSDataController storeURL] error:nil];
    [fileManager removeItemAtURL:[DSDataController storeWALURL] error:nil];
    [fileManager removeItemAtURL:[DSDataController storeSHMURL] error:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

@end

NS_ASSUME_NONNULL_END
