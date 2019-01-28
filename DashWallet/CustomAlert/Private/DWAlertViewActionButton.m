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

#import "DWAlertViewActionButton.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - UIFont Helper

@implementation UIFont (DWAlertViewActionButtonHelper)

+ (UIFont *)dw_titleFont {
    return [[UIFont systemFontOfSize:17.0] dw_scaledFont];
}

+ (UIFont *)dw_preferredTitleFont {
    return [[UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold] dw_scaledFont];
}

- (UIFont *)dw_scaledFont {
    // Don't scale font less than Default content size (as UIAlertController does)
    CGFloat scaler = MAX([UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize / 17.0, 1.0);
    CGFloat newSize = self.pointSize * scaler;
    UIFont *scaledFont = [self fontWithSize:newSize];
    return scaledFont;
}

@end

#pragma mark - Label

@interface DWAlertActionButtonLabel : UILabel

@property (assign, nonatomic) UIEdgeInsets edgeInsets;

@end

@implementation DWAlertActionButtonLabel

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.edgeInsets)];
}

- (CGSize)sizeThatFits:(CGSize)size {
    UIEdgeInsets edgeInsets = self.edgeInsets;
    CGSize superSizeThatFits = [super sizeThatFits:size];
    CGFloat width = superSizeThatFits.width + edgeInsets.left + edgeInsets.right;
    CGFloat height = superSizeThatFits.height + edgeInsets.top + edgeInsets.bottom;
    return CGSizeMake(width, height);
}

@end

#pragma mark - Button

@interface DWAlertViewActionButton ()

@property (readonly, strong, nonatomic) DWAlertActionButtonLabel *titleLabel;

@end

@implementation DWAlertViewActionButton

- (instancetype)initWithAlertAction:(DWAlertAction *)alertAction {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _alertAction = alertAction;

        self.exclusiveTouch = YES;

        DWAlertActionButtonLabel *titleLabel = [[DWAlertActionButtonLabel alloc] initWithFrame:self.bounds];
        titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        titleLabel.minimumScaleFactor = 0.58;
        titleLabel.edgeInsets = UIEdgeInsetsMake(0.0, 12.0, 0.0, 12.0);
        titleLabel.highlightedTextColor = [UIColor colorWithRed:0.0 green:122.0 / 255.0 blue:1.0 alpha:1.0];
        titleLabel.textColor = [UIColor colorWithWhite:104.0 / 255.0 alpha:0.8];
        titleLabel.text = alertAction.title;
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        [self mvvm_observe:@"alertAction.enabled" with:^(typeof(self) self, NSNumber * value) {
            self.titleLabel.highlighted = self.alertAction.enabled;
        }];
    }
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size {
    return [self.titleLabel sizeThatFits:size];
}

- (void)setHighlighted:(BOOL)highlighted {
    if (highlighted) {
        if (!_highlighted) {
            self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.7];
        }
    }
    else {
        if (!_highlighted) {
            self.backgroundColor = [UIColor clearColor];
        }
    }
    _highlighted = highlighted;
}

- (void)setPreferred:(BOOL)preferred {
    _preferred = preferred;

    if (preferred) {
        self.titleLabel.font = [UIFont dw_preferredTitleFont];
    }
    else {
        self.titleLabel.font = [UIFont dw_titleFont];
    }
}

- (void)updateForCurrentContentSizeCategory {
    self.preferred = _preferred;
}

#pragma mark UIResponder

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch) {
        [self.delegate actionButton:self touchBegan:touch];
    }
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch) {
        [self.delegate actionButton:self touchMoved:touch];
    }
    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch) {
        [self.delegate actionButton:self touchEnded:touch];
    }
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch) {
        [self.delegate actionButton:self touchCancelled:touch];
    }
    [super touchesCancelled:touches withEvent:event];
}

@end

NS_ASSUME_NONNULL_END
