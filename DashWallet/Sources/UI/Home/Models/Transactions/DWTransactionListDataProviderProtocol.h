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

@import UIKit;
#import "DWTransactionListDataItem.h"
//#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@protocol DWTransactionListDataProviderProtocol <NSObject>

- (id<DWTransactionListDataItem>)transactionDataForTransaction:(DSTransaction *)transaction;

- (NSDate *)dateForTransaction:(DSTransaction *)transaction;
- (NSString *)shortDateStringForTransaction:(DSTransaction *)transaction;
- (NSString *)longDateStringForTransaction:(DSTransaction *)transaction;
- (NSString *)ISO8601StringForTransaction:(DSTransaction *)transaction;
- (NSString *)dashAmountStringFrom:(id<DWTransactionListDataItem>)transactionData;
- (NSAttributedString *)dashAmountStringFrom:(id<DWTransactionListDataItem>)transactionData
                                        font:(UIFont *)font;
- (NSAttributedString *)dashAmountStringFrom:(id<DWTransactionListDataItem>)transactionData
                                   tintColor:(UIColor *)color
                                        font:(UIFont *)font;

@end

NS_ASSUME_NONNULL_END
