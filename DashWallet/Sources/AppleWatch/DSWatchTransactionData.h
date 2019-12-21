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

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSInteger {
    BRAWTransactionTypeSent,
    BRAWTransactionTypeReceive,
    BRAWTransactionTypeMove,
    BRAWTransactionTypeInvalid
} BRAWTransactionType;

@protocol DSWatchTransactionData <NSObject>

@property (readonly, nonatomic, copy) NSString *amountText;
@property (readonly, nonatomic, copy) NSString *amountTextInLocalCurrency;
@property (readonly, nonatomic, copy) NSString *dateText;
@property (readonly, assign, nonatomic) BRAWTransactionType type;

@end

NS_ASSUME_NONNULL_END
