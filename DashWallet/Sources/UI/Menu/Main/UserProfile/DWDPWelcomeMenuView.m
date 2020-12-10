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

#import "DWDPWelcomeMenuView.h"

#import "DWActionButton.h"
#import "DWShadowView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const ButtonHeight = 39.0;

@interface DWDPWelcomeMenuView ()

@end

NS_ASSUME_NONNULL_END

@implementation DWDPWelcomeMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        DWShadowView *shadowView = [[DWShadowView alloc] initWithFrame:CGRectZero];
        shadowView.translatesAutoresizingMaskIntoConstraints = NO;
        shadowView.insetsLayoutMarginsFromSafeArea = YES;
        [self addSubview:shadowView];

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = [UIColor dw_backgroundColor];
        contentView.layer.cornerRadius = 8.0;
        contentView.layer.masksToBounds = YES;
        [shadowView addSubview:contentView];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.numberOfLines = 0;
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        titleLabel.text = NSLocalizedString(@"Join DashPay", nil);
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [contentView addSubview:titleLabel];

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.textColor = [UIColor dw_tertiaryTextColor];
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.adjustsFontForContentSizeCategory = YES;
        subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
        subtitleLabel.text = NSLocalizedString(@"Create a username, add your friends.", nil);
        subtitleLabel.textAlignment = NSTextAlignmentCenter;
        [contentView addSubview:subtitleLabel];

        DWActionButton *joinButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        joinButton.translatesAutoresizingMaskIntoConstraints = NO;
        joinButton.usedOnDarkBackground = NO;
        joinButton.small = YES;
        joinButton.inverted = NO;
        [joinButton setTitle:NSLocalizedString(@"Join", nil) forState:UIControlStateNormal];
        [contentView addSubview:joinButton];
        _joinButton = joinButton;

        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 1 forAxis:UILayoutConstraintAxisVertical];
        [subtitleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 2 forAxis:UILayoutConstraintAxisVertical];

        const CGFloat padding = 16.0;
        const CGFloat horizontalPadding = 12;
        const CGFloat verticalPadding = 16;
        [NSLayoutConstraint activateConstraints:@[
            [shadowView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                     constant:padding],
            [shadowView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.trailingAnchor constraintEqualToAnchor:shadowView.trailingAnchor
                                                constant:padding],
            [self.bottomAnchor constraintEqualToAnchor:shadowView.bottomAnchor
                                              constant:8.0],

            [contentView.leadingAnchor constraintEqualToAnchor:shadowView.leadingAnchor],
            [contentView.topAnchor constraintEqualToAnchor:shadowView.topAnchor],
            [shadowView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [shadowView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:25.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                     constant:horizontalPadding],
            [contentView.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                       constant:horizontalPadding],

            [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                    constant:2.0],
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                        constant:horizontalPadding],
            [contentView.trailingAnchor constraintEqualToAnchor:subtitleLabel.trailingAnchor
                                                       constant:horizontalPadding],


            [joinButton.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor
                                                 constant:22.0],
            [joinButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:joinButton.bottomAnchor
                                                     constant:12.0],

            [joinButton.heightAnchor constraintEqualToConstant:ButtonHeight],
        ]];
    }
    return self;
}

@end
