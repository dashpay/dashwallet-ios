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

#import "DWAmountObject.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWAmountType) {
    // Amount in Dash
    DWAmountTypeMain,
    // Amount in local currency
    DWAmountTypeSupplementary,
};

typedef NS_ENUM(NSUInteger, DWAmountModelActionState) {
    DWAmountModelActionStateLocked,
    DWAmountModelActionStateUnlockedInactive,
    DWAmountModelActionStateUnlockedActive,
};

@interface DWAmountBaseModel : NSObject

@property (readonly, assign, nonatomic) DWAmountType activeType;
@property (readonly, strong, nonatomic) DWAmountObject *amount;
@property (readonly, assign, nonatomic) DWAmountModelActionState actionState;
@property (nullable, readonly, copy, nonatomic) NSAttributedString *balanceString;
@property (readonly, copy, nonatomic) NSString *actionButtonTitle;

- (BOOL)isSwapToLocalCurrencyAllowed;
- (void)swapActiveAmountType;

- (void)updateAmountWithReplacementString:(NSString *)string range:(NSRange)range;

- (void)unlock;

- (void)selectAllFunds;

@end

NS_ASSUME_NONNULL_END
