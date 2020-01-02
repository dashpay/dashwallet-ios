//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWAmountModel.h"

NS_ASSUME_NONNULL_BEGIN

@class DWUpholdCardObject;
@class DWUpholdAmountModel;

typedef NS_ENUM(NSUInteger, DWUpholdRequestTransferModelState) {
    DWUpholdRequestTransferModelState_None,
    DWUpholdRequestTransferModelState_Loading,
    DWUpholdRequestTransferModelState_Success,
    DWUpholdRequestTransferModelState_Fail,
    DWUpholdRequestTransferModelState_FailInsufficientFunds,
    DWUpholdRequestTransferModelState_OTP,
};

@protocol DWUpholdAmountModelStateNotifier <NSObject>

- (void)upholdAmountModel:(DWUpholdAmountModel *)model
           didUpdateState:(DWUpholdRequestTransferModelState)state;

@end


@interface DWUpholdAmountModel : DWAmountModel

@property (nullable, nonatomic, weak) id<DWUpholdAmountModelStateNotifier> stateNotifier;

- (void)resetAttributedValues;

- (void)createTransactionWithOTPToken:(nullable NSString *)otpToken;
- (void)resetCreateTransactionState;

- (instancetype)initWithCard:(DWUpholdCardObject *)card;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
