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

#import <Foundation/Foundation.h>

#import "DWSelectorFormItem.h"

NS_ASSUME_NONNULL_BEGIN

@class DWBalanceDisplayOptions;

@interface DWSecurityMenuModel : NSObject

@property (readonly, assign, nonatomic) BOOL hasTouchID;
@property (readonly, assign, nonatomic) BOOL hasFaceID;
@property (readonly, copy, nonatomic) NSString *biometricAuthSpendingLimit;
@property (readonly, assign, nonatomic) BOOL biometricsEnabled;
@property (assign, nonatomic) BOOL balanceHidden;

- (void)changePinContinueBlock:(void (^)(BOOL allowed))continueBlock;
- (void)setupNewPin:(NSString *)pin;

- (void)setBiometricsEnabled:(BOOL)enabled completion:(void (^)(BOOL success))completion;

- (void)requestBiometricsSpendingLimitOptions:(void (^)(BOOL authenticated, NSArray<id<DWSelectorFormItem>> *_Nullable options, NSUInteger selectedIndex))completion;
- (void)setBiometricsSpendingLimitForOption:(id<DWSelectorFormItem>)option;

- (instancetype)initWithBalanceDisplayOptions:(DWBalanceDisplayOptions *)balanceDisplayOptions;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
