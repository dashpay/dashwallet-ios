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

#import "DWEnvironment.h"
#import "DWUpholdMainnetConstants.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *DWUpholdInfoPlistValue(NSString *key) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Uphold-Info" ofType:@"plist"];
    if (path.length == 0) {
        return @"";
    }

    NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:path];
    id value = dictionary[key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }

    return @"";
}

@implementation DWUpholdConstants

+ (NSString *)authorizeURLFormat {
    if ([[DWEnvironment sharedInstance].currentChain isTestnet]) {
        return @"https://sandbox.uphold.com/authorize/7aadd33b84e942632ed7ffd9b09578bd64be2099?scope=accounts:read%%20cards:read%%20cards:write%%20transactions:deposit%%20transactions:read%%20transactions:transfer:application%%20transactions:transfer:others%%20transactions:transfer:self%%20transactions:withdraw%%20transactions:commit:otp%%20user:read&state=%@";
    }
    else if ([[DWEnvironment sharedInstance].currentChain isMainnet]) {
        return [DWUpholdMainnetConstants authorizeURLFormat];
    }
    return @"";
}

+ (NSString *)baseURLString {
    if ([[DWEnvironment sharedInstance].currentChain isTestnet]) {
        return @"https://api-sandbox.uphold.com/";
    }
    else if ([[DWEnvironment sharedInstance].currentChain isMainnet]) {
        return [DWUpholdMainnetConstants baseURLString];
    }
    return @"";
}

+ (NSString *)clientID {
    if ([[DWEnvironment sharedInstance].currentChain isTestnet]) {
        return @"7aadd33b84e942632ed7ffd9b09578bd64be2099";
    }
    else if ([[DWEnvironment sharedInstance].currentChain isMainnet]) {
        return [DWUpholdMainnetConstants clientID];
    }
    return @"";
}

+ (NSString *)clientSecret {
    if ([[DWEnvironment sharedInstance].currentChain isTestnet]) {
        return DWUpholdInfoPlistValue(@"SANDBOX_CLIENT_SECRET");
    }
    else if ([[DWEnvironment sharedInstance].currentChain isMainnet]) {
        return [DWUpholdMainnetConstants clientSecret];
    }
    return @"";
}

+ (NSString *)buyCardURLFormat {
    if ([[DWEnvironment sharedInstance].currentChain isTestnet]) {
        return @"https://sandbox.uphold.com/dashboard/cards/%@/add";
    }
    else if ([[DWEnvironment sharedInstance].currentChain isMainnet]) {
        return [DWUpholdMainnetConstants buyCardURLFormat];
    }
    return @"";
}

+ (NSString *)transactionURLFormat {
    if ([[DWEnvironment sharedInstance].currentChain isTestnet]) {
        return @"https://sandbox.uphold.com/reserve/transactions/%@";
    }
    else if ([[DWEnvironment sharedInstance].currentChain isMainnet]) {
        return [DWUpholdMainnetConstants transactionURLFormat];
    }
    return @"";
}

@end

NS_ASSUME_NONNULL_END
