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

#import "NSAttributedString+DWBuilder.h"

#import "UIColor+DWStyle.h"
#import <DashSync/DashSync.h>
#import <DashSync/NSString+Dash.h>
#import <DashSync/UIImage+DSUtils.h>

NS_ASSUME_NONNULL_BEGIN

#define NBSP @"\xC2\xA0" // no-break space (utf-8)

@implementation NSAttributedString (DWBuilder)

+ (NSAttributedString *)dw_dashAttributedStringForAmount:(uint64_t)amount
                                               tintColor:(UIColor *)tintColor
                                              symbolSize:(CGSize)symbolSize {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSString *dashAmount = [priceManager stringForDashAmount:amount];
    NSAttributedString *result = [dashAmount
        attributedStringForDashSymbolWithTintColor:tintColor
                                    dashSymbolSize:symbolSize];

    return result;
}

+ (NSAttributedString *)dw_dashAttributedStringForAmount:(uint64_t)amount
                                               tintColor:(UIColor *)tintColor
                                                    font:(UIFont *)font {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSString *string = [priceManager stringForDashAmount:amount];

    return [self dw_dashAttributedStringForFormattedAmount:string tintColor:tintColor font:font];
}

+ (NSAttributedString *)dw_dashAttributedStringForFormattedAmount:(NSString *)string
                                                        tintColor:(UIColor *)tintColor
                                                             font:(UIFont *)font {
    NSAttributedString *dashSymbolAttributedString = [self dw_dashSymbolAttributedStringForFont:font
                                                                                      tintColor:tintColor];

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:string];

    const NSRange range = [attributedString.string rangeOfString:DASH];
    const BOOL dashSymbolFound = range.location != NSNotFound;
    if (dashSymbolFound) {
        [attributedString replaceCharactersInRange:range withAttributedString:dashSymbolAttributedString];
    }
    else {
        [attributedString insertAttributedString:[[NSAttributedString alloc] initWithString:NBSP] atIndex:0];
        [attributedString insertAttributedString:dashSymbolAttributedString atIndex:0];
    }

    const NSRange fullRange = NSMakeRange(0, attributedString.length);
    [attributedString addAttribute:NSForegroundColorAttributeName value:tintColor range:fullRange];
    [attributedString addAttribute:NSFontAttributeName value:font range:fullRange];

    return [attributedString copy];
}

+ (NSAttributedString *)dw_dashAddressAttributedString:(NSString *)address withFont:(UIFont *)font {
    const CGFloat scaleFactor = 1.5; // 24pt (image size) / 16pt (font size)
    const CGFloat side = font.pointSize * scaleFactor;
    const CGSize symbolSize = CGSizeMake(side, side);
    NSTextAttachment *dashIcon = [[NSTextAttachment alloc] init];
    const CGFloat y = -3.335 * scaleFactor; // -5pt / scaleFactor
    dashIcon.bounds = CGRectMake(0, y, symbolSize.width, symbolSize.height);
    dashIcon.image = [UIImage imageNamed:@"icon_tx_list_dash"];
    NSAttributedString *dashIconAttributedString =
        [NSAttributedString attributedStringWithAttachment:dashIcon];

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];

    [attributedString insertAttributedString:[[NSAttributedString alloc] initWithString:NBSP] atIndex:0];
    [attributedString insertAttributedString:dashIconAttributedString atIndex:0];

    NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName : font};
    NSAttributedString *attributedAddress = [[NSAttributedString alloc] initWithString:address
                                                                            attributes:attributes];
    [attributedString appendAttributedString:attributedAddress];

    return [attributedString copy];
}

#pragma mark - Private

+ (NSAttributedString *)dw_dashSymbolAttributedStringForFont:(UIFont *)font
                                                   tintColor:(UIColor *)tintColor {
    const CGFloat scaleFactor = 0.665;
    const CGFloat side = font.pointSize * scaleFactor;
    const CGSize symbolSize = CGSizeMake(side, side);
    NSTextAttachment *dashSymbol = [[NSTextAttachment alloc] init];
    dashSymbol.bounds = CGRectMake(0, 0, symbolSize.width, symbolSize.height);
    dashSymbol.image = [[UIImage imageNamed:@"icon_dash_currency"] ds_imageWithTintColor:tintColor];

    return [NSAttributedString attributedStringWithAttachment:dashSymbol];
}

@end

NS_ASSUME_NONNULL_END
