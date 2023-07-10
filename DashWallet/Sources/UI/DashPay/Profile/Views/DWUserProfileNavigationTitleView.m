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

#import "DWUserProfileNavigationTitleView.h"

#import "DWDPAvatarView.h"
#import "DWUIKit.h"

#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

static CGFloat const AVATAR_SIZE = 28.0;
static CGFloat const VIEW_HEIGHT = 44.0;

@interface DWUserProfileNavigationTitleView ()

@property (readonly, nonatomic, strong) DWDPAvatarView *avatarView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) NSLayoutConstraint *titleTopConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileNavigationTitleView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;

        DWDPAvatarView *avatarView = [[DWDPAvatarView alloc] initWithFrame:CGRectZero];
        avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        avatarView.small = YES;
        avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
        [self addSubview:avatarView];
        _avatarView = avatarView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = self.backgroundColor;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.font = [UIFont dw_navigationBarTitleFont];
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisHorizontal];

        [NSLayoutConstraint activateConstraints:@[
            [avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [avatarView.widthAnchor constraintEqualToConstant:AVATAR_SIZE],
            [avatarView.heightAnchor constraintEqualToConstant:AVATAR_SIZE],

            (_titleTopConstraint = [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor]),
            [titleLabel.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor
                                                     constant:10.0],
            [self.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [titleLabel.heightAnchor constraintEqualToAnchor:self.heightAnchor],
        ]];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, VIEW_HEIGHT);
}

- (void)updateWithBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self.titleLabel.text = blockchainIdentity.currentDashpayUsername;
    self.avatarView.blockchainIdentity = blockchainIdentity;

    [self setScrollingPercent:0.0];
}

- (void)setScrollingPercent:(float)percent {
    const CGFloat threshold = 0.4;
    if (percent > threshold) {
        const float translatedPercent = (percent - threshold) * (1.0 / (1.0 - threshold));
        self.avatarView.alpha = MIN(1.0, translatedPercent);
        self.titleTopConstraint.constant = MAX(0.0, VIEW_HEIGHT * (1.0 - translatedPercent));
    }
    else {
        self.avatarView.alpha = 0.0;
        self.titleTopConstraint.constant = VIEW_HEIGHT;
    }
}

@end
