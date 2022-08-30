//
//  Created by Samuel Westrich
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

#import "DWUpholdMainnetConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWUpholdMainnetConstants

+ (NSString *)authorizeURLFormat {
    return @"https://uphold.com/authorize/c184650d0cb44e73d8e5cb2021753a721c41f74a?scope=accounts:read%%20cards:read%%20cards:write%%20transactions:deposit%%20transactions:read%%20transactions:transfer:application%%20transactions:transfer:others%%20transactions:transfer:self%%20transactions:withdraw%%20transactions:commit:otp%%20user:read&state=%@";
}

+ (NSString *)baseURLString {
    return @"https://api.uphold.com/";
}

+ (NSString *)clientID {
    return @"c184650d0cb44e73d8e5cb2021753a721c41f74a";
}

+ (NSString *)clientSecret {
    return @"da72feee8236f7709df6d0c235a8896ad45f2a91";
}

+ (NSString *)buyCardURLFormat {
    return @"https://uphold.com/dashboard/cards/%@/add";
}

+ (NSString *)transactionURLFormat {
    return @"https://uphold.com/reserve/transactions/%@";
}

+ (NSString *)logoutURLString {
    return @"https://uphold.com/dashboard";
}

@end

NS_ASSUME_NONNULL_END
