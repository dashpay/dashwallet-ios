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

typedef NS_ENUM(NSUInteger, DWUpholdConfirmTransferModelState) {
    DWUpholdConfirmTransferModelState_None,
    DWUpholdConfirmTransferModelState_Loading,
    DWUpholdConfirmTransferModelState_Success,
    DWUpholdConfirmTransferModelState_Fail,
    DWUpholdConfirmTransferModelState_OTP,
};

@class DWUpholdCardObject;
@class DWUpholdTransactionObject;
@class DWUpholdConfirmTransferModel;

@protocol DWUpholdConfirmTransferModelStateNotifier <NSObject>

- (void)upholdConfirmTransferModel:(DWUpholdConfirmTransferModel *)model
                    didUpdateState:(DWUpholdConfirmTransferModelState)state;

@end

@interface DWUpholdConfirmTransferModel : NSObject

@property (nullable, nonatomic, weak) id<DWUpholdConfirmTransferModelStateNotifier> stateNotifier;
@property (readonly, strong, nonatomic) DWUpholdTransactionObject *transaction;

- (instancetype)initWithCard:(DWUpholdCardObject *)card
                 transaction:(DWUpholdTransactionObject *)transaction;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)confirmWithOTPToken:(nullable NSString *)otpToken;
- (void)cancel;
- (void)resetState;

@end

NS_ASSUME_NONNULL_END
