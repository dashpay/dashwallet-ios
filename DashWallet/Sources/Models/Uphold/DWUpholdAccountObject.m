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

#import "DWUpholdAccountObject.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWUpholdAccountObject

- (nullable instancetype)initWithDictionary:(NSDictionary *)dictionary {
    NSString *identifier = dictionary[@"id"];
    NSString *brand = dictionary[@"brand"];
    NSString *currency = dictionary[@"currency"];
    NSString *label = dictionary[@"label"];
    NSString *type = dictionary[@"type"];
    NSString *status = dictionary[@"status"];

    if (!identifier || !brand || !currency || !label || !type || !status) {
        return nil;
    }

    self = [super init];
    if (self) {
        _identifier = identifier;
        _brand = brand;
        _currency = currency;
        _label = label;
        if ([type isEqualToString:@"card"]) {
            _type = DWUpholdAccountObjectTypeCard;
        }
        else {
            _type = DWUpholdAccountObjectTypeOther;
        }
        if ([status isEqualToString:@"ok"]) {
            _status = DWUpholdAccountObjectStatusOK;
        }
        else {
            _status = DWUpholdAccountObjectStatusFailed;
        }
    }
    return self;
}


@end

NS_ASSUME_NONNULL_END
