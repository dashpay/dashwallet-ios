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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DWSelectorFormCellModel;

@interface DWSettingsControllerModel : NSObject

@property (readonly, assign, nonatomic) BOOL hasTouchID;
@property (readonly, assign, nonatomic) BOOL hasFaceID;
@property (readonly, assign, nonatomic) BOOL advancedFeaturesEnabled;
@property (readonly, copy, nonatomic) NSString *networkName;
@property (readonly, copy, nonatomic) NSString *localCurrencyCode;
@property (readonly, copy, nonatomic) NSString *biometricAuthSpendingLimit;

@property (assign, nonatomic) BOOL enableNotifications;

- (void)enableAdvancedFeatures;

- (void)switchToMainnetWithCompletion:(void (^)(BOOL success))completion;
- (void)switchToTestnetWithCompletion:(void (^)(BOOL success))completion;

- (void)requestBiometricAuthSpendingLimitOptions:(void (^)(BOOL authenticated, NSArray<NSString *> *_Nullable options, NSUInteger selectedIndex))completion;
- (void)setBiometricAuthSpendingLimitForOptionIndex:(NSUInteger)index;

- (void)requestLocalCurrencyOptions:(void (^)(NSArray<NSString *> *_Nullable options, NSUInteger selectedIndex))completion;
- (void)setLocalCurrencyForOptionIndex:(NSUInteger)index;

- (void)changePasscode;
- (void)rescanBlockchain;

@end

NS_ASSUME_NONNULL_END
