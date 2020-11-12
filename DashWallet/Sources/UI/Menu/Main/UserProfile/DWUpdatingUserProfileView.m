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

#import "DWUpdatingUserProfileView.h"

#import "DWDashPayAnimationView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpdatingUserProfileView ()

@property (readonly, nonatomic, strong) DWDashPayAnimationView *loadingView;

@end

NS_ASSUME_NONNULL_END

@implementation DWUpdatingUserProfileView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;

        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = self.backgroundColor;
        [self addSubview:contentView];

        DWDashPayAnimationView *loadingView = [[DWDashPayAnimationView alloc] init];
        loadingView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:loadingView];
        _loadingView = loadingView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        titleLabel.textColor = [UIColor dw_secondaryTextColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.numberOfLines = 0;
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        titleLabel.minimumScaleFactor = 0.5;
        titleLabel.text = NSLocalizedString(@"Updating Profile on Dash Network", nil);
        [contentView addSubview:titleLabel];

        const CGFloat padding = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                      constant:padding],
            [self.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentView.bottomAnchor],
            [self.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                constant:padding],
            [contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [loadingView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [loadingView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:loadingView.bottomAnchor
                                                 constant:padding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor],
        ]];
    }
    return self;
}

- (void)willMoveToWindow:(nullable UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];

    if (newWindow == nil) {
        [self.loadingView stopAnimating];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];

    if (self.window) {
        [self.loadingView startAnimating];
    }
}

@end
