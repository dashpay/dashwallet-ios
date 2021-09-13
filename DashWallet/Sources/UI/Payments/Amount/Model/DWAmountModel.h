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

#import "DWAmountDescriptionViewModel.h"
#import "DWAmountInputControlSource.h"
#import "DWAmountObject.h"
#import "DWDPBasicUserItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAmountModel : NSObject

@property (readonly, nonatomic, assign) BOOL showsMaxButton;
@property (readonly, assign, nonatomic) DWAmountType activeType;
@property (readonly, strong, nonatomic) DWAmountObject *amount;
@property (readonly, nullable, nonatomic, strong) id<DWDPBasicUserItem> contactItem;
@property (readonly, nullable, nonatomic, strong) DWAmountDescriptionViewModel *descriptionModel;

- (BOOL)amountIsValidForProceeding NS_REQUIRES_SUPER;
- (BOOL)isSwapToLocalCurrencyAllowed;
- (void)swapActiveAmountType;

- (void)updateAmountWithReplacementString:(NSString *)string range:(NSRange)range;

- (void)selectAllFundsWithPreparationBlock:(void (^)(void))preparationBlock;

- (BOOL)isEnteredAmountLessThenMinimumOutputAmount;
- (NSString *)minimumOutputAmountFormattedString;

- (void)reloadAttributedData;
- (void)rebuildAmounts;

- (instancetype)initWithContactItem:(nullable id<DWDPBasicUserItem>)contactItem NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
