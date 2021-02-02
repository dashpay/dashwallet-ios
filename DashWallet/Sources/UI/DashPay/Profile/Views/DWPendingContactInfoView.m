//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWPendingContactInfoView.h"

#import "DWHourGlassAnimationView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPendingContactInfoView ()

@property (readonly, nonatomic, strong) DWHourGlassAnimationView *animationView;
@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWPendingContactInfoView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_disabledButtonColor];

        self.layer.masksToBounds = YES;
        self.layer.cornerRadius = 8;

        DWHourGlassAnimationView *animationView = [[DWHourGlassAnimationView alloc] initWithFrame:CGRectZero];
        animationView.translatesAutoresizingMaskIntoConstraints = NO;
        _animationView = animationView;

        UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"dp_pending_contact"]];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.contentMode = UIViewContentModeCenter;
        _iconImageView = imageView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.numberOfLines = 0;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel = titleLabel;

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:animationView];
        [contentView addSubview:imageView];
        [contentView addSubview:titleLabel];
        [self addSubview:contentView];

        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [contentView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintGreaterThanOrEqualToAnchor:contentView.trailingAnchor],

            [animationView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [animationView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
            [imageView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [imageView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:animationView.trailingAnchor
                                                     constant:15.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor
                                                     constant:15.0],
            [contentView.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        ]];
    }
    return self;
}

- (void)setAsSendingRequest {
    self.iconImageView.hidden = YES;

    self.animationView.hidden = NO;
    [self.animationView startAnimating];

    self.titleLabel.text = NSLocalizedString(@"Sending Contact Request", nil);
}

- (void)setAsPendingRequest {
    self.animationView.hidden = YES;
    [self.animationView stopAnimating];

    self.iconImageView.hidden = NO;

    self.titleLabel.text = NSLocalizedString(@"Contact Request Pending", nil);
}

@end
