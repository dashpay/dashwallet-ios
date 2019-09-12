//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWWindow.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const DWDeviceDidShakeNotification = @"DWDeviceDidShakeNotification";

static NSTimeInterval const BLUR_ANIMATION_DURATION = 0.15;

@interface DWWindow ()

@property (nullable, nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, assign, getter=isBlurringDisabled) BOOL blurringDisabled;

@end

@implementation DWWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(applicationWillResignActiveNotification)
                                   name:UIApplicationWillResignActiveNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(applicationDidBecomeActiveNotification)
                                   name:UIApplicationDidBecomeActiveNotification
                                 object:nil];
    }
    return self;
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(nullable UIEvent *)event {
    [super motionEnded:motion withEvent:event];

    if (event.type == UIEventTypeMotion && event.subtype == UIEventSubtypeMotionShake) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DWDeviceDidShakeNotification
                                                            object:nil];
    }
}

- (void)setBlurringScreenDisabledOneTime {
    self.blurringDisabled = YES;
}

#pragma mark - Notifications

- (void)applicationWillResignActiveNotification {
    if (self.isBlurringDisabled) {
        return;
    }

    if (self.blurView) {
        return;
    }

    UIVisualEffectView *visualEffectView = [self createVisualEffectView];
    visualEffectView.alpha = 0.0;
    [self addSubview:visualEffectView];
    self.blurView = visualEffectView;

    UIViewPropertyAnimator *animator =
        [[UIViewPropertyAnimator alloc] initWithDuration:BLUR_ANIMATION_DURATION
                                                   curve:UIViewAnimationCurveLinear
                                              animations:^{
                                                  visualEffectView.alpha = 1.0;
                                              }];
    [animator startAnimation];
}

- (void)applicationDidBecomeActiveNotification {
    self.blurringDisabled = NO;

    if (!self.blurView) {
        return;
    }

    UIViewPropertyAnimator *animator =
        [[UIViewPropertyAnimator alloc] initWithDuration:BLUR_ANIMATION_DURATION
                                                   curve:UIViewAnimationCurveLinear
                                              animations:^{
                                                  self.blurView.alpha = 0.0;
                                              }];
    [animator addCompletion:^(UIViewAnimatingPosition finalPosition) {
        [self.blurView removeFromSuperview];
        self.blurView = nil;
    }];
    [animator startAnimation];
}

#pragma mark - Private

- (UIVisualEffectView *)createVisualEffectView {
    UIVisualEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    UIVisualEffectView *visualEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    visualEffectView.frame = [UIScreen mainScreen].bounds;
    visualEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    visualEffectView.backgroundColor = [UIColor clearColor];

    return visualEffectView;
}

@end

NS_ASSUME_NONNULL_END
