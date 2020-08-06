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

#import "DWActionButton.h"
#import "DWDPAvatarView.h"
#import "DWUIKit.h"
#import "DWUserProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const AVATAR_SIZE = 128.0;
static CGFloat const BUTTON_HEIGHT = 40.0;

@interface DWUserProfileHeaderView ()

@property (readonly, nonatomic, strong) UIView *centerContentView;
@property (readonly, nonatomic, strong) DWDPAvatarView *avatarView;
@property (readonly, nonatomic, strong) UILabel *detailsLabel;
@property (readonly, nonatomic, strong) UIView *bottomContentView;
@property (readonly, nonatomic, strong) UILabel *pendingLabel;
@property (readonly, nonatomic, strong) DWActionButton *actionButton;
@property (readonly, nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;

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

        UILabel *pendingLabel = [[UILabel alloc] init];
        pendingLabel.translatesAutoresizingMaskIntoConstraints = NO;
        pendingLabel.attributedText = [self.class pendingInfo];
        pendingLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        pendingLabel.textAlignment = NSTextAlignmentCenter;
        pendingLabel.textColor = [UIColor dw_orangeColor];
        _pendingLabel = pendingLabel;

        UIStackView *pendingStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ pendingLabel ]];
        pendingStackView.translatesAutoresizingMaskIntoConstraints = NO;
        pendingStackView.axis = UILayoutConstraintAxisVertical;
        [bottomContentView addSubview:pendingStackView];

        DWActionButton *actionButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        [actionButton addTarget:self action:@selector(actionButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [actionButton setTitle:NSLocalizedString(@"Pay", nil) forState:UIControlStateNormal];
        [bottomContentView addSubview:actionButton];
        _actionButton = actionButton;

        UIActivityIndicatorView *activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
        activityIndicatorView.color = [UIColor dw_dashBlueColor];
        [bottomContentView addSubview:activityIndicatorView];
        _activityIndicatorView = activityIndicatorView;

        UILayoutGuide *guide = self.layoutMarginsGuide;

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

            [bottomGrayView.topAnchor constraintEqualToAnchor:actionButton.centerYAnchor],
            [bottomGrayView.leadingAnchor constraintEqualToAnchor:bottomContentView.leadingAnchor],
            [bottomContentView.trailingAnchor constraintEqualToAnchor:bottomGrayView.trailingAnchor],
            [bottomContentView.bottomAnchor constraintEqualToAnchor:bottomGrayView.bottomAnchor],

            [pendingStackView.topAnchor constraintEqualToAnchor:bottomContentView.topAnchor],
            [pendingStackView.leadingAnchor constraintEqualToAnchor:bottomContentView.leadingAnchor
                                                           constant:buttonPadding],
            [bottomContentView.trailingAnchor constraintEqualToAnchor:pendingStackView.trailingAnchor
                                                             constant:buttonPadding],

            [actionButton.topAnchor constraintEqualToAnchor:pendingStackView.bottomAnchor
                                                   constant:spacing],
            [actionButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor
                                                       constant:buttonPadding],
            [guide.trailingAnchor constraintEqualToAnchor:actionButton.trailingAnchor
                                                 constant:buttonPadding],
            [bottomContentView.bottomAnchor constraintEqualToAnchor:actionButton.bottomAnchor
                                                           constant:spacing],
            [actionButton.heightAnchor constraintEqualToConstant:BUTTON_HEIGHT],

            [activityIndicatorView.centerYAnchor constraintEqualToAnchor:actionButton.centerYAnchor],
            [activityIndicatorView.centerXAnchor constraintEqualToAnchor:bottomContentView.centerXAnchor],
        ]];

        [self mvvm_observe:DW_KEYPATH(self, model.state)
                      with:^(typeof(self) self, id value) {
                          [self updateState:self.model.state];
                      }];
    }
    return self;
}

- (void)setModel:(DWUserProfileModel *)model {
    _model = model;

    [self updateUsername:model.username];
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

#pragma mark - Private

- (void)updateState:(DWUserProfileModelState)state {
    switch (state) {
        case DWUserProfileModelState_None:
            self.actionButton.hidden = YES;
            self.pendingLabel.hidden = YES;
            [self.activityIndicatorView stopAnimating];

            break;
        case DWUserProfileModelState_Error:
            [self.activityIndicatorView stopAnimating];
            [self updateActions];

            break;
        case DWUserProfileModelState_Loading:
            self.actionButton.hidden = YES;
            self.pendingLabel.hidden = YES;
            [self.activityIndicatorView startAnimating];

            break;
        case DWUserProfileModelState_Done:
            [self.activityIndicatorView stopAnimating];
            [self updateActions];
            break;
    }
}

- (void)updateUsername:(NSString *)username {
    self.detailsLabel.text = username;
    self.avatarView.username = username;

    [self setScrollingPercent:0.0];
}

- (void)updateActions {
    const DSBlockchainIdentityFriendshipStatus friendshipStatus = self.model.friendshipStatus;
    switch (friendshipStatus) {
        case DSBlockchainIdentityFriendshipStatus_Unknown:
        case DSBlockchainIdentityFriendshipStatus_None:
            self.actionButton.hidden = YES;
            self.pendingLabel.hidden = YES;

            break;
        case DSBlockchainIdentityFriendshipStatus_Outgoing:
            self.actionButton.hidden = YES;
            self.pendingLabel.hidden = NO;

            break;
        case DSBlockchainIdentityFriendshipStatus_Incoming:
        case DSBlockchainIdentityFriendshipStatus_Friends:
            self.actionButton.hidden = NO;
            self.pendingLabel.hidden = YES;

            break;
    }
}

- (void)actionButtonAction:(UIButton *)sender {
    [self.delegate userProfileHeaderView:self actionButtonAction:sender];
}

+ (NSAttributedString *)pendingInfo {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    UIImage *image = [UIImage imageNamed:@"dp_pending_contact"];
    NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
    textAttachment.image = image;
    textAttachment.bounds = CGRectMake(-3.0, -2.0, image.size.width, image.size.height);

    [result beginEditing];
    [result appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"Contact Request Pending", nil)]];
    [result endEditing];

    return [result copy];
}

@end
