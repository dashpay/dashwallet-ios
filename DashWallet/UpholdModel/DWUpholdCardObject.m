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

#import "DWUpholdCardObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdCardObject ()

@property (nullable, copy, nonatomic) NSString *address;

@end

@implementation DWUpholdCardObject

- (nullable instancetype)initWithDictionary:(NSDictionary *)dictionary {
    NSString *identifier = dictionary[@"id"];
    NSString *available = dictionary[@"available"];
    if (!identifier || !available) {
        return nil;
    }

    NSString *address = dictionary[@"address"][@"dash"];

    self = [super init];
    if (self) {
        _identifier = identifier;
        _available = [NSDecimalNumber decimalNumberWithString:available];
        _address = address;

        NSDictionary *settings = dictionary[@"settings"];
        if ([settings isKindOfClass:NSDictionary.class]) {
            NSNumber *position = settings[@"position"];
            _position = position ? position.integerValue : NSNotFound;
            _starred = [settings[@"starred"] boolValue];
        }
        else {
            _position = NSNotFound;
        }
    }
    return self;
}

#pragma mark - Internal

- (void)updateAddress:(NSString *)address {
    NSParameterAssert(address);
    self.address = address;
}

@end

NS_ASSUME_NONNULL_END
