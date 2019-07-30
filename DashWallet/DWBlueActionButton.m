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
        self.inverted = NO;
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.inverted = NO;
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.inverted = _inverted;
}

- (void)setInverted:(BOOL)inverted {
    _inverted = inverted;
    
    [self setBackgroundColor:[self.class backgroundColorForInverted:inverted] forState:UIControlStateNormal];
    [self setBackgroundColor:[self.class highlightedBackgroundColorForInverted:inverted] forState:UIControlStateHighlighted];
    [self setBackgroundColor:[self.class disabledBackgroundColorForInverted:inverted] forState:UIControlStateDisabled];
    
    [self setTitleColor:[self.class textColorForInverted:inverted] forState:UIControlStateNormal];
    [self setTitleColor:[self.class highlightedTextColorForInverted:inverted] forState:UIControlStateHighlighted];
    [self setTitleColor:[self.class disabledTextColorForInverted:inverted] forState:UIControlStateDisabled];
    
    [self setBorderWidth:[self.class borderWidthForInverted:inverted] forState:UIControlStateNormal];
    
    [self setBorderColor:[self.class borderColorForInverted:inverted] forState:UIControlStateNormal];
    [self setBorderColor:[self.class disabledBorderColorForInverted:inverted] forState:UIControlStateDisabled];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.layer.cornerRadius = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds)) / 2.0;
    self.layer.masksToBounds = YES;
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

+ (UIColor *)backgroundColorForInverted:(BOOL)inverted {
    return inverted ? [UIColor whiteColor] : UIColorFromRGB(0x008DE4);
}

+ (UIColor *)highlightedBackgroundColorForInverted:(BOOL)inverted {
    return [self backgroundColorForInverted:!inverted];
}

+ (UIColor *)disabledBackgroundColorForInverted:(BOOL)inverted {
    return inverted ? [UIColor whiteColor] : [UIColor grayColor];
}

+ (UIColor *)textColorForInverted:(BOOL)inverted {
    return [self backgroundColorForInverted:!inverted];
}

+ (UIColor *)highlightedTextColorForInverted:(BOOL)inverted {
    return [self textColorForInverted:!inverted];
}

+ (UIColor *)disabledTextColorForInverted:(BOOL)inverted {
    return inverted ? [UIColor grayColor] : [UIColor whiteColor];
}

+ (UIColor *)borderColorForInverted:(BOOL)inverted {
    return UIColorFromRGB(0x008DE4);
}

+ (UIColor *)disabledBorderColorForInverted:(BOOL)inverted {
    return [UIColor grayColor];
}

+ (CGFloat)borderWidthForInverted:(BOOL)inverted {
    return 2.0;
}

@end

NS_ASSUME_NONNULL_END
