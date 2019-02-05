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

static NSLineBreakMode const LineBreakMode = NSLineBreakByTruncatingMiddle;
static NSTextAlignment const TextAlignment = NSTextAlignmentCenter;
static CGFloat const MinimumScaleFactor = 0.58;
static UIEdgeInsets const TextEdgeInsets = {0.0, 12.0, 0.0, 12.0};

static UIColor *HighlightedTextColor(DWAlertActionStyle style) {
    switch (style) {
        case DWAlertActionStyleDefault:
        case DWAlertActionStyleCancel:
            return [UIColor colorWithRed:0.0 green:122.0 / 255.0 blue:1.0 alpha:1.0];
        case DWAlertActionStyleDestructive:
            return [UIColor colorWithRed:1.0 green:59.0 / 255.0 blue:48.0 / 255.0 alpha:1.0];
    }
}

static UIColor *DisabledTextColor() {
    return [UIColor colorWithWhite:104.0 / 255.0 alpha:0.8];
}

static UIColor *BackgroundColor() {
    return [UIColor clearColor];
}

static UIColor *BackgroundHighlightedColor() {
    return [UIColor colorWithWhite:1.0 alpha:0.7];
}

@interface DWAlertViewActionButton ()

@property (readonly, strong, nonatomic) DWAlertActionButtonLabel *titleLabel;

@end

@implementation DWAlertViewActionButton

@synthesize titleLabel = _titleLabel;

- (DWAlertActionButtonLabel *)titleLabel {
    if (!_titleLabel) {
        DWAlertActionButtonLabel *titleLabel = [[DWAlertActionButtonLabel alloc] initWithFrame:self.bounds];
        titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        titleLabel.lineBreakMode = LineBreakMode;
        titleLabel.textAlignment = TextAlignment;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        titleLabel.minimumScaleFactor = MinimumScaleFactor;
        titleLabel.edgeInsets = TextEdgeInsets;
        titleLabel.highlightedTextColor = HighlightedTextColor(self.alertAction.style);
        titleLabel.textColor = DisabledTextColor();
        titleLabel.text = self.alertAction.title;
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;
    }
    return _titleLabel;
}

- (CGSize)sizeThatFits:(CGSize)size {
    return [self.titleLabel sizeThatFits:size];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];

    if (highlighted) {
        self.backgroundColor = BackgroundHighlightedColor();
    }
    else {
        self.backgroundColor = BackgroundColor();
    }
}

- (void)setPreferred:(BOOL)preferred {
    [super setPreferred:preferred];

    if (preferred) {
        self.titleLabel.font = [UIFont dw_preferredTitleFont];
    }
    else {
        self.titleLabel.font = [UIFont dw_titleFont];
    }
}

- (void)updateForCurrentContentSizeCategory {
    self.preferred = self.preferred;
}

- (void)updateEnabledState {
    self.titleLabel.highlighted = self.alertAction.enabled;
}

@end

NS_ASSUME_NONNULL_END
