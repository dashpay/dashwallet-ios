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

#import "DWBorderedActionButton.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWBorderedActionButton

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.accentColor = [UIColor dw_dashBlueColor];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accentColor = [UIColor dw_dashBlueColor];
    }
    return self;
}

- (void)setAccentColor:(UIColor *)accentColor {
    _accentColor = accentColor;

    [self resetAppearance];
}

#pragma mark - Private

- (void)resetAppearance {
    UIFontTextStyle textStyle = UIFontTextStyleSubheadline;
    self.titleLabel.font = [UIFont dw_fontForTextStyle:textStyle];

    self.contentEdgeInsets = [self.class buttonContentEdgeInsets];

    self.layer.cornerRadius = [self.class cornerRadius];
    self.layer.masksToBounds = YES;

    [self setBackgroundColor:[UIColor clearColor] forState:UIControlStateNormal];
    [self setBorderWidth:[self.class borderWidth] forState:UIControlStateNormal];

    UIColor *color = self.accentColor;
    [self setTitleColor:color forState:UIControlStateNormal];
    [self setBorderColor:color forState:UIControlStateNormal];

    color = [self.class highlightedColorForColor:self.accentColor];
    [self setTitleColor:color forState:UIControlStateHighlighted];
    [self setBorderColor:color forState:UIControlStateHighlighted];

    color = [self.class disabledColorForColor:self.accentColor];
    [self setTitleColor:color forState:UIControlStateDisabled];
    [self setBorderColor:color forState:UIControlStateDisabled];
}

#pragma mark - Styles

+ (CGFloat)borderWidth {
    return 1.0;
}

+ (UIEdgeInsets)buttonContentEdgeInsets {
    return UIEdgeInsetsMake(10.0, 20.0, 10.0, 20.0);
}

+ (CGFloat)cornerRadius {
    return 8.0;
}

+ (UIColor *)highlightedColorForColor:(UIColor *)color {
    return [color colorWithAlphaComponent:0.5];
}

+ (UIColor *)disabledColorForColor:(UIColor *)color {
    CGFloat hue, saturation, brightness, alpha;
    BOOL result = [color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
    NSAssert(result, @"Invalid color");
    if (!result) {
        return [color colorWithAlphaComponent:0.35];
    }

    UIColor *disabledColor = [UIColor colorWithHue:hue
                                        saturation:saturation * 0.35
                                        brightness:brightness * 0.95
                                             alpha:alpha];
    return disabledColor;
}

@end

NS_ASSUME_NONNULL_END
