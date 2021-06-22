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

#import <DashSync/DSPermissionNotification.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const DWDeviceDidShakeNotification = @"DWDeviceDidShakeNotification";

@interface DWWindow ()

@property (nullable, nonatomic, strong) UIVisualEffectView *blurView;
@property (nullable, nonatomic, strong) NSDate *lastPermissionRequestDate;

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
        [notificationCenter addObserver:self
                               selector:@selector(willRequestOSPermissionNotification)
                                   name:DSWillRequestOSPermissionNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(didRequestOSPermissionNotification)
                                   name:DSDidRequestOSPermissionNotification
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

#pragma mark - Notifications

- (void)applicationWillResignActiveNotification {
    if (self.blurView) {
        return;
    }

    const NSTimeInterval allowedGap = 1;
    if (self.lastPermissionRequestDate && -[self.lastPermissionRequestDate timeIntervalSinceNow] < allowedGap) {
        return;
    }

    UIVisualEffectView *visualEffectView = [self createVisualEffectView];
    [self addSubview:visualEffectView];
    self.blurView = visualEffectView;
}

- (void)applicationDidBecomeActiveNotification {
    [self.blurView removeFromSuperview];
    self.blurView = nil;
}

- (void)willRequestOSPermissionNotification {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");
    self.lastPermissionRequestDate = [NSDate date];
}

- (void)didRequestOSPermissionNotification {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");
    self.lastPermissionRequestDate = nil;
}

#pragma mark - Private

- (UIVisualEffectView *)createVisualEffectView {
    UIVisualEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    UIVisualEffectView *visualEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    visualEffectView.frame = [UIScreen mainScreen].bounds;
    visualEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    return visualEffectView;
}

@end

NS_ASSUME_NONNULL_END
