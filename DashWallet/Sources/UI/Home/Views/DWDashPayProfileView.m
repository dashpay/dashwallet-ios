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

#import "DWDashPayProfileView.h"

#import "DWDPAvatarView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize const AVATAR_SIZE = {72.0, 72.0};

@interface DWDashPayProfileView ()

@property (readonly, nonatomic, strong) DWDPAvatarView *avatarView;
@property (readonly, nonatomic, strong) UIImageView *bellImageView;

@end

NS_ASSUME_NONNULL_END

@implementation DWDashPayProfileView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_dashBlueColor];

        DWDPAvatarView *avatarView = [[DWDPAvatarView alloc] init];
        avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
        [self addSubview:avatarView];
        _avatarView = avatarView;

        UIImageView *bellImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon_bell"]];
        bellImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:bellImageView];
        _bellImageView = bellImageView;

        [NSLayoutConstraint activateConstraints:@[
            [avatarView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [avatarView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [avatarView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [avatarView.widthAnchor constraintEqualToConstant:AVATAR_SIZE.width],
            [avatarView.heightAnchor constraintEqualToConstant:AVATAR_SIZE.height],

            [bellImageView.trailingAnchor constraintEqualToAnchor:avatarView.trailingAnchor],
            [bellImageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)setUsername:(NSString *)username {
    _username = username;

    self.avatarView.username = username;
}

@end
