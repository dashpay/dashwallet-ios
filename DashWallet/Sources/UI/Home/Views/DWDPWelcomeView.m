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

#import "DWDPWelcomeView.h"

#import "DWShadowView.h"
#import "DWUIKit.h"
#import "UIView+DWAnimations.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPWelcomeView ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *subtitleLabel;
@property (readonly, nonatomic, strong) UIImageView *arrowImageView;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPWelcomeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        self.layoutMargins = UIEdgeInsetsMake(0, 16, 0, 16);

        DWShadowView *shadowView = [[DWShadowView alloc] initWithFrame:CGRectZero];
        shadowView.translatesAutoresizingMaskIntoConstraints = NO;
        shadowView.insetsLayoutMarginsFromSafeArea = YES;
        shadowView.userInteractionEnabled = NO;
        [self addSubview:shadowView];

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = [UIColor dw_backgroundColor];
        contentView.layer.cornerRadius = 8.0;
        contentView.layer.masksToBounds = YES;
        contentView.userInteractionEnabled = NO;
        [shadowView addSubview:contentView];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.numberOfLines = 0;
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        titleLabel.text = NSLocalizedString(@"Join DashPay", nil);
        titleLabel.userInteractionEnabled = NO;
        [contentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.textColor = [UIColor dw_tertiaryTextColor];
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.adjustsFontForContentSizeCategory = YES;
        subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
        subtitleLabel.text = NSLocalizedString(@"Create a username, add your friends.", nil);
        subtitleLabel.userInteractionEnabled = NO;
        [contentView addSubview:subtitleLabel];
        _subtitleLabel = subtitleLabel;

        UIImageView *arrowImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pay_user_accessory"]];
        arrowImageView.translatesAutoresizingMaskIntoConstraints = NO;
        arrowImageView.userInteractionEnabled = NO;
        [contentView addSubview:arrowImageView];
        _arrowImageView = arrowImageView;

        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 1 forAxis:UILayoutConstraintAxisHorizontal];
        [subtitleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 2 forAxis:UILayoutConstraintAxisHorizontal];
        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 1 forAxis:UILayoutConstraintAxisVertical];
        [subtitleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 2 forAxis:UILayoutConstraintAxisVertical];

        const CGFloat horizontalPadding = 12;
        const CGFloat verticalPadding = 16;
        UILayoutGuide *guide = self.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [shadowView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [shadowView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:shadowView.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:shadowView.bottomAnchor],

            [contentView.leadingAnchor constraintEqualToAnchor:shadowView.leadingAnchor],
            [contentView.topAnchor constraintEqualToAnchor:shadowView.topAnchor],
            [shadowView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [shadowView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:verticalPadding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                     constant:horizontalPadding],

            [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                    constant:2.0],
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                        constant:horizontalPadding],
            [contentView.bottomAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor
                                                     constant:verticalPadding],

            [arrowImageView.leadingAnchor constraintEqualToAnchor:subtitleLabel.trailingAnchor
                                                         constant:horizontalPadding],
            [arrowImageView.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                         constant:horizontalPadding],
            [arrowImageView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:arrowImageView.trailingAnchor
                                                       constant:horizontalPadding],

            [arrowImageView.widthAnchor constraintEqualToConstant:32.0],
            [arrowImageView.heightAnchor constraintEqualToConstant:32.0],
        ]];
    }
    return self;
}

@end
