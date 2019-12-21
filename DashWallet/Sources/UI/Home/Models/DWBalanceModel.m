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

#import "DWBalanceModel.h"

#import <DashSync/DashSync.h>
#import <DashSync/UIImage+DSUtils.h>
#import <UIKit/UIKit.h>

#import "NSAttributedString+DWBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWBalanceModel

- (instancetype)initWithValue:(uint64_t)value {
    self = [super init];
    if (self) {
        _value = value;
    }
    return self;
}

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

- (NSAttributedString *)dashAmountStringWithFont:(UIFont *)font tintColor:(UIColor *)tintColor {
    return [NSAttributedString dw_dashAttributedStringForAmount:self.value tintColor:tintColor font:font];
}

- (NSString *)fiatAmountString {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSString *result = [priceManager localCurrencyStringForDashAmount:self.value];

    return result;
}

@end

NS_ASSUME_NONNULL_END
