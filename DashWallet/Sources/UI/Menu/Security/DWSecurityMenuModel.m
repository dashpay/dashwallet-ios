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
@property (readonly, strong, nonatomic) DWBalanceDisplayOptions *balanceDisplayOptions;
@property (readonly, nonatomic, strong) DWBiometricAuthModel *biometricAuthModel;

@end

@implementation DWSecurityMenuModel

- (instancetype)initWithBalanceDisplayOptions:(DWBalanceDisplayOptions *)balanceDisplayOptions {
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
                                                   if (completion) {
                                                       completion(NO);
                                                   }
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

@end

NS_ASSUME_NONNULL_END
