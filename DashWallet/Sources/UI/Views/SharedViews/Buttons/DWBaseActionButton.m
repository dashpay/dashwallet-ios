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

#import "DWBaseActionButton.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBaseActionButton ()

@property (strong, nonatomic) NSMutableDictionary<NSNumber *, UIColor *> *backgroundColors;
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, UIColor *> *borderColors;
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, NSNumber *> *borderWidths;

@end

@implementation DWBaseActionButton

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];

    [self updateButtonHighlighted:self.highlighted selected:self.selected];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];

    [self updateButtonHighlighted:highlighted selected:self.selected];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];

    [self updateButtonHighlighted:self.highlighted selected:selected];
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

    [self updateButtonHighlighted:self.highlighted selected:self.selected];
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

    [self updateButtonHighlighted:self.highlighted selected:self.selected];
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

    [self updateButtonHighlighted:self.highlighted selected:self.selected];
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

- (void)updateButtonHighlighted:(BOOL)highlighted selected:(BOOL)selected {
    UIControlState state = self.enabled ? UIControlStateNormal : UIControlStateDisabled;
    if (highlighted) {
        state = UIControlStateHighlighted;
    }

    NSNumber *fallbackStateKey = @(UIControlStateNormal);

    UIColor *backgroundColor = self.backgroundColors[@(state)];
    if (!backgroundColor) {
        backgroundColor = self.backgroundColors[fallbackStateKey];
    }
    if (backgroundColor) {
        self.backgroundColor = backgroundColor;
    }

    UIColor *borderColor = self.borderColors[@(state)];
    if (!borderColor) {
        borderColor = self.borderColors[fallbackStateKey];
    }
    if (borderColor) {
        self.layer.borderColor = borderColor.CGColor;
    }

    NSNumber *borderWidth = self.borderWidths[@(state)];
    if (!borderWidth) {
        borderWidth = self.borderWidths[fallbackStateKey];
    }
    if (borderWidth) {
        self.layer.borderWidth = borderWidth.doubleValue;
    }
}

@end

NS_ASSUME_NONNULL_END
