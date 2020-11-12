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

#import "DWEditProfileAvatarView.h"

#import <DashSync/DashSync.h>
#import <SDWebImage/SDWebImage.h>

static CGFloat const AvatarSize = 134.0;
static CGSize const EditSize = {46.0, 45.0};

NS_ASSUME_NONNULL_BEGIN

@interface DWEditProfileAvatarView ()

@property (readonly, nonatomic, strong) UIImageView *avatarImageView;

@end

NS_ASSUME_NONNULL_END

@implementation DWEditProfileAvatarView

- (UIImage *)image {
    return self.avatarImageView.image;
}

- (void)setImage:(UIImage *)image {
    self.avatarImageView.image = image;
}

- (void)setImageWithBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    NSURL *url = [NSURL URLWithString:blockchainIdentity.matchingDashpayUserInViewContext.avatarPath];
    [self.avatarImageView sd_setImageWithURL:url placeholderImage:[UIImage imageNamed:@"dp_current_user_placeholder"]];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIImageView *avatarImageView = [[UIImageView alloc] init];
        avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
        avatarImageView.image = [UIImage imageNamed:@"dp_current_user_placeholder"];
        avatarImageView.layer.cornerRadius = AvatarSize / 2.0;
        avatarImageView.layer.masksToBounds = YES;
        [self addSubview:avatarImageView];
        _avatarImageView = avatarImageView;

        UIButton *editButton = [UIButton buttonWithType:UIButtonTypeCustom];
        editButton.translatesAutoresizingMaskIntoConstraints = NO;
        [editButton setImage:[UIImage imageNamed:@"dp_avatar_edit"] forState:UIControlStateNormal];
        [editButton addTarget:self action:@selector(editButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:editButton];

        const CGFloat topSpacing = 32.0;
        const CGFloat bottomSpacing = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [avatarImageView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                      constant:topSpacing],
            [avatarImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [avatarImageView.widthAnchor constraintEqualToConstant:AvatarSize],
            [avatarImageView.heightAnchor constraintEqualToConstant:AvatarSize],
            [self.bottomAnchor constraintEqualToAnchor:avatarImageView.bottomAnchor
                                              constant:bottomSpacing],

            [editButton.trailingAnchor constraintEqualToAnchor:avatarImageView.trailingAnchor],
            [editButton.bottomAnchor constraintEqualToAnchor:avatarImageView.bottomAnchor],
            [editButton.widthAnchor constraintEqualToConstant:EditSize.width],
            [editButton.heightAnchor constraintEqualToConstant:EditSize.height],
        ]];
    }
    return self;
}

- (void)editButtonAction:(UIButton *)sender {
    [self.delegate editProfileAvatarView:self editAvatarAction:sender];
}

@end
