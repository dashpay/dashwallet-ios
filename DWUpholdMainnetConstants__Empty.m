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

+ (NSDictionary *)plistDictionary {
    static NSDictionary *dict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Uphold-Info" ofType:@"plist"];
        dict = path ? [NSDictionary dictionaryWithContentsOfFile:path] : @{};
    });
    return dict;
}

+ (NSString *)clientID {
    return [self plistDictionary][@"CLIENT_ID"] ?: @"";
}

+ (NSString *)clientSecret {
    return [self plistDictionary][@"CLIENT_SECRET"] ?: @"";
}

+ (NSString *)authorizeURLFormat {
    NSString *clientId = [self clientID];
    if (clientId.length == 0) {
        return @"";
    }
    NSString *prefix = [NSString stringWithFormat:@"https://wallet.uphold.com/authorize/%@", clientId];
    return [prefix stringByAppendingString:@"?scope=accounts:read%%20cards:read%%20cards:write%%20transactions:deposit%%20transactions:read%%20transactions:transfer:application%%20transactions:transfer:others%%20transactions:transfer:self%%20transactions:withdraw%%20transactions:commit:otp%%20user:read&state=%@"];
}

+ (NSString *)baseURLString {
    return @"https://api.uphold.com/";
}

+ (NSString *)buyCardURLFormat {
    return @"https://wallet.uphold.com/dashboard/cards/%@/add";
}

+ (NSString *)transactionURLFormat {
    return @"https://wallet.uphold.com/reserve/transactions/%@";
}

+ (NSString *)logoutURLString {
    return @"https://wallet.uphold.com/dashboard";
}

@end

NS_ASSUME_NONNULL_END
