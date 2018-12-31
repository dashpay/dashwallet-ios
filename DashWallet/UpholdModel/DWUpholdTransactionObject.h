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

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdTransactionObject : NSObject

@property (readonly, copy, nonatomic) NSString *identifier;
@property (readonly, strong, nonatomic) NSDecimalNumber *amount;
@property (readonly, strong, nonatomic) NSDecimalNumber *fee;
@property (readonly, strong, nonatomic) NSDecimalNumber *total;

@property (assign, nonatomic) BOOL feeWasDeductedFromAmount;

- (nullable instancetype)initWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
