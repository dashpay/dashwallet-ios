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

#import "DWBlueActionButton.h"

#import "UIFont+DWFont.h"
#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBlueActionButton ()

@property (strong, nonatomic) NSMutableDictionary<NSNumber *, UIColor *> *backgroundColors;
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, UIColor *> *borderColors;
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, NSNumber *> *borderWidths;

@end

@implementation DWBlueActionButton

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self performInitialSetup];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self performInitialSetup];
    }
    return self;
}

- (void)performInitialSetup {
    self.usedOnDarkBackground = NO;
    self.inverted = NO;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(setNeedsLayout)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)setUsedOnDarkBackground:(BOOL)usedOnDarkBackground {
    _usedOnDarkBackground = usedOnDarkBackground;
    
    [self resetAppearance];
}

- (void)setInverted:(BOOL)inverted {
    _inverted = inverted;
    
    [self resetAppearance];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];

    [self updateButtonState];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];

    [self updateButtonState];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];

    [self updateButtonState];
}

#pragma mark - Background color

- (UIColor *)backgroundColorForState:(UIControlState)state {
    return self.backgroundColors[@(state)];
}

- (void)setBackgroundColor:(UIColor *)color forState:(UIControlState)state {
    if (color) {
        self.backgroundColors[@(state)] = color;
    }
    else {
        [self.backgroundColors removeObjectForKey:@(state)];
    }
    [self updateButtonState];
}

#pragma mark - Border color

- (UIColor *)borderColorForState:(UIControlState)state {
    return self.borderColors[@(state)];
}

- (void)setBorderColor:(UIColor *)color forState:(UIControlState)state {
    if (color) {
        self.borderColors[@(state)] = color;
    }
    else {
        [self.borderColors removeObjectForKey:@(state)];
    }
    [self updateButtonState];
}

#pragma mark - Border width

- (CGFloat)borderWidthForState:(UIControlState)state {
    return self.borderWidths[@(state)].doubleValue;
}

- (void)setBorderWidth:(CGFloat)width forState:(UIControlState)state {
    if (width) {
        self.borderWidths[@(state)] = @(width);
    }
    else {
        [self.borderWidths removeObjectForKey:@(state)];
    }
    [self updateButtonState];
}

#pragma mark - Private

- (NSMutableDictionary<NSNumber *, UIColor *> *)backgroundColors {
    if (_backgroundColors == nil) {
        _backgroundColors = [NSMutableDictionary dictionary];
    }
    return _backgroundColors;
}

- (NSMutableDictionary<NSNumber *, UIColor *> *)borderColors {
    if (_borderColors == nil) {
        _borderColors = [NSMutableDictionary dictionary];
    }
    return _borderColors;
}

- (NSMutableDictionary<NSNumber *, NSNumber *> *)borderWidths {
    if (_borderWidths == nil) {
        _borderWidths = [NSMutableDictionary dictionary];
    }
    return _borderWidths;
}

- (void)resetAppearance {
    self.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];
    
    self.layer.cornerRadius = [self.class cornerRadius];
    self.layer.masksToBounds = YES;
    
    [self setBackgroundColor:[self.class backgroundColorForInverted:self.inverted
                                               usedOnDarkBackground:self.usedOnDarkBackground]
                    forState:UIControlStateNormal];
    [self setBackgroundColor:[self.class highlightedBackgroundColorForInverted:self.inverted
                                                          usedOnDarkBackground:self.usedOnDarkBackground]
                    forState:UIControlStateHighlighted];
    [self setBackgroundColor:[self.class disabledBackgroundColorForInverted:self.inverted
                                                       usedOnDarkBackground:self.usedOnDarkBackground]
                    forState:UIControlStateDisabled];
    
    [self setTitleColor:[self.class textColorForInverted:self.inverted
                                    usedOnDarkBackground:self.usedOnDarkBackground]
               forState:UIControlStateNormal];
    [self setTitleColor:[self.class highlightedTextColorForInverted:self.inverted
                                               usedOnDarkBackground:self.usedOnDarkBackground]
               forState:UIControlStateHighlighted];
    [self setTitleColor:[self.class disabledTextColorForInverted:self.inverted
                                            usedOnDarkBackground:self.usedOnDarkBackground]
               forState:UIControlStateDisabled];
    
    [self setBorderWidth:[self.class borderWidthForInverted:self.inverted
                                       usedOnDarkBackground:self.usedOnDarkBackground]
                forState:UIControlStateNormal];
    
    [self setBorderColor:[self.class borderColorForInverted:self.inverted
                                       usedOnDarkBackground:self.usedOnDarkBackground]
                forState:UIControlStateNormal];
    [self setBorderColor:[self.class disabledBorderColorForInverted:self.inverted
                                               usedOnDarkBackground:self.usedOnDarkBackground]
                forState:UIControlStateDisabled];
}

