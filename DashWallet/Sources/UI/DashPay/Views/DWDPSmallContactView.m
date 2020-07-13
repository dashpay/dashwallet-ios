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

#import "DWDPSmallContactView.h"

#import "DWDPAvatarView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPSmallContactView ()

@property (readonly, nonatomic, strong) DWDPAvatarView *avatarView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPSmallContactView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup_smallContactView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup_smallContactView];
    }
    return self;
}

- (void)setup_smallContactView {
    DWDPAvatarView *avatarView = [[DWDPAvatarView alloc] initWithFrame:CGRectZero];
    avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarView.small = YES;
    avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
    [self addSubview:avatarView];
    _avatarView = avatarView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.textColor = [UIColor dw_darkTitleColor];
    titleLabel.numberOfLines = 0;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.5;
    [self addSubview:titleLabel];
    _titleLabel = titleLabel;

    const CGFloat avatarSize = 30.0;

    [NSLayoutConstraint activateConstraints:@[
        [avatarView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor],
        [avatarView.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
        [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:avatarView.bottomAnchor],
        [avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [avatarView.widthAnchor constraintEqualToConstant:avatarSize],
        [avatarView.heightAnchor constraintEqualToConstant:avatarSize],

        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor
                                                 constant:12.0],
        [self.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
        [self.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
    ]];
}

- (void)setItem:(id<DWDPBasicUserItem>)item {
    _item = item;

    self.avatarView.username = item.username;
    self.titleLabel.text = item.displayName ?: item.username;
}

@end
