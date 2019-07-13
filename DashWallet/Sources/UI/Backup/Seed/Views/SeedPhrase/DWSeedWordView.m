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

#import "DWSeedWordView.h"

#import "DWSeedWordModel.h"
#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat VerticalPadding(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return 10.0;
        case DWSeedPhraseType_Select:
            return 13.0;
    }
}

static CGFloat HorizontalPadding(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return 8.0;
        case DWSeedPhraseType_Select:
            return 20.0;
    }
}

static UIColor *BackgroundColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return [UIColor dw_backgroundColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_secondaryBackgroundColor];
    }
}

static UIColor *TextColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return [UIColor dw_dashBlueColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_lightTitleColor];
    }
}

static UIColor *TextBackgroundColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return [UIColor dw_backgroundColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_dashBlueColor];
    }
}

static UIColor *TextSelectedBackgroundColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            NSCAssert(NO, @"DWSeedPhraseType_Preview is not selectable");
            return [UIColor dw_backgroundColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_disabledButtonColor];
    }
}

static UIFont *WordFont(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
        case DWSeedPhraseType_Select:
            return [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];
    }
}

static CGFloat CornerRadius(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return 0.0;
        case DWSeedPhraseType_Select:
            return 8.0;
    }
}

static BOOL MasksToBounds(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return NO;
        case DWSeedPhraseType_Select:
            return YES;
    }
}

static NSDictionary *TextAttributes(DWSeedPhraseType type) {
    NSDictionary *attributes = @{
        NSFontAttributeName : WordFont(type),
    };
    return attributes;
}

@interface DWSeedWordView ()

@property (readonly, nonatomic, assign) DWSeedPhraseType type;
@property (readonly, strong, nonatomic) UILabel *wordLabel;

@end

@implementation DWSeedWordView

- (instancetype)initWithType:(DWSeedPhraseType)type {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _type = type;

        self.layer.cornerRadius = CornerRadius(type);
        self.layer.masksToBounds = MasksToBounds(type);

        self.backgroundColor = BackgroundColor(type);

        UILabel *wordLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        wordLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        wordLabel.backgroundColor = TextBackgroundColor(type);
        wordLabel.textColor = TextColor(type);
        wordLabel.textAlignment = NSTextAlignmentCenter;
        wordLabel.adjustsFontForContentSizeCategory = YES;
        wordLabel.font = WordFont(type);
        wordLabel.numberOfLines = 0;
        wordLabel.adjustsFontSizeToFitWidth = YES; // protects from clipping text
        wordLabel.minimumScaleFactor = 0.5;
        [self addSubview:wordLabel];
        _wordLabel = wordLabel;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.wordLabel.frame = self.bounds;
}

- (void)setModel:(nullable DWSeedWordModel *)model {
    _model = model;

    NSAssert(model.word.length > 0, @"Seed word cell is broken. It's crucially important!");

    NSDictionary *attributes = TextAttributes(self.type);
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:model.word
                                                                           attributes:attributes];
    self.wordLabel.attributedText = attributedString;

    self.selected = model.selected;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];

    DWSeedPhraseType type = self.type;
    if (type == DWSeedPhraseType_Preview) {
        return;
    }

    self.wordLabel.backgroundColor = selected ? TextSelectedBackgroundColor(type) : TextBackgroundColor(type);
}

#pragma mark - Class

+ (CGSize)sizeForModel:(DWSeedWordModel *)model maxWidth:(CGFloat)maxWidth type:(DWSeedPhraseType)type {
    NSAssert(model.word.length > 0, @"Invalid seed word");

    NSString *const text = model.word;
    const CGSize maxSize = CGSizeMake(maxWidth, CGFLOAT_MAX);
    NSDictionary *const attributes = TextAttributes(type);

    const CGRect rect = [text boundingRectWithSize:maxSize
                                           options:NSStringDrawingUsesLineFragmentOrigin
                                        attributes:attributes
                                           context:nil];

    const CGFloat horizontalPadding = HorizontalPadding(type);
    const CGFloat verticalPadding = VerticalPadding(type);
    const CGSize size = CGSizeMake(ceil(CGRectGetWidth(rect) + horizontalPadding * 2),
                                   ceil(CGRectGetHeight(rect) + verticalPadding * 2));

    return size;
}

@end

NS_ASSUME_NONNULL_END
