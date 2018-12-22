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

#import "DWUpholdTransactionObject.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWUpholdTransactionObject

- (nullable instancetype)initWithDictionary:(NSDictionary *)dictionary {
    NSString *identifier = dictionary[@"id"];
    NSDictionary *origin = dictionary[@"origin"];
    if (!identifier || !origin) {
        return nil;
    }
    
    self = [super init];
    if (self) {
        _identifier = identifier;
        _base = [NSDecimalNumber decimalNumberWithString:origin[@"base"]];
        _amount = [NSDecimalNumber decimalNumberWithString:origin[@"amount"]];
        _fee = [NSDecimalNumber decimalNumberWithString:origin[@"fee"]];
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