- (void)updateButtonState {
    UIControlState state = self.state;

    for (NSNumber *flag in @[ @0, @(UIControlStateDisabled), @(UIControlStateSelected), @(UIControlStateHighlighted) ]) {
        state &= ~flag.unsignedIntegerValue;
        UIColor *backgroundColor = self.backgroundColors[@(state)];
        if (backgroundColor) {
            self.backgroundColor = backgroundColor;
            break;
        }
    }

    for (NSNumber *flag in @[ @0, @(UIControlStateDisabled), @(UIControlStateSelected), @(UIControlStateHighlighted) ]) {
        state &= ~flag.unsignedIntegerValue;
        UIColor *borderColor = self.borderColors[@(state)];
        if (borderColor) {
            self.layer.borderColor = borderColor.CGColor;
            break;
        }
    }
    
    for (NSNumber *flag in @[ @0, @(UIControlStateDisabled), @(UIControlStateSelected), @(UIControlStateHighlighted) ]) {
        state &= ~flag.unsignedIntegerValue;
        NSNumber *borderWidth = self.borderWidths[@(state)];
        if (borderWidth) {
            self.layer.borderWidth = borderWidth.doubleValue;
            break;
        }
    }
}

#pragma mark - Styles

+ (UIColor *)backgroundColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    if (usedOnDarkBackground) {
        return inverted ? [UIColor clearColor] : [UIColor dw_dashBlue];
    }
    else {
        return inverted ? [UIColor whiteColor] : [UIColor dw_dashBlue];
    }
}

+ (UIColor *)highlightedBackgroundColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    if (usedOnDarkBackground) {
        return [UIColor clearColor];
    }
    else {
        return [UIColor whiteColor];
    }
}

+ (UIColor *)disabledBackgroundColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    if (usedOnDarkBackground) {
        return inverted ? [UIColor clearColor] : [UIColor dw_disabledButton];
    }
    else {
        return inverted ? [UIColor whiteColor] : [UIColor dw_disabledButton];
    }
}

+ (UIColor *)textColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    if (usedOnDarkBackground) {
        return [UIColor dw_title];
    }
    else {
        return inverted ? [UIColor dw_dashBlue] : [UIColor dw_title];
    }
}

+ (UIColor *)highlightedTextColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    if (usedOnDarkBackground) {
        return [UIColor dw_dashBlue];
    }
    else {
        return inverted ? [UIColor dw_title] : [UIColor dw_dashBlue];
    }
}

+ (UIColor *)disabledTextColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return inverted ? [UIColor dw_disabledButton] : [UIColor dw_title];
}

+ (UIColor *)borderColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return inverted ? [UIColor clearColor] : [UIColor dw_dashBlue];
}

+ (UIColor *)disabledBorderColorForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return inverted ? [UIColor clearColor] : [UIColor dw_disabledButton];
}

+ (CGFloat)borderWidthForInverted:(BOOL)inverted usedOnDarkBackground:(BOOL)usedOnDarkBackground {
    return 2.0;
}

+ (CGFloat)cornerRadius {
    return 8.0;
}

@end

NS_ASSUME_NONNULL_END
