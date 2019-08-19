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
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSString *string = [priceManager stringForDashAmount:self.value];

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:string];

    const NSRange range = [attributedString.string rangeOfString:DASH];
    const BOOL dashSymbolFound = range.location != NSNotFound;
    NSAssert(dashSymbolFound, @"Dash number formatter invalid");
    if (dashSymbolFound) {
        const CGFloat scaleFactor = 0.665;
        const CGFloat side = font.pointSize * scaleFactor;
        const CGSize symbolSize = CGSizeMake(side, side);
        NSTextAttachment *dashSymbol = [[NSTextAttachment alloc] init];
        dashSymbol.bounds = CGRectMake(0, 0, symbolSize.width, symbolSize.height);
        dashSymbol.image = [[UIImage imageNamed:@"Dash-Light"] ds_imageWithTintColor:tintColor];
        NSAttributedString *dashSymbolAttributedString = [NSAttributedString attributedStringWithAttachment:dashSymbol];

        [attributedString replaceCharactersInRange:range withAttributedString:dashSymbolAttributedString];

        const NSRange fullRange = NSMakeRange(0, attributedString.length);
        [attributedString addAttribute:NSForegroundColorAttributeName value:tintColor range:fullRange];
        [attributedString addAttribute:NSFontAttributeName value:font range:fullRange];
    }

    return [attributedString copy];
}

- (NSString *)fiatAmountString {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSString *result = [priceManager localCurrencyStringForDashAmount:self.value];

    return result;
}

@end

NS_ASSUME_NONNULL_END
