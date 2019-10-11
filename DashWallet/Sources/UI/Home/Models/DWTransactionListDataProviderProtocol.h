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
#import <UIKit/UIColor.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DSTransactionDirection);

@class DSTransaction;

@protocol DWTransactionListDataItem <NSObject>

/// From (received)
@property (readonly, nonatomic, strong) NSArray<NSString *> *outputReceiveAddresses;
/// To (sent)
@property (readonly, nonatomic, strong) NSArray<NSString *> *inputSendAddresses;
@property (readonly, nonatomic, assign) uint64_t dashAmount;
@property (readonly, nonatomic, assign) DSTransactionDirection direction;
@property (readonly, nonatomic, strong) UIColor *dashAmountTintColor;
@property (readonly, nonatomic, copy) NSString *fiatAmount;

@end

@protocol DWTransactionListDataProviderProtocol <NSObject>

- (id<DWTransactionListDataItem>)transactionDataForTransaction:(DSTransaction *)transaction;

- (NSString *)dateForTransaction:(DSTransaction *)transaction;

- (NSAttributedString *)dashAmountStringFrom:(id<DWTransactionListDataItem>)transactionData
                                        font:(UIFont *)font;

@end

NS_ASSUME_NONNULL_END
