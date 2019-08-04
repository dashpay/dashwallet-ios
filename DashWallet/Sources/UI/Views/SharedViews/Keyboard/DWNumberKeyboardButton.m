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

#import "DWNumberKeyboardButton.h"

#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

static UIColor *TextColor() {
    return [UIColor dw_numberKeyboardTextColor];
}

static UIColor *TextHighlightedColor() {
    return [UIColor dw_numberKeyboardHighlightedTextColor];
}

static UIColor *BackgroundColor() {
    return [UIColor dw_secondaryBackgroundColor];
}

static UIColor *BackgroundHighlightedColor() {
    return [UIColor dw_dashBlueColor];
}

static UIFont *TitleFont() {
    return [UIFont dw_fontForTextStyle:UIFontTextStyleCallout respectMinSize:YES];
}

static UIFont *CustomTitleFont() {
    const CGFloat minSize = 14.0;
    // UIFontTextStyleBody doesn't support minimum size, check it manually
    UIFont *font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    if (font.pointSize < minSize) {
        font = [UIFont fontWithName:font.fontName size:minSize];
    }
    return font;
}

static CGFloat const CORNER_RADIUS = 8.0;

@interface DWNumberKeyboardButton ()

@property (readonly, strong, nonatomic) UILabel *titleLabel;

@end

@implementation DWNumberKeyboardButton

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.exclusiveTouch = YES;

        self.backgroundColor = BackgroundColor();

        self.layer.cornerRadius = CORNER_RADIUS;
        self.layer.masksToBounds = YES;

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:self.bounds];
        titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.textColor = TextColor();
        titleLabel.font = TitleFont();
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)setType:(DWNumberKeyboardButtonType)type {
    _type = type;

    switch (type) {
        case DWNumberKeyboardButtonType_Separator: {
            self.titleLabel.text = [NSLocale currentLocale].decimalSeparator;
#if SNAPSHOT
            titleLabel.accessibilityIdentifier = @"amount_button_separator";
#endif /* SNAPSHOT */

            break;
        }
        case DWNumberKeyboardButtonType_Custom: {
            self.titleLabel.font = CustomTitleFont();
            self.titleLabel.adjustsFontSizeToFitWidth = YES;

            break;
        }
        case DWNumberKeyboardButtonType_Clear: {
            UIImage *image = [[UIImage imageNamed:@"backspace"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
            textAttachment.image = image;
            textAttachment.bounds = CGRectMake(-3.0, -2.0, image.size.width, image.size.height);
            // Workaround to make UIKit correctly set text color of the attribute string:
            // Attributed string that consists only of NSTextAttachment will not change it's color
            // To solve it append any regular string at the begining (and at the end to center the image)
            NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] init];
            [attributedText beginEditing];
            [attributedText appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
            [attributedText appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];
            [attributedText appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
            [attributedText endEditing];
            self.titleLabel.attributedText = attributedText;

            break;
        }
        default: {
            self.titleLabel.text = [NSString stringWithFormat:@"%lu", type];

            break;
        }
    }
}

- (void)setHighlighted:(BOOL)highlighted {
    _highlighted = highlighted;

    if (highlighted) {
        self.backgroundColor = BackgroundHighlightedColor();
        self.titleLabel.textColor = TextHighlightedColor();
    }
    else {
        self.backgroundColor = BackgroundColor();
        self.titleLabel.textColor = TextColor();
    }
}

- (void)configureAsCustomTypeWithTitle:(NSString *)title {
    self.type = DWNumberKeyboardButtonType_Custom;
    self.titleLabel.text = title;
}

#pragma mark - UIResponder

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch) {
        [self.delegate numberButton:self touchBegan:touch];
    }
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch) {
        [self.delegate numberButton:self touchMoved:touch];
    }
    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch) {
        [self.delegate numberButton:self touchEnded:touch];
    }
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(nullable UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch) {
        [self.delegate numberButton:self touchCancelled:touch];
    }
    [super touchesCancelled:touches withEvent:event];
}

#pragma mark - Private

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    if (self.type == DWNumberKeyboardButtonType_Custom) {
        self.titleLabel.font = CustomTitleFont();
    }
    else {
        self.titleLabel.font = TitleFont();
    }
}

@end

NS_ASSUME_NONNULL_END
