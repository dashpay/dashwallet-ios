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

#import "DWInputValidator.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWUpholdTransferModelValidationResult) {
    DWUpholdTransferModelValidationResultValid,
    DWUpholdTransferModelValidationResultInvalidAmount,
    DWUpholdTransferModelValidationResultInsufficientFunds,
};

typedef NS_ENUM(NSUInteger, DWUpholdRequestTransferModelState) {
    DWUpholdRequestTransferModelStateNone,
    DWUpholdRequestTransferModelStateLoading,
    DWUpholdRequestTransferModelStateSuccess,
    DWUpholdRequestTransferModelStateFail,
    DWUpholdRequestTransferModelStateFailInsufficientFunds,
    DWUpholdRequestTransferModelStateOTP,
};

@class DWUpholdCardObject;
@class DWUpholdTransactionObject;

@interface DWUpholdRequestTransferModel : NSObject

@property (readonly, copy, nonatomic) NSString *availableString;
@property (readonly, strong, nonatomic) id<DWInputValidator> amountValidator;
@property (readonly, assign, nonatomic) DWUpholdRequestTransferModelState state;
@property (readonly, nullable, strong, nonatomic) DWUpholdTransactionObject *transaction;

- (instancetype)initWithCard:(DWUpholdCardObject *)card;

- (NSAttributedString *)availableDashString;
- (DWUpholdTransferModelValidationResult)validateInput:(NSString *)input;
- (void)createTransactionForAmount:(NSString *)amount otpToken:(nullable NSString *)otpToken;
- (void)resetState;

@end

NS_ASSUME_NONNULL_END
