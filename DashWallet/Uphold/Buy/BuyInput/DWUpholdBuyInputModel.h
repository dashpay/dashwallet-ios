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

#import "DWInputValidator.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWUpholdBuyInputModelState) {
    DWUpholdBuyInputModelStateNone,
    DWUpholdBuyInputModelStateLoading,
    DWUpholdBuyInputModelStateSuccess,
    DWUpholdBuyInputModelStateFail,
    DWUpholdBuyInputModelStateOTP,
};

@class DWUpholdCardObject;
@class DWUpholdTransactionObject;
@class DWUpholdAccountObject;

@interface DWUpholdBuyInputModel : NSObject

@property (readonly, assign, nonatomic) DWUpholdBuyInputModelState state;

@property (readonly, nullable, strong, nonatomic) DWUpholdTransactionObject *transaction;

- (instancetype)initWithCard:(DWUpholdCardObject *)card
                     account:(DWUpholdAccountObject *)account;

- (void)updateAmountWithReplacementString:(NSString *)string range:(NSRange)range;
- (BOOL)isAmountInputValid:(NSString *)input;
- (void)createTransactionForAmount:(NSString *)amount cvc:(NSString *)cvc otpToken:(nullable NSString *)otpToken;
- (void)resetState;

@end

NS_ASSUME_NONNULL_END
