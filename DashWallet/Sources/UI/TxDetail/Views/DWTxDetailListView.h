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

#import <UIKit/UIKit.h>

#import "DWTitleDetailCellView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTxDetailListView : UIStackView

@property (readonly, copy, nonatomic) NSArray<DWTitleDetailCellView *> *arrangedSubviews;

@property (nonatomic, assign) DWTitleDetailCellViewPadding contentPadding;

- (void)configureWithInputAddressesCount:(NSUInteger)inputAddressesCount
                    outputAddressesCount:(NSUInteger)outputAddressesCount
                                  hasFee:(BOOL)hasFee
                                 hasDate:(BOOL)hasDate;

- (void)updateDataWithInputAddresses:(NSArray<id<DWTitleDetailItem>> *)inputAddresses
                     outputAddresses:(NSArray<id<DWTitleDetailItem>> *)outputAddresses
                                 fee:(nullable id<DWTitleDetailItem>)fee
                                date:(nullable id<DWTitleDetailItem>)date;

@end

NS_ASSUME_NONNULL_END
