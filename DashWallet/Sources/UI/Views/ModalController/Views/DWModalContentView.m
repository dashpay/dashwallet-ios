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

#import "DWModalContentView.h"

#import "DWModalChevronView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const PADDING = 16.0;
static CGFloat const TITLE_HEIGHT = 55.0;
static CGFloat const SEPARATOR = 1.0;

@interface DWModalContentView ()

@property (readonly, strong, nonatomic) DWModalChevronView *chevronView;
@property (readonly, strong, nonatomic) UILabel *titleLabel;

@end

@implementation DWModalContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        DWModalChevronView *chevronView = [[DWModalChevronView alloc] initWithFrame:CGRectZero];
        chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:chevronView];
        _chevronView = chevronView;

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = self.backgroundColor;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        titleLabel.minimumScaleFactor = 0.5;
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        UIView *separatorView = [[UIView alloc] initWithFrame:CGRectZero];
        separatorView.translatesAutoresizingMaskIntoConstraints = NO;
        separatorView.backgroundColor = [UIColor dw_separatorLineColor];
        [self addSubview:separatorView];

        UIView *contentView = [[UIView alloc] initWithFrame:CGRectZero];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = self.backgroundColor;
        [self addSubview:contentView];
        _contentView = contentView;

        [NSLayoutConstraint activateConstraints:@[
            [chevronView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                  constant:PADDING],
            [chevronView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:chevronView.bottomAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [titleLabel.heightAnchor constraintEqualToConstant:TITLE_HEIGHT],

            [separatorView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
            [separatorView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [separatorView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [separatorView.heightAnchor constraintEqualToConstant:SEPARATOR],

            [contentView.topAnchor constraintEqualToAnchor:separatorView.bottomAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (nullable NSString *)title {
    return self.titleLabel.text;
}

- (void)setTitle:(nullable NSString *)title {
    self.titleLabel.text = title;
}

- (void)setChevronViewFlattened:(BOOL)flattened {
    self.chevronView.flattened = flattened;
}

@end

NS_ASSUME_NONNULL_END
