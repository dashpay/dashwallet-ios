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

#import "DWAmountInputValidator.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAmountModel ()

@property (assign, nonatomic) DWAmountType activeType;
@property (strong, nonatomic) DWAmountObject *amount;
@property (assign, nonatomic, getter=isLocked) BOOL locked;

@property (nullable, nonatomic, strong) DWAmountDescriptionViewModel *descriptionModel;

@property (strong, nonatomic) DWAmountInputValidator *dashValidator;
@property (strong, nonatomic) DWAmountInputValidator *localCurrencyValidator;
@property (nullable, strong, nonatomic) DWAmountObject *amountEnteredInDash;
@property (nullable, strong, nonatomic) DWAmountObject *amountEnteredInLocalCurrency;

- (void)updateCurrentAmount NS_REQUIRES_SUPER;

@end

NS_ASSUME_NONNULL_END
