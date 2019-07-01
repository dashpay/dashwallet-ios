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

#import "DWUpholdConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWUpholdConstants

+ (NSString *)authorizeURLFormat {
    return @"https://sandbox.uphold.com/authorize/7aadd33b84e942632ed7ffd9b09578bd64be2099?scope=accounts:read%%20cards:read%%20cards:write%%20transactions:deposit%%20transactions:read%%20transactions:transfer:application%%20transactions:transfer:others%%20transactions:transfer:self%%20transactions:withdraw%%20transactions:commit:otp%%20user:read&state=%@";
}

+ (NSString *)baseURLString {
    return @"https://api-sandbox.uphold.com/";
}

+ (NSString *)clientID {
    return @"7aadd33b84e942632ed7ffd9b09578bd64be2099";
}

+ (NSString *)clientSecret {
    return @"7db0b6bbf766233c0eafcad6b9d8667d526c899e";
}

+ (NSString *)buyCardURLFormat {
    return @"https://sandbox.uphold.com/dashboard/cards/%@/add";
}

+ (NSString *)transactionURLFormat {
    return @"https://sandbox.uphold.com/reserve/transactions/%@";
}

+ (NSString *)logoutURLString {
    return @"https://sandbox.uphold.com/";
}

@end

NS_ASSUME_NONNULL_END
