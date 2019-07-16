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

#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UIColor (DWStyle)

+ (UIColor *)dw_backgroundColor {
    UIColor *color = [UIColor colorNamed:@"BackgroundColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_secondaryBackgroundColor {
    UIColor *color = [UIColor colorNamed:@"SecondaryBackgroundColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_tintColor {
    UIColor *color = [UIColor colorNamed:@"TintColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_dashBlueColor {
    UIColor *color = [UIColor colorNamed:@"DashBlueColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_lightTitleColor {
    UIColor *color = [UIColor colorNamed:@"LightTitleColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_darkTitleColor {
    UIColor *color = [UIColor colorNamed:@"DarkTitleColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_secondaryTextColor {
    UIColor *color = [UIColor colorNamed:@"SecondaryTextColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_redColor {
    UIColor *color = [UIColor colorNamed:@"RedColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_disabledButtonColor {
    UIColor *color = [UIColor colorNamed:@"DisabledButtonColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_pinBackgroundColor {
    UIColor *color = [UIColor colorNamed:@"PinBackgroundColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_pinInputDotColor {
    UIColor *color = [UIColor colorNamed:@"PinInputDotColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_numberKeyboardTextColor {
    UIColor *color = [UIColor colorNamed:@"NumberKeyboardTextColor"];
    NSParameterAssert(color);
    return color;
}

+ (UIColor *)dw_numberKeyboardHighlightedTextColor {
    UIColor *color = [UIColor colorNamed:@"NumberKeyboardHighlightedTextColor"];
    NSParameterAssert(color);
    return color;
}

@end

NS_ASSUME_NONNULL_END
