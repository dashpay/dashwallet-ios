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

#import "DWSuccessInvitationView.h"

#import "DWDPAvatarView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSuccessInvitationView ()

@property (readonly, nonatomic, strong) UIImageView *backImageView;
@property (readonly, nonatomic, strong) UIView *avatarContainer;
@property (readonly, nonatomic, strong) DWDPAvatarView *avatarView;
@property (readonly, nonatomic, strong) UIImageView *topImageView;
@property (readonly, nonatomic, strong) NSLayoutConstraint *avatarTopConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation DWSuccessInvitationView

- (DSBlockchainIdentity *)blockchainIdentity {
    return self.avatarView.blockchainIdentity;
}

- (void)setBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self.avatarView.blockchainIdentity = blockchainIdentity;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIImageView *backImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"invite_letterbox_back"]];
        backImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:backImageView];
        _backImageView = backImageView;

        UIView *avatarContainer = [[UIView alloc] init];
        avatarContainer.translatesAutoresizingMaskIntoConstraints = NO;
        avatarContainer.backgroundColor = [UIColor dw_lightBlueColor];
        [self addSubview:avatarContainer];
        _avatarContainer = avatarContainer;

        DWDPAvatarView *avatarView = [[DWDPAvatarView alloc] initWithFrame:CGRectZero];
        avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
        [avatarContainer addSubview:avatarView];
        _avatarView = avatarView;

        UIImageView *topImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"invite_letterbox_top"]];
        topImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:topImageView];
        _topImageView = topImageView;

        NSLayoutConstraint *avatarTopConstraint = [avatarContainer.topAnchor constraintEqualToAnchor:self.topAnchor constant:56];
        _avatarTopConstraint = avatarTopConstraint;

        [NSLayoutConstraint activateConstraints:@[
            [backImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [backImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:backImageView.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:backImageView.bottomAnchor],

            [topImageView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                   constant:89.0],
            [topImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

            [avatarView.topAnchor constraintEqualToAnchor:avatarContainer.topAnchor
                                                 constant:8.0],
            [avatarView.leadingAnchor constraintEqualToAnchor:avatarContainer.leadingAnchor
                                                     constant:8.0],
            [avatarContainer.trailingAnchor constraintEqualToAnchor:avatarView.trailingAnchor
                                                           constant:8.0],
            [avatarContainer.bottomAnchor constraintEqualToAnchor:avatarView.bottomAnchor
                                                         constant:8.0],
            [avatarView.widthAnchor constraintEqualToConstant:64.0],
            [avatarView.heightAnchor constraintEqualToConstant:64.0],

            avatarTopConstraint,
            [avatarContainer.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        ]];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(152.0, 175.0);
}

- (void)prepareForAnimation {
    self.backImageView.alpha = 0;
    self.topImageView.alpha = 0;
    self.avatarContainer.alpha = 0;
    self.avatarTopConstraint.constant = 0;
    [self layoutIfNeeded];
}

- (void)showAnimated {
    [UIView animateWithDuration:0.35
        animations:^{
            self.backImageView.alpha = 1.0;
            self.topImageView.alpha = 1.0;
        }
        completion:^(BOOL finished) {
            self.avatarTopConstraint.constant = 56.0;
            [UIView animateWithDuration:0.35
                             animations:^{
                                 [self layoutIfNeeded];
                                 self.avatarContainer.alpha = 1.0;
                             }];
        }];
}

@end
