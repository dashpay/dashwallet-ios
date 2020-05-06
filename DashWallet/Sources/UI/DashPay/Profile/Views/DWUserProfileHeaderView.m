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

#import "DWUserProfileHeaderView.h"

#import "DWBlueActionButton.h"
#import "DWDPAvatarView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const AVATAR_SIZE = 128.0;
static CGFloat const BUTTON_HEIGHT = 40.0;

@interface DWUserProfileHeaderView ()

@property (readonly, nonatomic, strong) UIView *centerContentView;
@property (readonly, nonatomic, strong) DWDPAvatarView *avatarView;
@property (readonly, nonatomic, strong) UILabel *detailsLabel;
@property (readonly, nonatomic, strong) UIView *bottomContentView;
@property (readonly, nonatomic, strong) DWBlueActionButton *actionButton;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        UIView *topContainerView = [[UIView alloc] init];
        topContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        topContainerView.backgroundColor = self.backgroundColor;
#ifdef DEBUG
        topContainerView.accessibilityIdentifier = @"topContainerView";
#endif /* DEBUG */
        [self addSubview:topContainerView];

        UIView *centerContentView = [[UIView alloc] init];
        centerContentView.translatesAutoresizingMaskIntoConstraints = NO;
        centerContentView.backgroundColor = self.backgroundColor;
#ifdef DEBUG
        centerContentView.accessibilityIdentifier = @"centerContentView";
#endif /* DEBUG */
        [topContainerView addSubview:centerContentView];
        _centerContentView = centerContentView;

        DWDPAvatarView *avatarView = [[DWDPAvatarView alloc] initWithFrame:CGRectZero];
        avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
#ifdef DEBUG
        avatarView.accessibilityIdentifier = @"avatarView";
#endif /* DEBUG */
        [centerContentView addSubview:avatarView];
        _avatarView = avatarView;

        UILabel *detailsLabel = [[UILabel alloc] init];
        detailsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        detailsLabel.backgroundColor = self.backgroundColor;
        detailsLabel.textColor = [UIColor dw_darkTitleColor];
        detailsLabel.textAlignment = NSTextAlignmentCenter;
        detailsLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        detailsLabel.adjustsFontForContentSizeCategory = YES;
        detailsLabel.numberOfLines = 0;
        [centerContentView addSubview:detailsLabel];
        _detailsLabel = detailsLabel;

        UIView *bottomContentView = [[UIView alloc] init];
        bottomContentView.translatesAutoresizingMaskIntoConstraints = NO;
        bottomContentView.backgroundColor = self.backgroundColor;
#ifdef DEBUG
        bottomContentView.accessibilityIdentifier = @"bottomContentView";
#endif /* DEBUG */
        [self addSubview:bottomContentView];
        _bottomContentView = bottomContentView;

        UIView *bottomGrayView = [[UIView alloc] init];
        bottomGrayView.translatesAutoresizingMaskIntoConstraints = NO;
        bottomGrayView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
#ifdef DEBUG
        bottomGrayView.accessibilityIdentifier = @"bottomGrayView";
#endif /* DEBUG */
        [bottomContentView addSubview:bottomGrayView];

        DWBlueActionButton *actionButton = [[DWBlueActionButton alloc] initWithFrame:CGRectZero];
        actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        [bottomContentView addSubview:actionButton];
        _actionButton = actionButton;

        UILayoutGuide *guide = self.layoutMarginsGuide;

        const CGFloat overlap = BUTTON_HEIGHT / 2.0;
        const CGFloat buttonPadding = 16.0;
        const CGFloat spacing = 20.0;

        [detailsLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                      forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [topContainerView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [topContainerView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:topContainerView.trailingAnchor],

            [bottomContentView.topAnchor constraintEqualToAnchor:topContainerView.bottomAnchor
                                                        constant:spacing],
            [bottomContentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:bottomContentView.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:bottomContentView.bottomAnchor],

            [centerContentView.topAnchor constraintGreaterThanOrEqualToAnchor:topContainerView.topAnchor],
            [centerContentView.leadingAnchor constraintEqualToAnchor:topContainerView.leadingAnchor],
            [topContainerView.trailingAnchor constraintEqualToAnchor:centerContentView.trailingAnchor],
            [topContainerView.bottomAnchor constraintGreaterThanOrEqualToAnchor:centerContentView.bottomAnchor],
            [centerContentView.centerYAnchor constraintEqualToAnchor:topContainerView.centerYAnchor],

            [avatarView.topAnchor constraintEqualToAnchor:centerContentView.topAnchor],
            [avatarView.centerXAnchor constraintEqualToAnchor:centerContentView.centerXAnchor],
            [avatarView.widthAnchor constraintEqualToConstant:AVATAR_SIZE],
            [avatarView.heightAnchor constraintEqualToConstant:AVATAR_SIZE],

            [detailsLabel.topAnchor constraintEqualToAnchor:avatarView.bottomAnchor
                                                   constant:spacing],
            [detailsLabel.leadingAnchor constraintEqualToAnchor:centerContentView.leadingAnchor],
            [centerContentView.trailingAnchor constraintEqualToAnchor:detailsLabel.trailingAnchor],
            [centerContentView.bottomAnchor constraintEqualToAnchor:detailsLabel.bottomAnchor],

            [bottomGrayView.topAnchor constraintEqualToAnchor:bottomContentView.topAnchor
                                                     constant:overlap],
            [bottomGrayView.leadingAnchor constraintEqualToAnchor:bottomContentView.leadingAnchor],
            [bottomContentView.trailingAnchor constraintEqualToAnchor:bottomGrayView.trailingAnchor],
            [bottomContentView.bottomAnchor constraintEqualToAnchor:bottomGrayView.bottomAnchor],

            [actionButton.topAnchor constraintEqualToAnchor:bottomContentView.topAnchor],
            [actionButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor
                                                       constant:buttonPadding],
            [guide.trailingAnchor constraintEqualToAnchor:actionButton.trailingAnchor
                                                 constant:buttonPadding],
            [actionButton.heightAnchor constraintEqualToConstant:BUTTON_HEIGHT],
            [bottomContentView.bottomAnchor constraintEqualToAnchor:actionButton.bottomAnchor],
        ]];
    }
    return self;
}

- (void)updateWithUsername:(NSString *)username {
    self.detailsLabel.text = username;
    self.avatarView.username = username;

    // TODO
    [self.actionButton setTitle:@"Send Contact Request" forState:UIControlStateNormal];

    [self setScrollingPercent:0.0];
}

- (void)setScrollingPercent:(float)percent {
    if (percent < 0) { // stretching
        const CGFloat scale = MIN(1.5, 1.0 + ABS(percent));
        self.centerContentView.transform = CGAffineTransformMakeScale(scale, scale);
        self.centerContentView.alpha = 1.0;
    }
    else {
        self.centerContentView.transform = CGAffineTransformIdentity;
        self.centerContentView.alpha = MAX(0.0, 1.0 - percent * 2.5); // x2.5 speed

        const CGFloat threshold = 0.5;
        if (percent > threshold) {
            const float translatedPercent = (percent - threshold) * (1.0 / (1.0 - threshold));
            const CGFloat clampPercent = MIN(1.0, translatedPercent);
            self.actionButton.alpha = 1.0 - clampPercent * 2; // 2x speed
        }
        else {
            self.actionButton.alpha = 1.0;
        }
    }
}

@end
