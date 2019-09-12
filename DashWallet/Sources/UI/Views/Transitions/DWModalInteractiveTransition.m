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
@property (nonatomic, assign) CGPoint originalTouchPoint;

@end

@implementation DWModalInteractiveTransition

- (instancetype)init {
    self = [super init];
    if (self) {
        _presenting = YES;
        _originalTouchPoint = CGPointZero;
    }
    return self;
}

- (void)setPresentedController:(nullable UIViewController<DWModalInteractiveTransitionProgressHandler> *)controller {
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
    UIView *view = sender.view;
    const CGPoint touchPoint = [sender locationInView:view.superview];

    switch (sender.state) {
        case UIGestureRecognizerStateBegan: {
            self.originalTouchPoint = touchPoint;

            [self pauseInteractiveTransition];

            if (self.isPresenting == NO && self.percentComplete == 0.0) {
                [self.presentedController dismissViewControllerAnimated:YES completion:nil];
            }

            break;
        }
        case UIGestureRecognizerStateChanged: {
            // allow to pull view to the top (negative offset)
            CGFloat offset = touchPoint.y - self.originalTouchPoint.y;
            offset = offset < 0.0 ? -pow(-offset, 0.7) : 0.0;
            sender.view.transform = CGAffineTransformMakeTranslation(0, offset);

            CGFloat currentPercent = [sender dw_percentOfTranslationSinceLastChange];
            if (self.isPresenting) {
                currentPercent *= -1;
            }

            const CGFloat percent = self.percentComplete + currentPercent;
            [self updateInteractiveTransition:percent];

            [self didUpdateProgress:percent];

            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            self.timingCurve = nil;
            const CGFloat velocity = [sender dw_projectedVelocity:UIScrollViewDecelerationRateNormal].y;
            if (velocity > 0) {
                const CGFloat height = CGRectGetHeight(sender.view.bounds);
                const CGFloat distanceRemaining = height - self.percentComplete * height;
                if (distanceRemaining > 0) {
                    const CGFloat minVelocity = 0.001;
                    const CGFloat maxVelocity = 30.0;
                    const CGFloat relativeVelocity = MIN(MAX(ABS(velocity) / distanceRemaining, minVelocity), maxVelocity);
                    self.timingCurve =
                        [[UISpringTimingParameters alloc] initWithDamping:0.8
                                                                 response:0.3
                                                          initialVelocity:CGVectorMake(relativeVelocity, relativeVelocity)];
                }
            }

            const BOOL hasVelocity = velocity > 0.0;
            BOOL finished;
            if (self.isPresenting) {
                finished = !hasVelocity;
            }
            else {
                finished = hasVelocity;
            }

            if (finished) {
                [self finishInteractiveTransition];
                [self didUpdateProgress:1.0];
            }
            else {
                [self cancelInteractiveTransition];
                [self didUpdateProgress:0.0];

                // rubberbanding
                UISpringTimingParameters *timingParameters =
                    [[UISpringTimingParameters alloc] initWithDamping:0.6
                                                             response:0.3];
                UIViewPropertyAnimator *animator =
                    [[UIViewPropertyAnimator alloc] initWithDuration:0.0
                                                    timingParameters:timingParameters];
                [animator addAnimations:^{
                    sender.view.transform = CGAffineTransformIdentity;
                }];
                animator.interruptible = YES;
                [animator startAnimation];
            }

            break;
        }
        case UIGestureRecognizerStateFailed: {
            [self cancelInteractiveTransition];

            [self didUpdateProgress:0.0];

            break;
        }
        default:
            break;
    }
}

#pragma mark - Private

- (void)didUpdateProgress:(CGFloat)progress {
    if ([self.presentedController respondsToSelector:@selector(interactiveTransitionDidUpdateProgress:)]) {
        [self.presentedController interactiveTransitionDidUpdateProgress:progress];
    }
}

@end

NS_ASSUME_NONNULL_END
