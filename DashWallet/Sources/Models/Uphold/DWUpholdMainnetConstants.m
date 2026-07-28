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

@implementation DWUpholdMainnetConstants

+ (NSString *)authorizeURLFormat {
    return DWUpholdInfoPlistValue(@"AUTHORIZE_URL_FORMAT");
}

+ (NSString *)baseURLString {
    return @"https://api.uphold.com/";
}

+ (NSString *)clientID {
    return DWUpholdInfoPlistValue(@"CLIENT_ID");
}

+ (NSString *)clientSecret {
    return DWUpholdInfoPlistValue(@"CLIENT_SECRET");
}

+ (NSString *)transactionURLFormat {
    return @"https://uphold.com/reserve/transactions/%@";
}

+ (NSString *)logoutURLString {
    return @"https://uphold.com/";
}

@end

NS_ASSUME_NONNULL_END
