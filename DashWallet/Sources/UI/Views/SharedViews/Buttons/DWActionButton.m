//
//  Created by Sam Westrich
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

#import "DWActionButton.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWActionButton

@synthesize accentColor = _accentColor;

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self setup_ActionButton];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup_ActionButton];
    }
    return self;
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self resetAppearance];
}

- (void)setUsedOnDarkBackground:(BOOL)usedOnDarkBackground {
    _usedOnDarkBackground = usedOnDarkBackground;

    [self resetAppearance];
}

- (void)setInverted:(BOOL)inverted {
    _inverted = inverted;

    [self resetAppearance];
}

- (void)setSmall:(BOOL)small {
    _small = small;

    [self resetAppearance];
}

- (UIColor *)accentColor {
    if (_accentColor == nil) {
        _accentColor = [UIColor dw_dashBlueColor];
    }
    return _accentColor;
}

- (void)setAccentColor:(nullable UIColor *)accentColor {
    _accentColor = accentColor;

    [self resetAppearance];
}

#pragma mark - Private

- (void)setup_ActionButton {
    self.usedOnDarkBackground = NO;
    self.inverted = NO;
}

- (void)resetAppearance {
    UIFontTextStyle textStyle = UIFontTextStyleSubheadline;
    self.titleLabel.font = [UIFont dw_fontForTextStyle:textStyle];

    if (self.small) {
        self.contentEdgeInsets = [self _smallButtonContentEdgeInsets];
    }

    self.layer.cornerRadius = [self _cornerRadius];
    self.layer.masksToBounds = YES;

    BOOL dark = self.usedOnDarkBackground;
    BOOL inverted = self.inverted;

    UIColor *color = [self _backgroundColorForInverted:inverted usedOnDarkBackground:dark];
    [self setBackgroundColor:color forState:UIControlStateNormal];

    color = [self _highlightedBackgroundColorForInverted:inverted usedOnDarkBackground:dark];
    [self setBackgroundColor:color forState:UIControlStateHighlighted];

    color = [self _disabledBackgroundColorForInverted:inverted usedOnDarkBackground:dark];
    [self setBackgroundColor:color forState:UIControlStateDisabled];

    color = [self _textColorForInverted:inverted usedOnDarkBackground:dark];
    [self setTitleColor:color forState:UIControlStateNormal];

    color = [self _highlightedTextColorForInverted:inverted usedOnDarkBackground:dark];
    [self setTitleColor:color forState:UIControlStateHighlighted];

    color = [self _disabledTextColorForInverted:inverted usedOnDarkBackground:dark];
    [self setTitleColor:color forState:UIControlStateDisabled];

    CGFloat width = [self _borderWidthForInverted:inverted usedOnDarkBackground:dark];
    [self setBorderWidth:width forState:UIControlStateNormal];

    color = [self _borderColorForInverted:inverted usedOnDarkBackground:dark];
    [self setBorderColor:color forState:UIControlStateNormal];

    color = [self _disabledBorderColorForInverted:inverted usedOnDarkBackground:dark];
    [self setBorderColor:color forState:UIControlStateDisabled];
}

#pragma mark - Styles

- (UIColor *)_backgroundColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return inverted ? [UIColor clearColor] : self.accentColor;
}

- (UIColor *)_highlightedBackgroundColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return [UIColor clearColor];
}

- (UIColor *)_disabledBackgroundColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    if (usedOnDarkBackground) {
        return inverted ? [UIColor clearColor] : [UIColor dw_disabledButtonColor];
    }
    else {
        return inverted ? [UIColor whiteColor] : [UIColor dw_disabledButtonColor];
    }
}

- (UIColor *)_textColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    if (usedOnDarkBackground) {
        return [UIColor dw_lightTitleColor];
    }
    else {
        return inverted ? self.accentColor : [UIColor dw_lightTitleColor];
    }
}

- (UIColor *)_highlightedTextColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    if (usedOnDarkBackground) {
        return inverted ? [[UIColor dw_lightTitleColor] colorWithAlphaComponent:0.5] : self.accentColor;
    }
    else {
        return inverted ? [self.accentColor colorWithAlphaComponent:0.5] : self.accentColor;
    }
}

- (UIColor *)_disabledTextColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return inverted ? [UIColor dw_disabledButtonColor] : [UIColor dw_disabledButtonTextColor];
}

- (UIColor *)_borderColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return inverted ? [UIColor clearColor] : self.accentColor;
}

- (UIColor *)_disabledBorderColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return inverted ? [UIColor clearColor] : [UIColor dw_disabledButtonColor];
}

- (CGFloat)_borderWidthForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return 2.0;
}

- (UIEdgeInsets)_smallButtonContentEdgeInsets {
    return UIEdgeInsetsMake(0.0, 12.0, 0.0, 12.0);
}

- (CGFloat)_cornerRadius {
    return 8.0;
}

@end

NS_ASSUME_NONNULL_END
