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
    return @"";
}

+ (NSString *)baseURLString {
    return @"https://api.uphold.com/";
}

+ (NSString *)clientID {
    return @"";
}

+ (NSString *)clientSecret {
    return @"";
}

+ (NSString *)buyCardURLFormat {
    return @"https://uphold.com/dashboard/cards/%@/add";
}

+ (NSString *)transactionURLFormat {
    return @"https://uphold.com/reserve/transactions/%@";
}

+ (NSString *)logoutURLString {
    return @"https://uphold.com/";
}

@end

NS_ASSUME_NONNULL_END
