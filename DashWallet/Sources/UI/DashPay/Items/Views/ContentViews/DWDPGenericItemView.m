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

#import "DWDPGenericItemView.h"

#import "DWUIKit.h"
#import "UIFont+DWDPItem.h"

static CGFloat const AVATAR_SIZE = 36.0;

@implementation DWDPGenericItemView

@synthesize avatarView = _avatarView;
@synthesize textLabel = _textLabel;
@synthesize accessoryView = _accessoryView;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup_genericItemView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup_genericItemView];
    }
    return self;
}

- (void)setup_genericItemView {
    DWDPAvatarView *avatarView = [[DWDPAvatarView alloc] initWithFrame:CGRectZero];
    avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarView.small = YES;
    avatarView.backgroundMode = DWDPAvatarBackgroundMode_Random;
    [self addSubview:avatarView];
    _avatarView = avatarView;

    UILabel *textLabel = [[UILabel alloc] init];
    textLabel.translatesAutoresizingMaskIntoConstraints = NO;
    textLabel.font = [UIFont dw_itemTitleFont];
    textLabel.adjustsFontForContentSizeCategory = YES;
    textLabel.textColor = [UIColor dw_darkTitleColor];
    textLabel.numberOfLines = 0;
    [self addSubview:textLabel];
    _textLabel = textLabel;

    UIView *accessoryView = [[UIView alloc] init];
    accessoryView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:accessoryView];
    _accessoryView = accessoryView;

    [textLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [accessoryView setContentCompressionResistancePriority:UILayoutPriorityRequired - 2 forAxis:UILayoutConstraintAxisVertical];

    [textLabel setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [accessoryView setContentHuggingPriority:UILayoutPriorityDefaultLow + 1 forAxis:UILayoutConstraintAxisHorizontal];

    [textLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 3 forAxis:UILayoutConstraintAxisHorizontal];
    [accessoryView setContentCompressionResistancePriority:UILayoutPriorityRequired - 2 forAxis:UILayoutConstraintAxisHorizontal];

    const CGFloat spacing = 10.0;

    NSLayoutConstraint *avatarTopConstraint = [avatarView.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor];
    avatarTopConstraint.priority = UILayoutPriorityRequired - 10;
    NSLayoutConstraint *avatarBottomConstraint = [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:avatarView.bottomAnchor];
    avatarBottomConstraint.priority = UILayoutPriorityRequired - 11;

    [NSLayoutConstraint activateConstraints:@[
        [avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        avatarTopConstraint,
        avatarBottomConstraint,
        [avatarView.widthAnchor constraintEqualToConstant:AVATAR_SIZE],
        [avatarView.heightAnchor constraintEqualToConstant:AVATAR_SIZE],

        [textLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [textLabel.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor
                                                constant:spacing],
        [self.bottomAnchor constraintEqualToAnchor:textLabel.bottomAnchor],

        [accessoryView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [accessoryView.leadingAnchor constraintEqualToAnchor:textLabel.trailingAnchor
                                                    constant:spacing],
        [self.trailingAnchor constraintEqualToAnchor:accessoryView.trailingAnchor],
        [self.bottomAnchor constraintEqualToAnchor:accessoryView.bottomAnchor],
    ]];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    [super setBackgroundColor:backgroundColor];

    self.textLabel.backgroundColor = backgroundColor;
    self.accessoryView.backgroundColor = backgroundColor;
}

@end
