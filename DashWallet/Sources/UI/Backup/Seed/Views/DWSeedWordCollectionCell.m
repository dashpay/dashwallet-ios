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

#import "DWSeedWordCollectionCell.h"

#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const VERTICAL_PADDING = 10.0;
static CGFloat const HORIZONTAL_PADDING = 4.0;

static UIFont *WordFont(void) {
    return [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
}

@interface DWSeedWordCollectionCell ()

@property (strong, nonatomic) UILabel *wordLabel;

@end

@implementation DWSeedWordCollectionCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupView];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [UIColor dw_backgroundColor];
    self.contentView.backgroundColor = self.backgroundColor;

    UILabel *wordLabel = [[UILabel alloc] init];
    wordLabel.translatesAutoresizingMaskIntoConstraints = NO;
    wordLabel.backgroundColor = self.backgroundColor;
    wordLabel.textColor = [UIColor dw_dashBlueColor];
    wordLabel.textAlignment = NSTextAlignmentCenter;
    wordLabel.adjustsFontForContentSizeCategory = YES;
    wordLabel.font = WordFont();
    wordLabel.numberOfLines = 0;
    wordLabel.adjustsFontSizeToFitWidth = YES;
    wordLabel.minimumScaleFactor = 0.5;
    [self.contentView addSubview:wordLabel];
    self.wordLabel = wordLabel;

    [NSLayoutConstraint activateConstraints:@[
        [wordLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                            constant:VERTICAL_PADDING],
        [wordLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                constant:HORIZONTAL_PADDING],
        [wordLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                               constant:-VERTICAL_PADDING],
        [wordLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                 constant:-HORIZONTAL_PADDING],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (nullable NSString *)text {
    return self.wordLabel.text;
}

- (void)setText:(nullable NSString *)text {
    NSAssert(self.wordLabel, @"Seed word cell is broken. It's crucially important!");
    NSAssert(text.length > 0, @"Invalid seed word");

    NSDictionary *attributes = @{
        NSFontAttributeName : WordFont(),
    };
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    self.wordLabel.attributedText = attributedString;
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self invalidateIntrinsicContentSize];
}

+ (CGSize)sizeForText:(NSString *)text maxWidth:(CGFloat)maxWidth {
    CGSize maxSize = CGSizeMake(maxWidth, CGFLOAT_MAX);
    NSDictionary *attributes = @{
        NSFontAttributeName : WordFont(),
    };

    CGRect rect = [text boundingRectWithSize:maxSize
                                     options:NSStringDrawingUsesLineFragmentOrigin
                                  attributes:attributes
                                     context:nil];

    CGSize size = CGSizeMake(ceil(CGRectGetWidth(rect) + HORIZONTAL_PADDING * 2),
                             ceil(CGRectGetHeight(rect) + VERTICAL_PADDING * 2));

    return size;
}

@end

NS_ASSUME_NONNULL_END
