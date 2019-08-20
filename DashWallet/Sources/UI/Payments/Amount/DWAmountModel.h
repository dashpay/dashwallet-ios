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

#import "DWAmountInputControlSource.h"
#import "DWAmountObject.h"
#import "DWAmountSendingOptionsModel.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWAmountInputIntent) {
    DWAmountInputIntentRequest,
    DWAmountInputIntentSend,
};

@interface DWAmountModel : NSObject

@property (readonly, assign, nonatomic) DWAmountInputIntent inputIntent;
@property (readonly, assign, nonatomic) DWAmountType activeType;
@property (readonly, strong, nonatomic) DWAmountObject *amount;
@property (readonly, assign, nonatomic, getter=isLocked) BOOL locked;
@property (nullable, readonly, copy, nonatomic) NSAttributedString *balanceString;
@property (readonly, copy, nonatomic) NSString *actionButtonTitle;
@property (nullable, readonly, strong, nonatomic) DWAmountSendingOptionsModel *sendingOptions;

- (instancetype)initWithInputIntent:(DWAmountInputIntent)inputIntent
                 sendingDestination:(nullable NSString *)sendingDestination
                     paymentDetails:(nullable DSPaymentProtocolDetails *)paymentDetails;

- (BOOL)isSwapToLocalCurrencyAllowed;
- (void)swapActiveAmountType;

- (void)updateAmountWithReplacementString:(NSString *)string range:(NSRange)range;

- (void)unlock;

- (void)selectAllFunds;

- (BOOL)isEnteredAmountLessThenMinimumOutputAmount;
- (NSString *)minimumOutputAmountFormattedString;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
