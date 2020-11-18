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

#import "DWCurrentUserProfileView.h"

#import "DSBlockchainIdentity+DWDisplayTitleSubtitle.h"
#import "DWButton.h"
#import "DWUIKit.h"

#import <DashSync/DashSync.h>
#import <SDWebImage/SDWebImage.h>

NS_ASSUME_NONNULL_BEGIN

static CGFloat const AvatarSize = 134.0;
static CGSize const ShowQRSize = {46.0, 45.0};

@interface DWCurrentUserProfileView ()

@property (readonly, nonatomic, strong) UIImageView *avatarImageView;
@property (readonly, nonatomic, strong) UILabel *infoLabel;
@property (readonly, nonatomic, strong) UIButton *editProfileButton;

@end

NS_ASSUME_NONNULL_END

@implementation DWCurrentUserProfileView

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

        UIButton *showQRButton = [UIButton buttonWithType:UIButtonTypeCustom];
        showQRButton.translatesAutoresizingMaskIntoConstraints = NO;
        [showQRButton setImage:[UIImage imageNamed:@"dp_show_qr"] forState:UIControlStateNormal];
        [showQRButton addTarget:self action:@selector(showQRButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:showQRButton];

        UILabel *infoLabel = [[UILabel alloc] init];
        infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
        infoLabel.numberOfLines = 0;
        infoLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:infoLabel];
        _infoLabel = infoLabel;

        DWButton *editProfileButton = [DWButton buttonWithType:UIButtonTypeSystem];
        editProfileButton.translatesAutoresizingMaskIntoConstraints = NO;
        editProfileButton.tintColor = [UIColor dw_dashBlueColor];
        [editProfileButton setTitle:NSLocalizedString(@"Edit Profile", nil) forState:UIControlStateNormal];
        [editProfileButton addTarget:self action:@selector(editProfileButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:editProfileButton];
        _editProfileButton = editProfileButton;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadAttributedData)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];

        const CGFloat padding = 20.0;
        const CGFloat spacing = 32.0;
        [NSLayoutConstraint activateConstraints:@[
            [avatarImageView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                      constant:spacing],
            [avatarImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [avatarImageView.widthAnchor constraintEqualToConstant:AvatarSize],
            [avatarImageView.heightAnchor constraintEqualToConstant:AvatarSize],

            [showQRButton.trailingAnchor constraintEqualToAnchor:avatarImageView.trailingAnchor],
            [showQRButton.bottomAnchor constraintEqualToAnchor:avatarImageView.bottomAnchor],
            [showQRButton.widthAnchor constraintEqualToConstant:ShowQRSize.width],
            [showQRButton.heightAnchor constraintEqualToConstant:ShowQRSize.height],

            [infoLabel.topAnchor constraintEqualToAnchor:avatarImageView.bottomAnchor
                                                constant:20],
            [infoLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:padding],
            [self.trailingAnchor constraintEqualToAnchor:infoLabel.trailingAnchor
                                                constant:padding],

            [editProfileButton.topAnchor constraintEqualToAnchor:infoLabel.bottomAnchor
                                                        constant:8.0],
            [editProfileButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                            constant:padding],
            [self.trailingAnchor constraintEqualToAnchor:editProfileButton.trailingAnchor
                                                constant:padding],
            [self.bottomAnchor constraintEqualToAnchor:editProfileButton.bottomAnchor
                                              constant:44.0],
            [editProfileButton.heightAnchor constraintEqualToConstant:spacing],
        ]];
    }
    return self;
}

- (void)setBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    _blockchainIdentity = blockchainIdentity;

    NSURL *url = [NSURL URLWithString:blockchainIdentity.avatarPath];
    [self.avatarImageView sd_setImageWithURL:url placeholderImage:[UIImage imageNamed:@"dp_current_user_placeholder"]];

    [self reloadAttributedData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self reloadAttributedData];
}

- (void)showQRButtonAction:(UIButton *)sender {
    [self.delegate currentUserProfileView:self showQRAction:sender];
}

- (void)editProfileButtonAction:(UIButton *)sender {
    [self.delegate currentUserProfileView:self editProfileAction:sender];
}

#pragma mark - Private

- (void)reloadAttributedData {
    self.infoLabel.attributedText = [self.blockchainIdentity dw_asTitleSubtitle];
}

@end
