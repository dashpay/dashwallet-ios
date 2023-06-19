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

#import "DWAvatarExternalLoadingView.h"

#import "DWActionButton.h"
#import "DWHourGlassAnimationView.h"
#import "DWUIKit.h"


NS_ASSUME_NONNULL_BEGIN

static CGFloat const ButtonHeight = 39.0;

@interface DWAvatarExternalLoadingView ()

@property (readonly, nonatomic, strong) DWHourGlassAnimationView *animationView;

@end

NS_ASSUME_NONNULL_END

@implementation DWAvatarExternalLoadingView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        const CGFloat circleSize = 86.0;

        UIView *bgView = [[UIView alloc] init];
        bgView.translatesAutoresizingMaskIntoConstraints = NO;
        bgView.backgroundColor = [UIColor colorWithRed:1.0 green:232.0 / 255.0 blue:194.0 / 255.0 alpha:1.0];
        bgView.layer.cornerRadius = circleSize / 2.0;
        bgView.layer.masksToBounds = YES;
        [self addSubview:bgView];

        DWHourGlassAnimationView *animationView = [[DWHourGlassAnimationView alloc] initWithFrame:CGRectZero];
        animationView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:animationView];
        _animationView = animationView;

        UILabel *subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.textAlignment = NSTextAlignmentCenter;
        subtitleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        subtitleLabel.textColor = [UIColor dw_darkTitleColor];
        subtitleLabel.text = NSLocalizedString(@"Fetching Image", nil);
        [self addSubview:subtitleLabel];

        DWActionButton *cancelButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
        cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        cancelButton.usedOnDarkBackground = NO;
        cancelButton.small = YES;
        cancelButton.inverted = YES;
        [cancelButton setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];
        [cancelButton addTarget:self
                         action:@selector(cancelButtonAction)
               forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:cancelButton];

        [NSLayoutConstraint activateConstraints:@[
            [bgView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [bgView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [bgView.widthAnchor constraintEqualToConstant:circleSize],
            [bgView.heightAnchor constraintEqualToConstant:circleSize],

            [animationView.centerXAnchor constraintEqualToAnchor:bgView.centerXAnchor],
            [animationView.centerYAnchor constraintEqualToAnchor:bgView.centerYAnchor],

            [subtitleLabel.topAnchor constraintEqualToAnchor:bgView.bottomAnchor
                                                    constant:16.0],
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                        constant:8.0],
            [self.trailingAnchor constraintEqualToAnchor:subtitleLabel.trailingAnchor
                                                constant:8.0],

            [cancelButton.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor
                                                   constant:56.0],
            [cancelButton.heightAnchor constraintEqualToConstant:ButtonHeight],
            [cancelButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.bottomAnchor constraintEqualToAnchor:cancelButton.bottomAnchor],
        ]];
    }
    return self;
}

- (void)cancelButtonAction {
    [self.delegate avatarExternalLoadingViewCancelAction:self];
}

- (void)willMoveToWindow:(nullable UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];

    if (newWindow == nil) {
        [self.animationView stopAnimating];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];

    if (self.window) {
        [self.animationView startAnimating];
    }
}

@end
