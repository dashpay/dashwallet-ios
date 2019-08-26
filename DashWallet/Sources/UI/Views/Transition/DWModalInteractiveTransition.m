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

#import "DWModalInteractiveTransition.h"

#import "UIPanGestureRecognizer+DWProjected.h"
#import "UISpringTimingParameters+DWInit.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIPanGestureRecognizer (DWInteractiveTransactionHelper)
@end

@implementation UIPanGestureRecognizer (DWInteractiveTransactionHelper)

- (CGFloat)dw_percentOfTranslationSinceLastChange {
    UIView *view = self.view;
    const CGPoint translation = [self translationInView:view];
    [self setTranslation:CGPointZero inView:nil];

    const CGFloat viewHeight = CGRectGetHeight(view.bounds);
    const CGFloat percent = translation.y / viewHeight;

    return percent;
}

@end

@interface DWModalInteractiveTransition ()

@property (nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;

@end

@implementation DWModalInteractiveTransition

- (instancetype)init {
    self = [super init];
    if (self) {
        _presenting = YES;
    }
    return self;
}

- (void)setPresentedController:(nullable UIViewController *)controller {
    _presentedController = controller;

    self.panGestureRecognizer = [[UIPanGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(panGestureRecognizerAction:)];

    [controller.view addGestureRecognizer:self.panGestureRecognizer];
}

- (BOOL)wantsInteractiveStart {
    if (self.presenting) {
        return NO;
    }
    else {
        return self.panGestureRecognizer.state == UIGestureRecognizerStateBegan;
    }
}

#pragma mark - Actions

- (void)panGestureRecognizerAction:(UIPanGestureRecognizer *)sender {
    switch (sender.state) {
        case UIGestureRecognizerStateBegan: {
            [self pauseInteractiveTransition];

            if (self.isPresenting == NO && self.percentComplete == 0.0) {
                [self.presentedController dismissViewControllerAnimated:YES completion:nil];
            }

            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGFloat currentPercent = [sender dw_percentOfTranslationSinceLastChange];
            if (self.isPresenting) {
                currentPercent *= -1;
            }

            [self updateInteractiveTransition:self.percentComplete + currentPercent];

            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            const CGFloat velocity = [sender dw_projectedVelocity:UIScrollViewDecelerationRateNormal].y;
            if (velocity != 0) {
                const CGFloat height = CGRectGetHeight(sender.view.bounds);
                const CGFloat distanceRemaining = height - self.percentComplete * height;
                if (distanceRemaining > 0) {
                    const CGFloat relativeVelocity = MIN(ABS(velocity) / distanceRemaining, 30);
                    self.timingCurve =
                        [[UISpringTimingParameters alloc] initWithDamping:0.8
                                                                 response:0.3
                                                          initialVelocity:CGVectorMake(relativeVelocity, relativeVelocity)];
                }
            }

            if (velocity > 0.0) {
                if (self.isPresenting) {
                    [self cancelInteractiveTransition];
                }
                else {
                    [self finishInteractiveTransition];
                }
            }
            else {
                if (self.isPresenting) {
                    [self finishInteractiveTransition];
                }
                else {
                    [self cancelInteractiveTransition];
                }
            }

            break;
        }
        case UIGestureRecognizerStateFailed: {
            [self cancelInteractiveTransition];

            break;
        }
        default:
            break;
    }
}

@end

NS_ASSUME_NONNULL_END
