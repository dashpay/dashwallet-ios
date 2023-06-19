//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWErrorUpdatingUserProfileView.h"

#import "DWActionButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const ButtonHeight = 39.0;

@interface DWErrorUpdatingUserProfileView ()
@end

NS_ASSUME_NONNULL_END

@implementation DWErrorUpdatingUserProfileView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:contentView];

        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon_error"]];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:iconImageView];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        titleLabel.textColor = [UIColor dw_secondaryTextColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.numberOfLines = 0;
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        titleLabel.minimumScaleFactor = 0.5;
        titleLabel.text = NSLocalizedString(@"Error updating your profile", nil);
        [contentView addSubview:titleLabel];

        DWActionButton *retryButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        retryButton.translatesAutoresizingMaskIntoConstraints = NO;
        retryButton.usedOnDarkBackground = NO;
        retryButton.small = YES;
        retryButton.inverted = NO;
        [retryButton setTitle:NSLocalizedString(@"Try again", nil) forState:UIControlStateNormal];
        [retryButton addTarget:self
                        action:@selector(retryButtonAction:)
              forControlEvents:UIControlEventTouchUpInside];

        DWActionButton *cancelButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        cancelButton.usedOnDarkBackground = NO;
        cancelButton.small = YES;
        cancelButton.inverted = YES;
        [cancelButton setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];
        [cancelButton addTarget:self
                         action:@selector(cancelButtonAction:)
               forControlEvents:UIControlEventTouchUpInside];

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ retryButton, cancelButton ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisHorizontal;
        stackView.distribution = UIStackViewDistributionFillEqually;
        stackView.spacing = 9.0;
        stackView.alignment = UIStackViewAlignmentCenter;
        [contentView addSubview:stackView];

        const CGFloat padding = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                      constant:padding],
            [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentView.bottomAnchor],
            [self.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                constant:padding],
            [contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [iconImageView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [iconImageView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:iconImageView.bottomAnchor
                                                 constant:padding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

            [stackView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                constant:50],
            [stackView.leadingAnchor constraintGreaterThanOrEqualToAnchor:contentView.leadingAnchor],
            [contentView.trailingAnchor constraintGreaterThanOrEqualToAnchor:stackView.trailingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:stackView.bottomAnchor],
            [stackView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],

            [retryButton.heightAnchor constraintEqualToConstant:ButtonHeight],
            [cancelButton.heightAnchor constraintEqualToConstant:ButtonHeight],
        ]];
    }
    return self;
}

- (void)cancelButtonAction:(UIButton *)sender {
    [self.delegate errorUpdatingUserProfileView:self cancelAction:sender];
}

- (void)retryButtonAction:(UIButton *)sender {
    [self.delegate errorUpdatingUserProfileView:self retryAction:sender];
}

@end
