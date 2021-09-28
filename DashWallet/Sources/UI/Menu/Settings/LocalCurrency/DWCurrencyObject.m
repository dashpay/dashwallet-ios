//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWCurrencyObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWCurrencyObject ()

@property (weak, nullable, nonatomic) id<DWCurrencyItemPriceProvider> provider;
@property (nonatomic, strong) NSNumber *price;

@end

NS_ASSUME_NONNULL_END

@implementation DWCurrencyObject

@synthesize code = _code;
@synthesize name = _name;
@synthesize flagName = _flagName;

- (instancetype)initWithPriceObject:(DSCurrencyPriceObject *)object
                           flagName:(NSString *)flagName
                           provider:(id<DWCurrencyItemPriceProvider>)provider {
    self = [super init];
    if (self) {
        _code = object.code;
        _name = object.name;
        _price = object.price;
        _flagName = flagName;
        _provider = provider;
    }
    return self;
}

- (NSString *)priceString {
    return [self.provider formatPrice:self.price];
}

@end
