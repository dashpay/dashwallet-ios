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

NS_ASSUME_NONNULL_BEGIN

static UIColor *TextColor() {
    return [UIColor whiteColor];
}

static UIColor *TextHighlightedColor() {
    return [UIColor colorWithRed:1.0 / 255.0 green:32.0 / 255.0 blue:96.0 / 255.0 alpha:1.0];
}

static UIColor *BackgroundColor() {
    return [UIColor colorWithRed:1.0 / 255.0 green:32.0 / 255.0 blue:96.0 / 255.0 alpha:1.0];
}

static UIColor *BackgroundHighlightedColor() {
    return [UIColor whiteColor];
}

@interface DWNumberKeyboardButton ()

@property (readonly, strong, nonatomic) UILabel *titleLabel;

@end

@implementation DWNumberKeyboardButton

- (instancetype)initWithWithType:(DWNumberKeyboardButtonType)type {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _type = type;

        self.exclusiveTouch = YES;

        self.backgroundColor = BackgroundColor();

        self.layer.masksToBounds = YES;

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:self.bounds];
        titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.textColor = TextColor();
        titleLabel.font = [UIFont systemFontOfSize:24.0];
        switch (type) {
            case DWNumberKeyboardButtonTypeSeparator: {
                titleLabel.text = [NSLocale currentLocale].decimalSeparator;
#if SNAPSHOT
                titleLabel.accessibilityIdentifier = @"amount_button_separator";
#endif /* SNAPSHOT */

                break;
            }
            case DWNumberKeyboardButtonTypeClear: {
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
                titleLabel.attributedText = attributedText;

                break;
            }
            default: {
                titleLabel.text = [NSString stringWithFormat:@"%lu", type];

                break;
            }
        }
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.layer.cornerRadius = ceil(CGRectGetHeight(self.bounds) / 2.0);
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

@end

NS_ASSUME_NONNULL_END
