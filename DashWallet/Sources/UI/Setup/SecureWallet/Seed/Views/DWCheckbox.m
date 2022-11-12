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

#import "DWCheckbox.h"

#import "DWUIKit.h"
#import "NSString+DWTextSize.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const MIN_HEIGHT = 44.0;
static CGFloat const ICON_TEXT_PADDING = 7.0;

@interface DWCheckbox ()

@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *textLabel;

@property (nonatomic, assign) CGSize currentSize;

@end

@implementation DWCheckbox

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor clearColor];

    UIView *contentView = [[UIView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.backgroundColor = self.backgroundColor;
    [self addSubview:contentView];
    self.contentView = contentView;

    UIImage *image = [UIImage imageNamed:@"icon_checkbox"];
    NSParameterAssert(image);
    UIImage *highlightedImage = [UIImage imageNamed:@"icon_checkbox_checked"];
    NSParameterAssert(highlightedImage);
    UIImageView *iconImageView = [[UIImageView alloc] initWithImage:image highlightedImage:highlightedImage];
    iconImageView.userInteractionEnabled = NO;
    [contentView addSubview:iconImageView];
    self.iconImageView = iconImageView;

    UILabel *textLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    textLabel.userInteractionEnabled = NO;
    textLabel.backgroundColor = self.backgroundColor;
    textLabel.numberOfLines = 0;
    textLabel.textAlignment = NSTextAlignmentLeft;
    textLabel.textColor = [UIColor dw_secondaryTextColor];
    textLabel.adjustsFontForContentSizeCategory = YES;
    textLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    textLabel.adjustsFontSizeToFitWidth = YES;
    textLabel.minimumScaleFactor = 0.5;
    [contentView addSubview:textLabel];
    self.textLabel = textLabel;

    UITapGestureRecognizer *gestureRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(tapGestureAction:)];
    [self addGestureRecognizer:gestureRecognizer];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGSize size = self.bounds.size;
    const CGSize imageSize = self.iconImageView.image.size;
    const CGFloat boundsWidth = size.width > 0.0 ? size.width : CGRectGetWidth([UIScreen mainScreen].bounds);
    const CGFloat maxTextWidth = boundsWidth - self.iconImageView.image.size.width - ICON_TEXT_PADDING;
    const CGSize textSize = [self.textLabel.text dw_textSizeWithFont:self.textLabel.font maxWidth:maxTextWidth];

    const CGFloat width = imageSize.width + ICON_TEXT_PADDING + textSize.width;
    const CGFloat height = MAX(MIN_HEIGHT, textSize.height);
    const CGSize intrinsicSize = CGSizeMake(width, height);

    CGFloat x = (size.width - width) / 2.0;
    self.iconImageView.frame = CGRectMake(x, (size.height - imageSize.height) / 2.0,
                                          imageSize.width, imageSize.height);
    x += imageSize.width + ICON_TEXT_PADDING;

    self.textLabel.frame = CGRectMake(x, 0.0, textSize.width, size.height);

    if (!CGSizeEqualToSize(self.currentSize, intrinsicSize)) {
        self.currentSize = intrinsicSize;
    }
}

- (CGSize)intrinsicContentSize {
    return self.currentSize;
}

- (nullable NSString *)title {
    return self.textLabel.text;
}

- (void)setTitle:(nullable NSString *)title {
    self.textLabel.text = title;

    [self setNeedsLayout];
}

- (void)setOn:(BOOL)on {
    _on = on;

    self.iconImageView.highlighted = on;
}

- (void)setStyle:(DWCheckBoxStyle)style {
    UIImage *image;
    UIImage *highlightedImage;
    
    if (style == DWCheckBoxStyle_Square) {
        image = [UIImage imageNamed:@"icon_checkbox_square"];
        highlightedImage = [UIImage imageNamed:@"icon_checkbox_square_checked"];
    } else {
        image = [UIImage imageNamed:@"icon_checkbox"];
        highlightedImage = [UIImage imageNamed:@"icon_checkbox_checked"];
    }
    
    NSParameterAssert(image);
    NSParameterAssert(highlightedImage);
    self.iconImageView.image = image;
    self.iconImageView.highlightedImage = highlightedImage;
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self setNeedsLayout];
}

#pragma mark - Private

- (void)tapGestureAction:(id)sender {
    self.on = !self.isOn;

    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)setCurrentSize:(CGSize)currentSize {
    _currentSize = currentSize;

    [self invalidateIntrinsicContentSize];
}

@end

NS_ASSUME_NONNULL_END
